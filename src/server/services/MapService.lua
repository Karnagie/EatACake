--[[
	MapService — builds the candy room (floor, walls with candy props, cake
	platform, CHECKPOINT platform, spawn, candle landmarks) from MapConfigData
	at boot; recolors per biome.

	The map is CODE-BUILT (no Studio-authored scene in this project yet) —
	one-time construction (Build is called from CakeSubs.Start, before the
	first cake), not a runtime hot path. Studded surfaces use the native
	Studs SurfaceType (the reference "chocolate LEGO wall" look).

	CHECKPOINT (fat extraction, features/checkpoint.md): a platform on 4 legs
	beside the loaf whose TOP tracks the current top-layer height. It carries the
	gym machine + a ProximityPrompt named MapConfigData.checkpoint.promptName
	(BodySubs connects the trigger, R4) AND an upgrade-station "computer" whose
	ProximityPrompt (checkpoint.upgradePromptName) opens the upgrades hex-tree
	client-side (UpgradesSubsClient). CakeSubs drives its height via
	SetCheckpointHeight and teleports players onto it (GetCheckpointCFrame) on the
	ReturnToCheckpoint remote. This service owns the parts (part refs are cached
	locals, the code-built-map pattern) but never subscribes to events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local MapService = {}

local mapCfg -- MapConfigData
local gridCfg -- CakeConfigData.cake.grid
local footprintCfg -- CakeConfigData.cake.composition.footprint (FIXED loaf)

local mapFolder: Folder?
local floorPart: BasePart?
local platformPart: BasePart?
local conveyorPart: BasePart?
local wallParts: { BasePart } = {}
local accentWallParts: { BasePart } = {}
local beamParts: { BasePart } = {}
local ceilingPart: BasePart?

-- Checkpoint platform (built once, moved by SetCheckpointHeight).
local checkpointFolder: Folder?
local checkpointPlate: BasePart?
local checkpointLegs: { BasePart } = {}
local checkpointMachine: BasePart?
local checkpointStationBody: BasePart? -- upgrade "computer" body (rides the plate)
local checkpointStationScreen: BasePart? -- its glowing screen
local checkpointCenter: Vector3? -- XZ center of the plate (Y unused)
local checkpointTopY: number? -- current world Y of the plate's top surface
local cakeSpawnPart: BasePart? -- CakeSpawn pad; Y rides the cake top (SetCheckpointHeight)

function MapService.Init(data)
	mapCfg = data.MapConfigData
	gridCfg = data.CakeConfigData.cake.grid
	footprintCfg = data.CakeConfigData.cake.composition.footprint
end

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

-- Every face gets the LEGO-stud look (reference walls/floor).
local function studAllSurfaces(part: BasePart)
	part.TopSurface = Enum.SurfaceType.Studs
	part.FrontSurface = Enum.SurfaceType.Studs
	part.BackSurface = Enum.SurfaceType.Studs
	part.LeftSurface = Enum.SurfaceType.Studs
	part.RightSurface = Enum.SurfaceType.Studs
end

-- Decorative prop part: never collides, never blocks rays or bites.
local function propPart(props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.Material = props.Material or Enum.Material.SmoothPlastic
	return makePart(props)
end

-- ── Candy props (reference wall decorations) ────────────────────────────
-- Each builder mounts at `pos` on a wall whose inward normal is `normal`.
-- Discs are Cylinders with their axis (local X) aligned to the normal via
-- CFrame.fromMatrix(pos, normal, up).

local function discCF(pos: Vector3, normal: Vector3): CFrame
	return CFrame.fromMatrix(pos, normal, Vector3.yAxis)
end

local function propGumball(folder, rng: Random, pos, normal, color)
	local d = rng:NextNumber(6, 10)
	propPart({
		Name = "Gumball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(d, d, d),
		CFrame = CFrame.new(pos),
		Color = color,
		Reflectance = 0.08,
		Parent = folder,
	})
end

local function propLollipop(folder, rng: Random, pos, normal, color)
	propPart({
		Name = "LollipopHead",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 9, 9),
		CFrame = discCF(pos, normal),
		Color = color,
		Reflectance = 0.08,
		Parent = folder,
	})
	local tilt = rng:NextNumber(-0.5, 0.5)
	propPart({
		Name = "LollipopStick",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(11, 1, 1),
		CFrame = CFrame.new(pos - Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90 + tilt * 25)),
		Color = Color3.fromRGB(250, 250, 250),
		Parent = folder,
	})
end

local function propPeppermint(folder, rng: Random, pos, normal, color)
	propPart({
		Name = "MintBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.8, 9, 9),
		CFrame = discCF(pos, normal),
		Color = Color3.fromRGB(252, 250, 248),
		Parent = folder,
	})
	propPart({
		Name = "MintSwirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.1, 4.6, 4.6),
		CFrame = discCF(pos + normal * 0.2, normal),
		Color = Color3.fromRGB(235, 45, 60),
		Parent = folder,
	})
end

local function propCookie(folder, rng: Random, pos, normal, color)
	propPart({
		Name = "Cookie",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 10, 10),
		CFrame = discCF(pos, normal),
		Color = Color3.fromRGB(198, 142, 80),
		Parent = folder,
	})
	local tangent = normal:Cross(Vector3.yAxis)
	for _ = 1, 4 do
		local u = rng:NextNumber(-3, 3)
		local v = rng:NextNumber(-3, 3)
		propPart({
			Name = "Chip",
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(pos + tangent * u + Vector3.new(0, v, 0) + normal * 1.0)
				* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			Color = Color3.fromRGB(66, 38, 22),
			Parent = folder,
		})
	end
