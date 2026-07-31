--[[
	RunResetSubs — wipes RUN-SCOPED progression on every profile load (ADR-0013).

	The upgrade tree and the spendable calorie balance are per-RUN, not permanent
	meta: you start a cake as a base eater and buy the whole tree back inside that
	cake (UpgradeConfig.run, features/upgrades.md). "Every profile load" covers
	both halves of the user's rule — entering the LOBBY and starting a new
	cake-eating RUN — because the lobby↔game handoff releases and reloads the
	profile on each teleport (ADR-0009), and a direct join loads it once.

	RESET:   upgrades.levels (all tiers -> 0), economy.calories, stomach
	         fill/stored, any open gym session.
	SURVIVES: gems, squishies (pets.owned/equipped), daily rewards, shop
	         purchases + gamepass ownership, timed boosts, and every
	         progress.lifetime* stat (the leaderboard reads
	         progress.lifetimeCalories, NOT economy.calories).

	R3/R4: this is a subscription, so it may orchestrate several services; it owns
	no state and no tuning (the flags live in UpgradeConfig.run).

	⚠ Runs from the OnProfileLoaded hook, not PushInitialState. Push hooks fire in
	alphabetical order, so resetting from one would race EconomySubs/UpgradeSubs
	(both sort earlier) and the client would be told the pre-reset values with no
	later correction. OnProfileLoaded is guaranteed to run before any push
	(PlayerLifecycleSubs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "RunResetSubs"

local RunResetSubs = {}

local services_
local runCfg

--API
-- Profile-load hook (PlayerLifecycleSubs). Nothing has been replicated yet, so
-- every domain's PushInitialState later sends the already-reset values.
function RunResetSubs.OnProfileLoaded(player: Player)
	if services_ == nil or runCfg == nil then
		Log.Warn(SCOPE, `OnProfileLoaded({player.Name}) before Start ran — run state NOT reset (the player keeps last run's upgrades)`)
		return
	end
	if runCfg.resetOnLoad ~= true then
		return -- opt-out: permanent-meta progression (UpgradeConfig.run)
	end
	local userId = player.UserId
	if not services_.PersistenceService.IsLoaded(userId) then
		Log.Warn(SCOPE, `{player.Name}: profile not loaded at OnProfileLoaded — run state NOT reset`)
		return
	end

	local tiersCleared = services_.UpgradeService.ResetTiers(userId)
	local spent = services_.EconomyService.GetCalories(userId) or 0
	local caloriesCleared = services_.EconomyService.ResetCalories(userId) ~= nil
	local bellyCleared = true
	if runCfg.resetBelly == true then
		-- An open gym session captured a baseline from the OLD belly; leaving it
		-- live would drain against numbers that no longer exist.
		if services_.GymService ~= nil then
			services_.GymService.EndSession(userId)
		end
		bellyCleared = services_.StomachService.SetBelly(userId, 0, 0)
	end

	if not (tiersCleared and caloriesCleared and bellyCleared) then
		Log.Warn(
			SCOPE,
			`{player.Name}: run reset INCOMPLETE (tiers={tiersCleared}, calories={caloriesCleared}, belly={bellyCleared}) `
				.. `— they may start this run with leftover power`
		)
		return
	end
	Log.Info(SCOPE, `{player.Name}: run state reset (tiers -> 0, {math.floor(spent)} calories cleared, belly emptied)`)
end

function RunResetSubs.Start(data, services)
	services_ = services
	runCfg = data.CakeConfigData and data.CakeConfigData.upgrades and data.CakeConfigData.upgrades.run
	if runCfg == nil then
		Log.Warn(SCOPE, "UpgradeConfig.run missing — run-scoped reset disabled (upgrades would persist across runs)")
		return
	end
	if services.UpgradeService == nil
		or services.EconomyService == nil
		or services.StomachService == nil
		or services.PersistenceService == nil
	then
		Log.Warn(SCOPE, "UpgradeService/EconomyService/StomachService/PersistenceService missing — run-scoped reset disabled")
		runCfg = nil
		return
	end
	if services.GymService == nil then
		-- Expected in the LOBBY partition: there is no gym there, so there can be
		-- no open session to end.
		Log.Info(SCOPE, "GymService absent (lobby partition) — no gym session to end on reset")
	end
	Log.Info(
		SCOPE,
		`armed: resetOnLoad={runCfg.resetOnLoad}, resetBelly={runCfg.resetBelly} (run-scoped progression, ADR-0013)`
	)
end

return RunResetSubs
