--[[
	SettingsSubsClient — settings wiring (R4).

	SettingsUpdate (persisted values on join) -> AppRoot state; toggles fire
	SetSetting (optimistic local update — the server write is fire-and-forget
	and validated against the profile section). The window itself is rendered
	by AppRoot (single-root contract) — this module only wires data/effects.

	EFFECT HOOK: `applySetting` below is where a toggle becomes real behaviour.
	Today it drives the audio layer — `music-enabled` gates the background
	playlist (MusicService), `sfx-enabled` mutes the SFX SoundGroup
	(SoundPool). Both are idempotent, so replaying the whole map on every
	SettingsUpdate is safe. Feature docs: settings.md, audio.md.

	The FIRST `music-enabled` apply also releases MusicService's start gate, so
	a player who saved "music off" never hears a note (audio.md, first-note
	contract) — do not make this call conditional on the value changing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "SettingsSubsClient"

local SettingsSubsClient = {}

function SettingsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local MusicService = modules.MusicService
	local rSetSetting = Net.Remote("SetSetting")

	-- Seed from defaults: an optimistic toggle BEFORE the server snapshot
	-- must not publish a one-key map (it would render other toggles OFF).
	local values = modules.LocalSettingsService.Defaults()

	local function applySetting(id: string, value: boolean)
		if id == "music-enabled" then
			if MusicService == nil then
				Log.Once(SCOPE, "no-music-service", "MusicService missing — the music toggle does nothing")
				return
			end
			MusicService.SetEnabled(value)
		elseif id == "sfx-enabled" then
			if SoundPool == nil then
				Log.Once(SCOPE, "no-sound-pool", "SoundPool missing — the SFX toggle does nothing")
				return
			end
			SoundPool.SetEnabled(value)
		else
			-- A setting with no effect is a half-built feature, not a no-op.
			Log.Once(SCOPE, `no-effect-{id}`, `setting '{id}' has no effect hook in SettingsSubsClient — it persists but changes nothing`)
			return
		end
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
