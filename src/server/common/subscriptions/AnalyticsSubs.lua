--[[
	AnalyticsSubs — the game's instrumentation front door (R4: the ONE place
	that connects analytics events; Analytics/Sink is the ONE place that calls
	AnalyticsService).

	Feature doc: docs/features/analytics.md. Catalog: Shared.config
	.AnalyticsConfig. Decision: ADR-0017.

	Every other subscription pushes beats IN through the registry
	(`subscriptions.AnalyticsSubs`, the ADR-0009 coupling pattern) — this
	module never reaches into a domain itself, and every caller treats it as
	OPTIONAL (`if AnalyticsSubs then`) so a missing analytics module can never
	take a gameplay path down.

	The four things it owns:

	  THE FLOW      `Flow(player, stepKey)` records one beat of the initial
	                player flow — 31 ordered steps from "joined" to "returned
	                to lobby", spanning BOTH places on one funnel session id.
	                Idempotent per session, so callers fire it from wherever
	                the truth is without tracking whether it already happened.
	  THE FUNNELS   `Funnel(player, funnelKey, stepKey)` for the seven
	                narrower funnels (matchmaking, tutorial, match, shop,
	                upgrades, gym, finds).
	  THE COUNTERS  `Event(...)` and `Economy(...)`, the denominators without
	                which "reached step 17" means nothing.
	  THE BUDGET    a slow tick that refills the rate-limit bucket, drains the
	                coalescing buffer, fires `flow_stall` for players who have
	                been stuck on one step too long, and reports its own
	                dropped events.

	⚠ A LEG IS NOT A SESSION. The game is two places (ADR-0009) and every
	lobby<->game teleport ends the player on THIS server and starts a fresh
	one on the next, so a per-server timer can only ever measure one leg —
	naming it `session_minutes` would report a 30-minute session as "3 + 26".
	The legs are logged separately and honestly (`place_minutes_lobby` /
	`place_minutes_game`); Roblox's own engagement metric already reports
	true cross-place session length, so it is not rebuilt here. The FUNNEL,
	by contrast, does span the teleport — that is what the carried session id
	in Analytics/Session is for.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))
local PlaceConfig = require(Shared:WaitForChild("config"):WaitForChild("PlaceConfig"))

local Helpers = script.Parent:WaitForChild("Analytics")
local Sink = require(Helpers:WaitForChild("Sink"))
local Session = require(Helpers:WaitForChild("Session"))
local Ingest = require(Helpers:WaitForChild("Ingest"))

local SCOPE = "Analytics"
local TICK_SECONDS = 5
local DROP_REPORT_SECONDS = 120

local AnalyticsSubs = {}

local joinedAt: { [number]: number } = {}

-- The pre-catalog API took hand-written names and a small set of onboarding
-- keys. Both are kept working (and mapped onto the catalog) so a call site
-- missed during the rewrite degrades into the RIGHT metric instead of a
-- warning nobody reads.
local LEGACY_ONBOARDING = {
	joined = "join",
	firstBite = "first-bite",
	firstFind = "first-find",
	firstLayer = "first-layer",
	firstGym = "first-gym",
	firstUpgrade = "first-upgrade",
	tutorialDone = "tutorial-done",
}

local legacyEventKeys: { [string]: string } = {}
for key, name in pairs(AnalyticsConfig.events) do
	legacyEventKeys[name] = key
end

-- ── public API ──────────────────────────────────────────────────────────
--API
-- One beat of the initial player flow (AnalyticsConfig.flowSteps). Safe to
-- call repeatedly and from more than one place: the second call for a step
-- inside one session is dropped.
function AnalyticsSubs.Flow(player: Player, stepKey: string): boolean
	return Session.Flow(player, stepKey)
end

--API
-- One step of a narrower funnel (`queue`, `tutorial`, `match`, `shop`,
-- `upgrades`, `gym`, `find`).
function AnalyticsSubs.Funnel(player: Player, funnelKey: string, stepKey: string): boolean
	return Session.Funnel(player, funnelKey, stepKey)
end

--API
-- Starts a fresh ATTEMPT at a recurring funnel, so a player's fifth shop
-- visit is a fifth attempt rather than more step-1s on the first.
function AnalyticsSubs.BeginVisit(player: Player, funnelKey: string, explicitId: string?): string?
	return Session.BeginVisit(player, funnelKey, explicitId)
end

