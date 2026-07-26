--[[
	TeleportControlSubsClient -- freezes local movement during profile-safe
	cross-place handoff (R4). TeleportSubs owns the server-written Teleporting
	attribute; this subscription mirrors it into the shared reason-keyed control
	gate and restores controls if the handoff recovers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "TeleportControl"

local TeleportControlSubsClient = {}

function TeleportControlSubsClient.Start(data, modules)
	local control_data = data.PlayerControlData
	local control_service = modules.PlayerControlService
	local SoundPool = modules.SoundPool
	if control_data == nil or control_service == nil or type(control_service.SetLocked) ~= "function" then
		Log.Warn(SCOPE, "PlayerControlData/PlayerControlService missing -- teleport movement freeze skipped")
		return
	end

	local attribute_name = control_data["teleport-attribute"]
	local reason = control_data.reasons and control_data.reasons.teleport
	if type(attribute_name) ~= "string" or attribute_name == "" or type(reason) ~= "string" or reason == "" then
		Log.Warn(SCOPE, "teleport attribute/reason config invalid -- teleport movement freeze skipped")
		return
	end

	local player = Players.LocalPlayer
	local locked = false
	local function sync()
		local now_locked = player:GetAttribute(attribute_name) == true
		-- Rising edge only: the handoff whoosh belongs to the moment controls
		-- freeze, and TeleportSubs may re-write the attribute during retries.
		if now_locked and not locked and SoundPool then
			SoundPool.Play("matchStart")
		end
		locked = now_locked
		control_service.SetLocked(reason, now_locked)
	end

	player:GetAttributeChangedSignal(attribute_name):Connect(sync)
	player.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "PlayerModule" and descendant:IsA("ModuleScript") then
			control_service.Reconcile()
		end
	end)
	player.CharacterAdded:Connect(function()
		if type(control_service.Refresh) == "function" then
			control_service.Refresh()
		else
			Log.Warn(SCOPE, "PlayerControlService.Refresh missing -- respawn control state could not be reconciled")
		end
	end)
	sync()
end

return TeleportControlSubsClient
