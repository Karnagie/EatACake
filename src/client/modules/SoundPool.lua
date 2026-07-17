--[[
	SoundPool — pooled 2D SFX (GDD §7.7): 16 Sound instances created ONCE
	at Init, zero Instance.new in hot paths. Pitch randomized ±10%, combo
	raises bite pitch. One dedicated looping granular slump channel whose
	volume follows avalanche energy (§7.4 — the game's signature sound).

	Keys/ids/volumes live in JuiceConfig.sounds (placeholder rbxasset ids).
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local SoundPool = {}

local pool: { Sound } = {}
local cursor = 1
local slumpLoop: Sound?
local slumpTargetVolume = 0

function SoundPool.Init()
	local group = Instance.new("SoundGroup")
	group.Name = "GameSfx"
	group.Parent = SoundService

	for k = 1, JuiceConfig.soundPoolSize do
		local sound = Instance.new("Sound")
		sound.Name = `Pooled_{k}`
		sound.SoundGroup = group
		sound.Parent = SoundService
		table.insert(pool, sound)
	end

	local loopCfg = JuiceConfig.sounds.slumpLoop
	slumpLoop = Instance.new("Sound")
	slumpLoop.Name = "SlumpLoop"
	slumpLoop.SoundId = loopCfg.id
	slumpLoop.Volume = 0
	slumpLoop.PlaybackSpeed = loopCfg.pitch
	slumpLoop.Looped = true
	slumpLoop.SoundGroup = group
	slumpLoop.Parent = SoundService
	slumpLoop:Play()
end

--API
-- Plays a JuiceConfig.sounds key. opts: { pitchMult, volumeMult }.
function SoundPool.Play(key: string, opts: { pitchMult: number?, volumeMult: number? }?)
	local def = JuiceConfig.sounds[key]
	if not def then
		Log.Once("SoundPool", `no-sound-{key}`, `unknown sound key '{key}' — check JuiceConfig.sounds`)
		return
	end
	local sound = pool[cursor]
	cursor = cursor % #pool + 1
	local jitter = 1 + (math.random() * 2 - 1) * JuiceConfig.pitchJitter
	sound:Stop()
	sound.SoundId = def.id
	sound.Volume = def.volume * ((opts and opts.volumeMult) or 1)
	sound.PlaybackSpeed = def.pitch * jitter * ((opts and opts.pitchMult) or 1)
	sound:Play()
end

--API
-- Bite SFX with the combo pitch ramp (§7.5).
function SoundPool.PlayBite(key: string, combo: number)
	SoundPool.Play(key, { pitchMult = 1 + JuiceConfig.comboPitchPerStep * math.max(0, combo - 1) })
end

--API
-- Feeds avalanche energy (studs³) into the granular loop volume.
-- Peak-hold: deltas arrive at ~12 Hz while this is called every frame with
-- mostly-zero energy — overwriting would starve the loop to silence.
function SoundPool.PushSlumpEnergy(studs3: number)
	if studs3 > 0 then
		slumpTargetVolume = math.max(
			slumpTargetVolume,
			math.clamp(studs3 / JuiceConfig.slumpVolumeDiv, 0, JuiceConfig.slumpMaxVolume)
		)
	end
end

--API
-- Per-frame decay/lerp of the slump loop (called by CakeSubsClient).
function SoundPool.Step(dt: number)
	if slumpLoop then
		local v = slumpLoop.Volume
		slumpLoop.Volume = v + (slumpTargetVolume - v) * math.min(1, dt * 6)
		slumpTargetVolume = math.max(0, slumpTargetVolume - dt * JuiceConfig.slumpDecayPerSecond)
	end
end

return SoundPool