--API
-- A custom event. `eventKey` is a catalog key (AnalyticsConfig.events).
-- `fieldValues` is a positional array of up to 3 breakdown values; pass nil
-- to get the standard cohort/platform/place triple.
-- opts: { tier = "critical"|"normal"|"bulk", coalesce = boolean }
function AnalyticsSubs.Event(player: Player, eventKey: string, value: number?, fieldValues: { any }?, opts: any?)
	return Sink.Custom(player, eventKey, value, fieldValues or Session.Fields(player), opts)
end

--API
-- A currency movement, on Roblox's own economy vocabulary
-- (AnalyticsConfig.economy). `flow` is "source" or "sink".
function AnalyticsSubs.Economy(
	player: Player,
	flow: string,
	currency: string,
	amount: number,
	endingBalance: number,
	transactionType: string,
	sku: string?
)
	return Sink.Economy(player, flow, currency, amount, endingBalance, transactionType, sku, Session.Fields(player))
end

--API
-- Tags this player's session with the match they are in, so every funnel
-- step and event they produce can be broken down by difficulty, and the
-- `match` funnel groups by round id.
function AnalyticsSubs.SetMatch(player: Player, roundId: string?, difficulty: string?)
	Session.SetMatch(player, roundId, difficulty)
end

--API
-- The analytics block the lobby attaches to its launch TeleportData. Without
-- it the funnel breaks in half at the teleport — see Analytics/Session.
function AnalyticsSubs.HandoffPayload(players: { Player }): { any }
	return Session.HandoffPayload(players)
end

--API
-- DEPRECATED shim for the pre-catalog onboarding API. New code calls Flow().
function AnalyticsSubs.Onboard(player: Player, key: string)
	local stepKey = LEGACY_ONBOARDING[key] or key
	if AnalyticsConfig.FlowIndex(stepKey) == nil then
		Log.Once(SCOPE, `bad-beat-{key}`, `unknown onboarding beat '{key}' — not logged (use AnalyticsSubs.Flow with an AnalyticsConfig.flowSteps key)`)
		return
	end
	Session.Flow(player, stepKey)
end

--API
-- DEPRECATED shim for the pre-catalog counter API, which took a raw event
-- NAME. New code calls Event() with a catalog key.
function AnalyticsSubs.Count(player: Player, eventName: string, value: number?)
	local key = legacyEventKeys[eventName] or eventName
	return Sink.Custom(player, key, value, Session.Fields(player), { tier = "normal" })
end

--API
-- Discovered by PlayerLifecycleSubs. The profile is what says whether this
-- is the player's first ever session, and it lands AFTER the first few flow
-- beats — this releases the onboarding calls that were held waiting for it.
function AnalyticsSubs.OnProfileLoaded(player: Player)
	Session.OnProfileLoaded(player)
end

--API
function AnalyticsSubs.Stats(): { [string]: any }
	local stats = Sink.Stats()
	local ingest = Ingest.Stats()
	stats.beatsAccepted = ingest.accepted
	stats.beatsRefused = ingest.refused
	return stats
end

