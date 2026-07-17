--[[
	MapConfigData — candy-room map tuning (R1). MapService builds from
	these numbers at boot; biome palettes recolor per cake (GDD §9).

	Reference look: an indoor candy world — studded chocolate walls with
	X-braces and one pink accent wall, dessert props (gumballs, lollipops,
	peppermints, cookies, chocolate bars, cupcakes) glued to the walls,
	dark chocolate floor, cream cake plate. The cake itself lives at
	CakeConfig.grid.origin (bottom y=2).
]]

local MapConfigData = {}

MapConfigData.floor = { size = 340, thickness = 2 }
-- Rectangular cake tray under the loaf (84x57 studs of cake + a lip).
MapConfigData.platform = { length = 100, width = 72, height = 2 } -- top = cake bottom
MapConfigData.spawnHeightAboveCake = 8 -- fall onto the frosting (§7.1 crust crack)

-- The room: four decorated walls around the play area.
MapConfigData.room = {
	size = 340, -- inner width (walls at ±170)
	wallHeight = 110,
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

-- Gym zone (GDD §8): a pad with machines, right next to the cake so the
-- eat->burn loop takes seconds, not a hike.
MapConfigData.gym = {
	center = { x = 78, z = 0 },
	padSize = 28,
	machineCount = 4,
	promptName = "GymPrompt", -- BodySubs listens for this prompt name
	maxUseDistanceStuds = 14, -- server-side range validation
}

-- Landmark candles (§6.3): static towers on the TRAY corners, just outside
-- the loaf footprint (±42 × ±28.5) but inside the plate (±50 × ±36).
-- Inside-the-cake placement clipped through the mesh walls and read as
-- rendering glitches (user feedback 2026-07-17).
MapConfigData.candles = {
	{ x = 46, z = 32, height = 78, radius = 2.5 },
	{ x = -46, z = -32, height = 72, radius = 2 },
	{ x = -46, z = 32, height = 84, radius = 3 },
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
