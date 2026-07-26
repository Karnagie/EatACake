--[[
	Teleport.Recovery -- bounded recovery after a committed teleport release.

	ProfileStore session acquisition may retry through a DataStore outage. Each
	player therefore recovers in an independent worker with a hard watchdog and
	an opaque generation token stored in TeleportData. The same token/deadline is
	part of PersistenceService.LoadProfile's StartSessionAsync cancellation, so a
	late worker releases any session it acquires instead of publishing stale state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Teleport"

local Recovery = {}

local function clearHandoff(player: Player, teleportData, persistence)
	player:SetAttribute("Teleporting", nil)
	teleportData.Clear(player)
	persistence.ClearReleaseState(player.UserId)
end

local function kickRecoveryFailure(player: Player, teleportData)
	if player.Parent == Players then
		local message = teleportData["recovery-failure-message"]
		if type(message) ~= "string" then
			Log.Warn(SCOPE, `recovery failure message missing for {player.Name}; using Roblox's default kick copy`)
			player:Kick()
		else
			player:Kick(message)
		end
	end
end

--API
-- Schedules recovery and returns immediately. The caller never waits on a
-- ProfileStore retry, so every member of a failed group begins recovery at once.
function Recovery.Start(player: Player, teleportData, persistence, timeRewards, onRecovered): boolean
	local userId = player.UserId
	if player.Parent ~= Players then
		teleportData.Clear(player)
		persistence.ClearReleaseState(userId)
		return false
	end
	if teleportData["teleporting"][player] ~= true then
		Log.Warn(SCOPE, `recovery refused for {player.Name}: no active handoff`)
		return false
	end
	if persistence.IsLoaded(userId) then
		Log.Info(SCOPE, `recovery skipped for {player.Name}: profile is already loaded`)
		clearHandoff(player, teleportData, persistence)
		return true
	end
	if not persistence.IsReleased(userId) then
		Log.Warn(SCOPE, `recovery refused for {player.Name}: intentional release is not verified`)
		clearHandoff(player, teleportData, persistence)
		kickRecoveryFailure(player, teleportData)
		return false
	end

	local recoveryTokens = teleportData["recovery-tokens"]
	if recoveryTokens[player] ~= nil then
		Log.Info(SCOPE, `recovery already running for {player.Name}`)
		return true
	end
	local timeoutSeconds = teleportData["recovery-timeout-seconds"]
	if type(timeoutSeconds) ~= "number" or timeoutSeconds <= 0 then
		Log.Warn(SCOPE, `recovery refused for {player.Name}: invalid recovery timeout`)
		clearHandoff(player, teleportData, persistence)
		kickRecoveryFailure(player, teleportData)
		return false
	end

	local token = {}
	local deadline = os.clock() + timeoutSeconds
	recoveryTokens[player] = token

	-- StartSessionAsync can be inside a yielding DataStore request when its
	-- Cancel callback's deadline turns true. This independent watchdog makes the
	-- user-visible recovery bound real; the token then cancels the late worker.
	task.delay(timeoutSeconds, function()
		if recoveryTokens[player] ~= token then
			return
		end
		Log.Warn(SCOPE, `profile recovery timed out for {player.Name} after {timeoutSeconds}s; kicking safely released player`)
		clearHandoff(player, teleportData, persistence)
		kickRecoveryFailure(player, teleportData)
	end)

	task.spawn(function()
		local ok, profileOrError = pcall(persistence.LoadProfile, player, {
			deadline = deadline,
			cancel = function()
				return recoveryTokens[player] ~= token
			end,
			kickOnFailure = false,
		})
		if recoveryTokens[player] ~= token then
			if not ok then
				Log.Warn(SCOPE, `stale recovery worker FAILED for {player.Name}: {profileOrError}`)
			end
			return
		end

		local profile = if ok then profileOrError else nil
		if profile ~= nil and player.Parent == Players then
			local sessionOk, sessionError = pcall(timeRewards.BeginSession, userId)
			if not sessionOk then
				Log.Warn(SCOPE, `TimeRewardService.BeginSession FAILED after recovering {player.Name}: {sessionError}`)
			end
			if type(onRecovered) == "function" then
				local pushOk, pushError = pcall(onRecovered, player)
				if not pushOk then
					Log.Warn(SCOPE, `authoritative resync FAILED after recovering {player.Name}: {pushError}`)
				end
			else
				Log.Warn(SCOPE, `authoritative resync callback missing after recovering {player.Name}`)
			end
			Log.Info(SCOPE, `re-acquired profile for {player.Name} after a failed teleport`)
			clearHandoff(player, teleportData, persistence)
			return
		end

		if not ok then
			Log.Warn(SCOPE, `profile recovery FAILED for {player.Name}: {profileOrError}`)
		else
			Log.Warn(SCOPE, `could not re-acquire {player.Name}'s safely released profile`)
		end
		clearHandoff(player, teleportData, persistence)
		kickRecoveryFailure(player, teleportData)
	end)

	Log.Info(SCOPE, `scheduled profile recovery for {player.Name} (deadline {timeoutSeconds}s)`)
	return true
end

return Recovery
