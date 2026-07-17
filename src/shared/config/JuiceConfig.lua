--[[
	JuiceConfig — every ASMR/juice tuning number (GDD §7). Client-only
	consumers (SoundPool, ParticlePool, CameraShake, Combo, Squish).

	⚠ Sound ids are rbxasset:// BUILT-INS as guaranteed-to-play placeholders.
	Replace with uploaded close-mic'd ASMR samples before release — keys stay,
	only the ids change. Layer sfx keys come from CakeConfig.layers[*].sfx.
]]

local JuiceConfig = {}

JuiceConfig.sounds = {
	-- key = { id, volume, basePitch }; pitch is randomized ±pitchJitter
	squish = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.5, pitch = 1.1 },
	crumble = { id = "rbxasset://sounds/splat.mp3", volume = 0.45, pitch = 1.0 },
	crack = { id = "rbxasset://sounds/snap.mp3", volume = 0.7, pitch = 0.9 },
	blorp = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.55, pitch = 0.7 },
	pshhh = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.4, pitch = 1.3 },
	stretch = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.5, pitch = 0.5 },
	shhh = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.35, pitch = 0.8 },
	slumpLoop = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.0, pitch = 0.6 }, -- granular loop, volume driven by avalanche volume
	gymWhoosh = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.7, pitch = 1.0 },
	coinBurst = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, pitch = 1.2 },
	uiClick = { id = "rbxasset://sounds/button.wav", volume = 0.4, pitch = 1.0 },
	fanfare = { id = "rbxasset://sounds/victory.wav", volume = 0.7, pitch = 1.0 },
	crustCrack = { id = "rbxasset://sounds/snap.mp3", volume = 0.9, pitch = 0.7 },
}
JuiceConfig.soundPoolSize = 16 -- hard cap, GDD §14
JuiceConfig.pitchJitter = 0.1 -- ±10%
-- Combo raises bite pitch: pitch * (1 + comboPitchPerStep * (combo - 1))
JuiceConfig.comboPitchPerStep = 0.04
-- Slump loop: volume = clamp(avalanche studs³ / slumpVolumeDiv, 0, slumpMaxVolume),
-- peak-held and decayed at slumpDecayPerSecond.
JuiceConfig.slumpVolumeDiv = 60
JuiceConfig.slumpMaxVolume = 0.6
JuiceConfig.slumpDecayPerSecond = 0.8

JuiceConfig.particles = {
	maxActive = 200, -- pooled emit budget, GDD §14
	emitterPoolSize = 12, -- pooled emitter-parts (created once at Init)
	crumbsPerBite = 6,
	shardsPerCrack = 12, -- chocolate shatter / frosting crust
	coinsPerGymBurn = 14,
}

JuiceConfig.camera = {
	biteShakeAmp = 0.12, -- studs, scaled by bite size
	crustCrackAmp = 0.5,
	maxAmp = 0.7,
	traumaDecayPerSecond = 2.2,
}

JuiceConfig.combo = {
	max = 10,
	growEvery = 2, -- +1 step per 2 s of continuous eating
	resetAfter = 1.5, -- pause > 1.5 s resets
}

-- Underfoot squish (§7.2): visual-only, local-only, client-only.
JuiceConfig.squish = {
	depth = 0.7, -- studs of dent under the character (reference: butter dents)
	radius = 3.2, -- studs
	recover = 0.3, -- seconds to spring back
}

-- Flying bite chunks ("chunk ripped out" feel): pooled physical crumbs.
JuiceConfig.chunks = {
	poolSize = 14,
	perBite = 2, -- + combo intensity adds up to +2
	sizeMin = 0.9,
	sizeMax = 1.8,
	upSpeedMin = 16,
	upSpeedMax = 26,
	sideSpeed = 10,
	lifetime = 1.2,
}

-- Walk crunch (§7.2 "the cake feels alive"): footstep-cadence crust sounds
-- + tiny crumb puffs while moving on the cake.
JuiceConfig.walkCrunch = {
	interval = 0.38, -- seconds between crunches at walk cadence
	minSpeed = 4, -- studs/s of horizontal velocity to count as walking
	volumeMult = 0.35,
	pitchMult = 1.15,
	particles = 2,
}

JuiceConfig.floatingNumbers = {
	lifetime = 0.8,
	riseStuds = 4,
	baseTextSize = 22,
	maxTextSize = 42, -- scales with combo
	poolSize = 24,
}

-- Squash & stretch on the character per bite (§7.3).
JuiceConfig.squash = {
	compress = 0.92, -- Y scale at impact
	time = 0.12,
}

return JuiceConfig
