--[[
	MapService — builds the candy room (floor, walls with candy props, cake
	platform, gym zone, spawn, candle landmarks) from MapConfigData at boot;
	recolors per biome.

	The map is CODE-BUILT (no Studio-authored scene in this project yet) —
	one-time construction (Build is called from CakeSubs.Start, before the
	first cake), not a runtime hot path. Studded surfaces use the native
	Studs SurfaceType (the reference "chocolate LEGO wall" look). Gym
	machines carry a ProximityPrompt named MapConfigData.gym.promptName;
	BodySubs connects the trigger (R4 — no event wiring here).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local MapService = {}

local mapCfg -- MapConfigData
local gridCfg -- CakeConfigData.cake.grid

local mapFolder: Folder?
local floorPart: BasePart?
local platformPart: BasePart?
local conveyorPart: BasePart?
local wallParts: { BasePart } = {}
local accentWallParts: { BasePart } = {}
local beamParts: { BasePart } = {}
local ceilingPart: BasePart?
local machinePositions: { Vector3 } = {}

function MapService.Init(data)
	mapCfg = data.MapConfigData
	gridCfg = data.CakeConfigData.cake.grid
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

	-- Gym zone (§8).
	local gym = mapCfg.gym
	local pad = makePart({
		Name = "GymPad",
		Size = Vector3.new(gym.padSize, 1, gym.padSize),
		CFrame = CFrame.new(origin.x + gym.center.x, 0.5, origin.z + gym.center.z),
		Color = Color3.fromRGB(240, 130, 190),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	pad.TopSurface = Enum.SurfaceType.Studs
	table.clear(machinePositions)
	for k = 1, gym.machineCount do
		local angle = (k - 1) / gym.machineCount * math.pi * 2
		local mx = origin.x + gym.center.x + math.cos(angle) * gym.padSize * 0.32
		local mz = origin.z + gym.center.z + math.sin(angle) * gym.padSize * 0.32
		local machine = makePart({
			Name = `GymMachine_{k}`,
			Size = Vector3.new(4, 6, 4),
			CFrame = CFrame.new(mx, 4, mz),
			Color = Color3.fromRGB(220, 60, 80),
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
		studAllSurfaces(machine)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = gym.promptName
		prompt.ActionText = "Burn it off!"
		prompt.ObjectText = "Gym"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = machine
		table.insert(machinePositions, machine.Position)
	end

	-- Spawn: directly on the cake (§12.1) — invisible, non-colliding pad
	-- above the frosting; players drop onto the crust.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CakeSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(origin.x, origin.y + gridCfg.maxHeight + mapCfg.spawnHeightAboveCake, origin.z)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

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
		`candy room built — floor, plate, 4 walls (+props x{mapCfg.room.propsPerWall * 4}), {#mapCfg.candles} candles, gym x{gym.machineCount}, cake spawn`
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
-- Whether a character position is close enough to any gym machine
-- (server-side range check for GymStart).
function MapService.NearGym(position: Vector3): boolean
	for _, machinePos in ipairs(machinePositions) do
		if (position - machinePos).Magnitude <= mapCfg.gym.maxUseDistanceStuds then
			return true
		end
	end
	return false
end

return MapService