end

local function propChocolateBar(folder, rng: Random, pos, normal, color)
	local tangent = normal:Cross(Vector3.yAxis)
	propPart({
		Name = "BarBase",
		Size = Vector3.new(8.5, 11.5, 1.6),
		CFrame = CFrame.fromMatrix(pos, tangent, Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-20, 20))),
		Color = Color3.fromRGB(80, 46, 26),
		Parent = folder,
	})
	for gx = -1, 1, 2 do
		for gy = -1, 1 do
			propPart({
				Name = "BarSquare",
				Size = Vector3.new(3.1, 3.1, 0.8),
				CFrame = CFrame.fromMatrix(pos + tangent * (gx * 2.05) + Vector3.new(0, gy * 3.5, 0) + normal * 1.0, tangent, Vector3.yAxis),
				Color = Color3.fromRGB(96, 58, 34),
				Parent = folder,
			})
		end
	end
end

local function propCupcake(folder, rng: Random, pos, normal, color)
	propPart({
		Name = "CupcakeBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(5, 6.5, 6.5),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(238, 200, 140),
		Parent = folder,
	})
	propPart({
		Name = "CupcakeFrosting",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 5.6, 7),
		CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)),
		Color = color,
		Reflectance = 0.05,
		Parent = folder,
	})
	propPart({
		Name = "Cherry",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(pos + Vector3.new(0, 7, 0)),
		Color = Color3.fromRGB(235, 45, 60),
		Reflectance = 0.15,
		Parent = folder,
	})
end

local function propStrawberry(folder, rng: Random, pos, normal, color)
	propPart({
		Name = "Strawberry",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6.5, 8, 6.5),
		CFrame = CFrame.new(pos),
		Color = Color3.fromRGB(230, 40, 60),
		Reflectance = 0.06,
		Parent = folder,
	})
	propPart({
		Name = "StrawberryTop",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.4, 3.6, 3.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 170, 80),
		Parent = folder,
	})
end

local function propCandyWrap(folder, rng: Random, pos, normal, color)
	local tangent = normal:Cross(Vector3.yAxis)
	propPart({
		Name = "CandyBody",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 4.4, 4.4),
		CFrame = CFrame.fromMatrix(pos, tangent, Vector3.yAxis),
		Color = color,
		Reflectance = 0.1,
		Parent = folder,
	})
	for side = -1, 1, 2 do
		propPart({
			Name = "CandyTwist",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.4, 2, 2),
			CFrame = CFrame.fromMatrix(pos + tangent * (side * 3.7), tangent, Vector3.yAxis),
			Color = Color3.fromRGB(250, 250, 250),
			Parent = folder,
		})
	end
end

local PROP_BUILDERS = {
	propGumball,
	propLollipop,
	propPeppermint,
	propCookie,
	propChocolateBar,
	propCupcake,
	propStrawberry,
	propCandyWrap,
}

