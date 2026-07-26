--[[
	PlayerControlService -- reason-keyed PlayerModule movement gate (R2).

	Subscriptions acquire/release named locks. Movement is enabled only when the
	last lock is released, so independent overlays and teleport handoffs cannot
	race each other's direct Controls:Enable()/Disable() calls.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "PlayerControl"

local PlayerControlService = {}
local playerControlData

function PlayerControlService.Init(data)
	playerControlData = data.PlayerControlData
	if playerControlData == nil then
		Log.Warn(SCOPE, "PlayerControlData missing -- movement locks cannot be coordinated")
	end
end

local function resolveControls()
	if playerControlData.controls ~= nil then
		return playerControlData.controls
	end

	local player_scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local player_module = player_scripts and player_scripts:FindFirstChild("PlayerModule")
	if player_module == nil or not player_module:IsA("ModuleScript") then
		Log.GraceOnce(SCOPE, "player-module-missing", 5, function()
			local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
			return scripts == nil or scripts:FindFirstChild("PlayerModule") == nil
		end, "PlayerScripts.PlayerModule never arrived -- requested movement lock could not be applied")
		return nil
	end

	local ok, player_module_api = pcall(require, player_module)
	if not ok or type(player_module_api) ~= "table" or type(player_module_api.GetControls) ~= "function" then
		Log.Once(SCOPE, "player-module-invalid", `PlayerModule controls unavailable -- requested movement lock could not be applied: {tostring(player_module_api)}`)
		return nil
	end

	local controls_ok, controls = pcall(player_module_api.GetControls, player_module_api)
	if not controls_ok or controls == nil then
		Log.Once(SCOPE, "controls-missing", `PlayerModule:GetControls failed -- requested movement lock could not be applied: {tostring(controls)}`)
		return nil
	end
	playerControlData.controls = controls
	return controls
end

local function hasLocks(): boolean
	return next(playerControlData.locks) ~= nil
end

--API
function PlayerControlService.IsLocked(): boolean
	if playerControlData == nil then
		Log.Warn(SCOPE, "IsLocked failed closed: PlayerControlData was not initialized")
		return true
	end
	return hasLocks()
end

--API
function PlayerControlService.Reconcile()
	if playerControlData == nil then
		Log.Warn(SCOPE, "Reconcile skipped: PlayerControlData was not initialized")
		return
	end

	local should_disable = hasLocks()
	if playerControlData["controls-disabled"] == should_disable then
		return
	end
	local controls = resolveControls()
	if controls == nil then
		return
	end

	local ok, err = pcall(function()
		if should_disable then
			controls:Disable()
		else
			controls:Enable()
		end
	end)
	if not ok then
		Log.Warn(SCOPE, `failed to {if should_disable then "disable" else "enable"} PlayerModule controls -- {err}`)
		return
	end
	playerControlData["controls-disabled"] = should_disable
	Log.Info(SCOPE, `movement {if should_disable then "disabled" else "enabled"} ({if should_disable then "lock active" else "all locks released"})`)
end

--API
function PlayerControlService.SetLocked(reason: string, locked: boolean)
	if playerControlData == nil then
		Log.Warn(SCOPE, `SetLocked('{tostring(reason)}') skipped: PlayerControlData was not initialized`)
		return
	end
	if type(reason) ~= "string" or reason == "" or type(locked) ~= "boolean" then
		Log.Warn(SCOPE, `SetLocked received invalid reason/state ('{tostring(reason)}', {tostring(locked)})`)
		return
	end

	if locked then
		playerControlData.locks[reason] = true
	else
		playerControlData.locks[reason] = nil
	end
	PlayerControlService.Reconcile()
end

--API
function PlayerControlService.Refresh()
	if playerControlData == nil then
		Log.Warn(SCOPE, "Refresh skipped: PlayerControlData was not initialized")
		return
	end
	playerControlData.controls = nil
	playerControlData["controls-disabled"] = false
	PlayerControlService.Reconcile()
end

return PlayerControlService
