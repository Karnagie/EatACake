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
	-- ⚠ Seconds after a bite during which the walk crunch is MUTED. It plays the
	-- SAME `layer.sfx` sample as the bite itself, and a bite drops the collision
	-- column under you — the settle drift alone clears `minSpeed`, so a single
	-- click fired the bite plus 2 crunches and read as a stuttering burst of bite
	-- sounds (measured in Studio: 1 click -> 4 sound plays, user-reported).
	-- Because a HELD bite refreshes the timestamp at the eat-rate, this also keeps
	-- the crunch quiet for the whole time you are eating — deliberate: while
	-- eating you should hear bites, not footsteps of the same sample. Walking
	-- crunch returns as soon as you stop eating and actually walk.
	biteSuppressSeconds = 0.8,
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

-- FOOD BURST: the celebration confetti (features/food-burst.md). A whole GROUP
-- of food sprites is launched from below the bottom edge of the screen, arcs to
-- roughly mid-screen and falls back off — fired when a layer is cleared and,
-- bigger, when the Cake Monster dies.
--
-- ⚠ Every distance here is in SCREEN HEIGHTS, never pixels: the burst must read
-- identically on a phone and on a 1440p monitor, and a pixel-tuned arc does not
-- (the same 900 px/s launch clears a phone screen and dies halfway up a
-- monitor). `gravity` is therefore screen-heights/s², and apex height follows
-- from it: h = v²/(2g), so `launchApex` picks the arc and the launch speed is
-- DERIVED. Tune the apex, not the speed.
JuiceConfig.foodBurst = {
	-- Hard ceiling on live sprites. Sized for the WORST OVERLAP, not the worst
	-- single burst: `Fire` recycles round-robin, so if two bursts are ever in
	-- the air together a smaller pool would relaunch sprites that are still on
	-- their way up. 88 > 48 + 36, the largest pair.
	poolSize = 88,
	-- Sprites per burst, by celebration KIND. The Cake Monster dying is rarer
	-- and bigger than a layer clear, and the burst has to say so.
	counts = {
		layer = { 22, 28 },
		crumb = { 30, 36 }, -- a zone gate is the mid-tier beat of the three
		monster = { 40, 48 },
	},

	gravity = 2.55, -- screen heights / s²
	-- Apex measured from the LAUNCH point, which is `spawnBelow` under the
	-- bottom edge — so 0.52..0.78 tops out between 57% and 31% down the screen,
	-- i.e. "about halfway up" with enough spread that the wave has a silhouette.
	launchApex = { 0.52, 0.78 },
	spawnBelow = 0.09, -- start this far under the bottom edge (offscreen)
	spawnSpread = { 0.02, 0.98 }, -- X band the launchers fire from (screen fraction)
	stagger = 0.028, -- seconds between consecutive launches -> reads as a WAVE
	staggerJitter = 0.022, -- ...with enough slop that it never looks metronomic

	driftSpeed = 0.30, -- max |horizontal| velocity, screen heights / s
	driftOutward = 0.45, -- 0..1 of the drift that is forced AWAY from centre, so
	-- the burst BLOOMS OPEN instead of the whole wave sliding one way. ⚠ Raising
	-- this spreads the burst WIDER (it was misnamed `driftInward` for one commit
	-- and the comment claimed the opposite of what the code does).
	spinSpeed = { 90, 420 }, -- degrees / s, sign randomised
	-- Sprite height as a fraction of screen height. ⚠ Scaled x1.5 on 2026-08-13
	-- (user request) from {0.052, 0.125}. The offscreen test already keys off
	-- `size`, so bigger sprites simply leave the screen slightly later; nothing
	-- else in the arc depends on this.
	sizeRange = { 0.078, 0.1875 },
	popTime = 0.12, -- scale-in on launch (0 -> full), seconds
	-- Scale-in curve `pop(t) = A*t + (1-A)*t²`, which always lands on exactly 1
	-- at t=1. ⚠ **A must exceed 2 to overshoot AT ALL** — below that the curve is
	-- monotonic and the "pop" is just a slower ramp (1.35 shipped for one commit
	-- and did nothing). Peak = `A² / (4(A-1))`, so 3.1 ≈ 1.15x before settling.
	popOvershoot = 3.1,
	stretch = 0.30, -- squash & stretch amount driven by vertical speed.
	-- ⚠ MUST stay in (0, 1): the factor is `1 + stretch*(speed01-0.5)*2`, so at
	-- 1.0 it hits exactly 0 at the apex and the width divides by zero.
	stretchRefSpeed = 1.7, -- |vy| that counts as "full speed" for the stretch
	-- Half-extent used by the offscreen test, as a multiple of `size`. Bigger
	-- than 0.5 because a stretched sprite is up to 1.3x tall and it is also
	-- SPINNING, so its rotated bounding box reaches further than its own height.
	exitMargin = 0.75,
	fadeBelow = 0.02, -- extra slack before a fully-offscreen sprite is recycled
	maxLifetime = 4.0, -- ⚠ hard backstop: a sprite that somehow never falls
	-- (zero gravity after a bad config edit) must still return to the pool
	maxStep = 1 / 20, -- a hitched frame must not fling the burst off in one step
}

-- The GROUPS the burst draws from. One burst = ONE group, so every celebration
-- reads as a coherent theme ("that was the candy one") instead of food soup.
-- Values are Theme.Icons NAMES, never asset ids — a typo warns through
-- Theme.Icon() instead of silently rendering the fallback glyph.
-- ⚠ Order matters only for the docs; the roll is uniform over the list.
JuiceConfig.foodBurstGroups = {
	{
		id = "orchard", -- apples, stone fruit, berries — the "juicy red" burst
		icons = {
			"FoodApple", "FoodPear", "FoodPeach", "FoodCherry",
			"FoodStrawberry", "FoodRaspberry", "FoodBlueberry", "FoodWatermelon",
		},
	},
	{
		id = "tropical", -- citrus + tropical — the "bright yellow/green" burst
		icons = {
			"FoodBanana", "FoodMango", "FoodPineapple", "FoodKiwi",
			"FoodOrange", "FoodLemon", "FoodAvocado",
		},
	},
	{
		id = "bakery", -- everything baked — the burst that matches the cake itself
		icons = {
			"FoodCake", "FoodCheesecake", "FoodDoughnut",
			"FoodPancakes", "FoodPie", "FoodWaffle",
		},
	},
	{
		id = "candy", -- wrapped sweets, gummies, floss — the loudest, most saturated
		icons = {
			"FoodCandyBlue", "FoodCandyPink", "FoodCandyYellow", "FoodCandyFloss",
			"FoodLollipop", "FoodGummyRed", "FoodGummyGreen", "FoodGummyYellow",
		},
	},
	{
		id = "creamery", -- frozen + creamy. Only four icons, and that is fine: a
		-- burst repeats sprites anyway, and four distinct shapes still read as
		-- one theme at burst speed.
		icons = { "FoodIceCream", "FoodPopsicle", "FoodYogurt", "FoodChocolate" },
	},
}

return JuiceConfig
