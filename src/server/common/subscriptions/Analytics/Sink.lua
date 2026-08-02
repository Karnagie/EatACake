--[[
	Analytics.Sink — the ONLY code in the game that calls AnalyticsService.

	It exists because the platform budget is small and the game is chatty.
	Roblox allows 120 + 20 x CCU events per minute PER SERVER; a solo game
	server therefore gets ~140/min, about two per second, while a player
	mashing the EAT button and walking a HUD full of buttons can generate ten
	times that. Sending anyway does not raise the limit — the overflow is
	discarded on Roblox's side, and the dashboard shows an undercount that
	looks exactly like a real one. So the sink spends the budget deliberately:

	  TOKEN BUCKET   refilled continuously at the live allowance (recomputed
	                 from the current player count, since the allowance grows
	                 with CCU) and never overfilled past one minute's worth.
	  PRIORITY       three tiers with reserves (AnalyticsConfig.tiers). A
	                 funnel step happens ONCE and cannot be reconstructed, so
	                 it outranks the ten-thousandth bite. Bulk traffic is only
	                 admitted while half the minute's budget is still unspent.
	  COALESCING     identical (event, fields, player) tuples inside a short
	                 window collapse into ONE call carrying the count as the
	                 event's `value`. Roblox's own docs name this as the way
	                 to stay under the rate limit, and it is why "every tap"
	                 is affordable at all: 40 taps on one button cost 1 event.
	  HONEST LOSS    whatever is still refused is COUNTED and reported through
	                 `analytics_dropped`, so a thin metric is visibly thin
	                 instead of quietly wrong (R8).

	Failure handling distinguishes the two ways AnalyticsService says no:
	  * "unpublished place" — throws on EVERY call. Three strikes and the
	    sink turns itself off for the server with one warn (this is Studio,
	    and spamming the console helps nobody).
	  * "too many events" — a rate limit, not a fault. The bucket is emptied
	    for the rest of the minute and the sink keeps running.
	Getting that distinction wrong in either direction is fatal: disable on a
	rate limit and a busy server stops reporting for good.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))

local SCOPE = "Analytics"

local Sink = {}

-- ── custom field keys ───────────────────────────────────────────────────
-- The API wants the enum item's NAME as the dictionary key. Resolved once
-- and guarded: an engine without the enum must degrade to a plain string
-- rather than error inside every single log call.
local FIELD_NAMES = { "CustomField01", "CustomField02", "CustomField03" }
local fieldKeys: { string } = {}
do
	for index, name in ipairs(FIELD_NAMES) do
		local ok, resolved = pcall(function()
			return (Enum :: any).AnalyticsCustomFieldKeys[name].Name
		end)
		fieldKeys[index] = if ok and type(resolved) == "string" then resolved else name
	end
end

-- ── state ───────────────────────────────────────────────────────────────
local tokens = 0
local capacity = AnalyticsConfig.BudgetPerMinute(0)
local lastRefillAt = os.clock()
local disabled = false
local consecutiveFailures = 0
local rateLimitedUntil = 0

local sent = 0
local dropped: { [string]: number } = {} -- tier -> count since the last report
local droppedTotal = 0
local rateLimitHits = 0

-- Coalescing buffer: signature -> { player, name, value, fields, firstAt }
local pending: { [string]: any } = {}
local pendingCount = 0
local COALESCE_SECONDS = 6
local MAX_PENDING = 240

