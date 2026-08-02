--[[
	Analytics.Ingest — validates and admits the client's beat stream.

	AnalyticsService is server-only and published-place-only, so every tap
	the player makes has to cross the wire before it can be counted. That
	makes this the widest-open remote in the game: it is called constantly,
	by every client, with free-form strings. It is therefore treated exactly
	like a currency remote (R6), minus the currency:

	  BUDGETED   a per-player token bucket on MESSAGES and a per-minute cap on
	             BEATS. A modded client firing in a loop cannot burn this
	             server's shared analytics budget, or its CPU.
	  BOUNDED    a hard cap on beats per message, and every string is clamped
	             and sanitized before it can reach a custom field, where an
	             unbounded value would eat the experience-wide 8000-unique-
	             value budget and take every breakdown down with it.
	  TRUSTED ONLY WITH WHAT ONLY IT KNOWS — the client may assert that a
	             popup rendered or a button was pressed. It may NOT assert
	             that a bite landed, a purchase completed or a match started:
	             those are logged where the server observes them. The
	             allow-lists are AnalyticsConfig.clientFlowSteps /
	             .clientFunnels, and anything outside them is refused.

	A refusal here is never fatal and never kicks: the worst case is one
	missing dot on a chart, and telemetry must never be able to take a
	gameplay path down with it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))
local Sink = require(script.Parent:WaitForChild("Sink"))
local Session = require(script.Parent:WaitForChild("Session"))

local SCOPE = "Analytics"

local Ingest = {}

local BEAT = AnalyticsConfig.beat

-- userId -> { tokens, lastAt, minuteBeats, minuteAt, refused, values, valueCount }
local budgets: { [number]: any } = {}

local accepted = 0
local refused = 0

local function budgetFor(userId: number)
	local entry = budgets[userId]
	if entry == nil then
		entry = {
			tokens = BEAT.messageBurst,
			lastAt = os.clock(),
			minuteBeats = 0,
			minuteAt = os.clock(),
			refused = 0,
			-- The distinct field values this player has introduced (see
			-- `maxDistinctValuesPerPlayer`).
			values = {},
			valueCount = 0,
		}
		budgets[userId] = entry
	end
	return entry
end

--API
function Ingest.Forget(userId: number)
	budgets[userId] = nil
end

-- ⚠ NOTHING derived from a client string may become a `Log.Once` KEY.
-- `Log.onceFired` is a module table that is never cleared, so a key built from
-- an attacker-chosen payload is unbounded server memory AND an unbounded warn
-- stream — one modded client at the legal 240 beats/min with a fresh `k` each
-- time would add 240 permanent entries and 240 `warn()` calls a minute,
-- forever, burying the R8 boot report. Keys here are always bounded: a fixed
-- string plus, at most, the player's own id.
local function refuse(player: Player, key: string, message: string)
	refused += 1
	Log.Once(SCOPE, `{key}-{player.UserId}`, `{player.Name}: {message}`)
end

