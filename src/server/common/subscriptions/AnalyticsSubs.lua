--[[
	AnalyticsSubs — the retention instrumentation (R4: the ONE place that talks
	to AnalyticsService).

	Retention is a fact about players, not about the build, so it cannot be
	measured offline — but it CAN be made visible, and an onboarding funnel is
	the single highest-signal way to find where first-session players fall out.
	This module owns:

	  * the ONBOARDING FUNNEL — the first-session beats in order, logged once per
	    player per step (`LogOnboardingFunnelStepEvent`). Roblox reports these
	    against D1/D7 retention directly in the Creator Dashboard.
	  * TIME PER PLACE LEG on leave (`place_minutes_lobby` / `place_minutes_game`).
	  * a small set of loop counters so the funnel has denominators.

	⚠ A LEG IS NOT A SESSION. This game is two places (ADR-0009) and every
	lobby↔game teleport ends the player on THIS server and starts a fresh one on
	the next — so a per-server timer can only ever measure one leg, and naming it
	`session_minutes` would report a 30-minute session as e.g. "3 + 26". The legs
	are logged SEPARATELY and honestly: `place_minutes_game` is the number the
	30-minute engagement target actually lives on (lobby time is queue overhead,
	not play), and Roblox's own built-in engagement metric already reports true
	cross-place session length for the universe — do not rebuild it here.

	Other subscriptions push beats in through the registry (`subscriptions
	.AnalyticsSubs`, the ADR-0009 coupling pattern) — this module never reaches
	into a domain itself.

	⚠ Every call is pcall-wrapped and no-ops in Studio: AnalyticsService throws
	when the place is unpublished, and a telemetry failure must never take a
	gameplay path down with it (R8 — it warns ONCE and stays quiet after).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local PlaceConfig = require(Shared:WaitForChild("config"):WaitForChild("PlaceConfig"))

local SCOPE = "Analytics"

local AnalyticsSubs = {}

-- The first-session beats, in the order a healthy player hits them. Step 1 is
-- the join itself; anything a player never reaches is where onboarding leaks.
local ONBOARDING = {
	joined = { step = 1, name = "Joined" },
	firstBite = { step = 2, name = "First Bite" },
	firstFind = { step = 3, name = "First Find Collected" },
	firstLayer = { step = 4, name = "First Layer Cleared" },
	firstGym = { step = 5, name = "First Fat Burned" },
	firstUpgrade = { step = 6, name = "First Upgrade Bought" },
}

local joinedAt: { [number]: number } = {}
local reached: { [number]: { [string]: boolean } } = {}
local disabled = false

local function safe(what: string, fn: () -> ())
	if disabled then
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		-- Unpublished places throw on every call; one warn, then silence.
		disabled = true
		Log.Warn(SCOPE, `AnalyticsService unavailable ({what}: {err}) — telemetry OFF for this server (expected in Studio / unpublished places)`)
	end
end

--API
-- Records an onboarding beat ONCE per player. `key` must be a field of the
-- ONBOARDING table above; an unknown key warns rather than silently vanishing.
function AnalyticsSubs.Onboard(player: Player, key: string)
	local beat = ONBOARDING[key]
	if beat == nil then
		Log.Once(SCOPE, `bad-beat-{key}`, `unknown onboarding beat '{key}' — not logged (add it to ONBOARDING)`)
		return
	end
	local seen = reached[player.UserId]
	if seen == nil or seen[key] then
		return
	end
	seen[key] = true
	safe(`onboarding {key}`, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, beat.step, beat.name)
	end)
	Log.Info(SCOPE, `{player.Name}: onboarding {beat.step} '{beat.name}'`)
end

--API
-- A loop counter (finds collected, layers cleared, cakes finished…). These give
-- the funnel its denominators — "reached step 3" means little without "how many
-- finds does a retained player dig in session one".
function AnalyticsSubs.Count(player: Player, eventName: string, value: number?)
	safe(`custom {eventName}`, function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1)
	end)
end

function AnalyticsSubs.Start(_data, _services)
	-- Which leg this server IS, resolved once. "unknown" (place ids unset) still
	-- logs — a bucket named for the gap is more useful than a silent drop.
	local legEvent = `place_minutes_{PlaceConfig.current()}`

	local function onJoin(player: Player)
		-- os.time(), NOT os.clock(): Roblox documents os.clock() as CPU time used
		-- by Lua, so on a mostly-idle server it can run well behind wall time and
		-- would UNDER-report the metric. Whole seconds is ample for a minutes stat.
		joinedAt[player.UserId] = os.time()
		reached[player.UserId] = {}
		AnalyticsSubs.Onboard(player, "joined")
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onJoin(player) -- a sub can Start after the first player is already in
	end
	Players.PlayerAdded:Connect(onJoin)

	Players.PlayerRemoving:Connect(function(player)
		local started = joinedAt[player.UserId]
		joinedAt[player.UserId] = nil
		reached[player.UserId] = nil
		if started == nil then
			return
		end
		local minutes = (os.time() - started) / 60
		-- Rounded to a tenth so the dashboard buckets stay readable. This is ONE
		-- LEG (see the header) — sum the game legs, don't read it as a session.
		AnalyticsSubs.Count(player, legEvent, math.floor(minutes * 10) / 10)
		local handoff = player:GetAttribute("Teleporting") == true and " (teleporting out)" or ""
		Log.Info(SCOPE, `{player.Name}: {legEvent} {string.format("%.1f", minutes)}{handoff}`)
	end)

	local beats = 0
	for _ in pairs(ONBOARDING) do
		beats += 1
	end
	Log.Sum(SCOPE, `retention instrumentation armed — leg '{legEvent}', {#Players:GetPlayers()} present, {beats} onboarding beats`)
end

return AnalyticsSubs
