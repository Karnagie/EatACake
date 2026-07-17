--[[
	CakeConfig — the single source of tuning for the cake heightfield,
	its layers, composition rolls and the cake cycle (GDD §4, §5, §9).

	Pure data, shared by both sides:
	  server — simulation (repose/flowRate/hardness), composition rolls,
	           cycle timings, calories
	  client — rendering (colors), SFX keys, wobble/FX flags

	NO logic here. All numbers are starting values for tuning, never law.
	Heights are stored as u16 fixed-point: 1 unit = 0.01 studs (see GridUtil).
]]

local CakeConfig = {}

-- ── Grid ────────────────────────────────────────────────────────────────
CakeConfig.grid = {
	size = 64, -- 64x64 cells
	cell = 1.5, -- studs per cell -> 96x96 stud field
	maxHeight = 70, -- studs, hard ceiling (u16 easily covers it)
	-- World placement: bottom of the cake sits at this Y; grid is centered
	-- on origin XZ. MapService builds the platform to match.
	origin = { x = 0, y = 2, z = 0 },
}

-- ── Simulation (server) ─────────────────────────────────────────────────
CakeConfig.sim = {
	settleHz = 20, -- cellular-automaton tick rate
	settleBudget = 1500, -- MAX cells processed per settle tick (GDD §14)
	moveFactor = 0.35, -- fraction of the over-repose delta moved per relax (slow ooze)
	-- The BITE FEEL: the crater rips out instantly, then after this pause
	-- the crater walls start slowly flowing back in (like a real bite).
	settleDelayAfterBite = 0.7,
	-- Auto-sweep (§7.6): when the volume remaining in the current top band
	-- falls below this fraction of the band's initial volume, the tail
	-- collapses to the band floor. Never make the player hunt crumbs.
	autoSweepFraction = 0.1,
	statsScanHz = 1, -- full-field scan for progress % / auto-sweep
}

-- ── Networking (server -> client) ───────────────────────────────────────
CakeConfig.net = {
	syncHz = 12, -- delta flush rate
	-- ⚠ UnreliableRemoteEvent payloads over ~900 bytes are DROPPED by the
	-- engine. Each packet must stay under it: (maxCellsPerPacket +
	-- repairCellsPerPacket) * 4 bytes + envelope <= ~900. Backlogs drain via
	-- several packets per flush (maxPacketsPerFlush) instead of bigger ones.
	maxCellsPerPacket = 150,
	maxPacketsPerFlush = 3, -- burst drain: up to 450 dirty cells per tick
	-- Self-heal for packet loss: the FIRST packet of every flush also
	-- carries this many cells from a rotating cursor over the whole field
	-- (full sweep ≈ 4096 / (40 * 12 Hz) ≈ 9 s).
	repairCellsPerPacket = 40,
	collisionHz = 5, -- server collision grid update rate
	-- Server-side safety grid only (16x16 = 256 parts, 6-stud blocks).
	-- PRECISE walking collision is the client renderer's columns
	-- (CanCollide, 1 column = 2x2 cells) — the 8x8 averaged slabs left
	-- players waist-deep in the visual cake.
	collisionGrid = 16,
}

-- ── Client rendering (GDD §4.5) ─────────────────────────────────────────
CakeConfig.render = {
	-- EditableMesh is THE renderer: ONE MeshPart PER LAYER BAND (clamped
	-- heightfield slabs) so every layer carries its own material,
	-- transparency and reflectance, plus a thin textured CRUST band on top
	-- of each layer that cracks under players' feet. The part grid stays as
	-- the no-EditableMesh fallback. Invisible collision columns always exist.
	forceFallback = false,
	lerpSpeed = 3.5, -- 1/s display approach fallback (layers override via oozeSpeed)
	-- Bite feel: a target DROP bigger than this snaps instantly (the chunk
	-- is ripped out); smaller moves and refills ooze at the layer's oozeSpeed.
	snapDropStuds = 0.4,
	-- Crunchy crust between layers (reference: the butter-stick skin): a
	-- thin visual-only band at the TOP of every edible layer, lighter and
	-- glossier than the layer, textured so footstep cracks can be drawn in.
	crust = {
		depth = 0.7, -- studs of skin at the top of each edible layer
		lighten = 0.4, -- toward white from the layer's top color
		gloss = 0.3,
		imageSize = 256, -- crust texture (XZ-planar over the whole grid)
		noise = 0.06, -- subtle per-pixel mottling of the crust base fill
	},
	-- Footstep / landing cracks drawn INTO the crust texture (persist until
	-- the next cake). Lengths in studs, converted to texture pixels.
	cracks = {
		darken = 0.55, -- crack line color = crust color toward black
		landLines = { 4, 6 }, -- radial polylines on a landing crack
		landLength = { 3.5, 6 },
		stepLines = { 2, 3 }, -- smaller cracks while walking
		stepLength = { 1.2, 2.6 },
		stepChance = 0.6, -- chance per crunchy footstep to leave a crack
		segmentStuds = 0.9, -- polyline segment length
		jitter = 0.55, -- radians of direction wander per segment
	},
	boundaryBlend = 2, -- studs of color blend across band boundaries
	paletteStep = 0.25, -- studs per palette entry
	-- Jelly wobble (§5): pure renderer sine, zero sim cost.
	wobbleAmp = 0.18, -- studs
	wobbleSpeed = 5,
	wobbleSliceDiv = 10, -- 1/N of vertices refreshed per frame while wobbling
	-- Fallback part-grid renderer (§4.5): 32x32 columns over the field,
	-- styled as a juicy "keycap" grid (reference look): visible grooves
	-- between glossy columns, per-column shade jitter, walkable 1:1.
	fallbackGrid = 32,
	fallback = {
		gap = 0.35, -- studs of dark groove between columns
		colorJitter = 0.10, -- ±lightness per column (deterministic noise)
		minVisibleHeight = 0.05,
	},
	-- Rare-cake tints (renderer): saturated butter-gold, not washed beige.
	goldenTint = { color = Color3.fromRGB(255, 200, 45), alpha = 0.5 },
	rainbowTintAlpha = 0.6,
}

