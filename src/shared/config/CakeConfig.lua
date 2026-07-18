--[[
	CakeConfig — the single source of tuning for the cake heightfield,
	its layers, composition rolls and the cake cycle (GDD §4, §5, §9).

	Pure data, shared by both sides:
	  server — simulation (repose/flowRate/hardness), composition rolls,
	           cycle timings, calories
	  client — rendering (colors/materials/crust), SFX keys, wobble/FX
	           flags, per-layer feel (jumpMult/bounce, CakeFeelSubsClient)

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
	-- EditableMesh is THE renderer: ONE MeshPart PER SIM LAYER (clamped
	-- heightfield slabs) so every layer carries its own material,
	-- transparency and reflectance. The CRUST skin at the top of each layer
	-- is painted INTO the layer's XZ-planar EditableImage texture (lighter,
	-- mottled) and footstep/landing cracks are drawn into the same texture.
	-- Memory-budget ladder (weak devices): per-layer meshes -> ONE mesh with
	-- the height palette texture -> visible part grid. Invisible collision
	-- columns always exist.
	forceFallback = false,
	lerpSpeed = 3.5, -- 1/s display approach fallback (layers override via oozeSpeed)
	-- Bite feel: a target DROP bigger than this snaps instantly (the chunk
	-- is ripped out); smaller moves and refills ooze at the layer's oozeSpeed.
	snapDropStuds = 0.4,
	-- Crust = a thin HARD PALE SKIN at the TOP of every edible layer (reference:
	-- the wax/butter slab crust), lighter than the layer body, painted into the
	-- layer's texture. A cell shows crust while its surface is within `depth` of
	-- the layer's top; eating below repaints it as layer body. The crust is the
	-- brittle shell that BUCKLES and breaks under the foot (render.fracture).
	crust = {
		depth = 0.7, -- studs of film at the top of each edible layer
		lighten = 0.35, -- toward white from the layer's top color (a PALE waxy
		-- coat, but still clearly the layer's hue — not washed to snow)
		gloss = 0.3, -- fallback-column reflectance inside the film band
		imageSize = 384, -- layer texture (XZ-planar over the whole grid, 4 px/stud)
		noise = 0.05, -- subtle per-pixel mottling of the film
	},
	-- Soft SQUISH of the mesh under the foot (a gentle round dent that springs
	-- back; deeper on a landing). The always-visible wax crust that CRACKS is
	-- render.wax below (CakeWaxShell) — it reads riseRate/healRate/sinkDepth here
	-- for its own dent so the wax dents WITH the surface.
	fracture = {
		radius = 3.6, -- studs of the squish zone
		sinkDepth = 0.9, -- studs the surface dents in (a gentle butter squish)
		riseRate = 12, -- 1/s squish press-in (springy)
		healRate = 8, -- 1/s squish spring-back
		landDepthMult = 1.6, -- deeper dent on a hard landing
		landRadius = 4.6, -- studs of the landing dent
	},
	-- Always-visible WAX SHELL over the WHOLE cake (CakeRenderer wax section):
	-- one mesh of Voronoi wax plates that COATS the entire top and rides the
	-- deforming surface. Light wax (the surface layer's color toward white);
	-- the slabs beneath render the layer BODY, so where the player's feet CRACK
	-- the local plates (they pull apart + lift) the darker cake shows in the
	-- gaps, then SLOWLY heals shut. The wax is always there — the cracks are
	-- local and reverting, never spawned parts.
	wax = {
		step = 2, -- grid cells per wax quad (2 = ~3-stud tiles riding the surface)
		plateStuds = 4.5, -- avg wax plate size (Voronoi feature-point spacing)
		lift = 0.3, -- studs the intact wax sits above the slab surface (a clear coat)
		dome = 0.1, -- studs each piece bulges up at its centre — small, so the
		-- layer looks SMOOTH at rest; the pieces only read when they crack open
		-- Coating colour = the current outermost layer, made BRIGHTER/more vivid
		-- than the original (a glossy tasty glaze, not a dull pale wax):
		satBoost = 1.4, -- ×saturation of the layer colour (more vivid)
		valBoost = 1.12, -- ×brightness of the layer colour (brighter than original)
		hideDepth = 1.5, -- studs below the layer top before the wax hides (eaten away)
		edgeInset = 1.5, -- studs the wax stops short of the loaf edge (clean rim, no overhang)
		gloss = 0.18, -- wax Reflectance
		-- Cracking under the foot — driven by the DENT (per piece, reverting; the
		-- dent ramp/spring-back speed comes from render.fracture riseRate/healRate,
		-- so the wax dents WITH the surface). Smooth at rest; a step makes each
		-- piece dent, tilt and spread, so cracks open only underfoot.
		crackRadius = 3.8, -- studs around the foot whose pieces dent + crack
		gap = 0.5, -- FRACTION each dented piece spreads toward its centroid (gap)
		tilt = 18, -- degrees each pressed piece tips (one edge up — "наклоняются")
	},
	-- Eaten-through slabs are TUCKED this far under the local surface (a
	-- FixedSize mesh can't delete faces; alpha does not render): deeper
	-- than the biggest downward fracture dip (sinkDepth × landDepthMult) +
	-- wobble so nothing ever peeks out; under a TRANSLUCENT surface layer they
	-- tuck below that layer's bottom instead (see-through-marmalade stays clean).
	hideSink = { base = 3.6, perBand = 0.05 },
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
		-- Glass: wet refraction on high quality, plastic-smooth on low.
		-- KNOWN engine tradeoff: semi-transparent Glass hides TRANSPARENT
		-- things behind it (particles, translucent FX) on high quality —
		-- opaque layers below render fine (the actual goal). Switch to
		-- SmoothPlastic if FX-through-jelly ever matters more.
		material = Enum.Material.Glass,
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
	onCakeYTolerance = 7, -- studs above/below the surface still "on the cake"
	bounceMinImpact = 25, -- studs/s of fall speed before a layer bounces you
	bounceMaxUp = 85, -- studs/s cap on the bounce-back velocity
	crackMinImpact = 12, -- studs/s of fall speed for a landing crust crack
}

-- ── Composition rolls (GDD §5 "Cake composition") ───────────────────────
-- Every cake: frosting on top, core at the bottom, 3-4 middle layers drawn
-- from the pool without immediate repeats. Thicknesses are rolled within
-- the ranges, then normalized to the rolled total height. FEWER, THICKER
-- layers: each layer is a floor you live on for a while, not a stripe.
CakeConfig.composition = {
	middlePool = { "sponge", "chocolate", "jelly", "cotton", "caramel", "crumb" },
	middleCountMin = 3,
	middleCountMax = 4,
	frostingThickness = { 6, 8 }, -- studs
	coreThickness = 3, -- exposed cavity floor, not edible
	middleThickness = { 10, 16 },
	totalHeight = { 52, 68 }, -- clamped to grid.maxHeight
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
