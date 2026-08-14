--[[
	MapConfigData — candy-room map tuning (R1).

	Since ADR-0007 the static scene is CLONED from editable place-authored models
	in `ReplicatedStorage.Assets` (Environment + Checkpoint), NOT built from these
	numbers at runtime. These numbers now serve two roles: they SEED the default
	look (`MapService.GenerateAssets` — the fallback generator the user replaces in
	Studio), and the `checkpoint` + `biomes` blocks still drive RUNTIME logic
	(SetCheckpointHeight placement + reach math; per-biome recolor of role-tagged
	parts). Visual props/colours are otherwise authored in the place now.

	Reference look: an indoor candy world — studded chocolate walls with
	X-braces and one pink accent wall, dessert props (gumballs, lollipops,
	peppermints, cookies, chocolate bars, cupcakes) glued to the walls,
	dark chocolate floor, cream cake plate. The cake itself lives at
	CakeConfig.grid.origin (bottom y=2).
]]

local MapConfigData = {}

MapConfigData.floor = { size = 340, thickness = 2 }
-- Cake tray under the cake. A 5-stud lip read as a bare slab at ground level —
-- the cake appeared to meet the floor with nothing under it (map inspection,
-- 2026-07-26). A ~12-stud lip and a thicker slab read as a cake PLATE, which is
-- what the eye expects under a layer cake.
-- ROUND since 2026-08-03, when the cake became ROUND (MapService gives the part
-- a CylinderMesh, so length == width is a DIAMETER): the cake is a disc of
-- radius `footprint.corner * grid.cell` = 46.65 studs, so the old 114x102 tray
-- kept a 10.4-stud lip in X but left only 4.4 in Z — the thin-lip bug above,
-- back on two sides. ⌀117.3 restores the uniform ~12-stud lip all round.
-- ⚠ DEFAULT-GENERATOR ONLY (ADR-0007): an already-authored Environment keeps
-- its own tray, so this number does NOT ship. MEASURED in Studio 2026-08-03:
-- the authored `Assets.Environment.CakePlate` is 100 x 88 (±50 x ±44), so the
-- round cake CLEARS it by 3.35 studs in X but OVERHANGS it by 2.65 in Z. The
-- authored plate has to be re-modelled (round, ⌀ ≥ 117) — a config edit cannot
-- move it.
MapConfigData.platform = { length = 117.3, width = 117.3, height = 4 } -- top = cake bottom
MapConfigData.spawnHeightAboveCake = 8 -- fall onto the frosting (§7.1 crust crack)

-- The room: four decorated walls around the play area.
MapConfigData.room = {
	size = 340, -- inner width (walls at ±170)
	-- Height of the GENERATED fallback room, sized for the 170-stud classic: its
	-- top is grid.origin.y (2) + 170 = 172 and the spawn pad rides ~8 above.
	-- Selectable taller cakes use their own authored environment (rainbow uses
	-- Environment1, whose shipped room has no central ceiling). Any future room
	-- with a ceiling must clear that variant's cake top + spawn drop.
	-- ⚠ KEEP THIS IN STEP WITH the CLASSIC height. It was left at 380 when the cake
	-- came down from 330 to 170, which builds a cavernous 2x-too-tall room around
	-- the loaf in any fresh clone — the scale reads wrong and the walls stop
	-- framing the cake at all.
	-- (The scene is CLONED from place-authored ReplicatedStorage.Assets — this
	-- only reseeds the DEFAULT generator, so an already-authored room keeps its
	-- own height until you lower it in Studio, ADR-0007.)
	wallHeight = 210,
	wallThickness = 6,
	braceThickness = 2.5, -- diagonal X-braces on chocolate walls
	propsPerWall = 20,
	propSeed = 7, -- deterministic prop layout
	-- Candy prop palette (bright, saturated — the world must look edible).
	propColors = {
		Color3.fromRGB(255, 105, 180), -- hot pink
		Color3.fromRGB(235, 45, 60), -- candy red
		Color3.fromRGB(80, 200, 90), -- apple green
		Color3.fromRGB(70, 160, 255), -- berry blue
		Color3.fromRGB(255, 160, 40), -- orange
		Color3.fromRGB(185, 100, 235), -- grape purple
	},
}

