--[[
	TutorialSubs — onboarding domain, server side (R4). features/tutorial.md.

	The server owns exactly ONE fact: has this account finished the guided
	steps. Everything else about the tutorial (which step is showing, where the
	beam points, when the arrow appears) is local UI and lives on the client —
	a round trip per step would buy nothing and cost latency on a flow whose
	whole job is to feel immediate.

	GAME partition: the tutorial only runs in the game place, so the remote
	handler only exists there. The `tutorial` profile SECTION is common
	(src/server/common/data/ProfileSchema) because the lobby loads the same
	profile and must not drop the key.

	TutorialUpdate payload: { done = boolean }  (pushed once, on join)
	TutorialComplete: no arguments — the client says "I finished". Trusting it
	is safe by design (R6 still applies: it is validated): the flag grants
	nothing, it only SUPPRESSES a tutorial. The worst a forged call achieves is
	that the caller never sees the hints again, which the Skip button already
	offers for free.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local TutorialConfig = require(Shared:WaitForChild("config"):WaitForChild("TutorialConfig"))

local SCOPE = "TutorialSubs"

local TutorialSubs = {}

local profileData
local uTutorial
local AnalyticsSubs -- optional retention instrumentation (features/analytics.md)

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load +
-- ClientReady, so the client knows whether to run steps 2-4 before it has
-- rendered anything. The SLIDES do not wait on this — they play regardless.
function TutorialSubs.PushInitialState(player: Player)
	if uTutorial == nil then
		Log.Warn(SCOPE, `PushInitialState({player.Name}) before Start ran — push dropped`)
		return
	end
	local profile = profileData.Get(player.UserId)
	if not profile then
		Log.Warn(SCOPE, `PushInitialState({player.Name}): profile not loaded — push dropped, tutorial stays hidden`)
		return
	end
	local done = profile.tutorial.done == true
	uTutorial:FireClient(player, { done = done })
	Log.Info(SCOPE, `{player.Name}: tutorial done = {done}`)
end

function TutorialSubs.Start(data, services, subscriptions)
	profileData = data.PlayerProfileData
	uTutorial = Net.Update("TutorialUpdate")
	AnalyticsSubs = subscriptions and subscriptions.AnalyticsSubs
	if AnalyticsSubs == nil then
		Log.Warn(SCOPE, "AnalyticsSubs missing -- the tutorial completion beat will not be logged")
	end

	Net.Remote("TutorialComplete").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		local profile = profileData.Get(userId)
		if not profile then
			-- P4: a player can leave (or be mid-teleport-release) between the
			-- last hint and this call. Nothing to write, and nothing is lost —
			-- they simply see the tutorial once more next time.
			-- Keyed Log.Once, not Log.Warn: this is a client-fired remote with
			-- no rate limit, and the profile-nil window is seconds wide during
			-- the lobby→game session handoff — an unthrottled warn here lets a
			-- looping client bury the boot report (same reason CakeSubs uses
			-- `return-preload-{userId}` and BodySubs `gym-preload-{userId}`).
			Log.Once(SCOPE, `tutorial-preload-{userId}`, `TutorialComplete({player.Name}): profile not loaded — flag NOT written`)
			return
		end
		if profile.tutorial.done == true then
			return -- already finished; a re-fire is not an error, just a no-op
		end
		profile.tutorial.done = true
		-- No explicit Save: the section auto-saves while the session is live
		-- (ProfileStore autosave + the final save on leave/shutdown, P4/P5).
		-- Losing this to a crash costs one replayed tutorial, not currency.
		Log.Info(SCOPE, `{player.Name}: tutorial COMPLETE — flag persisted`)
		if AnalyticsSubs then
			local ok, err = pcall(function()
				AnalyticsSubs.Flow(player, TutorialConfig.analyticsBeat)
				AnalyticsSubs.Funnel(player, "tutorial", "done")
				AnalyticsSubs.Event(player, "tutorial-done", 1, nil, { tier = "critical" })
			end)
			if not ok then
				Log.Once(SCOPE, "tutorial-analytics", `tutorial analytics beat FAILED (telemetry only): {err}`)
			end
		end
	end)

	Log.Info(SCOPE, "tutorial completion flag armed (game place)")
end

return TutorialSubs
