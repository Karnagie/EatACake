--[[
	LocalAnalyticsService — the client's outbound beat queue.

	AnalyticsService is server-only and published-place-only, so nothing the
	player does with their fingers can be logged where it happens. Every tap,
	panel open and client-observed flow beat therefore has to cross the wire —
	and a remote fired once per tap would be a firehose aimed at a rate limit.

	So beats are QUEUED, COALESCED and FLUSHED on a slow cadence:

	  * repeats of the same (kind, a, b) inside the queue merge and SUM their
	    value, so mashing one button ten times sends one beat with v=10;
	  * ordinary beats leave on the `flushSeconds` tick;
	  * a beat marked URGENT (a funnel step — it happens once and cannot be
	    reconstructed) pulls the next flush forward instead of waiting;
	  * the queue is bounded. Overflow is COUNTED and reported rather than
	    silently forgotten (R8) — an undercount that knows it is an
	    undercount is data; one that does not is a lie.

	Tuning is AnalyticsConfig.beat; the subscription (AnalyticsSubsClient)
	owns every connection that feeds this, including the pump. This module is
	logic + one buffer, and holds no game state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))

local SCOPE = "Analytics"
local BEAT = AnalyticsConfig.beat

local LocalAnalyticsService = {}

local queue: { any } = {}
local index: { [string]: any } = {} -- coalescing signature -> queued beat
local remote: RemoteEvent? = nil
local screen: string? = nil
local nextFlushAt = 0
local overflow = 0
local sentBeats = 0
local sentMessages = 0
-- Beats that mean the same thing however many times they fire (a funnel step,
-- a flow beat). See `opts.once` in Track.
local sentOnce: { [string]: boolean } = {}

-- Kinds whose `v` is a COUNT and may therefore be merged. A measurement
-- (a hold's duration, a tutorial step's dwell) must never be summed: two
-- merged holds would report one impossible 12-second press.
local COUNTABLE = { press = true, ["dead-press"] = true, error = true }

-- ⚠ NEVER `Net.Remote` here: it is `WaitForChild` with no timeout, and pcall
-- does not stop a yield. A missing AnalyticsBeat would block this Init, and
-- with it the whole client bootstrap — every later module Init, every
-- subscription Start, and the `ClientReady` fire the SERVER holds all initial
-- state behind. Telemetry taking the entire client down is precisely what this
-- module's header says cannot happen. Resolve without yielding and degrade.
function LocalAnalyticsService.Init()
	remote = Net.Remotes:FindFirstChild("AnalyticsBeat") :: RemoteEvent?
	if remote == nil then
		-- It is Rojo-mapped content, so it can legitimately replicate late.
		Log.GraceOnce(SCOPE, "no-beat-remote", 10, function()
			remote = Net.Remotes:FindFirstChild("AnalyticsBeat") :: RemoteEvent?
			return remote == nil
		end, "AnalyticsBeat remote never replicated — NO client-side telemetry (taps, panels, tutorial beats) will be sent")
	end
end

--API
-- The panel the player is looking at, attached to every press so a tap can
-- be read in context ("Close pressed" is useless; "Close pressed on Shop"
-- is a funnel step).
function LocalAnalyticsService.SetScreen(name: string?)
	screen = name
end

--API
function LocalAnalyticsService.GetScreen(): string?
	return screen
end

--API
-- Queue one beat. `opts = { value = number?, urgent = boolean? }`.
function LocalAnalyticsService.Track(kind: string, a: string?, b: string?, opts: any?)
	-- Deliberately NOT gated on `remote`: it can replicate late, the queue is
	-- bounded, and the beats produced in the first seconds (hud-ready, the
	-- platform report, the first taps) are the ones worth keeping.
	if not AnalyticsConfig.clientBeatKinds[kind] then
		Log.Once(SCOPE, `local-kind-{kind}`, `client tried to send unknown beat kind '{kind}' — dropped (AnalyticsConfig.clientBeatKinds)`)
		return false
	end
	opts = opts or {}
	local value = opts.value

	-- Idempotent beats are deduped HERE as well as on the server. The server
	-- would drop the repeat anyway, but each one pulls the next flush forward
	-- (they are urgent), and four flushes a second would exceed the server's
	-- 3/s admission and cost the WHOLE message — funnel steps included.
	if opts.once then
		local key = `{kind}|{tostring(a)}|{tostring(b)}`
		if sentOnce[key] then
			return true
		end
		sentOnce[key] = true
	end

	if COUNTABLE[kind] then
		local signature = `{kind}|{tostring(a)}|{tostring(b)}`
		local existing = index[signature]
		if existing ~= nil then
			existing.v = (existing.v or 1) + (value or 1)
			return true
		end
	end

	if #queue >= BEAT.maxQueued then
		overflow += 1
		return false
	end

	local beat = { k = kind, a = a, b = b, v = value }
	table.insert(queue, beat)
	if COUNTABLE[kind] then
		index[`{kind}|{tostring(a)}|{tostring(b)}`] = beat
	end

	if opts.urgent then
		-- A funnel step waiting two seconds behind a tap queue is a funnel
		-- step that can be lost to a teleport. Pull the flush forward.
		nextFlushAt = math.min(nextFlushAt, os.clock() + BEAT.urgentFlushSeconds)
	end
	return true
