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
-- Rectangular cake tray under the loaf (90x78 studs of cake + a ~5-stud lip;
-- grown from 100x72 for the bigger footprint so the loaf never overhangs it).
MapConfigData.platform = { length = 100, width = 88, height = 2 } -- top = cake bottom
MapConfigData.spawnHeightAboveCake = 8 -- fall onto the frosting (§7.1 crust crack)

-- The room: four decorated walls around the play area.
MapConfigData.room = {
	size = 340, -- inner width (walls at ±170)
	-- Tall enough to clear the 3× cake: a 4-player loaf tops out ~261 studs
	-- (grid.origin.y 2 + composition height), so the walls + ceiling (at
	-- wallHeight+1) must sit above it or players eating the top clip through the
	-- ceiling / spawn above the room. (The scene is CLONED from place-authored
	-- ReplicatedStorage.Assets — if the room is already authored at the old
	-- height, raise its walls/ceiling in Studio too; this only reseeds the
	-- default generator, ADR-0007.)
	wallHeight = 300,
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
-- Placement: the +X side of the loaf. The loaf's +X edge is at
-- footprint.hx * grid.cell (30 * 1.5 = 45 studs); the plate's inner edge sits
-- `edgeGap` studs off it (its z-span stays inside the straight edge, clear of
-- the rounded corners). Legs drop to the floor (y = 0). All heights are RELATIVE
-- to the cake origin; MapService adds origin.x/z.
MapConfigData.checkpoint = {
	edgeGap = 0.5, -- studs between the loaf edge and the plate's inner (cake-side) edge
	plateDepth = 18, -- studs, X extent (away from the cake)
	plateWidth = 26, -- studs, Z extent (along the cake side; < straight-edge span)
	plateThickness = 2,
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

-- Landmark candles (§6.3): static towers on the TRAY corners, just outside
-- the loaf footprint (now ±45 × ±39) but inside the tray (±50 × ±44).
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
