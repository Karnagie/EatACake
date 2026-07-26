--[[
	AudioSubsClient — the audio layer's wiring (R4). Runs in BOTH places.

	  * injects the kit's click/hover sound handler (UIKit.SetSoundHandler) —
	    one hook gives every kit button in the game press + hover feedback
	  * turns AppRoot's `onPanelChanged` into the panel open/close whoosh
	  * drives MusicService.Step every frame (playlist advance + fades)

	It owns no state and no volumes: cues map to samples in AudioConfig, the
	mute toggles live in SettingsSubsClient. Feature doc: docs/features/audio.md.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local SCOPE = "AudioSubsClient"

-- Kit interaction cue -> AudioConfig.sounds key.
local KIT_CUES = {
	press = "uiClick",
	hover = "uiHover",
}

local AudioSubsClient = {}

function AudioSubsClient.Start(data, modules)
	local SoundPool = modules.SoundPool
	local MusicService = modules.MusicService
	local AppRoot = modules.AppRoot

	-- SFX and MUSIC are wired independently: an early return here used to take
	-- the music step down with the SFX wiring while the console only mentioned
	-- sound effects (R8 — the log must let you answer what was skipped and why).
	if SoundPool == nil then
		Log.Warn(SCOPE, "SoundPool module missing — NO sound effects (music is wired separately below)")
	elseif type(UIKit.SetSoundHandler) == "function" then
		UIKit.SetSoundHandler(function(cue: string)
			local key = KIT_CUES[cue]
			if key == nil then
				Log.Once(SCOPE, `kit-cue-{cue}`, `kit emitted unknown interaction cue '{cue}' — add it to KIT_CUES`)
				return
			end
			SoundPool.Play(key)
		end)
		Log.Info(SCOPE, "kit interaction sounds wired (press + hover)")
	else
		Log.Warn(SCOPE, "UIKit.SetSoundHandler missing — kit buttons will be silent (stale UIKit?)")
	end

	-- Panel whoosh. AppRoot fires this only on a real change, never on mount.
	if AppRoot ~= nil and SoundPool ~= nil then
		AppRoot.SetCallbacks({
			onPanelChanged = function(panel: string?)
				SoundPool.Play(if panel ~= nil then "uiOpen" else "uiClose")
			end,
		})
	elseif AppRoot == nil then
		Log.Warn(SCOPE, "AppRoot module missing — panel open/close sounds disabled")
	end

	if MusicService == nil then
		Log.Warn(SCOPE, "MusicService module missing — the game will have NO music")
		return
	end
	RunService.Heartbeat:Connect(function(dt)
		MusicService.Step(dt)
	end)
	Log.Info(SCOPE, "music playlist stepping")
end

return AudioSubsClient
