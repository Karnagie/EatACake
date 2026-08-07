--[[
	MapService — the static candy scene (floor, walls with candy props, cake
	tray, ceiling, candle landmarks) + the CHECKPOINT platform (gym machine +
	upgrade station), built by CLONING editable templates from
	`ReplicatedStorage.Assets` (R5) — NOT procedurally spawned.

	EDITABLE ASSETS (features/map): the scene lives as two models under
	`ReplicatedStorage.Assets` — `Environment` (the whole static room, at world
	positions) and `Checkpoint` (named parts). Edit / replace them in Studio to
	improve the look; MapService just clones them at boot. Because they are
	PLACE-AUTHORED (not Rojo-synced), the user edits them in Studio and SAVES the
	place to keep changes.
	Self-heal: if a template is MISSING, MapService GENERATES the default look
	into `ReplicatedStorage.Assets` on boot (the old code-built geometry, kept ONLY
	as the generator) so the game always runs — but a runtime-generated model does
	NOT persist; author + save to keep edits. Every missing/failed resolve warns
	(R8) and degrades.

	CHECKPOINT is dynamic (features/checkpoint.md): SetCheckpointHeight positions
	the NAMED parts (CheckpointPlate, CheckpointLeg×4, GymMachine[+GymPrompt],
	UpgradeStationBody[+UpgradeStation prompt], UpgradeStationScreen, LayerEater
	[+LayerEaterPrompt — the ONE part whose authored POSE is preserved rather than
	recomputed; it rides the plate by its captured offset]) to track the
	current top cake layer. KEEP the names; each may be a single BasePart OR a
	MODEL (code positions via PivotTo + sizes via GetExtentsSize, so a resized /
	multi-part authored model still aligns). POSITION is code-driven for all of
	them (they ride the moving plate); LEGS also telescope (their Y is code-driven,
	their X/Z cross-section is kept — keep legs as single BaseParts). CakeSubs
	drives the height and teleports players onto it. This service owns the cloned
	parts (cached locals) but never subscribes to events.
	(The templates live in ReplicatedStorage.Assets AND are cloned into
	workspace.Map, so the scene replicates ~twice — negligible for the default
	simple-part scene; if authored assets get heavy, strip them post-clone or move
	to ServerStorage.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local MapService = {}

local ASSETS_FOLDER = "Assets" -- ReplicatedStorage.Assets (place-authored, editable)

local mapCfg -- MapConfigData
local gridCfg -- CakeConfigData.cake.grid
local footprintCfg -- CakeConfigData.cake.composition.footprint (FIXED loaf)
local compCfg -- CakeConfigData.cake.composition (cake height for the boot placeholder)

local mapFolder: Folder?
local floorPart: BasePart?
local platformPart: BasePart?
local conveyorPart: BasePart?
local wallParts: { BasePart } = {}
local accentWallParts: { BasePart } = {}
local beamParts: { BasePart } = {}
local ceilingPart: BasePart?

-- Checkpoint platform (cloned once, moved by SetCheckpointHeight). PVInstance
-- (BasePart OR Model) so a user can author a nicer plate/machine/computer AS A
-- MODEL — code positions via PivotTo + sizes via GetExtentsSize, never
-- `.CFrame`/`.Position` (which THROW on a Model). Legs stay single BaseParts
-- (they telescope: Y is code-driven).
local checkpointFolder: Folder?
local checkpointPlate: PVInstance?
local checkpointLegs: { BasePart } = {}
local checkpointMachine: PVInstance?
local checkpointStationBody: PVInstance? -- upgrade "computer" body (rides the plate)
local checkpointStationScreen: PVInstance? -- its glowing screen
-- LayerEater (paid one-shot layer clear). Unlike everything above it is NOT
-- placed at a computed corner: it keeps the pose it was AUTHORED with and only
-- rides the plate. `layerEaterOffset` is its authored pivot MINUS the authored
-- plate pivot, captured once at resolve time; `layerEaterPivot` is that authored
-- pivot (rotation included — a `PivotTo(CFrame.new(...))` would discard the yaw
-- the prop was posed with).
local checkpointLayerEater: PVInstance?
local layerEaterOffset: Vector3?
local layerEaterPivot: CFrame?
local checkpointCenter: Vector3? -- XZ center of the plate (Y unused), from config
local checkpointTopY: number? -- current world Y of the plate's top surface
local cakeSpawnPart: BasePart? -- CakeSpawn pad; Y rides the cake top (SetCheckpointHeight)

function MapService.Init(data)
	mapCfg = data.MapConfigData
	gridCfg = data.CakeConfigData.cake.grid
	compCfg = data.CakeConfigData.cake.composition
	footprintCfg = compCfg.footprint
end

-- ── Geometry generators (the DEFAULT look; used to author the assets) ────────
-- These build the same scene the game shipped with. They are NOT the runtime
-- path (Build clones from ReplicatedStorage.Assets); they exist only to populate
-- the editable templates the first time (GenerateAssets), so the user has a
-- starting point to replace in Studio.

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

-- Builds the static room (floor, conveyor, cake tray, walls + candy props,
-- ceiling, candle landmarks) into `folder`. World positions (relative to the
-- cake origin). The DEFAULT look — edit the authored copy in Studio instead.
local function buildEnvironment(folder: Instance)
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
	floorP:SetAttribute("BiomeRole", "floor")

	local conveyor = makePart({
		Name = "Conveyor",
		Size = Vector3.new(mapCfg.conveyor.length, mapCfg.conveyor.height, mapCfg.conveyor.width),
		CFrame = CFrame.new(origin.x, mapCfg.conveyor.height / 2, origin.z),
		Color = biome.conveyorColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	conveyor.TopSurface = Enum.SurfaceType.Studs
	conveyor:SetAttribute("BiomeRole", "conveyor")

	-- ROUND plate under the round cake. `CylinderMesh` (not a native cylinder
	-- Part) for the same reason CakeWrapper uses one: no rotation, so the part
	-- stays axis-aligned and its faces/UVs behave normally. Fallback only —
	-- an authored Environment brings its own plate (ADR-0007).
	local plate = makePart({
		Name = "CakePlate",
		Size = Vector3.new(mapCfg.platform.length, mapCfg.platform.height, mapCfg.platform.width),
		CFrame = CFrame.new(origin.x, origin.y - mapCfg.platform.height / 2, origin.z),
		Color = biome.platformColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.05,
		Parent = folder,
	})
	Instance.new("CylinderMesh").Parent = plate
	plate:SetAttribute("BiomeRole", "platform")

	-- ── Walls: 3 chocolate + 1 pink accent, studded, with X-braces ──────
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
		-- Biome recolor resolves accent by attribute (survives renaming).
		part:SetAttribute("BiomeRole", if wall.accent then "accentWall" else "wall")

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
				brace:SetAttribute("BiomeRole", "beam")
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
	ceiling:SetAttribute("BiomeRole", "ceiling")

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
end

-- Builds the checkpoint parts (plate, 4 legs, gym machine + prompt, upgrade
-- station body + screen + prompt) into `folder`, at reference positions
-- (SetCheckpointHeight repositions them per cake). Named so the runtime resolves
-- them; edit the authored copy's LOOK in Studio but KEEP the names.
local function buildCheckpoint(folder: Instance)
	local origin = gridCfg.origin
	local cp = mapCfg.checkpoint
	-- +X extreme of the cake. The cake is ROUND (2026-08-03), so this is reached
	-- only at z = origin.z — the plate's gap to the cake opens up toward its
	-- z-ends. See MapConfigData.checkpoint for the numbers.
	local loafEdgeX = footprintCfg.hx * gridCfg.cell
	local plateCenterX = origin.x + loafEdgeX + cp.edgeGap + cp.plateDepth / 2
	local plateCenterZ = origin.z

	local plate = makePart({
		Name = "CheckpointPlate",
		Size = Vector3.new(cp.plateDepth, cp.plateThickness, cp.plateWidth),
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.plateColor,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.04,
		Parent = folder,
	})
	plate.TopSurface = Enum.SurfaceType.Studs

	for _ = 1, 4 do
		makePart({
			Name = "CheckpointLeg",
			Size = Vector3.new(cp.legSize, cp.minLegHeight, cp.legSize),
			CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
			Color = cp.legColor,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
	end

	local machine = makePart({
		Name = "GymMachine",
		Size = cp.machineSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.machineColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	studAllSurfaces(machine)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = cp.promptName
	prompt.ActionText = "Burn it off!"
	prompt.ObjectText = "Gym"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cp.promptRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = machine

	local stationBody = makePart({
		Name = "UpgradeStationBody",
		Size = cp.stationSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.stationBodyColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	studAllSurfaces(stationBody)
	local screen = makePart({
		Name = "UpgradeStationScreen",
		Size = cp.stationScreenSize,
		CFrame = CFrame.new(plateCenterX, 0, plateCenterZ),
		Color = cp.stationScreenColor,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	local screenLight = Instance.new("PointLight")
	screenLight.Color = cp.stationScreenColor
	screenLight.Range = 12
	screenLight.Brightness = 1.2
	screenLight.Parent = screen
	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = cp.upgradePromptName
	upgradePrompt.ActionText = "Upgrades"
	upgradePrompt.ObjectText = "Upgrade Station"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = cp.upgradePromptRange
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.Parent = stationBody

	-- Layer eater: the paid one-shot layer clear. The default look is a plain box
	-- on the plate's OTHER cake-side corner (−Z, mirroring the station at +Z) —
	-- the authored copy replaces it with the real contraption, and its pose there
	-- is what ships (SetCheckpointHeight preserves the authored offset).
	local layerEater = makePart({
		Name = cp.layerEaterName,
		Size = cp.layerEaterSize,
		CFrame = CFrame.new(
			plateCenterX - cp.plateDepth / 2 + cp.layerEaterSize.X / 2 + 1,
			cp.plateThickness / 2 + cp.layerEaterSize.Y / 2,
			plateCenterZ - cp.plateWidth / 2 + cp.layerEaterSize.Z / 2 + 1.5
		),
		Color = cp.layerEaterColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	studAllSurfaces(layerEater)
	local eatPrompt = Instance.new("ProximityPrompt")
	eatPrompt.Name = cp.layerEaterPromptName
	eatPrompt.ActionText = "Eat this layer"
	eatPrompt.ObjectText = "Layer Eater"
	eatPrompt.HoldDuration = 0
	eatPrompt.MaxActivationDistance = cp.layerEaterPromptRange
	eatPrompt.RequiresLineOfSight = false
	eatPrompt.Parent = layerEater
end

--API
-- Ensures ReplicatedStorage.Assets holds `Environment` + `Checkpoint` templates,
-- generating the DEFAULT look for any that is missing. Idempotent. Run it once
-- in Studio (Edit) and SAVE the place to author editable starting models; the
-- runtime also calls it as a self-heal so the game never boots empty.
-- A usable template is a Folder/Model container that actually holds parts —
-- treat a missing OR malformed (empty / a bare Part named "Environment") node as
-- absent so GenerateAssets rebuilds it (existence ≠ validity).
local function validTemplate(node: Instance?): boolean
	return node ~= nil
		and (node:IsA("Folder") or node:IsA("Model"))
		and node:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

function MapService.GenerateAssets(): Folder
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER)
	if assets == nil or not (assets:IsA("Folder") or assets:IsA("Model")) then
		if assets then
			assets:Destroy() -- a bad non-container named "Assets"
		end
		assets = Instance.new("Folder")
		assets.Name = ASSETS_FOLDER
		assets.Parent = ReplicatedStorage
	end
	if not validTemplate(assets:FindFirstChild("Environment")) then
		local old = assets:FindFirstChild("Environment")
		if old then
			old:Destroy()
		end
		local env = Instance.new("Folder")
		env.Name = "Environment"
		buildEnvironment(env)
		env.Parent = assets
		Log.Sum("Map", "generated default Environment template into ReplicatedStorage.Assets (edit + save to keep)")
	end
	if not validTemplate(assets:FindFirstChild("Checkpoint")) then
		local old = assets:FindFirstChild("Checkpoint")
		if old then
			old:Destroy()
		end
		local cp = Instance.new("Folder")
		cp.Name = "Checkpoint"
		buildCheckpoint(cp)
		cp.Parent = assets
		Log.Sum("Map", "generated default Checkpoint template into ReplicatedStorage.Assets (edit + save to keep)")
	end
	return assets :: Folder
end

-- ── Resolve cloned parts by name (R8: warn on anything missing) ─────────────

-- Resolve a named node as a POSITIONABLE (BasePart or Model — both PVInstance).
-- A named node that is neither is rejected (nil), so the caller warns.
local function resolvePV(folder: Instance, name: string): PVInstance?
	local node = folder:FindFirstChild(name)
	if node and node:IsA("PVInstance") then
		return node
	end
	return nil
end

-- Bounding size of a positionable (works for a Model too).
local function pvSize(pv: PVInstance): Vector3
	if pv:IsA("BasePart") then
		return pv.Size
	end
	return (pv :: Model):GetExtentsSize()
end

-- Biome recolor is OPT-IN via the `BiomeRole` attribute (the generated defaults
-- set it: floor/conveyor/platform/ceiling/wall/accentWall/beam). A part the user
-- re-authored WITHOUT the attribute keeps its own colour — ApplyBiome never
-- touches it. So editing a model's LOOK sticks; only role-tagged parts skin per
-- biome. (Geometry/mesh/material edits always flow through the clone.)
local function resolveEnvironment(folder: Folder)
	table.clear(wallParts)
	table.clear(accentWallParts)
	table.clear(beamParts)
	floorPart, conveyorPart, platformPart, ceilingPart = nil, nil, nil, nil
	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("BiomeRole")
			if role == "floor" then
				floorPart = child
			elseif role == "conveyor" then
				conveyorPart = child
			elseif role == "platform" then
				platformPart = child
			elseif role == "ceiling" then
				ceilingPart = child
			elseif role == "accentWall" then
				table.insert(accentWallParts, child)
			elseif role == "wall" then
				table.insert(wallParts, child)
			elseif role == "beam" then
				table.insert(beamParts, child)
			end
		end
	end
	-- R8: a non-nil but fully-unresolved Environment (empty / all roles stripped)
	-- would leave players in a floorless scene with no other signal.
	if floorPart == nil and #wallParts == 0 and #accentWallParts == 0 then
		Log.Warn(
			"Map",
			"Assets.Environment resolved NO role-tagged parts (floor/walls) — biome recolor off + a possibly floorless scene (see the asset contract in features/map)"
		)
	end
end

-- The LayerEater's ProximityPrompt is what SELLS the paid layer clear
-- (features/checkpoint.md). The prop is place-authored, so the prompt may or may
-- not have been authored with it — ensure it either way, exactly like
-- GenerateAssets self-heals a missing template. Idempotent: an authored prompt
-- of that name is adopted (its tuning wins) and only the range is re-asserted.
local function ensureLayerEaterPrompt(eater: PVInstance)
	local cp = mapCfg.checkpoint
	-- The BIGGEST part, not the first one found: an authored contraption is a pile
	-- of same-named `Part`s in no meaningful order, so `FindFirstChildWhichIsA`
	-- lands on whatever whisker happens to be first and floats the prompt off the
	-- model — and it would move whenever the author re-orders anything. Volume is
	-- stable and picks the body. A PrimaryPart, if the author set one, wins.
	local host: BasePart? = nil
	if eater:IsA("BasePart") then
		host = eater
	else
		host = (eater :: Model).PrimaryPart
		if host == nil then
			local best = -1
			for _, descendant in ipairs(eater:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
					if volume > best then
						best, host = volume, descendant
					end
				end
			end
		end
	end
	if host == nil then
		Log.Warn(
			"Map",
			`Assets.Checkpoint '{cp.layerEaterName}' holds no BasePart to host its prompt — the paid layer clear cannot be bought`
		)
		return
	end
	local existing = eater:FindFirstChild(cp.layerEaterPromptName, true)
	if existing and existing:IsA("ProximityPrompt") then
		existing.MaxActivationDistance = cp.layerEaterPromptRange
		existing.Enabled = true
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = cp.layerEaterPromptName
	prompt.ActionText = "Eat this layer"
	prompt.ObjectText = "Layer Eater"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = cp.layerEaterPromptRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	Log.Info("Map", `'{cp.layerEaterName}' had no '{cp.layerEaterPromptName}' — added one on '{host.Name}'`)
end

local function resolveCheckpoint(folder: Folder)
	table.clear(checkpointLegs)
	checkpointPlate = resolvePV(folder, "CheckpointPlate")
	checkpointMachine = resolvePV(folder, "GymMachine")
	checkpointStationBody = resolvePV(folder, "UpgradeStationBody")
	checkpointStationScreen = resolvePV(folder, "UpgradeStationScreen")
	checkpointLayerEater = resolvePV(folder, mapCfg.checkpoint.layerEaterName)
	layerEaterOffset, layerEaterPivot = nil, nil
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "CheckpointLeg" then
			table.insert(checkpointLegs, child)
		end
	end
	-- Captured BEFORE the first SetCheckpointHeight, while the clone still holds
	-- the AUTHORED positions: everything after this is code-driven.
	if checkpointLayerEater == nil then
		Log.Warn(
			"Map",
			`Assets.Checkpoint '{mapCfg.checkpoint.layerEaterName}' missing or not a Part/Model — the paid layer clear has no world surface to sell from (features/checkpoint.md)`
		)
	else
		-- The prompt is ensured whether or not the PLATE resolved: those are
		-- independent failures, and an `and` here meant a renamed plate silently
		-- took the prompt down too, with only the generic plate warn to go on.
		ensureLayerEaterPrompt(checkpointLayerEater)
		if checkpointPlate then
			local pivot = checkpointLayerEater:GetPivot()
			layerEaterPivot = pivot
			layerEaterOffset = pivot.Position - checkpointPlate:GetPivot().Position
		else
			Log.Warn(
				"Map",
				`'{mapCfg.checkpoint.layerEaterName}' resolved but 'CheckpointPlate' did not — it keeps its authored position and will NOT ride the cake`
			)
		end
	end
	if checkpointPlate == nil then
		Log.Warn("Map", "Assets.Checkpoint 'CheckpointPlate' missing or not a Part/Model — checkpoint height/teleport DISABLED (keep the named parts, see features/checkpoint.md)")
	end
	if checkpointMachine == nil then
		Log.Warn("Map", "Assets.Checkpoint 'GymMachine' missing or not a Part/Model — the gym is unreachable (keep the named parts)")
	end
end

--API
-- Builds the whole scene once (idempotent) by CLONING the editable templates
-- from ReplicatedStorage.Assets. Called from CakeSubs.Start.
function MapService.Build()
	if mapFolder then
		return
	end
	-- The place file ships a default Baseplate + SpawnLocation — remove them
	-- (the candy room replaces both; players must spawn ON the cake).
	local stray = workspace:FindFirstChild("Baseplate")
	if stray then
		stray:Destroy()
	end
	local straySpawn = workspace:FindFirstChild("SpawnLocation")
	if straySpawn then
		straySpawn:Destroy()
	end

	-- Self-heal: author-missing templates get the default look (won't persist —
	-- edit + save the place to keep). Everything below CLONES from Assets (R5).
	local assets = MapService.GenerateAssets()

	local envTemplate = assets:FindFirstChild("Environment")
	local folder: Instance
	if envTemplate then
		folder = envTemplate:Clone()
		folder.Name = "Map"
	else
		Log.Warn("Map", "Assets.Environment missing after GenerateAssets — empty Map folder (scene will be bare)")
		folder = Instance.new("Folder")
		folder.Name = "Map"
	end
	-- NOTE: `mapFolder` (the build guard) is set only AFTER `folder.Parent =
	-- workspace` below — a throw mid-assembly must NOT leave an orphan that the
	-- guard then treats as "already built" (blocking a retry).
	resolveEnvironment(folder :: Folder)

	-- Checkpoint clone (into the Map). checkpointCenter comes from CONFIG (the
	-- template's authored positions are overwritten by SetCheckpointHeight).
	local origin = gridCfg.origin
	local cp = mapCfg.checkpoint
	local loafEdgeX = footprintCfg.hx * gridCfg.cell -- +X extreme of the round cake
	checkpointCenter = Vector3.new(origin.x + loafEdgeX + cp.edgeGap + cp.plateDepth / 2, 0, origin.z)

	local cpTemplate = assets:FindFirstChild("Checkpoint")
	if cpTemplate then
		local cpFolder = cpTemplate:Clone()
		cpFolder.Name = "Checkpoint"
		cpFolder.Parent = folder
		checkpointFolder = cpFolder :: Folder
		resolveCheckpoint(checkpointFolder)
	else
		Log.Warn("Map", "Assets.Checkpoint missing after GenerateAssets — no gym/upgrade platform")
	end

	-- Initial placement, live for the WHOLE reserved-round arrival window (the
	-- real SpawnNewCake is deferred until the roster/profile barrier clears), so
	-- it has to be a height a arriving player can actually stand at.
	-- ⚠ Use the CAKE height (core + maxTotalHeight), NOT `grid.maxHeight` — that is
	-- the u16 FIELD HEADROOM (340) and has no relation to how tall a cake is.
	-- `maxHeight * 0.6` = 204 put the pad at 214 while `room.wallHeight` is 210:
	-- arrivals spawned ON TOP of the collidable ceiling of a sealed room, outside
	-- the level, and SpawnNewCake's rescue only lifts players BELOW the cake top so
	-- they were never recovered. It only worked before because the room used to be
	-- 380 studs tall. This value now matches what SpawnNewCake will set.
	local placeholderTopY = origin.y + compCfg.coreThickness + compCfg.maxTotalHeight
	MapService.SetCheckpointHeight(placeholderTopY)

	-- Spawn: directly on the cake (§12.1) — invisible, non-colliding pad above
	-- the frosting; players drop onto the crust. FUNCTIONAL (not art) so it stays
	-- code-created. Its Y RIDES the current cake top via SetCheckpointHeight.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CakeSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(origin.x, placeholderTopY + mapCfg.spawnHeightAboveCake, origin.z)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	cakeSpawnPart = spawn

	folder.Parent = workspace
	mapFolder = folder :: Folder -- built + parented: NOW the guard may short-circuit

	-- Lighting is NOT configured from code (user preference) — set it up in Studio.

	Log.Sum("Map", `candy room CLONED from ReplicatedStorage.Assets — {#wallParts + #accentWallParts} walls, checkpoint platform (gym + upgrade station), cake spawn`)
end

--API
-- Recolors the scene for a biome (called on cake spawn). Best-effort on the
-- resolved named parts; parts the user re-authored without the names/roles keep
-- their own colors (nil-safe).
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
	-- Lighting is NOT configured from code (user preference) — biome recolor
	-- touches only the scene part colors now.
end

--API
-- Positions the checkpoint so its plate TOP sits at world Y `topY`: the legs
-- resize down to the floor (y = 0) and the gym machine / computer ride the plate
-- top. Called by CakeSubs on each new cake and whenever the top layer steps down.
-- POSITION is code-driven for all parts (they track the cake) via PivotTo (a
-- user's Model is fine); the machine/computer/plate use their AUTHORED size so a
-- resized model still aligns; legs telescope (Y code-driven, X/Z kept).
function MapService.SetCheckpointHeight(topY: number)
	if checkpointPlate == nil or checkpointCenter == nil then
		return -- no authored plate (resolveCheckpoint warned) — degrade silently
	end
	local cp = mapCfg.checkpoint
	local plate = checkpointPlate :: PVInstance
	local plateSize = pvSize(plate)
	-- Never let the plate sit so low the legs vanish (near-bare cake / core).
	topY = math.max(topY, cp.minLegHeight + plateSize.Y)
	-- Skip redundant moves (the 1 Hz scan re-asserts the same height between
	-- layer changes — no point re-replicating anchored parts every second).
	if checkpointTopY ~= nil and math.abs(checkpointTopY - topY) < 0.01 then
		return
	end
	checkpointTopY = topY
	local cx, cz = checkpointCenter.X, checkpointCenter.Z
	local plateBottomY = topY - plateSize.Y
	plate:PivotTo(CFrame.new(cx, topY - plateSize.Y / 2, cz))

	-- The cake spawn pad rides the SAME cake top so a (re)spawn is a small drop
	-- onto the crust, not a fall from the tall-cake ceiling.
	if cakeSpawnPart then
		cakeSpawnPart.CFrame =
			CFrame.new(cakeSpawnPart.Position.X, topY + mapCfg.spawnHeightAboveCake, cakeSpawnPart.Position.Z)
	end

	-- Legs stand on the floor (y = 0) up to the plate bottom (Y telescopes; the
	-- authored cross-section X/Z is kept). Corner inset off the AUTHORED plate.
	local legHalfDepth = plateSize.X / 2 - cp.legInset - cp.legSize / 2
	local legHalfWidth = plateSize.Z / 2 - cp.legInset - cp.legSize / 2
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
			leg.Size = Vector3.new(leg.Size.X, legHeight, leg.Size.Z)
			leg.CFrame = CFrame.new(cx + corner.X, legHeight / 2, cz + corner.Z)
		end
	end

	if checkpointMachine then
		local m = checkpointMachine :: PVInstance
		local mSize = pvSize(m)
		local machineX = cx + plateSize.X / 2 - mSize.X / 2 - 1
		-- PivotTo moves the collider AND its descendant parts (the authored treadmill
		-- visual), so the whole machine rides the plate together (user req 4 mount).
		m:PivotTo(CFrame.new(machineX, topY + mSize.Y / 2, cz))
	end

	-- The LayerEater keeps its AUTHORED pose and simply rides the plate: its
	-- captured offset is re-applied to the plate's new pivot, and the authored
	-- ROTATION is re-applied verbatim (`CFrame.new(pos) * rot` — building the
	-- CFrame from the position alone would flatten the yaw the prop was posed
	-- with, which for a modelled contraption reads as it snapping to face north).
	if checkpointLayerEater and layerEaterOffset and layerEaterPivot then
		local target = Vector3.new(cx, topY - plateSize.Y / 2, cz) + (layerEaterOffset :: Vector3)
		checkpointLayerEater:PivotTo(CFrame.new(target) * (layerEaterPivot :: CFrame).Rotation)
	end

	if checkpointStationBody then
		-- Cake-side (−X) edge, +Z corner: keeps the centre landing and the −X
		-- walk-back path to the loaf clear. The screen sits on top facing the
		-- plate centre (where a returning player arrives).
		local body = checkpointStationBody :: PVInstance
		local sSize = pvSize(body)
		local sx = cx - plateSize.X / 2 + sSize.X / 2 + 1
		local sz = cz + plateSize.Z / 2 - sSize.Z / 2 - 1.5
		body:PivotTo(CFrame.new(sx, topY + sSize.Y / 2, sz)) -- descendants (computer visual) ride via PivotTo
		if checkpointStationScreen then
			local screen = checkpointStationScreen :: PVInstance
			local scSize = pvSize(screen)
			local screenPos = Vector3.new(sx, topY + sSize.Y - scSize.Y / 2 + 0.4, sz)
			screen:PivotTo(CFrame.lookAt(screenPos, Vector3.new(cx, screenPos.Y, cz)))
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
	local pos = Vector3.new(
		checkpointCenter.X,
		checkpointTopY + mapCfg.checkpoint.standHeight,
		checkpointCenter.Z
	)
	return CFrame.lookAt(pos, pos - Vector3.xAxis)
end

--API
-- True if a world position sits over the checkpoint plate's XZ footprint. Uses
-- the plate's AUTHORED size so this server re-seat zone matches the client's
-- proximity check (BodySubsClient reads the plate's real Size too).
function MapService.IsOverCheckpoint(position: Vector3): boolean
	if checkpointCenter == nil then
		return false
	end
	local cp = mapCfg.checkpoint
	local plateSize = if checkpointPlate then pvSize(checkpointPlate) else Vector3.new(cp.plateDepth, cp.plateThickness, cp.plateWidth)
	local dx = math.abs(position.X - checkpointCenter.X)
	local dz = math.abs(position.Z - checkpointCenter.Z)
	return dx <= plateSize.X / 2 and dz <= plateSize.Z / 2
end

--API
-- Whether a character position is close enough to the checkpoint's gym machine
-- (server-side range check for GymStart). The machine moves with the platform.
function MapService.NearGym(position: Vector3): boolean
	if checkpointMachine == nil then
		return false
	end
	-- GetPivot (not .Position) so a Model machine works too.
	return (position - checkpointMachine:GetPivot().Position).Magnitude <= mapCfg.checkpoint.maxUseDistanceStuds
end

--API
-- Where to STAND on the treadmill (GymMachine) during a fat-burn run (user req 4):
-- centred on the machine's XZ, feet on the belt (checkpointTopY + config height),
-- facing along the belt (config yaw). nil until the checkpoint is built +
-- positioned (BodySubs falls back to the standing burn).
function MapService.GetGymMountCFrame(): CFrame?
	if checkpointMachine == nil or checkpointTopY == nil then
		return nil
	end
	local cp = mapCfg.checkpoint
	local pivot = checkpointMachine:GetPivot().Position
	local pos = Vector3.new(pivot.X, checkpointTopY + cp.treadmillStandHeight, pivot.Z)
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(cp.treadmillFaceYaw), 0)
end

--API
-- Step-off spot beside the treadmill after a completed run (user req 4): a few
-- studs toward the plate centre (−X, off the belt), facing the cake so a forward
-- step returns to the loaf. nil until built + positioned.
function MapService.GetGymDismountCFrame(): CFrame?
	if checkpointMachine == nil or checkpointTopY == nil then
		return nil
	end
	local cp = mapCfg.checkpoint
	local pivot = checkpointMachine:GetPivot().Position
	local pos = Vector3.new(pivot.X - cp.treadmillDismountBack, checkpointTopY + cp.treadmillDismountHeight, pivot.Z)
	return CFrame.lookAt(pos, pos - Vector3.xAxis)
end

return MapService