-- ── helpers ─────────────────────────────────────────────────────────────
local function sanitizeField(value: any): string?
	if value == nil then
		return nil
	end
	local text = if type(value) == "string" then value else tostring(value)
	-- Field VALUES share an 8000-unique-value budget across all three fields
	-- and everything past it becomes "Other", so they must be short, bounded
	-- vocabulary. Anything unbounded (a player name, a guid) would burn the
	-- budget in a day and take the useful breakdowns down with it.
	text = string.gsub(text, "[%c]", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		return nil
	end
	local limit = AnalyticsConfig.limits.maxFieldValueChars
	if #text > limit then
		text = string.sub(text, 1, limit)
	end
	return text
end

-- `values` is an ARRAY of up to 3 field values, positional: 1 -> CustomField01.
local function buildFields(values: { any }?): ({ [string]: string }?, string)
	if values == nil then
		return nil, ""
	end
	local fields = nil
	local signature = ""
	for index = 1, AnalyticsConfig.limits.maxCustomFields do
		local text = sanitizeField(values[index])
		if text ~= nil then
			fields = fields or {}
			fields[fieldKeys[index]] = text
			signature ..= `|{text}`
		else
			signature ..= "|"
		end
	end
	return fields, signature
end

local function playable(player: Player?): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function refill(now: number)
	local elapsed = math.max(0, now - lastRefillAt)
	lastRefillAt = now
	local previous = capacity
	capacity = AnalyticsConfig.BudgetPerMinute(#Players:GetPlayers())
	-- The allowance GROWS with CCU, and the reserves are fractions of it. A
	-- server that primed at 0 players and then had eight arrive would suddenly
	-- hold a small absolute number of tokens against a much larger capacity —
	-- putting it below the bulk reserve for ~30s, exactly during the arrival
	-- storm the reserve exists to survive. Scale the balance with the capacity
	-- so the FRACTION held is preserved.
	if capacity > previous and previous > 0 then
		tokens *= capacity / previous
	end
	tokens = math.min(capacity, tokens + elapsed * (capacity / 60))
end

local function noteDrop(tier: string, count: number)
	dropped[tier] = (dropped[tier] or 0) + count
	droppedTotal += count
end

-- True when the tier may spend a token right now. The reserve is what keeps
-- a tap storm from eating the budget a funnel step will need two seconds
-- later: bulk traffic simply cannot touch the bottom half of the bucket.
local function admit(tier: string): boolean
	-- Roblox has just told us we are over its limit. Spending anything before
	-- the window passes is throwing events away AND earning more errors, so
	-- the hold is honoured HERE rather than only in the warn throttle.
	if os.clock() < rateLimitedUntil then
		return false
	end
	local spec = AnalyticsConfig.tiers[tier] or AnalyticsConfig.tiers.normal
	if tokens < 1 then
		return false
	end
	if spec.reserve01 > 0 and tokens < capacity * spec.reserve01 then
		return false
	end
	return true
end

-- One real call to AnalyticsService, with the two failure modes told apart.
local function invoke(what: string, fn: () -> ()): boolean
	if disabled then
		return false
	end
	local ok, err = pcall(fn)
	if ok then
		sent += 1
		consecutiveFailures = 0
		return true
	end
	local message = tostring(err)
	if string.find(string.lower(message), "too many") ~= nil then
		-- A rate limit is not a fault. Stop spending for the rest of this
		-- minute and carry on; disabling here would silence a POPULAR server.
		rateLimitHits += 1
		tokens = 0
		if os.clock() >= rateLimitedUntil then
			rateLimitedUntil = os.clock() + 60
			Log.Warn(SCOPE, `AnalyticsService rate limit hit ({what}) — budget emptied for 60s; raise coalescing or drop a bulk beat`)
		end
		return false
	end
	consecutiveFailures += 1
	if consecutiveFailures >= 3 then
		disabled = true
		Log.Warn(
			SCOPE,
			`AnalyticsService unavailable after 3 failures (last: {what} — {message}) — telemetry OFF for this server. `
				.. `Expected in Studio and in any UNPUBLISHED place: analytics events are server-only and published-only.`
		)
	end
	return false
end

-- ── coalescing ──────────────────────────────────────────────────────────
local function emitCustom(player: Player, name: string, value: number, fields: { [string]: string }?)
	if not playable(player) then
		return
	end
	invoke(`custom {name}`, function()
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
end

local function flushEntry(signature: string, entry)
	pending[signature] = nil
	pendingCount -= 1
	tokens -= 1
	emitCustom(entry.player, entry.name, entry.value, entry.fields)
end

--API
-- Flush every coalesced entry older than the window (or all of them when
-- `force`). Called from the sink's tick and on player removal, so a leaving
-- player's last taps are not lost with them.
function Sink.Flush(now: number, force: boolean?, onlyPlayer: Player?)
	for signature, entry in pairs(pending) do
		if onlyPlayer == nil or entry.player == onlyPlayer then
			if force or now - entry.firstAt >= COALESCE_SECONDS then
				-- The flush obeys the SAME reserves as a direct send. It did not
				-- once, and that quietly defeated the whole priority design: up
				-- to MAX_PENDING bulk entries would drain the bucket to zero the
				-- moment the window elapsed, and the next funnel step — the one
				-- thing that cannot be reconstructed — would find it empty.
				if admit(entry.tier) then
					flushEntry(signature, entry)
				elseif force then
					-- Out of budget and out of time: count the loss instead of
					-- holding a buffer that will never drain. ONE dropped EVENT
					-- (its value is an occurrence count, not an event count).
					pending[signature] = nil
					pendingCount -= 1
					noteDrop(entry.tier, 1)
				end
			end
		end
	end
end

-- ── public logging API ──────────────────────────────────────────────────
--API
-- A custom event. `fieldValues` is a positional array of up to 3 values.
-- opts: { tier = "critical"|"normal"|"bulk", coalesce = boolean }
-- `coalesce` is for COUNTERS only (taps, bites): merged entries SUM their
-- value. Never coalesce a measurement — summing two dwell times produces a
-- number that describes nobody.
function Sink.Custom(player: Player, eventKey: string, value: number?, fieldValues: { any }?, opts: any?)
	if disabled or not playable(player) then
		return false
	end
	local name = AnalyticsConfig.Event(eventKey)
	if name == nil then
		Log.Once(SCOPE, `bad-event-{eventKey}`, `unknown analytics event key '{eventKey}' — NOT logged (add it to AnalyticsConfig.events)`)
		return false
	end
	opts = opts or {}
	local tier = opts.tier or "normal"
	local amount = if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		then value
		else 1
	local fields, signature = buildFields(fieldValues)

	if opts.coalesce then
		local key = `{name}#{player.UserId}{signature}`
		local entry = pending[key]
		if entry then
			entry.value += amount
			return true
		end
		if pendingCount < MAX_PENDING then
			pending[key] = {
				player = player,
				name = name,
				value = amount,
				fields = fields,
				firstAt = os.clock(),
				tier = tier,
			}
			pendingCount += 1
			return true
		end
		-- Buffer full: fall through and try to send it outright.
	end

	if not admit(tier) then
		noteDrop(tier, 1)
		return false
	end
	tokens -= 1
	emitCustom(player, name, amount, fields)
	return true
end

--API
-- One step of a custom funnel. `funnelName` and `stepName` come from the
-- catalog; `sessionId` groups the steps of one attempt (and is what makes a
-- funnel that spans the lobby->game teleport join up).
function Sink.Funnel(
	player: Player,
	funnelName: string,
	sessionId: string,
	step: number,
	stepName: string,
	fieldValues: { any }?
)
	if disabled or not playable(player) then
		return false
	end
	if not admit("critical") then
		noteDrop("critical", 1)
		return false
	end
	local fields = buildFields(fieldValues)
	tokens -= 1
	return invoke(`funnel {funnelName}/{step}`, function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, sessionId, step, stepName, fields)
	end)
end

--API
-- The built-in onboarding funnel: no session id, lifetime per player, and
-- de-duped by Roblox server-side. Reported against D1/D7 retention in the
-- Creator Dashboard, which is why it is worth its own call.
function Sink.Onboarding(player: Player, step: number, stepName: string, fieldValues: { any }?)
	if disabled or not playable(player) then
		return false
	end
	if not admit("critical") then
		noteDrop("critical", 1)
		return false
	end
	local fields = buildFields(fieldValues)
	tokens -= 1
	return invoke(`onboarding {step}`, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, fields)
	end)
end

--API
-- A currency movement. `flow` is "source" or "sink"; the rest is Roblox's
-- economy vocabulary (AnalyticsConfig.economy) — inventing strings here
-- burns the 10-currency / 20-transaction-type budgets on synonyms.
function Sink.Economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	sku: string?,
	fieldValues: { any }?
)
	if disabled or not playable(player) then
		return false
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false -- a zero/NaN movement is noise, and negatives are a caller bug
	end
	if not admit("critical") then
		noteDrop("critical", 1)
		return false
	end
	local flowType = if flow == "sink"
		then Enum.AnalyticsEconomyFlowType.Sink
		else Enum.AnalyticsEconomyFlowType.Source
	local fields = buildFields(fieldValues)
	local balance = if type(endingBalance) == "number" and endingBalance == endingBalance
		then math.max(0, math.floor(endingBalance))
		else 0
	tokens -= 1
	return invoke(`economy {currency}/{transactionType}`, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flowType,
			currency,
			math.floor(amount),
			balance,
			transactionType,
			sku,
			fields
		)
	end)
