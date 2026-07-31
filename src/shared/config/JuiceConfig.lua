--[[
	JuiceConfig — the non-audio ASMR/juice tuning numbers (GDD §7): particles,
	camera shake, combo, squish, chunks, walk cadence. Client-only consumers
	(ParticlePool, CameraShake, ComboMeter, ChunkDebris, CakeRenderer).

	SOUND LIVES IN `AudioConfig` (docs/features/audio.md) — sample map, pool,
	pitch jitter, combo pitch ramp and the slump-loop response all moved there
	when the game got its real audio layer. Layer sfx keys (CakeConfig.layers
	[*].sfx) index `AudioConfig.sounds`, not this file.
]]

local JuiceConfig = {}

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

-- FIND GLINT: a shimmer on the cake SURFACE above a nearly-uncovered buried
-- find (features/treasures.md). It marks the SPOT, never the item — showing
-- the item through cake would be an x-ray and would delete the dig. Slow and
-- small on purpose: a tell, not a firework.
JuiceConfig.findGlint = {
	interval = 0.45, -- seconds between shimmers per marker pass
	particles = 4,
	liftStuds = 0.6, -- just above the icing so it reads as ON the surface
	maxMarkers = 4, -- a swept layer can expose many at once; keep the budget sane
}

return JuiceConfig
