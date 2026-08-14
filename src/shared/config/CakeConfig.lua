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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- The layer LIBRARY (40 layers) and the GROUPS they are organised into. Split
-- out 2026-08-07 when layers stopped being a flat pool; `CakeConfig.layers` and
-- `CakeConfig.layerGroups` below are still what every consumer reads.
local CakeLayersConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("CakeLayersConfig")
)

local CakeConfig = {}

-- ── Grid ────────────────────────────────────────────────────────────────
CakeConfig.grid = {
	size = 64, -- 64x64 cells
	cell = 1.5, -- studs per cell -> 96x96 stud field
	-- Hard height ceiling, with room to spare: the classic cake is built to
	-- composition.maxTotalHeight (170 since 2026-07-26) regardless of difficulty
	-- or population. Selectable variants may apply a declared heightScale (the
	-- rainbow is 204 edible studs). 340 leaves selectable variants headroom without
	-- not require touching the u16 field layout. u16 fixed-point (655 stud max) easily covers it; taller =
	-- taller collision columns + render slabs, NOT more cells (weak-device
	-- vertex budget is driven by cell count, which is unchanged). Only the
	-- CURRENT + NEXT edible layer are rendered as slabs (CakeRenderer window);
	-- the bulk below is hidden behind the textured CakeWrapper wall, so more
	-- layers no longer grow the slab vertex budget.
	maxHeight = 340,
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
	-- ⚠ This is the anti-tedium valve AND a calorie tax (swept volume is
	-- forfeited by everyone). 0.10 is the balanced point: the sim finished
	-- every difficulty/population without a leftover hunt at this value.
	autoSweepFraction = 0.10,
	-- Floor on the EFFECTIVE bite radius (biteRadius stat × the active band's
	-- `scoop`, see composition.scoopTop). Below ~1 cell a bite can miss every
	-- cell centre and remove nothing; ApplyBite also always processes the
	-- centre cell so a floored bite still bites.
	minBiteRadiusStuds = 1.1,
	statsScanHz = 1, -- full-field scan for progress % / auto-sweep
	-- CLEAN CUT (Req 2): a bite clears its footprint TOWARD the active-band floor
	-- (not a shallow paraboloid that leaves hard-to-eat crumbs), scaled by falloff
	-- · (biteDepth / biteClearRefDepth) / hardness. At biteDepth = biteClearRefDepth
	-- the center clears fully in ONE bite on a soft layer — so one side of a layer
	-- clears completely while the other stays full: a clean cut edge with a soft
	-- (dripping) rim. Bigger biteDepth widens the full-clear core (harder layers
	-- take a few bites). Shared by CakeOps.ApplyBite (server + client prediction).
	biteClearRefDepth = 3.6, -- studs; the biteDepth at which a bite center clears fully
	-- Tiny leftover slivers on the active floor are swept away each stats scan
	-- (Req 2 — the layer gate makes sub-floor bits impossible to eat, and they look
	-- messy): any active-band cell within this many studs of the active floor
	-- collapses to it. Small enough that meaningful partial cake is left alone.
	sliverSweepStuds = 1.5,
	-- ⚠ BOTH sweep distances above and in `remnantSweep` are ABSOLUTE studs, and
	-- they are measured against the ACTIVE BAND — so the thinner the band, the
	-- more of it a fixed rule swallows. When the cake came down 330 -> 170 (bands
	-- 4.5-24 -> 3.4-12) the forfeited fraction rose 6.2% -> 8.3% purely from that.
	-- Each distance is therefore capped at this FRACTION of the active band's own
	-- thickness. Measured (`tools/headless-sim/pacing_scenario.lua`, section C):
	--   no cap 8.3% waste | 0.35 -> 7.4% | 0.25 -> 6.8% (+3.4% food) | 0.15 -> 6.6%
	-- 0.25 takes nearly all of it back for +0.7 min of clear time; below that the
	-- returns flatten and the eaten rim starts to keep visible crumbs, which is
	-- the whole reason these sweeps exist. nil/0 restores the old absolute rules.
	sweepBandFraction = 0.25,
	-- Eaten-zone cleanup sweep (user req: the eaten section should be COMPLETELY
	-- eaten — no small pieces). Each stats scan snaps partially-eaten OR isolated
	-- active-band cells that touch a CRATER down to the active floor, so the eaten
	-- area reads clean (no ragged rim, no leftover crumbs / wax fragments, no thin
	-- walls). A FULL cell (still ~at the band top) with a crater on only ONE side is
	-- LEFT — the clean cut edge (one side full, other floor) survives; the loaf
	-- PERIMETER survives too (out-of-cake neighbours are SUPPORT, never a crater).
	remnantSweep = {
		enabled = true,
		-- A neighbour within this many studs of the ACTIVE FLOOR = a crater ("cleared").
		clearedMarginStuds = 2,
		-- A cell whose surface is within this many studs of the ACTIVE FLOOR and
		-- that touches a crater snaps to the floor — the soft rim of a bite is
		-- swept away so the eaten footprint reads as a clean cliff.
		-- ⚠ This REPLACED the old `eatenEpsilonStuds` rule ("anything bitten >1
		-- stud below its band TOP"), which collapsed a whole cell the moment it
		-- was nicked: with chunky bands that forfeited most of the layer for
		-- free, made layer clear-time independent of the bite stats (~25% of
		-- every cake vanished uneaten) and left NO room to pace the cake.
		-- Measured near the floor instead, it only cleans the rim.
		nearFloorStuds = 2.5,
		-- A TALL isolated remnant (a full-height pillar/spike, or a 1-cell wall between
		-- craters) is swept too: >= this many crater neighbours (of 4), or exactly 2
		-- OPPOSITE. A solid EDGE (1 crater) / convex corner (2 ADJACENT) is preserved.
		minClearedNeighbors = 3,
	},
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
	-- Image textures on the LAYER slabs (layer.texture) TILE this many times across
	-- the loaf instead of stretching ONCE (which read blurry/smeared up close).
	-- ~4 ≈ one tile per ~24 studs, matching the wall's tiling. Baked into the slab
	-- UVs; a value of 1 = the old stretch-once mapping.
	layerTextureTiles = 4,
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
	-- back; deeper on a landing). When a variant enables it, the wax crust that
	-- CRACKS is render.wax below (CakeWaxShell) — it reads these rates/depth
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
	-- gaps, then SLOWLY heals shut. On wax-enabled variants it is always there;
	-- local and reverting, never spawned parts.
	wax = {
		step = 2, -- grid cells per wax quad (2 = ~3-stud tiles riding the surface)
		plateStuds = 4.5, -- avg wax plate size (Voronoi feature-point spacing)
		lift = 0.3, -- studs the intact wax sits above the slab surface (a clear coat)
		dome = 0.1, -- studs each piece bulges up at its centre — small, so the
		-- layer looks SMOOTH at rest; the pieces only read when they crack open
		-- Coating colour = the CURRENT outermost layer's OWN colour, only SLIGHTLY
		-- brighter (a waxy sheen) so each layer's wax reads as THAT layer (user req 1):
		satBoost = 1.05, -- keep ~the layer's OWN saturation (was 1.4 = too vivid/generic)
		valBrighten = 0.22, -- brighten toward full value by this FRACTION of the headroom (1-v)
		hideDepth = 1.5, -- studs the local wax must drop BELOW the outermost remaining layer before a piece HIDES (a HOLE eaten through — user req 3); above the underfoot squish so walking never hides it
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
	-- Outer WALL that hides the whole cake BELOW the single rendered top layer
	-- (CakeRenderer window, Task 2 / Req 1). A plain textured Part carrying a
	-- `CylinderMesh` (NOT an EditableMesh, and NOT a native cylinder Part — see
	-- the CakeWrapper header: a native cylinder must be ROTATED upright, which
	-- rotates the texture UVs with it and lays the cake photo on its side).
	-- Round-cake sized, standing from the base up to the current top layer's
	-- bottom and shrinking as each layer clears. Wears a RANDOM cake photo (one
	-- per cake, by cakeIndex) on its curved side + top cap. Driven by CakeWrapper.
	wrapper = {
		-- ⚠ These MUST be IMAGE ids, not DECAL ids. A decal id renders BLANK on a
		-- `Texture` (resolve one via `InsertService:LoadAsset(decalId)` → the
		-- loaded Decal's `.Texture`). The two ids that used to live here were the
		-- unresolved decals: one drew nothing and the other was a red/white
		-- diagonal STRIPE, which is why the loaf read as a candy-cane column from
		-- outside rather than a cake. These three are the resolved cake photos.
		-- ⚠ These MUST be IMAGE ids, not DECAL ids — a decal id renders BLANK on a
		-- `Texture`. (Toolbox right-click gives both; take "Copy Texture ID".)
		-- The wall used to carry the unresolved decals: one drew nothing, the
		-- other a red/white diagonal stripe, so the loaf read as a candy cane.
		-- The photos that replaced them read as cake but tiled with visible
		-- seams. This one is a SEAMLESS layered cross-section — horizontal sponge
		-- and cream bands, which also reinforce the eat-down-through-layers
		-- fantasy. Verified on screen 2026-07-26. Add more entries for per-cake
		-- variety (CakeWrapper picks one by cakeIndex) — keep them seamless.
		textures = {
			"rbxassetid://111184124905083", -- Toolbox "Cakie", layered sponge/cream
		},
		-- ⭑ THIS IS THE KNOB for how big the cake photo reads on the outer wall.
		-- Bigger = fewer, larger tiles (thicker sponge/cream bands); smaller = more,
		-- finer ones. A true SQUARE tile in studs, both directions.
		-- ⚠ It only works because the wall is a RING OF FLAT BLOCK SEGMENTS. A part
		-- carrying a mesh (CylinderMesh/SpecialMesh) maps its Textures through the
		-- MESH's UVs and IGNORES StudsPerTile entirely — 55/20/5 rendered
		-- pixel-identical when the wall was briefly one CylinderMesh. If this knob
		-- ever stops doing anything, that is the first thing to check.
		-- (The per-LAYER top-surface textures are a different knob:
		-- `render.layerTextureTiles` + each `layers.<id>.texture`.)
		-- Studs per texture tile. Sized so the cake photo reads a FEW times up the
		-- wall, not a dozen: at the old 26 on a 330-stud wall it tiled ~12x and
		-- turned the silhouette into stripes. ~55 on the 170-stud cake is ~3 up.
		-- Across: on the round wall each of the 4 faces spans a 74.5-stud quadrant
		-- of the 293-stud circumference (was a flat 90-stud side), so it reads ~1.35
		-- per quadrant / ~5.3 around — the layer BANDS are what must line up, and
		-- they run horizontally, so the circumferential figure is the loose one.
		tileStuds = 55,
		-- PER-ZONE BANDS (2026-08-07, user req: "look at the side and see which
		-- layers are coming next", then "1 wall on every group of layers"). The
		-- wall is no longer ONE ring wearing one cake photo: it is one ring per
		-- flavour ZONE (`composition.groups`), each wearing that GROUP's
		-- `sideTexture` (CakeLayersConfig), so the side of the cake reads
		-- "chocolate, then sponge, then butter, then cream". Classic draws a
		-- mini-boss on every transition; variants may keep a transition visual-only.
		-- ⚠ A ring per LAYER was tried first and is WRONG: ~28 near-identical
		-- stripes up the side read as noise rather than information, and cost
		-- ~560 parts to say less. `tileStuds` above is now only the FALLBACK
		-- ring's tile size; the per-LAYER `sideTexture` survives for the top CAP,
		-- which really is a single layer seen down a crater.
		-- COST is parts: bandSegments x zones. 20 x 4 = 80 anchored,
		-- non-colliding, non-query blocks, built ONCE into a pool and re-placed
		-- per cake (never re-created per layer). 20 segments puts the facet sag
		-- at 47.4*(1-cos(pi/20)) = 0.58 studs on the 93.3-stud cake, which still
		-- reads round at play distance; 32 would cost 60% more parts for 0.35
		-- studs less sag.
		bandSegments = 20,
		-- Studs each zone ring is stretched VERTICALLY past its own span, split
		-- top and bottom, so neighbouring rings can never show a hairline seam of
		-- sky between them.
		bandOverlapStuds = 0.08,
		-- Pool ceiling, in RINGS. Must be >= composition.groups.count (it was
		-- >= maxLayers while the wall was per-band) or the deepest zones go
		-- unbuilt; the pool only ever builds what a cake asks for, so the
		-- headroom is free.
		maxBands = 12,
		-- ⭑⭑ THE TWO KNOBS FOR HOW BIG THE WALL TEXTURE READS. Both are the
		-- size of ONE tile in studs, so BIGGER = fewer, larger tiles.
		--   bandTileStuds   ACROSS, around the cake. The circumference is
		--                   ~302 studs, so 26 wraps ~11.6 times.
		--   bandTileStudsY  UP the wall. This is the one to change if the image
		--                   looks too SHORT / squashed vertically.
		-- Whole-row snapping only kicks in once a zone is at least 1.5 tiles
		-- tall (CakeWrapper): snapping unconditionally squashed every zone
		-- SHORTER than one tile down to its own height -- the 3.4-stud candy cap
		-- rendered 87% vertically compressed. A partial row at the top of a band
		-- reads far better than a distorted image.
		-- Zone heights on a 170-stud cake run ~3 studs (the thin top zone) to
		-- ~100 (the deep one), so at 45 the deep zones show 2 rows and the thin
		-- ones show one uncompressed crop.
		bandTileStuds = 26,
		bandTileStudsY = 45,
		-- Flat Block segments the round wall is built from. More = rounder
		-- silhouette + softer facet shading, at one Part each (anchored, no
		-- collision, no query — cheap). 32 puts the facet sag at ~0.23 studs on the
		-- 47.4-stud radius, which reads as a smooth curve at play distance.
		segments = 32,
		segmentThickness = 0.4, -- studs; only ever seen edge-on at the top rim
		capThickness = 0.5, -- the flat top disc (shown through a crater, not a void)
		gloss = 0.05, -- Part.Reflectance
		color = Color3.fromRGB(232, 205, 165), -- warm cake tint under the texture (shows if it's missing)
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
	-- Walkable collision feel (the invisible column grid, Task 4 + Task 2 perf).
	-- Biting a crater DROPS the columns instantly (you fall into the hole you just
	-- bit), but cake OOZING/refilling back RISES the collision only at `riseRate`
	-- studs/s — so refilling cake never punts the player up (the old "constant
	-- bounce"): you stay partly BURIED in the crater and jump to get back on the
	-- surface. A new cake / full snapshot snaps columns straight to truth (no
	-- rate limit), so you never fall through fresh cake. The SAME riseRate caps
	-- the server safety slab's rise (CakeCollisionService) so a wide/fast refill
	-- can't punt a player resting on the coarse slab either; a rise bigger than
	-- `slabSnapStuds` in one 5 Hz tick (a new cake / big reset, never a refill)
	-- snaps.
	-- PERF (Task 2): only the collision columns within `updateRadiusStuds` of the
	-- LOCAL player are refreshed each frame. Eating + the settle automaton oozing
	-- change cells across the WHOLE cake; resizing every affected CanCollide
	-- column per frame re-indexes the physics broadphase and spiked the frame to
	-- 60+ ms while eating (settling only when the surface stabilized). The player
	-- only collides with nearby columns, so distant ones keep their last size
	-- until the player approaches (the radius scan corrects them then).
	collision = {
		riseRate = 6,
		slabSnapStuds = 8,
		updateRadiusStuds = 18,
		-- JOIN-RACE RESCUE (2026-08-03). `CakeSpawn` drops the character onto the
		-- crust the instant they join, but the cake only becomes COLLIDABLE when
		-- THIS client finishes its first `columnsRebuild`. On a slow load you fall
		-- clean through and the columns rise around you: measured HRP at Y=141 with
		-- the surface at 175 — 34 studs inside, permanently stuck. (A mid-session
		-- respawn is fine, which is what proves it a load race and not the spawn
		-- geometry.) After each rebuild the client lifts a LOCAL character found
		-- more than `buriedRescueStuds` under the surface to `buriedRescueLift`
		-- above it.
		-- ⚠ Keep `buriedRescueStuds` WELL above the depth you legitimately sink to
		-- when refilling cake buries you (riseRate above): that is deliberate feel
		-- ("jump to get back out") and must not be undone.
		buriedRescueStuds = 6,
		-- ⚠ Clearance ABOVE the solid top, not an HRP offset. It was 3 — the R15
		-- HumanoidRootPart offset — which lands the feet flush ON the surface with
		-- nothing to spare, the same mistake the server lift's old `+ 3` made
		-- (`composition.liftClearanceStuds`). Give the drop real room.
		buriedRescueLift = 8,
		-- The rescue is NO LONGER snapshot-only (2026-08-07). It used to run at
		-- exactly one moment — right after a snapshot's `columnsRebuild` — and a
		-- reserved match broadcasts ONE snapshot for a ~35-minute session, so any
		-- state that voided that single check (no character yet, a control lock
		-- held, a burial that happened later, a respawn) left the player inside the
		-- cake permanently. It now also runs on a slow timer and on every fresh
		-- character.
		-- `buriedRescueDwellSeconds` is what protects the deliberate crater feel
		-- from the new per-frame path: being buried is a legitimate transient
		-- state, being buried CONTINUOUSLY for this long is not. Keep it
		-- comfortably longer than the time it takes to jump out of a refill.
		buriedRescuePollSeconds = 0.5, -- how often the timed check samples
		buriedRescueDwellSeconds = 2.0, -- continuously buried this long => lift
		-- Delay after a fresh character before the columns are snapped to truth a
		-- SECOND time and the burial re-checked (CakeRenderer.SnapCollisionNow —
		-- once at spawn, once here, not a continuous window). Long enough that the
		-- character has landed. A character that just spawned was not on the cake
		-- while its columns went stale, so the rise cap has nothing to punt.
		freshCharacterSnapSeconds = 1.5,
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
--   calories: calories per stud^3 removed. RESCALED to ~⅓ of the pre-3×-cake
--             values so the taller cake (×3 edible volume) pays the SAME total
--             calories per cake and the same income/sec (bite volume is ×3 via
--             biteDepth ×3 in UpgradeConfig) — the cake is bigger, not richer.
--   texture:  OPTIONAL rbxassetid image mapped over the layer's top surface
--             (only the CURRENT/NEXT rendered slabs; nil = flat body Color).
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
-- sfx: key into AudioConfig.sounds for this layer's bite sound.
--   sideTexture: rbxassetid IMAGE mapped on the OUTER WALL band for this
--             layer (CakeWrapper) -- the side of the cake is a real
--             cross-section, so you can SEE which layers are coming.
--   sideColor: optional tint under `sideTexture`; defaults to colors.top.
-- GROUPS: layers are laid down in flavour ZONES (chocolate, jelly, cheese...),
-- several layers deep. Classic gates every boundary with a MINI-BOSS; a fixed
-- visual variant may explicitly leave selected boundaries open -- see
-- `composition.groups` below and `CakeLayersConfig`, which owns both tables.
CakeConfig.layers = CakeLayersConfig.layers
CakeConfig.layerGroups = CakeLayersConfig.groups

-- ── Feel (client, CakeFeelSubsClient) ───────────────────────────────────
CakeConfig.feel = {
	surfacePollSeconds = 0.12, -- layer-under-feet refresh for jump/speed feel
	onCakeYTolerance = 7, -- studs above/below the surface still "on the cake"
	bounceMinImpact = 25, -- studs/s of fall speed before a layer bounces you
	bounceMaxUp = 60, -- studs/s cap on the bounce-back velocity (was 85 — toned)
	crackMinImpact = 12, -- studs/s of fall speed for a landing crust crack
	-- FLAT WHILE EATING (Task 4): while actively eating, the character must move
	-- in a roughly STRAIGHT line — no trampoline bounce, no jump-boost. So the
	-- landing bounce is suppressed and the per-layer jumpMult is capped to this
	-- while eating; the toned per-layer feel below only applies when walking /
	-- exploring (not eating).
	noBounceWhileEating = true,
	jumpMultCapWhileEating = 1, -- jump ≈ normal while eating (no sponge super-jump)
}

-- ── Composition rolls (GDD §5 "Cake composition") ───────────────────────
-- THE PACING CURVE (2026-07-26 rework, docs/decisions/0011-cake-pacing-curve.md).
--
-- A bite CLEARS its footprint to the active band's floor, so a layer's clear
-- TIME is driven by AREA, not by how thick it is. Two per-band knobs therefore
-- carry the whole design, and `RollComposition` builds them TOP-DOWN:
--
--   scoop   — multiplies the eater's biteRadius on this band. The icing takes
--             a HUGE scoop (a ~7.8-stud bite: the top layer is gone in ~30 s);
--             every band below scoops a little smaller, down to ~2 studs at the
--             core. This is the difficulty ramp AND it reads instantly on screen
--             ("soft cream = giant spoonful, dense cake = small chip").
--   density — how RICH/FILLING that band is per stud³ (calories AND belly fill).
--             Computed so the food value of one bite stays ~constant as the
--             scoop shrinks and the layers change thickness, which is what keeps
--             the calorie income steady from the first layer to the last, on
--             every difficulty and party size — and what makes `capacity` the
--             SOLE owner of the belly→gym rhythm.
--             ⚠ That rhythm is NOT a constant any more (ADR-0019, 2026-08-05).
--             It is a curve — ~10 s per belly at capacity tier 0 stretching to
--             ~180 s at tier 5 — because how often the belly interrupts eating
--             is the progression the player feels. Changing `density`,
--             `scoop` or the layer count moves food-per-second and therefore
--             moves that whole curve: re-measure with
--             `tools/balance-model/pacing.py --intervals`.
--
-- Thickness rides the same curve (deeper == chunkier, `thicknessExponent`),
-- normalised to `maxTotalHeight × selectedVariant.heightScale`. Difficulty and
-- population never make that chosen silhouette taller — they add MORE (thinner)
-- layers and smaller scoops, i.e. more "layer cleared!" moments.
--
-- Sim-calibrated (scratchpad model, ports ApplyBite + the three sweeps + a
-- mowing player): solo easy 40 min; see features/cake-cycle.md for the matrix.
CakeConfig.composition = {
	-- ZONES (2026-08-07). A cake is a SEQUENCE of flavour GROUPS -- "3-4
	-- chocolate layers, then 4-6 jelly, then cheese" -- not a random flavour
	-- every layer. The pool of groups is `CakeConfig.layerGroups`; `count` of
	-- them are drawn per cake in a random order and laid down one after another.
	-- By default `count` ALSO sets the boss count: every boundary between two
	-- zones is a MINI-BOSS (features/cake-cycle.md), so classic has `count - 1`
	-- mini-bosses plus the Cake Guardian. A selectable variant may supply
	-- `gateBoundaries` to make a visual boundary intentionally open.
	groups = {
		-- ⚠ 4 -> 5 (2026-08-07, by request: "the last group is too large, split it
		-- into 2-3"). At 4 zones the deepest was TWELVE layers / ~15 min -- longer
		-- than the first three put together, so the last third of a run had no
		-- punctuation at all. With the default all-gated contract this is
		-- now 4 mini-bosses + the Cake Guardian = 5. That is one more than the
		-- original "3-4 bosses" ask; splitting the tail into THREE instead is a
		-- one-line change here (six zones, six shares) but costs a 5th mini-boss, and
		-- the rig pool only holds 5.
		count = 5,
		minLayers = 3, -- a zone is never one lonely layer
		-- Share of the cake's LAYERS each zone gets, TOP zone first. MUST have
		-- exactly `count` entries and sum to 1.
		--
		-- ⚠ LAYER COUNT, not clear-time cost — and that is a MEASUREMENT, not a
		-- simplification. The obvious model says a band near the core costs ~16x
		-- a band at the top (clear time goes as 1/scoop²), so zones should be
		-- split by cost. That is true for a FIXED eater and false for the run
		-- people play: the player buys tiers as they dig, and the upgrade ramp
		-- very nearly cancels the scoop ramp. `tools/balance-model/pacing.py`
		-- (ramped, 5 seeds) measures a FLAT ~1.21 min per layer across all 29
		-- bands — 1.89 min for the first (no upgrades yet) and 1.84 for the last.
		-- Splitting by cost put ELEVEN layers and 13.2 minutes in the opening
		-- zone; splitting by count puts 3 layers and ~4 min there, which is the
		-- requirement (opening zone 3-4 min, later zones longer).
		-- At the shipped 28-29 layers: 3 / 5 / 6 / 7 / 8 layers ≈ 4.5 / 6.1 /
		-- 7.3 / 8.5 / 9.7 min of a ~35-min solo-easy run -- every zone longer than
		-- the one above it, and none of them the 15-minute slog the 4-zone split
		-- ended on. Re-measure with `pacing.py` (its report prints the zone split)
		-- after touching these or the layer count.
		layerShares = { 0.103, 0.172, 0.207, 0.241, 0.277 },
	},
	coreThickness = 3, -- exposed cavity floor, not edible
	-- Footprint: a ROUND cake (2026-08-03; was a 30x26x10 rounded-rect loaf).
	-- A LANDMARK, not a per-player snack — the XZ size is FIXED for any
	-- population (the grid caps the radius just UNDER 31.5 cells — `InCake` uses
	-- `half = (size-1)*0.5 = 31.5` with a `<=`, so at exactly 31.5 the outermost
	-- columns x=0/x=63 become in-cake, `CakeRenderer` can no longer place a ring
	-- cell outside them, and the skirt seal opens up at the field boundary with no
	-- warning. 31.1 leaves 0.4 cells of margin. Growing the grid instead would
	-- blow the render vertex budget).
	--
	-- ⚠ `hx == hz == corner` is not a redundant triple — it is HOW a circle is
	-- expressed here. `GridUtil.InCake` is the standard rounded-rect SDF
	-- (`|q| - (h - corner)` clamped at 0, then `|q| <= corner`); setting the
	-- corner radius equal to BOTH half-extents collapses the straight edges to
	-- zero length and leaves a pure disc of radius `corner`. Every consumer
	-- inherits the circle for free — `CakeRenderer`'s outline projection
	-- degenerates to `dir * (R+0.5)*cell`, `CakeWaxShell`'s four corner arcs
	-- share one centre and concatenate into one circle, and `TreasureService`'s
	-- inset (`hx/hz/corner - margin`) stays a disc. Keep all THREE equal or the
	-- cake silently becomes a stadium/rect again.
	--
	-- AREA IS PRESERVED so the pacing curve (ADR-0011) is untouched: the balance
	-- quantity is the CELL COUNT (edible volume = cells × cell² × height, and
	-- height is always `maxTotalHeight`), not the continuous area. The loaf
	-- covered 3036 cells; R = 31.1 covers 3032 (-0.13%, the closest a 64-cell
	-- lattice can land — the count steps in jumps of 4-8 cells here). Measured
	-- end-to-end by `tools/headless-sim/pacing_scenario.lua`: session time and
	-- food both move < 0.5%. R = 31.1 cells × 1.5 = 46.65 stud radius, a 93.3-
	-- stud disc (was 90x78) — still inside the 96-stud field, with the render
	-- outline at (R+0.5)*cell = 47.4 of the 48-stud half-extent.
	footprint = { hx = 31.1, hz = 31.1, corner = 31.1 },
	-- How far PAST the footprint a player still counts as "in the new cake" when
	-- one materializes under them (CakeCycleSubs lifts them onto the fresh top).
	-- A body width, so someone hugging the rim comes up too. ⚠ Measured from the
	-- cell-CENTRE extreme (corner*cell = 46.65), while the rendered rim is at
	-- (corner+0.5)*cell = 47.4 — so the real grow past visible cake is ~3.25.
	liftMarginStuds = 4,
	-- How high ABOVE the fresh crust that lift places the HumanoidRootPart. It
	-- used to be a hard-coded `+ 3` — the HRP offset of an R15 rig, i.e. feet
	-- exactly ON the crust with zero clearance, at the one moment the cake has no
	-- collider yet (server slabs are a Heartbeat gate away, client columns a
	-- yielding mesh build away). Any downward motion at all then put the feet
	-- under the surface. Clearance is cheap: the drop is padded by the frosting.
	-- ⚠ Deliberately NOT shared with `MapConfigData.spawnHeightAboveCake` even
	-- though both are currently 8 — that one is the spawn PAD's height above the
	-- crust, this is the lift's clearance. Coupling them means tuning the spawn
	-- drop silently retunes the lift, which is how the `+ 3` went stale.
	liftClearanceStuds = 8,

	-- Layer count + silhouette
	baseLayers = 28, -- edible layers of a solo EASY cake (incl. the frosting)
	maxLayers = 42, -- ceiling; work beyond it goes into smaller scoops instead
	-- 2026-07-26: 330 -> 170. At 330 on a 90x78 loaf the cake was ~3.7x taller
	-- than wide and read as a candy-STRIPED TOWER, not a cake. 170 is ~1.8x the
	-- footprint — a tall layer cake.
	-- COST, measured by `tools/headless-sim/pacing_scenario.lua` (mows a whole
	-- cake through the real ApplyBite + layer gate + BOTH forfeiting sweeps):
	--   330 -> 170 : bites -2.2%, food -1.8%, forfeited 6.0% -> 6.8%
	--   330 -> 110 : food -7.1%, forfeited 9.3%
	-- (Those are WITH `sim.sweepBandFraction` shipped. Without the cap the same
	-- change cost food -4.7% and 8.3% waste — the cap exists because the sweeps
	-- are what height actually interacts with.)
	-- ⚠ NOT free — and an earlier version of that scenario reported it as free
	-- because it left the SWEEPS OUT. The sweeps are exactly what height
	-- interacts with: `sliverSweepStuds` and `remnantSweep.nearFloorStuds` are
	-- ABSOLUTE stud distances, so a thinner band has proportionally more of
	-- itself inside the sweep zone — which is exactly what `sweepBandFraction`
	-- now caps. 6.8% is well inside ADR-0011's tolerance (the failure it fixed
	-- was ~25%), so 170 ships — but do NOT push below ~130: waste climbs fast,
	-- the deepest band's density approaches `maxDensity` (11.7 of 12 at 110) and
	-- the thinnest hits `minLayerThickness`.
	maxTotalHeight = 170,
	minLayerThickness = 3.5, -- a layer must stay something you can stand on
	thicknessExponent = 0.6, -- how strongly thickness follows the scoop ramp

	-- The scoop ramp (multiplies biteRadius; see the header above)
	scoopTop = 2.23, -- icing: biteRadius 3.4 -> ~7.6 studs
	scoopBottom = 0.558, -- deepest band: ~1.9 studs
	-- Density reference: the thickness × scoop² of the solo-easy TOP band. Every
	-- band's density is `refBandWeight / (thickness × scoop²)`, so one bite is
	-- worth ~the same food anywhere in any cake.
	refBandWeight = 25.4, -- = refThickness 5.1 × scoopTop² (2.23²)
	maxDensity = 12,

	-- Work scaling. `work` = MatchConfig difficulty workMultiplier ×
	-- (1 + coopWork·(players−1)); it buys MORE LAYERS first (layerExponent) and
	-- whatever the maxLayers cap cannot absorb becomes SMALLER SCOOPS.
	coopWork = 0.5,
	layerExponent = 0.55,
	-- Calorie payout scaling: a shared loaf split N ways would pay each player a
	-- fraction of a solo run, so the cake pays out per HEAD. 0.62 leaves co-op
	-- slightly AHEAD of solo per minute — teaming up should be the better deal.
	coopCalories = 0.62,
	-- The SAME rule for the gems finds pay, and for the same reason: the find
	-- COUNT comes from cake volume (roster-independent — the footprint is fixed
	-- for any population) and a find is consumed by whoever reaches it first, so
	-- 4 players collect ~10 finds each out of the same 40. Gems are what boosts
	-- are priced against (500 = roughly one cleared solo cake), so without a
	-- per-head term a co-op player needed FOUR cakes for one boost.
	-- Deliberately NOT multiplied by the difficulty premium the way calories are:
	-- difficulty already pays in calories, and leaving gems out of it keeps
	-- "one cleared cake buys one boost" true on every difficulty.
	coopFinds = 0.62,

	-- Rare cakes (GDD §5): rolled per cake, announced server-wide.
	rare = {
		golden = { chance = 0.04, caloriesMult = 3 },
		rainbow = { chance = 0.01, caloriesMult = 1.5, guaranteedRarity = "epic" },
	},
}

-- ── Selectable cake variants ─────────────────────────────────────────────
-- Selectable cake variants (features/cake-select.md). The catalogue/unlock
-- rules live in CakeSelectConfig; this table owns only what a chosen cake
-- changes once a round starts. `durationScale` is the player-facing target;
-- `durationWorkScale` is the measured bite-area factor that actually reaches
-- it after fixed gym downtime, the minimum bite radius and cleanup sweeps.
-- Density is compensated alongside that work factor so calorie/belly milestones
-- stay at the same cake depth while wall time grows.
CakeConfig.defaultVariantId = "cake-classic"
-- Studio-only direct/fallback launch override. Pressing Play in either the
-- combined project or the GAME place starts this variant without changing the
-- production default or a real lobby match's authoritative TeleportData.
-- Set to nil to test the normal classic/direct-join path again.
CakeConfig.studioVariantId = nil--"cake-rainbow"
CakeConfig.variants = {
	["cake-classic"] = {
		environmentName = "Environment",
		heightScale = 1,
		durationScale = 1,
		durationWorkScale = 1,
		findRewardMultiplier = 1,
		-- Preserve the shipped classic deformation: every non-rigid layer used
		-- the same dent depth before selectable variants consumed squishMult.
		useLayerSquishMultiplier = false,
		waxEnabled = true,
		crustEnabled = true,
		rareEnabled = true,
	},
	["cake-rainbow"] = {
		environmentName = "Environment1",
		heightScale = 1.2,
		durationScale = 1.5,
		-- Five-seed ramped pacing model with the seven wider terrace masks: 1.75 work
		-- -> ~1.5x wall-clock duration versus classic solo/easy,
		-- inside the 1.45-1.55 acceptance band around the requested 1.5x.
		durationWorkScale = 1.75,
		findRewardMultiplier = 1.5,
		useLayerSquishMultiplier = true,
		waxEnabled = false,
		crustEnabled = false,
		rareEnabled = false,
		groups = {
			fixedOrder = true,
			useFrostingCap = false,
			pool = CakeLayersConfig.rainbowGroups,
			count = 7,
			minLayers = 3,
			-- Top -> bottom: deeper bands are intrinsically thicker, so the 29-band
			-- solo/easy roll uses 7/5/4/4/3/3/3 bands to keep all seven colour
			-- terraces visually substantial. These shares sum exactly to 1.
			layerShares = { 0.2414, 0.1724, 0.1379, 0.1379, 0.10345, 0.10345, 0.1035 },
			-- Top -> bottom: every colour terrace is wider than the one above.
			-- The base keeps the classic 31.1-cell radius because the 64-cell
			-- field and authored 100x88 CakePlate cannot hold a wider cake.
			radiusScales = { 0.72, 0.76, 0.81, 0.87, 0.94, 0.97, 1.00 },
			-- One boolean per visual boundary, top -> bottom. Colour terraces and
			-- chapter gates are deliberately independent: the five authored rigs
			-- guard the first five transitions; indigo -> violet stays open.
			-- Variants that omit this field gate every boundary (classic behavior).
			gateBoundaries = { true, true, true, true, true, false },
		},
	},
}

-- ── Biomes ──────────────────────────────────────────────────────────────
-- Palette + calorie multiplier per biome live in MapConfigData.biomes; this is
-- just the ORDER. Rebirth used to unlock them one by one; with rebirth removed
-- (2026-07-26) every cake uses `biomeOrder[1]` (ProgressService.BiomeFor), and
-- this list is where a future unlock rule would plug back in.
CakeConfig.biomeOrder = { "factory", "donut", "candy" }

-- ── Layer gate (eat top-down, ONE layer at a time) ──────────────────────
-- Bites may not dig below the current TOP band's bottom until that band is
-- consumed (leveled or auto-swept, §7.6). Once the top layer is gone the
-- active floor drops and the next layer unlocks. Trying to eat the still-
-- locked layer beneath shows a "finish the top layer first" cue on the
-- client (the server enforces the floor either way). enabled=false restores
-- the old free-dig behavior (a single bite could cut through many layers).
CakeConfig.layerGate = {
	enabled = true,
	-- Surface within this many studs of the active floor counts as "eaten to
	-- the floor here" (the top layer is gone at this spot) -> the client cues
	-- the lock. Tiny vs. band thickness, so it only fires at the true floor.
	lockEpsilon = 0.3,
	cueInterval = 1.2, -- seconds between locked cues (client debounce)
}

-- ── Aim (client input: WHERE the bite in front of you lands) ─────────────
-- You eat the cake directly in front of you (CakeSubsClient.computeBitePoint).
-- The naive rule — "sample the surface exactly `reach` studs ahead" — breaks the
-- single most common way a player eats: RUNNING HEAD-ON INTO THE WALL of the
-- layer they are clearing. Standing in the crater they just made, the point
-- `reach` ahead is still crater FLOOR, so:
--   * the layer-gate pre-check reads it as "already eaten to the floor here"
--     and SKIPS the bite outright (+ nags "eat the top layer first"), and
--   * even when it does fire, ApplyBite centres on a floor cell (h == floor,
--     nothing to remove) and only the falloff RIM reaches the wall — a sliver.
-- Running ACROSS the top surface centres the scoop on full cake and clears the
-- whole footprint to the floor, which is why the two felt so different (and why
-- a real playtest ran ~50% longer than the mowing model predicted).
-- So the aim point SEARCHES FORWARD for the nearest cake still standing above
-- the active floor. When there IS cake at the nominal point (the fast
-- surface-mowing case) nothing changes — the search only runs in the case that
-- was broken.
CakeConfig.aim = {
	-- Nominal point: `max(minReachStuds, scoopedRadius * reachMult)` ahead.
	-- ⚠ reachMult must stay under the front bite's own radius + the beneath
	-- bite's, or the two craters stop touching and every pass leaves an un-eaten
	-- RING around the eater (the densest cakes / smallest scoops hit this first).
	minReachStuds = 2.5,
	reachMult = 1.15,
	-- Forward search for standing cake, in `stepStuds` increments out to
	-- `max(nominalReach, scoopedRadius + probeStuds)`. Kept SHORT on purpose:
	-- pressed against a wall the face is ~2-3 studs out, so this only ever needs
	-- to step over the lip of the player's own crater. A long probe would let the
	-- front crater detach from the beneath crater (the un-eaten ring above).
	-- Everything here stays far inside the server's reach cap
	-- (CakeConfigData.antiCheat.maxBiteReachStuds = 18 + biteRadius).
	stepStuds = 0.6,
	probeStuds = 4.5,
}

-- ── Cycle (GDD §9) ──────────────────────────────────────────────────────
CakeConfig.cycle = {
	newCakeDelay = 15, -- seconds between pet reveal and the next cake
	-- The FINALE of a 25-45 minute cake, so it has to be a real moment: HP is
	-- sized for a ~20-30 s frantic tap fight, and the timer always leaves ~1.5x
	-- the time a base eater needs (MatchConfig bossHp/bossDuration multipliers).
	-- ⚠ Keep that margin when tuning: HP / (players x eatRate) must stay well
	-- under the timer or the match is unwinnable by construction.
	--   easy solo   90 taps / 67.5 s  |  hard solo  150 / 45 s
	--   easy 4p    360 taps / 67.5 s  |  hard 4p    600 / 45 s
	bossDuration = 45, -- boss timer; expiry is a LOSS in a reserved match
	bossTapsPerPlayer = 120, -- boss HP = taps * max(1, players) * difficulty
	bossName = "Cake Monster", -- SERVER LOG only since 2026-08-13 (no nameplate); player copy is LocaleData `cake-boss`
	-- ── MINI-BOSSES (2026-08-07) ────────────────────────────────────────
	-- One bursts up through the cake at every ZONE boundary
	-- (`composition.groups`) and must be beaten before the next zone can be
	-- eaten. It has NO timer on purpose: it is a GATE, not a race, and a
	-- timeout loss 8 minutes into a 35-minute run would be pure punishment.
	-- Deliberately short -- ~8-15 s of tapping, then back to eating.
	miniBoss = {
		-- HP = tapsPerPlayer x max(1, players) x difficulty bossHpMultiplier
		--      x tapsGrowth^(index-1), so each gate is a little meatier than the
		-- last: 50 / 63 / 78 / 98 taps for the FOUR gates of a 5-zone cake.
		-- ⚠ Growth came down 1.35 -> 1.25 when the cake went to 5 zones: at 1.35
		-- the fourth gate would be 123 taps, i.e. MORE than the Cake Guardian's
		-- 120, and a mini-boss must never out-fight the finale.
		tapsPerPlayer = 50,
		tapsGrowth = 1.25,
		-- Authored rigs under `ReplicatedStorage.Assets.MiniBosses` (moved out
		-- of Workspace 2026-08-07). The roll picks DISTINCT ones per cake; a
		-- name missing from the folder warns and the view falls back to the
		-- Cake Guardian's gummy bear (R8 -- never a silent no-show).
		models = { "MrsCCustom", "SweetyCarolCustom", "SammyCustom", "Shiny", "Onion" },
		-- SIZE TRACKS HP (user req): 4x a player at full HP shrinking to half a
		-- player at 0, then it pops. `playerHeightStuds` is what an avatar
		-- stands at, so the two multipliers read literally as "x the player".
		playerHeightStuds = 5,
		scaleFull = 4,
		scaleDead = 0.5,
		-- THE ENTRANCE. It starts buried this far under the freshly-cleared
		-- layer floor and punches up through it, overshooting before it settles
		-- -- "suddenly breaking through the top and standing up".
		emergeDepthStuds = 26,
		emergeSeconds = 0.7,
		emergeOvershootStuds = 3.5,
		settleSeconds = 0.35,
		-- It STANDS STILL and only yaws to face the player. Client-side, so
		-- every player is the one being looked at. Degrees/second.
		faceTurnDegrees = 220,
		bobAmplitude = 0.35, -- studs of idle breathing, so it isn't a statue
		bobSpeed = 2.2,
		hpBarWidthPx = 300,
	},
	-- Progress announcements (client hints "cotton candy in 18%").
	progressBroadcastHz = 1,
}

return CakeConfig
