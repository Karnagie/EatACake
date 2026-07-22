--[[
	SettingsSubsClient — settings wiring (R4).

	SettingsUpdate (persisted values on join) -> AppRoot state; toggles fire
	SetSetting (optimistic local update — the server write is fire-and-forget
	and validated against the profile section). The window itself is rendered
	by AppRoot (single-root contract) — this module only wires data/effects.

	EFFECT HOOK: apply the actual audio effects (SoundService group volumes)
	in applySetting below, per game.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "SettingsSubsClient"

local SettingsSubsClient = {}

function SettingsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local rSetSetting = Net.Remote("SetSetting")

	-- Seed from defaults: an optimistic toggle BEFORE the server snapshot
	-- must not publish a one-key map (it would render other toggles OFF).
	local values = modules.LocalSettingsService.Defaults()

	local function applySetting(id: string, value: boolean)
		-- EFFECT HOOK (per game): e.g.
		-- if id == "music-enabled" then MusicGroup.Volume = value and 0.5 or 0 end
		Log.Info(SCOPE, `setting '{id}' -> {value}`)
	end

	AppRoot.SetCallbacks({
		onToggleSetting = function(id, value)
			if type(id) ~= "string" then
				return
			end
			value = value == true
			values[id] = value
			AppRoot.Set({ settings = table.clone(values) }) -- optimistic
			applySetting(id, value)
			rSetSetting:FireServer(id, value)
		end,
	})

	Net.Update("SettingsUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.settings) ~= "table" then
			return
		end
		values = {}
		for id, value in pairs(payload.settings) do
			if type(id) == "string" then
				values[id] = value == true
				applySetting(id, values[id])
			end
		end
		AppRoot.Set({ settings = table.clone(values) })
	end)
end

return SettingsSubsClient