-- A short, printable, bounded string or nil. Everything that reaches a
-- custom field goes through here.
local function text(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	if #value > 256 then
		value = string.sub(value, 1, 256) -- bound the work before the gsubs
	end
	local cleaned = string.gsub(value, "[^%w%-%_%./ ]", "")
	cleaned = string.gsub(cleaned, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	if cleaned == "" then
		return nil
	end
	local limit = AnalyticsConfig.limits.maxFieldValueChars
	return if #cleaned > limit then string.sub(cleaned, 1, limit) else cleaned
end

-- Length-clamping is not cardinality-clamping. A value that is short but NEW
-- every time is exactly what exhausts the experience-wide 8000-unique-value
-- budget; past this player's allowance, everything else becomes "other" for
-- them alone, so an attacker cannot spend anyone else's breakdowns.
local function bounded(budget, value: string?): string?
	if value == nil then
		return nil
	end
	if budget.values[value] then
		return value
	end
	if budget.valueCount >= AnalyticsConfig.beat.maxDistinctValuesPerPlayer then
		return "other"
	end
	budget.values[value] = true
	budget.valueCount += 1
	return value
end

local function number(value: any, maximum: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(value, 0, maximum)
end

-- ── one beat ────────────────────────────────────────────────────────────
local function handle(player: Player, budget, beat: any): boolean
	if type(beat) ~= "table" then
		return false
	end
	local kind = beat.k
	if type(kind) ~= "string" or not AnalyticsConfig.clientBeatKinds[kind] then
		-- The offending kind is NOT in the key (see `refuse`); it is not in the
		-- message either, since a warn is a string an attacker would otherwise
		-- get to write into the console.
		refuse(player, "beat-kind", "sent an unknown analytics beat kind — dropped")
		return false
	end
	local a, b = bounded(budget, text(beat.a)), bounded(budget, text(beat.b))
	local fields = Session.Fields(player)

	if kind == "press" then
		if a == nil then
			return false
		end
		-- The "every tap" layer. Coalesced and BULK: a hundred presses cost
		-- one event, and they yield the budget to anything that happens once.
		Sink.Custom(player, "ui-press", number(beat.v, 500) or 1, { a, b or "world", fields[3] }, {
			tier = "bulk",
			coalesce = true,
		})
		return true
	elseif kind == "dead-press" then
		if a == nil then
			return false
		end
		-- Pressed something that could not answer. This is the single most
		-- direct "the player tried and the game said nothing" signal there
		-- is, so it outranks ordinary taps.
		Sink.Custom(player, "ui-dead-press", 1, { a, b or "world", fields[3] }, {
			tier = "normal",
			coalesce = true,
		})
		return true
	elseif kind == "panel" then
		if a == nil then
			return false
		end
		Sink.Custom(player, "ui-panel", 1, { a, b or "open", fields[3] }, { tier = "normal", coalesce = true })
		return true
	elseif kind == "hold" then
		if a == nil then
			return false
		end
		-- NOT coalesced: the value is a DURATION. Merging two six-second holds
		-- would report one impossible twelve-second press.
		Sink.Custom(player, "ui-hold", number(beat.v, 3600) or 0, { a, b or "world", fields[3] }, {
			tier = "bulk",
		})
		return true
	elseif kind == "flow" then
		if a == nil or not AnalyticsConfig.clientFlowSteps[a] then
			refuse(player, "beat-flow", "tried to assert a flow step the SERVER observes for itself — dropped (AnalyticsConfig.clientFlowSteps)")
			return false
		end
		return Session.Flow(player, a)
	elseif kind == "funnel" then
		-- Per-STEP, not per-funnel: `shop` and `upgrades` both end in a
		-- conversion step, and a funnel-wide allow-list would have let a client
		-- assert its own purchase.
		local allowed = a ~= nil and AnalyticsConfig.clientFunnels[a]
		if b == nil or type(allowed) ~= "table" or not allowed[b] then
			refuse(player, "beat-funnel", "tried to assert a funnel step the SERVER owns — dropped (AnalyticsConfig.clientFunnels)")
			return false
		end
		return Session.Funnel(player, a :: string, b)
	elseif kind == "tutorial" then
		local allowedTutorial = AnalyticsConfig.clientFunnels.tutorial
		if a == nil or not allowedTutorial[a] then
			refuse(player, "beat-tutorial", "tried to assert an unknown tutorial step — dropped")
			return false
		end
		Session.Funnel(player, "tutorial", a)
		Sink.Custom(player, "tutorial-step", number(beat.v, 3600) or 0, { a, fields[1], fields[2] }, {
			tier = "normal",
		})
		return true
	elseif kind == "shop" then
		local allowedShop = AnalyticsConfig.clientFunnels.shop
		if a == nil or not allowedShop[a] then
			refuse(player, "beat-shop", "tried to assert a shop step the SERVER owns (prompt/bought) — dropped")
			return false
		end
		local eventKey = if a == "open" then "shop-open" elseif a == "tab" then "shop-tab" else "shop-card"
		Sink.Custom(player, eventKey, 1, { b or "unknown", fields[1], fields[3] }, { tier = "normal" })
		Session.Funnel(player, "shop", a)
		return true
	elseif kind == "platform" then
		if a == nil then
			return false
		end
		Session.SetPlatform(player, a)
		Sink.Custom(player, "session-start", 1, { fields[1], a, b or "unknown" }, { tier = "critical" })
		return true
	elseif kind == "error" then
		if a == nil then
			return false
		end
		Sink.Custom(player, "client-error", 1, { a, b or "unknown", fields[3] }, { tier = "normal", coalesce = true })
		return true
	end
	return false
end

-- ── the remote handler ──────────────────────────────────────────────────
--API
-- Connected by AnalyticsSubs (R4). `beats` is an ARRAY of beat tables.
function Ingest.OnBeat(player: Player, beats: any)
	if Sink.IsDisabled() then
		return
	end
	local now = os.clock()
	local budget = budgetFor(player.UserId)

	-- message rate
	budget.tokens = math.min(
		BEAT.messageBurst,
		budget.tokens + (now - budget.lastAt) * BEAT.messagesPerSecond
	)
	budget.lastAt = now
	if budget.tokens < 1 then
		budget.refused += 1
		refuse(player, "beat-flood", `is sending analytics beats faster than {BEAT.messagesPerSecond}/s — excess dropped`)
		return
	end
	budget.tokens -= 1

	-- beat rate (a single message may legitimately carry a burst; a minute of
	-- them may not)
	if now - budget.minuteAt >= 60 then
		budget.minuteAt = now
		budget.minuteBeats = 0
	end

	if type(beats) ~= "table" then
		refuse(player, "beat-shape", "sent a non-array analytics payload — dropped")
		return
	end

	local count = 0
	for _, beat in ipairs(beats) do
		count += 1
		if count > BEAT.maxPerMessage then
			refuse(player, "beat-oversize", `sent more than {BEAT.maxPerMessage} beats in one message — the tail was dropped`)
			break
		end
		if budget.minuteBeats >= BEAT.beatsPerMinute then
			refuse(player, "beat-minute", `exceeded {BEAT.beatsPerMinute} analytics beats/min — excess dropped`)
			break
		end
		budget.minuteBeats += 1
		local ok, err = pcall(handle, player, budget, beat)
		if ok then
			accepted += 1
		else
			refused += 1
			-- The KEY is bounded; the error text is ours, not the client's.
			Log.Once(SCOPE, `beat-error-{player.UserId}`, `analytics beat from {player.Name} FAILED — {err}`)
		end
	end
end

--API
function Ingest.Stats(): { [string]: number }
	return { accepted = accepted, refused = refused }
end

return Ingest