--API
-- Builds the whole scene once (idempotent). Called from CakeSubs.Start.
function MapService.Build()
	if mapFolder then
		return
	end
	-- The place file ships a default Baseplate + SpawnLocation — remove
	-- them (the candy room replaces both; players must spawn ON the cake).
	local stray = workspace:FindFirstChild("Baseplate")
	if stray then
		stray:Destroy()
	end
	local straySpawn = workspace:FindFirstChild("SpawnLocation")
	if straySpawn then
		straySpawn:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Map"
	mapFolder = folder

	local origin = gridCfg.origin
	local biome = mapCfg.biomes.factory
	local room = mapCfg.room
	local half = room.size / 2

	local floorP = makePart({
		Name = "FactoryFloor",
		Size = Vector3.new(room.size + room.wallThickness * 2, mapCfg.floor.thickness, room.size + room.wallThickness * 2),
		CFrame = CFrame.new(origin.x, -mapCfg.floor.thickness / 2, origin.z),
		Color = biome.floorColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	floorP.TopSurface = Enum.SurfaceType.Studs
	floorPart = floorP

	conveyorPart = makePart({
		Name = "Conveyor",
		Size = Vector3.new(mapCfg.conveyor.length, mapCfg.conveyor.height, mapCfg.conveyor.width),
		CFrame = CFrame.new(origin.x, mapCfg.conveyor.height / 2, origin.z),
		Color = biome.conveyorColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	conveyorPart.TopSurface = Enum.SurfaceType.Studs

	platformPart = makePart({
		Name = "CakePlate",
		Size = Vector3.new(mapCfg.platform.length, mapCfg.platform.height, mapCfg.platform.width),
		CFrame = CFrame.new(origin.x, origin.y - mapCfg.platform.height / 2, origin.z),
		Color = biome.platformColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.05,
		Parent = folder,
	})

	-- ── Walls: 3 chocolate + 1 pink accent, studded, with X-braces ──────
	table.clear(wallParts)
	table.clear(accentWallParts)
	table.clear(beamParts)
	local walls = {
		{ center = Vector3.new(origin.x, room.wallHeight / 2, origin.z - half - room.wallThickness / 2), normal = Vector3.zAxis, accent = true },
		{ center = Vector3.new(origin.x, room.wallHeight / 2, origin.z + half + room.wallThickness / 2), normal = -Vector3.zAxis, accent = false },
		{ center = Vector3.new(origin.x - half - room.wallThickness / 2, room.wallHeight / 2, origin.z), normal = Vector3.xAxis, accent = false },
		{ center = Vector3.new(origin.x + half + room.wallThickness / 2, room.wallHeight / 2, origin.z), normal = -Vector3.xAxis, accent = false },
	}
	local rng = Random.new(room.propSeed)
	for wallIndex, wall in ipairs(walls) do
		local tangent = wall.normal:Cross(Vector3.yAxis)
		local wallLength = room.size + room.wallThickness * 2
		local part = makePart({
			Name = `Wall_{wallIndex}`,
			Size = Vector3.new(wallLength, room.wallHeight, room.wallThickness),
			CFrame = CFrame.fromMatrix(wall.center, tangent, Vector3.yAxis),
			Color = if wall.accent then biome.accentWallColor else biome.wallColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
		studAllSurfaces(part)
		table.insert(if wall.accent then accentWallParts else wallParts, part)

		-- X-braces on chocolate walls (reference structure).
		if not wall.accent then
			for angle = -1, 1, 2 do
				local brace = makePart({
					Name = `Brace_{wallIndex}_{angle}`,
					Size = Vector3.new(wallLength * 0.62, room.braceThickness * 2, 1.2),
					CFrame = CFrame.fromMatrix(
						wall.center + wall.normal * (room.wallThickness / 2 + 0.6),
						tangent,
						Vector3.yAxis
					) * CFrame.Angles(0, 0, math.rad(angle * 24)),
					Color = biome.beamColor,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = folder,
				})
				table.insert(beamParts, brace)
			end
		end

		-- Candy props scattered over the inner face.
		for _ = 1, room.propsPerWall do
			local u = rng:NextNumber(-half * 0.85, half * 0.85)
			local v = rng:NextNumber(14, room.wallHeight * 0.85)
			local pos = wall.center
				+ tangent * u
				+ Vector3.new(0, v - room.wallHeight / 2, 0)
				+ wall.normal * (room.wallThickness / 2 + 1.4)
			local color = room.propColors[rng:NextInteger(1, #room.propColors)]
			local builder = PROP_BUILDERS[rng:NextInteger(1, #PROP_BUILDERS)]
			builder(folder, rng, pos, wall.normal, color)
		end
	end

	-- Cotton-candy ceiling closes the room (reference: indoor candy world).
	local ceiling = makePart({
		Name = "Ceiling",
		Size = Vector3.new(room.size + room.wallThickness * 2, 2, room.size + room.wallThickness * 2),
		CFrame = CFrame.new(origin.x, room.wallHeight + 1, origin.z),
		Color = biome.ceilingColor,
		Material = Enum.Material.SmoothPlastic,
		CanQuery = false,
		Parent = folder,
	})
	ceiling.BottomSurface = Enum.SurfaceType.Studs
	ceilingPart = ceiling

	-- Candle landmarks: peppermint-striped towers (§6.3).
	for k, candle in ipairs(mapCfg.candles) do
		local body = makePart({
			Name = `Candle_{k}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(candle.height, candle.radius * 2, candle.radius * 2),
			CFrame = CFrame.new(origin.x + candle.x, origin.y + candle.height / 2, origin.z + candle.z)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 248, 235),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.04,
			Parent = folder,
		})
		-- Red spiral stripes: a few thin rings up the candle.
		for s = 1, 4 do
			makePart({
				Name = "CandleStripe",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(3, candle.radius * 2.15, candle.radius * 2.15),
				CFrame = body.CFrame * CFrame.new(candle.height * (s / 5) - candle.height / 2, 0, 0),
				Color = Color3.fromRGB(235, 45, 60),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = folder,
			})
		end
		local flame = makePart({
			Name = "Flame",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(candle.radius * 1.6, candle.radius * 2.4, candle.radius * 1.6),
			CFrame = body.CFrame * CFrame.new(candle.height / 2 + candle.radius, 0, 0),
			Color = Color3.fromRGB(255, 170, 40),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = folder,
		})
		local light = Instance.new("PointLight")
		light.Color = flame.Color
		light.Range = 24
		light.Parent = flame
	end

	-- Checkpoint platform (§8 gym): a platform on 4 legs beside the loaf whose
	-- TOP tracks the current top-layer height (SetCheckpointHeight, driven by
	-- CakeSubs). The gym machine + prompt ride it; players teleport onto it
	-- (GetCheckpointCFrame). Built once here, then positioned per cake.
	local cp = mapCfg.checkpoint
	local loafEdgeX = footprintCfg.hx * gridCfg.cell -- +X straight edge of the loaf
	local plateCenterX = origin.x + loafEdgeX + cp.edgeGap + cp.plateDepth / 2
	local plateCenterZ = origin.z
	checkpointCenter = Vector3.new(plateCenterX, 0, plateCenterZ)

	local cpFolder = Instance.new("Folder")
	cpFolder.Name = "Checkpoint"
	checkpointFolder = cpFolder

	checkpointPlate = makePart({
		Name = "CheckpointPlate",
		Size = Vector3.new(cp.plateDepth, cp.plateThickness, cp.plateWidth),
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.plateColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
		Parent = cpFolder,
	})
	checkpointPlate.TopSurface = Enum.SurfaceType.Studs

	-- 4 legs at the plate corners (positioned/resized by SetCheckpointHeight).
	table.clear(checkpointLegs)
	for _ = 1, 4 do
		table.insert(checkpointLegs, makePart({
			Name = "CheckpointLeg",
			Size = Vector3.new(cp.legSize, cp.minLegHeight, cp.legSize),
			CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
			Color = cp.legColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = cpFolder,
		}))
	end

	-- Gym machine near the OUTER edge (leaves the cake-side clear to walk back).
	checkpointMachine = makePart({
		Name = "GymMachine",
		Size = cp.machineSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.machineColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = cpFolder,
	})
	studAllSurfaces(checkpointMachine)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = cp.promptName
	prompt.ActionText = "Burn it off!"
	prompt.ObjectText = "Gym"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cp.promptRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = checkpointMachine

	-- Upgrade station "computer": a terminal on the cake-side corner of the plate
	-- whose ProximityPrompt opens the upgrades hex-tree (client handles the open —
	-- features/upgrades.md). Positioned/ridden by SetCheckpointHeight.
	checkpointStationBody = makePart({
		Name = "UpgradeStationBody",
		Size = cp.stationSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.stationBodyColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = cpFolder,
	})
	studAllSurfaces(checkpointStationBody)
	checkpointStationScreen = makePart({
		Name = "UpgradeStationScreen",
		Size = cp.stationScreenSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.stationScreenColor,
		Material = Enum.Material.Neon,
		Parent = cpFolder,
	})
	local screenLight = Instance.new("PointLight")
	screenLight.Color = cp.stationScreenColor
	screenLight.Range = 12
	screenLight.Brightness = 1.2
	screenLight.Parent = checkpointStationScreen
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = cp.upgradePromptName
	upgradePrompt.ActionText = "Upgrades"
	upgradePrompt.ObjectText = "Upgrade Station"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = cp.upgradePromptRange
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.Parent = checkpointStationBody

	cpFolder.Parent = folder

	-- Initial placement (spawnNewCake corrects it to the real top layer per cake).
	MapService.SetCheckpointHeight(origin.y + gridCfg.maxHeight * 0.6)

	-- Spawn: directly on the cake (§12.1) — invisible, non-colliding pad
	-- above the frosting; players drop onto the crust. Its Y RIDES the current
	-- cake top via SetCheckpointHeight (below) so the drop stays a small
	-- crust-crack, NOT a fall from `maxHeight` (which is now sized for the tall
	-- 4-player loaf — a fixed maxHeight pad would drop solo players ~40 studs).
	-- Initial Y matches the initial checkpoint height; the first cake corrects it.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CakeSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(origin.x, origin.y + gridCfg.maxHeight * 0.6 + mapCfg.spawnHeightAboveCake, origin.z)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	cakeSpawnPart = spawn

	folder.Parent = workspace

	Lighting.Brightness = biome.brightness
	Lighting.Ambient = biome.ambient
	Lighting.OutdoorAmbient = biome.ambient
	Lighting.EnvironmentDiffuseScale = 1
	-- Low specular: at 1.0 the frosting mirror-reflects the dark chocolate
	-- room at grazing angles and the whole cake top reads BROWN.
	Lighting.EnvironmentSpecularScale = 0.1
	Lighting.ClockTime = 14

	Log.Sum(
		"Map",
		`candy room built — floor, plate, 4 walls (+props x{mapCfg.room.propsPerWall * 4}), {#mapCfg.candles} candles, checkpoint platform (gym + upgrade station), cake spawn`
	)
end

--API
-- Recolors the scene for a biome (called on cake spawn).
function MapService.ApplyBiome(biomeId: string)
	local biome = mapCfg.biomes[biomeId]
	if not biome then
		Log.Warn("Map", `unknown biome '{biomeId}' — palette unchanged`)
		return
	end
	if floorPart then
		floorPart.Color = biome.floorColor
	end
	if platformPart then
		platformPart.Color = biome.platformColor
	end
	if conveyorPart then
		conveyorPart.Color = biome.conveyorColor
	end
	for _, part in ipairs(wallParts) do
		part.Color = biome.wallColor
	end
	for _, part in ipairs(accentWallParts) do
		part.Color = biome.accentWallColor
	end
	for _, part in ipairs(beamParts) do
		part.Color = biome.beamColor
	end
	if ceilingPart then
		ceilingPart.Color = biome.ceilingColor
	end
	Lighting.Brightness = biome.brightness
	Lighting.Ambient = biome.ambient
	Lighting.OutdoorAmbient = biome.ambient
end

--API
-- Positions the checkpoint so its plate TOP sits at world Y `topY`: the legs
-- resize down to the floor (y = 0) and the gym machine rides the plate top.
-- Called by CakeSubs on each new cake and whenever the top layer steps down.
function MapService.SetCheckpointHeight(topY: number)
	if checkpointPlate == nil or checkpointCenter == nil then
		Log.Warn("Map", "SetCheckpointHeight before the checkpoint was built — ignored")
		return
	end
	local cp = mapCfg.checkpoint
	-- Never let the plate sit so low the legs vanish (near-bare cake / core).
	topY = math.max(topY, cp.minLegHeight + cp.plateThickness)
	-- Skip redundant moves (the 1 Hz scan re-asserts the same height between
	-- layer changes — no point re-replicating 5 anchored parts every second).
	if checkpointTopY ~= nil and math.abs(checkpointTopY - topY) < 0.01 then
		return
	end
	checkpointTopY = topY
	local cx, cz = checkpointCenter.X, checkpointCenter.Z
	local plateBottomY = topY - cp.plateThickness
	checkpointPlate.CFrame = CFrame.new(cx, topY - cp.plateThickness / 2, cz)

	-- The cake spawn pad rides the SAME cake top (topY = the current top-layer
	-- surface, updated per cake + per layer step) so a (re)spawn is a small drop
	-- onto the crust, not a fall from the tall-cake ceiling (maxHeight, now sized
	-- for the 4-player loaf).
	if cakeSpawnPart then
		cakeSpawnPart.CFrame =
			CFrame.new(cakeSpawnPart.Position.X, topY + mapCfg.spawnHeightAboveCake, cakeSpawnPart.Position.Z)
	end

	-- Legs stand on the floor (y = 0) up to the plate bottom.
	local legHalfDepth = cp.plateDepth / 2 - cp.legInset - cp.legSize / 2
	local legHalfWidth = cp.plateWidth / 2 - cp.legInset - cp.legSize / 2
	local legHeight = math.max(cp.minLegHeight, plateBottomY)
	local corners = {
		Vector3.new(-legHalfDepth, 0, -legHalfWidth),
		Vector3.new(-legHalfDepth, 0, legHalfWidth),
		Vector3.new(legHalfDepth, 0, -legHalfWidth),
		Vector3.new(legHalfDepth, 0, legHalfWidth),
	}
	for k, leg in ipairs(checkpointLegs) do
		local corner = corners[k]
		if corner then
			leg.Size = Vector3.new(cp.legSize, legHeight, cp.legSize)
			leg.CFrame = CFrame.new(cx + corner.X, legHeight / 2, cz + corner.Z)
		end
	end

	if checkpointMachine then
		local machineX = cx + cp.plateDepth / 2 - cp.machineSize.X / 2 - 1
		checkpointMachine.CFrame = CFrame.new(machineX, topY + cp.machineSize.Y / 2, cz)
	end

	if checkpointStationBody then
		-- Cake-side (−X) edge, +Z corner: keeps the centre landing and the −X
		-- walk-back path to the loaf clear. The screen sits on top facing the plate
		-- centre (where a returning player arrives).
		local sx = cx - cp.plateDepth / 2 + cp.stationSize.X / 2 + 1
		local sz = cz + cp.plateWidth / 2 - cp.stationSize.Z / 2 - 1.5
		checkpointStationBody.CFrame = CFrame.new(sx, topY + cp.stationSize.Y / 2, sz)
		if checkpointStationScreen then
			local screenPos = Vector3.new(sx, topY + cp.stationSize.Y - cp.stationScreenSize.Y / 2 + 0.4, sz)
			checkpointStationScreen.CFrame = CFrame.lookAt(screenPos, Vector3.new(cx, screenPos.Y, cz))
		end
	end
end

--API
-- Teleport target: standing on the plate, facing the cake (walk forward, -X, to
-- step back onto the loaf). nil until the checkpoint is built + positioned.
function MapService.GetCheckpointCFrame(): CFrame?
	if checkpointCenter == nil or checkpointTopY == nil then
		return nil
	end
	-- Land at the plate center (within the gym prompt's range so it's active on
	-- arrival) facing the cake (walk forward, -X, to step back onto the loaf).
	local pos = Vector3.new(
		checkpointCenter.X,
		checkpointTopY + mapCfg.checkpoint.standHeight,
		checkpointCenter.Z
	)
	return CFrame.lookAt(pos, pos - Vector3.xAxis)
end

--API
-- True if a world position sits over the checkpoint plate's XZ footprint —
-- CakeSubs uses it to re-seat a player standing on the platform when it jumps
-- UP to a fresh cake (the anchored plate leaves them behind otherwise).
function MapService.IsOverCheckpoint(position: Vector3): boolean
	if checkpointCenter == nil then
		return false
	end
	local cp = mapCfg.checkpoint
	local dx = math.abs(position.X - checkpointCenter.X)
	local dz = math.abs(position.Z - checkpointCenter.Z)
	return dx <= cp.plateDepth / 2 and dz <= cp.plateWidth / 2
end

--API
-- Whether a character position is close enough to the checkpoint's gym machine
-- (server-side range check for GymStart). The machine moves with the platform.
function MapService.NearGym(position: Vector3): boolean
	if checkpointMachine == nil then
		return false
	end
	return (position - checkpointMachine.Position).Magnitude <= mapCfg.checkpoint.maxUseDistanceStuds
end

return MapService