end

-- ── housekeeping ────────────────────────────────────────────────────────
--API
-- Refill the bucket, drain the coalescing buffer, and report losses. Driven
-- by AnalyticsSubs on a slow loop — never per frame.
function Sink.Tick(now: number)
	if disabled then
		return
	end
	refill(now)
	Sink.Flush(now, false)
end

--API
-- Emits the loss report as a real event so an undercount is visible ON the
-- dashboard, not only in a server log nobody reads. Returns what it reported.
--
-- ⚠ Two things this must get right, both of which it once got wrong:
--   * the fields go through `buildFields` like every other call. Handing
--     LogCustomEvent a positional ARRAY fails the Dictionary cast and THROWS —
--     and a throw with no "too many" in it counts toward the disable rule, so
--     the honesty mechanism would have switched telemetry off entirely, two
--     minutes into every busy server, blaming Studio in the warn.
--   * the counts are only cleared once they have actually been SENT. Drops
--     happen precisely when the bucket is empty, so clearing first meant the
--     report was discarded exactly when it mattered. A token is RESERVED for
--     it here instead — one event a minute is worth spending to know the rest
--     of the minute is short.
function Sink.ReportDrops(player: Player?): number
	if droppedTotal <= 0 then
		return 0
	end
	local total = droppedTotal
	if disabled or player == nil or not playable(player) or os.clock() < rateLimitedUntil then
		return total -- keep the counts; the next report will carry them
	end
	local reason = if rateLimitHits > 0 then "rate-limited" else "budget"
	local reported = {}
	for tier, count in pairs(dropped) do
		-- Reserved, not admitted: this report IS the budget's own alarm and
		-- must not be silenced by the condition it exists to announce.
		tokens -= 1
		local fields = buildFields({ tier, reason, "sink" })
		emitCustom(player, AnalyticsConfig.Event("analytics-dropped") :: string, count, fields)
		table.insert(reported, tier)
	end
	for _, tier in ipairs(reported) do
		droppedTotal -= dropped[tier]
		dropped[tier] = nil
	end
	return total
end

--API
function Sink.Forget(player: Player)
	Sink.Flush(os.clock(), true, player)
end

--API
function Sink.IsDisabled(): boolean
	return disabled
end

--API
function Sink.Stats(): { [string]: any }
	return {
		sent = sent,
		dropped = droppedTotal,
		pending = pendingCount,
		tokens = math.floor(tokens),
		capacity = capacity,
		rateLimitHits = rateLimitHits,
		disabled = disabled,
	}
end

--API
-- Starts the bucket full so a server's opening beats (join, spawn, HUD
-- ready — all of them funnel-critical) are never refused for want of a
-- refill that has not happened yet.
function Sink.Prime()
	capacity = AnalyticsConfig.BudgetPerMinute(#Players:GetPlayers())
	tokens = capacity
	lastRefillAt = os.clock()
end

return Sink