end

--API
-- A tap on a named control. `screen` is filled in automatically.
function LocalAnalyticsService.Press(id: string, dead: boolean?)
	return LocalAnalyticsService.Track(if dead then "dead-press" else "press", id, screen or "world", { value = 1 })
end

--API
-- One beat of the master initial-player-flow funnel. Only the steps the
-- server cannot observe for itself are accepted (AnalyticsConfig
-- .clientFlowSteps) — the rest are logged where they actually happen.
function LocalAnalyticsService.Flow(stepKey: string)
	return LocalAnalyticsService.Track("flow", stepKey, nil, { urgent = true, once = true })
end

--API
-- ⚠ NOT deduped, unlike Flow: a `visit` funnel's first step legitimately
-- repeats (opening the shop a second time is a second ATTEMPT), and swallowing
-- it here would report one visit per session for the rest of the funnel.
function LocalAnalyticsService.Funnel(funnelKey: string, stepKey: string)
	return LocalAnalyticsService.Track("funnel", funnelKey, stepKey, { urgent = true })
end

--API
-- A tutorial step plus how long the player spent on the previous one.
function LocalAnalyticsService.Tutorial(stepKey: string, dwellSeconds: number?)
	return LocalAnalyticsService.Track("tutorial", stepKey, nil, {
		value = dwellSeconds,
		urgent = true,
	})
end

--API
function LocalAnalyticsService.Panel(name: string, opened: boolean)
	return LocalAnalyticsService.Track("panel", name, if opened then "open" else "close", { value = 1 })
end

--API
-- A hold button released. The VALUE is the duration, so this is never merged.
function LocalAnalyticsService.Hold(id: string, seconds: number)
	return LocalAnalyticsService.Track("hold", id, screen or "world", { value = seconds })
end

--API
function LocalAnalyticsService.Error(scope: string, detail: string?)
	return LocalAnalyticsService.Track("error", scope, detail, { value = 1 })
end

--API
-- Sends up to one message worth of beats. Returns how many left.
function LocalAnalyticsService.Flush(): number
	if remote == nil then
		-- Still replicating. The queue is bounded and counts its own overflow,
		-- so holding is safe and keeps the first seconds' beats.
		return #queue
	end
	if #queue == 0 then
		return 0
	end
	local batch = {}
	local taken = 0
	while #queue > 0 and taken < BEAT.maxPerMessage do
		local beat = table.remove(queue, 1)
		taken += 1
		table.insert(batch, beat)
	end
	-- The coalescing index only ever points at beats still in the queue; a
	-- stale entry would merge new taps into a table already sent, and those
	-- increments would never arrive anywhere.
	table.clear(index)
	for _, beat in ipairs(queue) do
		if COUNTABLE[beat.k] then
			index[`{beat.k}|{tostring(beat.a)}|{tostring(beat.b)}`] = beat
		end
	end

	if overflow > 0 then
		-- Report the loss in-band so a thin chart is visibly thin.
		table.insert(batch, { k = "error", a = "analytics-overflow", b = "client", v = overflow })
		overflow = 0
	end

	local ok, err = pcall(function()
		(remote :: RemoteEvent):FireServer(batch)
	end)
	if not ok then
		Log.Once(SCOPE, "beat-fire-failed", `AnalyticsBeat FireServer failed — client telemetry is not arriving: {err}`)
		return #queue
	end
	sentMessages += 1
	sentBeats += taken
	return #queue
end

--API
-- Driven by AnalyticsSubsClient on a throttled loop (never per frame).
function LocalAnalyticsService.Pump(now: number)
	if now < nextFlushAt then
		return
	end
	nextFlushAt = now + BEAT.flushSeconds
	LocalAnalyticsService.Flush()
end

--API
function LocalAnalyticsService.Stats(): { [string]: any }
	return {
		queued = #queue,
		overflow = overflow,
		sentBeats = sentBeats,
		sentMessages = sentMessages,
		connected = remote ~= nil,
	}
end

return LocalAnalyticsService
