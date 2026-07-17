--[[
	SettingsSubs — player settings domain, server side (R4).

	SetSetting(id, value): validates the id against the profile's own
	`core.settings` defaults (the section IS the whitelist — no separate
	list to maintain) and stores the boolean. Values replicate back on join
	via SettingsUpdate so settings survive rejoins.

	SettingsUpdate payload: { settings = { [id: string] = boolean } }.
	Applying the effects (music/sfx volume) is client-side, per game — see
	SettingsSubsClient.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "SettingsSubs"

local SettingsSubs = {}

local profileData
local uSettings

--API
-- Push the persisted settings on join (called by PlayerLifecycleSubs).
function SettingsSubs.SendSettings(player: Player)
	if uSettings == nil then
		Log.Warn(SCOPE, `SendSettings({player.Name}) before Start ran — push dropped`)
		return
	end
	local profile = profileData.Get(player.UserId)
	if not profile then
		Log.Warn(SCOPE, `SendSettings({player.Name}): profile not loaded — push dropped`)
		return
	end
	uSettings:FireClient(player, { settings = profile.core.settings })
end

function SettingsSubs.Start(data, services)
	profileData = data.PlayerProfileData
	uSettings = Net.Update("SettingsUpdate")

	Net.Remote("SetSetting").OnServerEvent:Connect(function(player, id, value)
		if type(id) ~= "string" then
			return
		end
		local profile = profileData.Get(player.UserId)
		if not profile then
			return
		end
		local settings = profile.core.settings
		if settings[id] == nil then
			return -- unknown setting id (the section defaults are the whitelist)
		end
		settings[id] = value == true
	end)
end

return SettingsSubs