-- ── wiring ──────────────────────────────────────────────────────────────
function AnalyticsSubs.Start(data, _services)
	Session.Init(data)

	local ok, report, problems = AnalyticsConfig.Validate()
	if ok then
		Log.Info(SCOPE, `catalog OK — {report}`)
	else
		-- A catalog over quota does not error at the call site: Roblox accepts
		-- the call and DROPS it server-side, so the metric simply never
		-- appears. That is unfindable at runtime, which is why it is checked
		-- here and shouted about (R8).
		Log.Warn(SCOPE, `catalog OVER QUOTA — {report}`)
		for _, problem in ipairs(problems) do
			Log.Warn(SCOPE, `  catalog: {problem}`)
		end
	end

	local place = PlaceConfig.current()
	local legEvent = `place-minutes-{place}`
	if AnalyticsConfig.Event(legEvent) == nil then
		-- "unknown" (place ids unset) has no event of its own; fold it into the
		-- lobby bucket rather than dropping the leg silently.
		legEvent = "place-minutes-lobby"
	end
	Sink.Prime()

	local function onJoin(player: Player)
		-- os.time() here, os.clock() everywhere else in this subsystem, and the
		-- split is deliberate. The LEG is a wall-clock duration that has to be
		-- comparable to Roblox's own engagement metric and to a human reading
		-- "27 minutes", so it uses the wall clock, at whole-second resolution
		-- it does not need more than. Everything else analytics measures — step
		-- dwell, stall budgets, the coalescing window — is a short INTERVAL,
		-- where os.clock()'s sub-second resolution matters and where it is
		-- already what every other timer in this codebase uses (the queue
		-- countdown, the teleport return window, the gym drain).
		joinedAt[player.UserId] = os.time()
		Session.Begin(player)
		AnalyticsSubs.Flow(player, "join")

		-- Coming BACK from a finished match is the last step of the loop and
		-- the first of the next one. It is told apart from a fresh join by the
		-- return TeleportData the game place attaches (features/game-round.md);
		-- the earlier steps are suppressed automatically because the adopted
		-- session already passed them.
		local okJoin, joinData = pcall(player.GetJoinData, player)
		local teleportData = okJoin and type(joinData) == "table" and joinData.TeleportData
		if type(teleportData) == "table" and teleportData.kind == "match-result" then
			-- The `match` funnel is keyed on the ROUND id, and the round is on
			-- the other server — so the round id has to be restored from the
			-- return payload before the step is logged. Without it the last
			-- step would go out under the analytics session id while steps 1-9
			-- went out under the round id, and "Returned To Lobby" would read
			-- 0% forever.
			if type(teleportData.roundId) == "string" then
				AnalyticsSubs.SetMatch(player, teleportData.roundId, nil)
			end
			AnalyticsSubs.Flow(player, "return-lobby")
			AnalyticsSubs.Funnel(player, "match", "return")
		end

		-- The character existing is its own beat: a join that never spawns is
		-- a completely different failure from a spawn that never moves.
		local function onCharacter()
			AnalyticsSubs.Flow(player, "spawn")
		end
		if player.Character then
			onCharacter()
		end
		player.CharacterAdded:Connect(onCharacter)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onJoin(player) -- a sub can Start after the first player is already in
	end
	Players.PlayerAdded:Connect(onJoin)

	Players.PlayerRemoving:Connect(function(player)
		local started = joinedAt[player.UserId]
		joinedAt[player.UserId] = nil

		-- Mid-teleport is NOT abandonment: the flow continues on the
		-- destination server under the same session id. Counting it as a drop
		-- would make the healthiest path in the game look like its worst leak.
		local handedOff = player:GetAttribute("Teleporting") == true
		Session.ReportExit(player, handedOff)

		if started ~= nil then
			local minutes = (os.time() - started) / 60
			-- ONE LEG (see the header) — sum the game legs, never read this as
			-- a session. Rounded to a tenth so the buckets stay readable.
			Sink.Custom(player, legEvent, math.floor(minutes * 10) / 10, Session.Fields(player), {
				tier = "critical",
			})
			Log.Info(
				SCOPE,
				`{player.Name}: {legEvent} {string.format("%.1f", minutes)}{if handedOff then " (teleporting out)" else ""}`
			)
		end

		-- Flush this player's coalesced taps BEFORE their session is gone:
		-- the buffer holds a Player reference the sink needs to log with.
		Sink.Forget(player)
		Ingest.Forget(player.UserId)
		Session.End(player)
	end)

	Net.Remote("AnalyticsBeat").OnServerEvent:Connect(Ingest.OnBeat)

	-- One slow loop drives the budget, the coalescing buffer, the stall
	-- detector and the self-report. Deliberately NOT per frame: none of it
	-- resolves faster than seconds, and analytics must never be a frame cost.
	local accumulated = math.huge
	local nextDropReportAt = os.clock() + DROP_REPORT_SECONDS
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < TICK_SECONDS then
			return
		end
		accumulated = 0
		local now = os.clock()
		Sink.Tick(now)
		Session.CheckStalls(now)
		if now >= nextDropReportAt then
			nextDropReportAt = now + DROP_REPORT_SECONDS
			local witness = Players:GetPlayers()[1]
			local lost = Sink.ReportDrops(witness)
			if lost > 0 then
				Log.Warn(
					SCOPE,
					`{lost} event(s) dropped in the last {DROP_REPORT_SECONDS}s — the analytics budget ({Sink.Stats().capacity}/min at this CCU) is saturated; expect undercounts on bulk metrics`
				)
			end
		end
	end)

	Log.Sum(
		SCOPE,
		`instrumentation armed — place '{place}', leg '{AnalyticsConfig.Event(legEvent)}', `
			.. `{#AnalyticsConfig.flowSteps}-step player flow, {Sink.Stats().capacity} events/min budget, `
			.. `{#Players:GetPlayers()} player(s) present`
	)
end

return AnalyticsSubs