-- Checkpoint platform (GDD §8 gym): a platform standing on 4 legs BESIDE the
-- cake, its top surface tracking the current TOP LAYER height — it steps DOWN
-- one layer at a time as the cake is eaten (CakeSubs.SetCheckpointHeight, driven
-- by CakeFieldService.ScanStats topBandIndex). You return to it (F key / HUD
-- button -> ReturnToCheckpoint remote) to burn fat at the gym machine on it.
-- This REPLACES the old floor gym zone: fat is now extracted here, always at
-- your eating height, so a full belly is seconds from the machine.
--
-- Placement: the +X side of the cake. MapService sets the plate's inner edge
-- `edgeGap` studs past `footprint.hx * grid.cell` — the cake's +X extreme, which
-- is 46.65 studs since the cake went ROUND (was the loaf's 45-stud straight edge,
-- so the whole checkpoint simply shifted out 1.65 studs).
-- ⚠ A DISC HAS NO STRAIGHT EDGE, so that gap is only `edgeGap` at z = 0 and
-- widens toward the plate's z-ends: at z = ±plateWidth/2 (±13) the cake has
-- curved back to x = 44.8, i.e. a 2.3-stud gap. Crossing happens at the centre
-- (the F teleport lands mid-plate and the walk-back path runs along z ~ 0), so
-- the crossing itself is unchanged — but do not widen `plateWidth` without
-- re-checking this, and treat the plate's two cake-side corners as a hop.
-- Legs drop to the floor (y = 0). All heights are RELATIVE
-- to the cake origin; MapService adds origin.x/z.
MapConfigData.checkpoint = {
	edgeGap = 0.5, -- studs from the cake's +X extreme (z=0 only — see above) to the plate
	plateDepth = 18, -- studs, X extent (away from the cake)
	plateWidth = 26, -- studs, Z extent. ⚠ Widening it widens the cake gap at the ends
	plateThickness = 2,
	-- Narrow selectable terraces cannot move the supported platform inward: its
	-- tall legs would pierce the wider layers below. MapService instead clones one
	-- plain authored CheckpointLeg into this horizontal, pooled walkway. Its
	-- cake-side edge follows the ACTIVE band's +X edge while the platform stays
	-- fixed beside the maximum footprint.
	bridgeName = "CheckpointBridge",
	bridgeWidth = 8, -- Z width; a centred character-safe path without a broad disc-edge gap
	bridgeThickness = 1,
	bridgePlateOverlap = 0.25, -- prevents a physics seam at the authored plate edge
	bridgeHideBelowStuds = 0.05, -- full-size/classic band: no bridge geometry needed
	legSize = 3, -- studs, square leg cross-section
	legInset = 2, -- studs the legs are inset from the plate edges
	minLegHeight = 2, -- studs, floor for the leg height when the cake is near-bare
	machineSize = Vector3.new(4, 6, 4), -- gym machine box, near the outer edge
	standHeight = 3.5, -- studs above the plate top for the teleport landing point
	promptName = "GymPrompt", -- BodySubs listens for this prompt name
	-- Gym reachability lives here (not baked in MapService): the teleport lands
	-- the player at the plate CENTRE, the machine sits near the outer edge —
	-- keep promptRange ≥ (plateDepth/2 - machineSize.X/2 - 1) so the prompt is
	-- active on arrival, and maxUseDistanceStuds ≥ promptRange so the server
	-- range re-check never rejects a legit prompt. Widen both if plateDepth grows.
	promptRange = 10, -- ProximityPrompt.MaxActivationDistance
	maxUseDistanceStuds = 16, -- server-side range validation (gym start)
	-- Upgrade station: a "computer" terminal standing on the plate (cake-side
	-- corner, clear of the centre landing + the walk-back path to the loaf). Its
	-- ProximityPrompt OPENS the upgrades hex-tree — handled entirely client-side
	-- (UpgradesSubsClient listens for this prompt name); no server round-trip,
	-- since opening a menu is local UI. Rides the plate height like the machine.
	stationSize = Vector3.new(4, 5, 3),
	stationScreenSize = Vector3.new(4.4, 3.2, 0.5),
	upgradePromptName = "UpgradeStation",
	upgradePromptRange = 10, -- ProximityPrompt.MaxActivationDistance (open range)
	-- LAYER EATER (features/checkpoint.md): an authored prop standing on the
	-- plate whose ProximityPrompt offers the 9 R$ `layer-eater` dev product; the
	-- receipt clears the layer the cake is currently on. Unlike the machine and
	-- the station — which code PLACES at computed corners — this one keeps the
	-- position and ROTATION it was authored with, expressed as its offset from
	-- the authored plate, and only rides the plate's movement. Two reasons:
	-- authoring it is the whole point (it is a decorative contraption, not a
	-- collider box), and its authored pivot carries a yaw that a
	-- `PivotTo(CFrame.new(...))` would silently throw away.
	-- ⚠ `layerEaterPromptName` is DUPLICATED in the client's `ShopUiData` (the
	-- client is what listens for the trigger — same split as `UpgradeStation` /
	-- `UpgradesUiData`). Rename in both or the prompt stops selling anything.
	layerEaterName = "LayerEater",
	layerEaterPromptName = "LayerEaterPrompt",
	-- ⚠ MEASURED, not guessed: the F-teleport lands the player at the plate CENTRE
	-- and the authored eater sits 10.1 studs from it, so at the machine's range of
	-- 10 the prompt was invisible at exactly the moment it is relevant (you arrive
	-- with a full belly, look at the checkpoint, and the thing you can buy is not
	-- there). 14 shows it on arrival with margin and still keeps it plate-local.
	-- Re-measure if the authored LayerEater is moved. There is NO server-side range
	-- re-check for this one (unlike the gym): buying the product from anywhere is a
	-- legitimate purchase, not an exploit.
	layerEaterPromptRange = 14, -- ProximityPrompt.MaxActivationDistance
	layerEaterSize = Vector3.new(4, 5, 4), -- DEFAULT GENERATOR ONLY (authored model wins)
	layerEaterColor = Color3.fromRGB(250, 170, 60),
	-- REFUSE the sale below this much of the top band left (fraction of what the
	-- band held when the cake was built). The prompt sits where a player arrives
	-- with a FULL BELLY — i.e. usually deep into the current layer — so without a
	-- floor the common case is paying a fixed 9 R$ for the last scraps, and a
	-- dev product's price is permanent so it can never be corrected downward.
	-- 0.25 keeps the offer worth at least a quarter of a layer; the refusal is
	-- logged and the Roblox dialog never opens, so the player is not charged.
	layerEaterMinRemainingFraction = 0.25,
	-- Treadmill (fat removal, user req 4): the GymMachine's authored Model IS a
	-- treadmill; pressing the gym prompt MOUNTS the player on the belt (anchored +
	-- a run animation, BodySubs) and, when the belly empties, DISMOUNTS them beside
	-- it. The machine (collider) + its authored visual RIDE the plate top (moved
	-- rigidly in SetCheckpointHeight), so this mount geometry is relative to the
	-- current PLATE TOP. Tune in Studio to line the feet up with the belt / clear
	-- the step-off of the machine.
	treadmillStandHeight = 6.2, -- HRP Y above the plate top while standing on the belt (Studio-verified: feet on the deck)
	treadmillFaceYaw = 0, -- degrees, facing along the belt (0 = −Z; set to the belt's long axis)
	treadmillDismountBack = 5, -- studs toward the plate centre (−X) for the step-off spot
	treadmillDismountHeight = 3.5, -- HRP Y above the plate top at the dismount spot
	-- Candy scaffold palette (static — it's structure, not a biome surface).
	plateColor = Color3.fromRGB(240, 130, 190),
	legColor = Color3.fromRGB(150, 92, 60),
	machineColor = Color3.fromRGB(220, 60, 80),
	stationBodyColor = Color3.fromRGB(70, 120, 190),
	stationScreenColor = Color3.fromRGB(120, 224, 255),
}

-- Landmark candles (§6.3): static towers on the TRAY corners, outside the cake
-- but inside the tray. The cake is a disc of radius 46.65 studs and the tray is
-- ±58.65, so the three corner candles (|pos| ~ 63.8 from the centre, minus their
-- own radius) sit in margin the disc cannot reach — a round cake frees the four
-- corners completely, which is exactly where these stand.
-- Inside-the-cake placement clipped through the mesh walls and read as
-- rendering glitches (user feedback 2026-07-17) — moved out with the bigger loaf.
MapConfigData.candles = {
	{ x = 48, z = 42, height = 78, radius = 2.5 },
	{ x = -48, z = -42, height = 72, radius = 2 },
	{ x = -48, z = 42, height = 84, radius = 3 },
}

-- Conveyor the cake "arrived" on: purely decorative.
MapConfigData.conveyor = { width = 40, length = 330, height = 1.6 }

MapConfigData.biomes = {
	factory = {
		nameKey = "biome-factory",
		caloriesMult = 1,
		floorColor = Color3.fromRGB(72, 44, 28), -- dark chocolate
		platformColor = Color3.fromRGB(252, 244, 230), -- cream cake plate
		conveyorColor = Color3.fromRGB(58, 36, 24),
		wallColor = Color3.fromRGB(96, 58, 34), -- milk chocolate
		accentWallColor = Color3.fromRGB(240, 130, 190), -- candy pink
		beamColor = Color3.fromRGB(62, 38, 24),
		ceilingColor = Color3.fromRGB(255, 190, 225), -- cotton-candy sky
		ambient = Color3.fromRGB(185, 172, 168),
		brightness = 2.2,
	},
	donut = {
		nameKey = "biome-donut",
		caloriesMult = 1.5,
		floorColor = Color3.fromRGB(92, 52, 40),
		platformColor = Color3.fromRGB(255, 238, 244),
		conveyorColor = Color3.fromRGB(70, 42, 34),
		wallColor = Color3.fromRGB(238, 148, 190), -- frosted pink
		accentWallColor = Color3.fromRGB(150, 92, 60), -- choco glaze
		beamColor = Color3.fromRGB(120, 66, 48),
		ceilingColor = Color3.fromRGB(255, 214, 235),
		ambient = Color3.fromRGB(190, 172, 172),
		brightness = 2.2,
	},
	candy = {
		nameKey = "biome-candy",
		caloriesMult = 2.25,
		floorColor = Color3.fromRGB(60, 76, 110),
		platformColor = Color3.fromRGB(236, 246, 255),
		conveyorColor = Color3.fromRGB(48, 58, 88),
		wallColor = Color3.fromRGB(120, 190, 255), -- bubblegum blue
		accentWallColor = Color3.fromRGB(255, 120, 190),
		beamColor = Color3.fromRGB(70, 110, 170),
		ceilingColor = Color3.fromRGB(210, 235, 255),
		ambient = Color3.fromRGB(178, 182, 195),
		brightness = 2.2,
	},
}

return MapConfigData