-- ── Layers (GDD §5) ─────────────────────────────────────────────────────
-- Every layer is ONE dedicated mesh on the client and must FEEL unique.
-- Simulation (server):
--   repose: max height delta (studs) a cell tolerates before flowing
--           (math.huge = solid, never flows).
--   flowRate: fraction of the excess moved per relaxation.
--   hardness: time-to-eat multiplier (bite depth is divided by it).
--   calories: calories per stud^3 removed.
--   walkSpeedMult: authoritative WalkSpeed mult while standing on it (BodySubs).
-- Rendering (client, per-layer MeshPart):
--   colors: top/bottom (body mesh uses a blend; crust lightens .top).
--   material: Enum.Material of the layer's MeshPart.
--   transparency: MeshPart.Transparency (see-through marmalade!).
--   gloss: Part.Reflectance (wet/juicy look; also fallback columns).
--   oozeSpeed: 1/s visual lerp toward server truth — HOW FAST the layer
--              visibly flows (honey creep vs liquid avalanche).
--   squishMult: underfoot dent depth multiplier (0 = rock hard).
--   wobble: renderer sine over the layer's vertices (jelly jiggle).
-- Feel (client, CakeFeelSubsClient):
--   jumpMult: jump power mult while standing on the layer.
--   bounce: landing restitution 0..1 (trampoline layers).
-- sfx: key into JuiceConfig.sounds for bite/slump sounds.
CakeConfig.layers = {
	frosting = {
		id = "frosting",
		-- soft pillow: deep dents, medium flow
		repose = 1.5,
		flowRate = 0.6,
		hardness = 0.5,
		calories = 1.2,
		colors = { top = Color3.fromRGB(255, 182, 220), bottom = Color3.fromRGB(246, 148, 196) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		gloss = 0.08,
		oozeSpeed = 4,
		squishMult = 1.6,
		jumpMult = 1,
		sfx = "squish",
		shatterFx = false,
		wobble = false,
	},
	sponge = {
		id = "sponge",
		-- TRAMPOLINE: springy pores — you jump way higher and bounce on landing
		repose = 3.0,
		flowRate = 0.35,
		hardness = 1.0,
		calories = 1.0,
		colors = { top = Color3.fromRGB(250, 198, 95), bottom = Color3.fromRGB(226, 168, 70) },
		material = Enum.Material.Sand, -- grainy crumb pores
		transparency = 0,
		gloss = 0.02,
		oozeSpeed = 2.5,
		squishMult = 1.0,
		jumpMult = 1.9,
		bounce = 0.55, -- landing restitution: boing
		sfx = "crumble",
		shatterFx = false,
		wobble = false,
	},
	chocolate = {
		id = "chocolate",
		-- hard shell: cliffs, never flows, no dents, shatters when bitten
		repose = math.huge,
		flowRate = 0,
		hardness = 3.0,
		calories = 2.0,
		colors = { top = Color3.fromRGB(96, 58, 34), bottom = Color3.fromRGB(66, 38, 22) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		gloss = 0.15,
		oozeSpeed = 12, -- nothing flows anyway; bite edits snap
		squishMult = 0,
		jumpMult = 1,
		sfx = "crack",
		shatterFx = true, -- client: shard burst on bite
		wobble = false,
	},
	jelly = {
		id = "jelly",
		-- SEE-THROUGH MARMALADE: translucent, jiggles, springy underfoot
		repose = 4.5,
		flowRate = 0.2,
		hardness = 1.5,
		calories = 1.4,
		colors = { top = Color3.fromRGB(238, 58, 88), bottom = Color3.fromRGB(196, 30, 62) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.45, -- see the layer below THROUGH the marmalade
		gloss = 0.15,
		oozeSpeed = 6,
		squishMult = 1.3,
		jumpMult = 1.25,
		bounce = 0.3,
		walkSpeedMult = 0.9,
		sfx = "blorp",
		shatterFx = false,
		wobble = true, -- client: sine wave over surface vertices
	},
	cotton = {
		id = "cotton",
		-- almost LIQUID: spectacular fast avalanches, light feet (+15% speed)
		repose = 0.5,
		flowRate = 0.95,
		hardness = 0.3,
		calories = 0.8,
		colors = { top = Color3.fromRGB(255, 176, 224), bottom = Color3.fromRGB(158, 196, 255) },
		material = Enum.Material.Fabric,
		transparency = 0,
		gloss = 0.03,
		oozeSpeed = 9, -- visibly pours
		squishMult = 1.2,
		jumpMult = 1.1,
		walkSpeedMult = 1.15,
		sfx = "pshhh",
		shatterFx = false,
		wobble = false,
	},
	caramel = {
		id = "caramel",
		-- STICKY HONEY: slowest visible creep, boots glued (-40% speed, low jump)
		repose = 5.5,
		flowRate = 0.07,
		hardness = 2.0,
		calories = 1.6,
		colors = { top = Color3.fromRGB(230, 150, 42), bottom = Color3.fromRGB(190, 110, 22) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		gloss = 0.35, -- wet glaze
		oozeSpeed = 0.8, -- honey-slow flow
		squishMult = 0.6,
		jumpMult = 0.75,
		walkSpeedMult = 0.6,
		sfx = "stretch",
		shatterFx = false,
		wobble = false,
	},
	crumb = {
		id = "crumb",
		-- loose sand: pours fast, soft steps
		repose = 1.0,
		flowRate = 0.85,
		hardness = 0.8,
		calories = 0.9,
		colors = { top = Color3.fromRGB(164, 112, 64), bottom = Color3.fromRGB(132, 88, 50) },
		material = Enum.Material.Sand,
		transparency = 0,
		gloss = 0,
		oozeSpeed = 7,
		squishMult = 1.1,
		jumpMult = 1,
		sfx = "shhh",
		shatterFx = false,
		wobble = false,
	},
	core = {
		id = "core",
		repose = math.huge, -- the floor of the cake, not edible
		flowRate = 0,
		hardness = math.huge,
		calories = 0,
		colors = { top = Color3.fromRGB(255, 242, 214), bottom = Color3.fromRGB(246, 226, 192) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
		gloss = 0.05,
		oozeSpeed = 12,
		squishMult = 0,
		jumpMult = 1,
		sfx = "squish",
		shatterFx = false,
		wobble = false,
	},
}

-- ── Feel (client, CakeFeelSubsClient) ───────────────────────────────────
CakeConfig.feel = {
	surfacePollSeconds = 0.12, -- layer-under-feet refresh for jump/speed feel
	bounceMinImpact = 25, -- studs/s of fall speed before a layer bounces you
	bounceMaxUp = 85, -- studs/s cap on the bounce-back velocity
	crackMinImpact = 12, -- studs/s of fall speed for a landing crust crack
}

-- ── Composition rolls (GDD §5 "Cake composition") ───────────────────────
-- Every cake: frosting on top, core at the bottom, 3-5 middle layers drawn
-- from the pool without immediate repeats. Thicknesses are rolled within
-- the ranges, then normalized to the rolled total height. FEWER, THICKER
-- layers: each layer is a floor you live on for a while, not a stripe.
CakeConfig.composition = {
	middlePool = { "sponge", "chocolate", "jelly", "cotton", "caramel", "crumb" },
	middleCountMin = 3,
	middleCountMax = 5,
	frostingThickness = { 5, 7 }, -- studs
	coreThickness = 3, -- exposed cavity floor, not edible
	middleThickness = { 9, 15 },
	totalHeight = { 46, 62 }, -- clamped to grid.maxHeight
	-- Footprint: a rounded-rectangle LOAF (Drain-the-Lake scale, fixed for
	-- any population — the cake is a landmark, not a per-player snack).
	-- 28x19 cells at 1.5 studs = 84x57 studs of cake.
	footprint = { hx = 28, hz = 19, corner = 8 },
	-- Rare cakes (GDD §5): rolled per cake, announced server-wide.
	rare = {
		golden = { chance = 0.04, caloriesMult = 3 },
		rainbow = { chance = 0.01, caloriesMult = 1.5, guaranteedRarity = "epic" },
	},
}

-- ── Cycle (GDD §9) ──────────────────────────────────────────────────────
CakeConfig.cycle = {
	newCakeDelay = 15, -- seconds between pet reveal and the next cake
	bossDuration = 30, -- boss auto-defeats after this (never blocks the loop)
	bossTapsPerPlayer = 40, -- boss HP = taps * max(1, players)
	bossName = "Cake Guardian",
	-- Progress announcements (client hints "cotton candy in 18%").
	progressBroadcastHz = 1,
}

return CakeConfig
