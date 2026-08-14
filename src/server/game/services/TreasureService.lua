--[[
	TreasureService — finds BURIED in the cake (GDD §6.1).

	2026-07-26 rework: a find is no longer a neon ball that pops at the
	surface. It is a chunky AUTHORED MODEL (the place-authored `Items`
	library, migrated to ReplicatedStorage.Assets on boot — ADR-0007) scaled
	to ~1.5-2× the player and sunk into the loaf at a rolled depth. The
	player DIGS it out: the model fades in a few studs before its crown would
	show, sparkles while it is partly exposed, and the moment nothing covers
	it any more it pops out of the hole and flies to the nearest player
	(auto-collect — user req).

	Exposure is MONOTONIC: cake oozing back can never re-bury a find, so a
	dug-out crown is never taken away. A find whose whole band gets consumed
	(auto-sweep) is freed too — no find can ever be stranded.

	R2/R3: state in CakeStateData.treasures; granting rewards + firing
	TreasureUpdate is CakeSimulationSubs' job — this service returns events.
	R5: every visual is a CLONE of the authored library / of the ONE fallback
	template built at Init. The authored library itself is NEVER mutated — each
	entry is prepared as an unparented CLONE, because preparing strips collision,
	rescales and destroys child Scripts, and the user is told to save the place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "Treasure"
local BASE_TRANSPARENCY = "BaseTransparency" -- attribute stamped on prepared parts/decals
local BASE_ENABLED = "BaseEnabled" -- attribute stamped on prepared emitters/lights

local TreasureService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake
local treasureCfg -- CakeConfigData.treasures

local fallbackTemplate: BasePart?
local sparkleTemplate: ParticleEmitter?
local highlightTemplate: Highlight?
local modelPool: { Instance } = {} -- prepared templates from the authored library
local modelByName: { [string]: Instance } = {}
local pickupFolder: Folder?
local cascadeClock = 0 -- staggers a burst of freed finds into a cascade
local pulseClock = 0 -- free-running, drives the rarity glow pulse
local foundCount = 0 -- collected this cake (HUD "FINDS n/N" — gives the run a goal)
local glowCount = 0 -- live Highlights (the engine only renders ~31)
local MAX_GLOWS = 6

-- ── Geometry helpers (pivot-agnostic: authored models pivot anywhere) ────

local function partsOf(root: Instance): { BasePart }
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Everything on an authored prop that carries its OWN `.Transparency`. ⚠ A
-- Decal/Texture on a fully transparent part STILL RENDERS — miss these and a
-- buried find hangs ghost decals inside the cake. `SurfaceAppearance` and mesh
-- textures follow the part, so they need no entry.
local function alphaTargetsOf(root: Instance): { Instance }
	local targets = {}
	if root:IsA("BasePart") then
		table.insert(targets, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			table.insert(targets, descendant) -- Texture is a subclass of Decal
		end
	end
	return targets
end

-- Authored FX that emit/glow on their own (a sparkling gem, a torch). They must
-- stay OFF while the prop is buried — light and particles ignore transparency.
local function emittersOf(root: Instance): { Instance }
	local emitters = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("Light")
		then
			table.insert(emitters, descendant)
		end
	end
	return emitters
end

-- The model's OWN size, in its own frame — what Studio's Scale tool shows.
-- Used ONLY to decide the uniform scale factor; everything spatial (burial
-- depth, footprint, crown) uses the world AABB below instead.
local function localSizeOf(node: Instance): Vector3
	if node:IsA("BasePart") then
		return (node :: BasePart).Size
	end
	local ok, extents = pcall(function()
		return (node :: Model):GetExtentsSize()
	end)
	if ok and extents ~= nil then
		return extents
	end
	local fallback = treasureCfg.model.targetSizeStuds
	return Vector3.new(fallback, fallback, fallback)
end

-- TRUE world-axis-aligned bounds of a Model/BasePart: (centre, size).
-- ⚠ NOT `Model:GetBoundingBox()` — that box is expressed in the PIVOT's frame,
-- so for a TILTED find (which every find is) its `.Y` is the model's own local
-- height, not the vertical span the player has to dig through. Burial depth,
-- the crown anchor and the footprint radius all need the WORLD span, so each
-- part's oriented box is projected onto the world axes here.
local function boundsOf(root: Instance): (Vector3, Vector3)
	local parts = partsOf(root)
	if #parts == 0 then
		local fallback = treasureCfg.model.targetSizeStuds
		return Vector3.zero, Vector3.new(fallback, fallback, fallback)
	end
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, part in ipairs(parts) do
		local cf, size = part.CFrame, part.Size
		local right, up, back = cf.RightVector, cf.UpVector, -cf.LookVector
		local hx = 0.5 * (math.abs(right.X) * size.X + math.abs(up.X) * size.Y + math.abs(back.X) * size.Z)
		local hy = 0.5 * (math.abs(right.Y) * size.X + math.abs(up.Y) * size.Y + math.abs(back.Y) * size.Z)
		local hz = 0.5 * (math.abs(right.Z) * size.X + math.abs(up.Z) * size.Y + math.abs(back.Z) * size.Z)
		local centre = cf.Position
		minX, maxX = math.min(minX, centre.X - hx), math.max(maxX, centre.X + hx)
		minY, maxY = math.min(minY, centre.Y - hy), math.max(maxY, centre.Y + hy)
		minZ, maxZ = math.min(minZ, centre.Z - hz), math.max(maxZ, centre.Z + hz)
	end
	return Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5),
		Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

local function pivotTo(root: Instance, cf: CFrame)
	if root:IsA("BasePart") then
		(root :: BasePart).CFrame = cf
	elseif root:IsA("Model") then
		(root :: Model):PivotTo(cf)
	end
end

local function pivotOf(root: Instance): CFrame
	if root:IsA("BasePart") then
		return (root :: BasePart).CFrame
	end
	return (root :: Model):GetPivot()
end

-- Orients the model (yaw + a random tilt) and then places it so its WORLD
-- bounding-box centre lands on `centre`. Two reasons for the second step: the
-- authored pivot may sit anywhere (a lid, a corner), and the tilt moves the box.
local function orientAt(root: Instance, centre: Vector3, yaw: number, pitch: number, roll: number)
	pivotTo(root, CFrame.new(centre) * CFrame.Angles(pitch, yaw, roll))
	local current = boundsOf(root)
	pivotTo(root, pivotOf(root) + (centre - current))
end

-- ── Authored library ────────────────────────────────────────────────────

-- Uniform-scales a template so its longest side is ~`targetSizeStuds` and
-- makes every part an inert anchored visual (R5 clones inherit all of it).
local function prepareTemplate(node: Instance): boolean
	if not (node:IsA("Model") or node:IsA("BasePart")) then
		return false
	end
	local parts = partsOf(node)
	if #parts == 0 then
		return false
	end

	-- LOCAL extents, not the world AABB: a prop authored at an angle has a world
	-- box much larger than itself, and scaling against that makes it come out
	-- visibly smaller than its neighbours (seen live in Studio).
	local size = localSizeOf(node)
	local largest = math.max(size.X, size.Y, size.Z)
	if largest <= 0.01 then
		return false
	end
	-- One rule, uniform: the longest dimension becomes `targetSizeStuds`. Whatever
	-- art is dropped into the library reads at a consistent, predictable size, and
	-- `tiltDegrees` is what turns a flat prop into something with a vertical span
	-- to dig through (targeting height instead would blow a pan up hugely).
	local modelCfg = treasureCfg.model
	local scale = modelCfg.targetSizeStuds / largest

	if node:IsA("Model") then
		local model = node :: Model
		if model.PrimaryPart == nil then
			-- ScaleTo/PivotTo need a pivot; the biggest part is the sane default.
			local biggest: BasePart? = nil
			local bestVolume = -1
			for _, part in ipairs(parts) do
				local volume = part.Size.X * part.Size.Y * part.Size.Z
				if volume > bestVolume then
					biggest, bestVolume = part, volume
				end
			end
			model.PrimaryPart = biggest
		end
		-- ⚠ `ScaleTo` is ABSOLUTE (relative to the model's AUTHORED size), while
		-- `scale` here is computed against the model's CURRENT size. Multiplying
		-- by GetScale() keeps the two consistent — passing `scale` raw would
		-- silently RESET an already-prepared template back to authored size.
		if not pcall(function()
			model:ScaleTo(model:GetScale() * scale)
		end) then
			Log.Warn(SCOPE, `library model '{node.Name}' could not be scaled — using its authored size`)
		end
	else
		-- Its OWN Size × scale. Assigning the world AABB here inflated any part
		-- that was authored rotated.
		(node :: BasePart).Size = (node :: BasePart).Size * scale
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	for _, target in ipairs(alphaTargetsOf(node)) do
		target:SetAttribute(BASE_TRANSPARENCY, (target :: any).Transparency)
	end
	for _, emitter in ipairs(emittersOf(node)) do
		-- Remember the authored state, then hold it off: clones start buried.
		emitter:SetAttribute(BASE_ENABLED, (emitter :: any).Enabled);
		(emitter :: any).Enabled = false
	end
	for _, descendant in ipairs(node:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy() -- authored props must not run code inside the cake
		end
	end
	return true
end

-- Moves the place-authored container (Workspace.Items) into the replicated
-- template library, then prepares every child.
local function buildLibrary()
	local folderName = treasureCfg.model.folderName
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets == nil then
		local created = Instance.new("Folder")
		created.Name = "Assets"
		created.Parent = ReplicatedStorage
		assets = created
		Log.Info(SCOPE, "created ReplicatedStorage.Assets (item library host)")
	end

	local authored = workspace:FindFirstChild(folderName)
	if authored ~= nil and (authored:IsA("Folder") or authored:IsA("Model")) then
		local existing = assets:FindFirstChild(folderName)
		if existing ~= nil and existing ~= authored then
			existing:Destroy()
		end
		authored.Parent = assets
		Log.Sum(
			SCOPE,
			`moved Workspace.{folderName} -> ReplicatedStorage.Assets.{folderName} (item template library — save the place to keep it there)`
		)
	end

	local library = assets:FindFirstChild(folderName)
	if library == nil or not (library:IsA("Folder") or library:IsA("Model")) then
		Log.Warn(
			SCOPE,
			`no '{folderName}' model library (expected Workspace.{folderName} or ReplicatedStorage.Assets.{folderName}) — finds fall back to plain orbs, see features/treasures.md`
		)
		return
	end

	-- Scenery stays RESOLVABLE BY NAME (an explicit pin still works) but is kept
	-- out of the round-robin pool — see `sceneryModels`.
	local scenery = {}
	for _, name in ipairs(treasureCfg.model.sceneryModels or {}) do
		scenery[name] = true
	end

	local names = {}
	local skipped = {}
	for _, child in ipairs(library:GetChildren()) do
		-- Prepare a CLONE, never the authored model. `prepareTemplate` rescales,
		-- anchors, strips collision AND DESTROYS child Scripts — doing that in
		-- place would permanently damage the user's source art the moment they
		-- saved the place (which the migration log explicitly tells them to do).
		-- The prepared clone stays UNPARENTED: clones-of-unparented work fine and
		-- it costs no replication.
		local template = child:Clone()
		if prepareTemplate(template) then
			modelByName[child.Name] = template
			if scenery[child.Name] then
				table.insert(skipped, child.Name)
			else
				table.insert(modelPool, template)
			end
			-- Report the RESULTING size per model (R8): it is the one number a
			-- human needs to eyeball whether a prop reads as "bigger than me",
			-- and it is the only view of the library available outside Studio.
			local _, prepared = boundsOf(template)
			table.insert(
				names,
				`{child.Name} {string.format("%.1f×%.1f×%.1f", prepared.X, prepared.Y, prepared.Z)}`
			)
		else
			template:Destroy()
			Log.Warn(SCOPE, `library entry '{child.Name}' is not a sized Model/Part — skipped`)
		end
	end
	if #modelPool == 0 then
		Log.Warn(
			SCOPE,
			`'{folderName}' library has no TREASURE models — finds fall back to plain orbs{#skipped > 0 and ` (all {#skipped} entries are listed as sceneryModels)` or ""}`
		)
		return
	end
	Log.Sum(
		SCOPE,
		`item library ready — {#modelPool} models scaled to ~{treasureCfg.model.targetSizeStuds} studs: {table.concat(names, ", ")}`
	)
	if #skipped > 0 then
		Log.Info(SCOPE, `scenery (pin-only, out of the round-robin): {table.concat(skipped, ", ")}`)
	end
end

-- Which template a find id uses: its declared `model`, else round-robin so
-- every authored model gets screen time without a config edit.
local function templateFor(defIndex: number, def): (Instance?, boolean)
	if #modelPool == 0 then
		return nil, false
	end
	if def.model ~= nil then
		local pinned = modelByName[def.model]
		if pinned ~= nil then
			return pinned, true
		end
		-- A pin that does not resolve is a CONTENT bug (renamed/removed art), and
		-- silently falling back would hide it behind a plausible-looking find.
		Log.Once(
			SCOPE,
			`pin-missing-{def.id}`,
			`find '{def.id}' pins model '{def.model}' which is not in the library — falling back to round-robin`
		)
	end
	return modelPool[(defIndex - 1) % #modelPool + 1], false
end

function TreasureService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
	treasureCfg = data.CakeConfigData.treasures

	buildLibrary()

	-- The ONE fallback template orb pickups clone from (R5) — used only when
	-- the authored library is missing, so the feature degrades instead of
	-- vanishing (R8).
	local size = treasureCfg.model.targetSizeStuds
	local template = Instance.new("Part")
	template.Name = "FindPickup"
	template.Shape = Enum.PartType.Ball
	template.Size = Vector3.new(size, size, size)
	template.Material = Enum.Material.Neon
	template.Anchored = true
	template.CanCollide = false
	template.CanTouch = false
	template.CanQuery = false
	template.CastShadow = false
	template:SetAttribute(BASE_TRANSPARENCY, 0)
	fallbackTemplate = template

	-- FX templates, cloned onto each spawned find (never Instance.new in the tick).
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "FindSparkle"
	sparkle.Enabled = false
	sparkle.Rate = treasureCfg.model.sparkleRate
	sparkle.Lifetime = NumberRange.new(0.5, 1.1)
	sparkle.Speed = NumberRange.new(2, 5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Acceleration = Vector3.new(0, 6, 0)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkleTemplate = sparkle

	-- Rim glow on an exposed find. Occluded (NOT AlwaysOnTop) so it only rims
	-- the part sticking out of the cake — a treasure radar through solid cake
	-- would kill the whole point of digging.
	local highlight = Instance.new("Highlight")
	highlight.Name = "FindGlow"
	highlight.FillTransparency = 0.85
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = true
	highlightTemplate = highlight
end

-- Rarity ladder, used to skew deep finds toward the good stuff (see
-- `spawn.depthRarityBias`). Anything unlisted ranks as common.
local RARITY_RANK = { common = 0, uncommon = 1, rare = 2, epic = 3, legendary = 4 }

-- `depthFrac`: 0 at the cake surface, 1 at the deepest edible band. At 0 the
-- distribution is byte-identical to a flat roll, so the early game is untouched.
local function weightedFind(depthFrac: number?): (number, any)
	local lift = 1 + (treasureCfg.spawn.depthRarityBias or 0) * math.clamp(depthFrac or 0, 0, 1)
	local weights, total = {}, 0
	for index, def in ipairs(treasureCfg.finds) do
		local w = def.weight * lift ^ (RARITY_RANK[def.rarity] or 0)
		weights[index] = w
		total += w
	end
	local roll = math.random() * total
	for index, def in ipairs(treasureCfg.finds) do
		roll -= weights[index]
		if roll <= 0 then
			return index, def
		end
	end
	return 1, treasureCfg.finds[1]
end

local function setFindAlpha(find, alpha: number)
	for _, target in ipairs(find.alphaTargets) do
		local base = target:GetAttribute(BASE_TRANSPARENCY)
		local baseAlpha = if type(base) == "number" then base else 0
		;(target :: any).Transparency = baseAlpha + (1 - baseAlpha) * alpha
	end
end

-- Authored emitters/lights only run once the prop is coming out of the cake.
local function setFindEmitters(find, enabled: boolean)
	for _, emitter in ipairs(find.emitters) do
		local base = emitter:GetAttribute(BASE_ENABLED)
		;(emitter :: any).Enabled = enabled and (base ~= false)
	end
end

-- ── Spawn ───────────────────────────────────────────────────────────────

--API
-- Rolls the find set for the freshly built cake (call AFTER ResetCake).
function TreasureService.SpawnForCake()
	local dropped = 0
	for _, find in ipairs(state.treasures) do
		if find.model then
			if find.state ~= "collected" then
				dropped += 1
			end
			find.model:Destroy()
		end
		find.model = nil
	end
	if dropped > 0 then
		-- Not a bug by itself (the boss phase + spawn delay give the cascade
		-- ~60 s to drain), but a silent reward loss must never be invisible (R8).
		Log.Warn(SCOPE, `{dropped} find(s) of the previous cake were never dug out — despawned uncollected`)
	end
	table.clear(state.treasures)
	cascadeClock = 0
	glowCount = 0
	foundCount = 0

	if not pickupFolder then
		local folder = Instance.new("Folder")
		folder.Name = "CakeFinds"
		folder.Parent = workspace
		pickupFolder = folder
	end

	local grid = cakeCfg.grid
	local modelCfg = treasureCfg.model
	local spawnCfg = treasureCfg.spawn
	local count = math.clamp(math.floor(state.edibleVolume / spawnCfg.volumePerFind), spawnCfg.minFinds, spawnCfg.maxFinds)

	-- Deal the finds ROUND-ROBIN over the edible bands (shuffled once) instead
	-- of sprinkling them at uniform heights: with ~28-42 layers and 40 finds
	-- that puts ~1 in every layer, so no layer is ever a dry stretch. The
	-- reward beat is what carries a 40-minute cake.
	local bands = {}
	for index = 2, #state.composition do -- index 1 is the inedible core
		table.insert(bands, index)
	end
	if #bands == 0 then
		Log.Warn(SCOPE, "cake has no edible bands — no finds buried")
		return
	end
	for index = #bands, 2, -1 do
		local swap = math.random(index)
		bands[index], bands[swap] = bands[swap], bands[index]
	end

	local topStuds = state.composition[#state.composition].top
	local floorStuds = GridUtil.UnitsToStuds(state.floorUnits)
	local footprint = state.footprint
	local usedModels = 0
	-- id -> model actually used, so the boot log shows whether rarity reads
	-- correctly ("*" = pinned by config, bare = round-robin fallback).
	local assignedModel: { [string]: string } = {}

	local depthSpan = math.max(1, topStuds - floorStuds)
	for k = 1, count do
		-- Which band this find is dealt to is fixed by `k` alone, so it can be
		-- resolved BEFORE the rarity roll — which is what lets depth bias the roll.
		local band = state.composition[bands[(k - 1) % #bands + 1]]
		local depthFrac = math.clamp((topStuds - band.top) / depthSpan, 0, 1)
		local defIndex, def = weightedFind(depthFrac)
		local template, pinned = templateFor(defIndex, def)
		if template ~= nil then
			assignedModel[def.id] = `{template.Name}{if pinned then "*" else ""}`
		end
		local root = if template ~= nil then template:Clone() else (fallbackTemplate :: BasePart):Clone()
		if template ~= nil then
			usedModels += 1
		else
			(root :: BasePart).Color = def.color
		end

		-- Per-find size jitter — variety without leaving the 1.5-2× band.
		-- RARITY IS SIZE (`rarityScale`): while a find is still buried its size is
		-- the only rarity cue available — the rim glow that carries colour does
		-- not exist until the crown breaks through. Folded into the same single
		-- rescale as the jitter so the model is only scaled ONCE.
		local rarityMul = (modelCfg.rarityScale or {})[def.rarity] or 1
		local jitter = (1 + (math.random() * 2 - 1) * modelCfg.sizeJitter) * rarityMul
		if root:IsA("Model") then
			local model = root :: Model
			pcall(function()
				model:ScaleTo(model:GetScale() * jitter)
			end)
		else
			(root :: BasePart).Size *= jitter
		end

		-- TILT it. Half-buried objects never lie perfectly flat — and more
		-- importantly, an elongated prop (a rolling pin, a tray) laid flat is
		-- only ~1 stud tall, so it would be uncovered by a single scoop. A tilt
		-- gives every shape a real VERTICAL span to dig through.
		local tilt = math.rad(modelCfg.tiltDegrees)
		local pitch = (math.random() * 2 - 1) * tilt
		local roll = (math.random() * 2 - 1) * tilt
		local yaw = math.random() * math.pi * 2
		pivotTo(root, CFrame.new(0, 0, 0) * CFrame.Angles(pitch, yaw, roll))

		local _, size = boundsOf(root) -- WORLD span, after the tilt
		local height = size.Y
		-- Footprint radius from the AREA-EQUIVALENT extent (geometric mean), not
		-- the longest side: a 13x5 prop covers nothing like a 13x13 square, and
		-- sizing off the longest side made its cover test include metres of cake
		-- it never touched — a fully dug-out item that would not collect.
		local spanCells = math.max(1, math.ceil(math.sqrt(size.X * size.Z) * 0.5 / grid.cell))

		-- Cell: far enough inside the loaf that THIS model's own footprint
		-- (spanCells, not a constant) stays on the cake — a wide prop needs a
		-- wider margin than a narrow one or it pokes out of the side.
		local margin = spanCells + modelCfg.edgeMarginCells
		local bandFootprint = band.footprint or footprint
		local shrunk = {
			hx = math.max(1, bandFootprint.hx - margin),
			hz = math.max(1, bandFootprint.hz - margin),
			corner = math.max(1, bandFootprint.corner - margin),
		}
		local x, z
		repeat
			x = math.random(0, grid.size - 1)
			z = math.random(0, grid.size - 1)
		until GridUtil.InCake(grid.size, shrunk, x, z)

		-- Depth: sink the find's TOP into the band it was dealt. A 9-stud model
		-- in a 5-12 stud band therefore spans 1-3 bands — with the layer gate you
		-- often see its crown in one layer and only free it in the next (user req).
		local thickness = band.top - band.bottom
		local frac = modelCfg.burialFraction[1]
			+ math.random() * (modelCfg.burialFraction[2] - modelCfg.burialFraction[1])
		local topY = math.min(band.top - thickness * frac, topStuds - modelCfg.topClearanceStuds)
		-- The whole model must stay ABOVE the inedible core, or its bottom could
		-- never be uncovered and the find would be stranded forever.
		topY = math.max(topY, floorStuds + height + 0.5)
		local bottomY = topY - height

		local wx, wz = GridUtil.CellToWorld(grid, x, z)
		orientAt(root, Vector3.new(wx, grid.origin.y + (topY + bottomY) * 0.5, wz), yaw, pitch, roll)
		root.Name = `Find_{k}_{def.id}`

		local find = {
			def = def,
			x = x,
			z = z,
			model = root,
			parts = partsOf(root),
			alphaTargets = alphaTargetsOf(root),
			emitters = emittersOf(root),
			-- World point where the crown breaks the surface (reveal FX anchor).
			crown = Vector3.new(wx, grid.origin.y + topY, wz),
			height = height,
			radiusCells = spanCells,
			topUnits = GridUtil.StudsToUnits(topY),
			bottomUnits = GridUtil.StudsToUnits(bottomY),
			footprint = bandFootprint,
			-- MONOTONIC: only ever advances. buried -> loaded -> revealed ->
			-- collected. Refilling cake can never take a dug-out find back.
			state = "buried",
			exposure = 0,
		}

		-- Sparkle on the TOPMOST part, so the glitter appears at the crown that
		-- breaks the surface first — not somewhere still deep in the cake.
		local anchor: BasePart? = nil
		for _, part in ipairs(find.parts) do
			if anchor == nil or part.Position.Y > anchor.Position.Y then
				anchor = part
			end
		end
		if anchor ~= nil then
			local sparkle = (sparkleTemplate :: ParticleEmitter):Clone()
			sparkle.Color = ColorSequence.new(def.color)
			sparkle.Parent = anchor
			find.sparkle = sparkle
		end

		setFindAlpha(find, 1) -- fully hidden until the surface nears it
		root.Parent = pickupFolder
		table.insert(state.treasures, find)
	end

	local mapping = {}
	for id, modelName in pairs(assignedModel) do
		table.insert(mapping, `{id}={modelName}`)
	end
	table.sort(mapping)
	Log.Info(
		SCOPE,
		`{count} finds buried in cake #{state.cakeIndex} ({usedModels} authored models, {count - usedModels} fallback orbs) across {#bands} bands`
	)
	if #mapping > 0 then
		Log.Info(SCOPE, `find art (* = pinned): {table.concat(mapping, ", ")}`)
	end
end

-- ── Uncovering ──────────────────────────────────────────────────────────

-- Surface stats over the find's own XZ footprint, in ONE pass:
--   minCover   — the LOWEST surface above it. The crown shows the moment this
--                drops past the find's top, which is what the player SEES.
--   clearFrac  — fraction of footprint cells already eaten to/below `freedAt`.
-- ⚠ Both used to be a single MAX, and both were wrong at the ends: reveal fired
-- late (it waited for the WHOLE footprint to drop), and a wide flat prop never
-- freed at all — its bounding footprint is far bigger than its silhouette, so
-- one un-eaten corner cell held a find that looked completely dug out (seen in
-- a playtest: an uncovered slab the player stood next to and could not collect).
local function coverStats(find, freedAt: number): (number, number)
	local field = state.field :: buffer
	local size = cakeCfg.grid.size
	local radius = find.radiusCells
	local footprint = find.footprint or state.footprint
	local minCover, cleared, total = 65535, 0, 0
	local r2 = radius * radius
	for dz = -radius, radius do
		local cz = find.z + dz
		for dx = -radius, radius do
			local cx = find.x + dx
			-- CIRCULAR, not the square bounding box: the corners of a square
			-- footprint are cake the item does not actually sit under, and they
			-- were holding fully-exposed finds hostage.
			if dx * dx + dz * dz <= r2 and GridUtil.InBounds(size, cx, cz) and GridUtil.InCake(size, footprint, cx, cz) then
				local h = GridUtil.ReadHeight(field, GridUtil.Index(size, cx, cz))
				total += 1
				if h < minCover then
					minCover = h
				end
				if h <= freedAt then
					cleared += 1
				end
			end
		end
	end
	if total == 0 then
		return 0, 1
	end
	return minCover, cleared / total
end

-- The pop-out + fly-to-player flourish, server-side so everyone sees it
-- (R4-safe: a timed loop, never an event subscription).
local function playCollect(find, player: Player)
	local root = find.model
	if root == nil then
		return
	end
	local modelCfg = treasureCfg.model
	local startCf = pivotOf(root)

	if find.sparkle then
		find.sparkle.Rate = modelCfg.sparkleRate * 4
	end
	-- Free of the cake: the rim glow goes full, nothing occludes it any more.
	if find.glow then
		find.glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		find.glow.FillTransparency = 0.6
	end

	task.spawn(function()
		-- 1) POP: burst out of the hole with an overshoot and a fast spin.
		local elapsed = 0
		while elapsed < modelCfg.pop.seconds and root.Parent ~= nil do
			elapsed += RunService.Heartbeat:Wait()
			local t = math.min(1, elapsed / modelCfg.pop.seconds)
			local eased = 1 - (1 - t) * (1 - t) -- ease-out
			local lift = modelCfg.pop.heightStuds
				* eased
				* (1 + (modelCfg.pop.overshoot - 1) * math.sin(t * math.pi))
			pivotTo(root, (startCf + Vector3.new(0, lift, 0)) * CFrame.Angles(0, math.rad(modelCfg.pop.spinDegrees) * t, 0))
		end

		-- 2) FLY: magnet into the collector, fading only at the very end.
		local flyStart = pivotOf(root).Position
		elapsed = 0
		while elapsed < modelCfg.fly.seconds and root.Parent ~= nil do
			elapsed += RunService.Heartbeat:Wait()
			local t = math.min(1, elapsed / modelCfg.fly.seconds)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local target = if hrp then hrp.Position + Vector3.new(0, 2.5, 0) else flyStart
			local position = flyStart:Lerp(target, t * t) -- accelerate into the player
				+ Vector3.new(0, math.sin(t * math.pi) * modelCfg.fly.arcStuds, 0)
			pivotTo(
				root,
				CFrame.new(position)
					* CFrame.Angles(0, math.rad(modelCfg.fly.spinDegrees) * t, 0)
					* CFrame.Angles(math.rad(25 * t), 0, 0)
			)
			setFindAlpha(find, t * t * t)
		end
		root:Destroy()
		find.model = nil
		find.sparkle = nil
		if find.glow ~= nil then
			find.glow = nil
			glowCount = math.max(0, glowCount - 1)
		end
	end)
end

--API
-- Per-cake collected / total, for the HUD "FINDS n/N" goal.
function TreasureService.FindCounts(): (number, number)
	return foundCount, #state.treasures
end

--API
-- Tick (2 Hz): fades finds in as the surface nears them, reveals their crown,
-- and auto-collects the ones that are fully dug out. `loadedUserIds` =
-- { [userId] = true } — only these players can consume a find (an unloaded
-- collector would destroy the pickup and then fail the grant). Returns:
--   near      — { find } (surface is CLOSE: the cake glints above it, so the
--                player digs somewhere on purpose instead of mowing blindly)
--   revealed  — { find } (first crown showing — dust puff + chime)
--   collected — { { find, player, position } }
--API
-- STUDIO DEV TOOL. Carves the cake away over the nearest still-buried find until
-- `leaveFraction` of its footprint is still covered, so the NEXT `Tick` walks it
-- through the real `loaded -> revealed -> strain -> freed` path. It does not set
-- states directly: bypassing the path would verify nothing.
--
-- Why this exists: at production scale a find takes MINUTES of eating to reach
-- the surface (clear time is area-driven), so every find-related visual was
-- effectively unverifiable — the only recorded workaround was to shrink the loaf
-- in config, replay, and revert, which is slow, easy to leave behind, and still
-- does not put a find under YOUR feet.
--
--   leaveFraction 0.5  -> revealed, mid-strain, will NOT free (watch the escalation)
--   leaveFraction 0    -> fully uncovered, frees on the next tick (watch the pop)
--
-- Returns the find id + how many cells it carved, or nil if there is nothing left
-- to uncover.
function TreasureService.DebugUncoverNearest(position: Vector3, leaveFraction: number?): (string?, number)
	-- Gated HERE as well as at the caller. The Studio check in CakeSimulationSubs
	-- protects the current call site; this protects every FUTURE one. A debug
	-- function that hands out rewards is exactly the thing that gets wired to a
	-- remote by accident later, and defence in depth costs two lines.
	if not RunService:IsStudio() then
		Log.Warn(SCOPE, "DebugUncoverNearest called outside Studio — refused (dev tool, never a live surface)")
		return nil, 0
	end
	if state == nil or state.field == nil or state.treasures == nil then
		Log.Warn(SCOPE, "DebugUncoverNearest: no live cake")
		return nil, 0
	end
	local grid = cakeCfg.grid
	local best, bestDist
	for _, find in ipairs(state.treasures) do
		if find.state ~= "collected" and find.model ~= nil then
			local wx, wz = GridUtil.CellToWorld(grid, find.x, find.z)
			local d = (Vector3.new(wx, position.Y, wz) - position).Magnitude
			if bestDist == nil or d < bestDist then
				best, bestDist = find, d
			end
		end
	end
	if best == nil then
		Log.Warn(SCOPE, "DebugUncoverNearest: every find on this cake is already collected")
		return nil, 0
	end

	-- Carve down to just above the find's BOTTOM so it reads as uncovered, over
	-- all but `leaveFraction` of its footprint (the outermost ring is kept, so
	-- what remains is a believable collar of cake rather than random holes).
	local keep = math.clamp(leaveFraction or 0, 0, 1)
	local target = best.bottomUnits + GridUtil.StudsToUnits(treasureCfg.model.freedEpsilonStuds) - 1
	local radius = best.radiusCells
	local cells = {}
	for dz = -radius, radius do
		for dx = -radius, radius do
			local d2 = dx * dx + dz * dz
			if d2 <= radius * radius then
				local cx, cz = best.x + dx, best.z + dz
				if GridUtil.InBounds(grid.size, cx, cz) and GridUtil.InCake(grid.size, state.footprint, cx, cz) then
					table.insert(cells, { i = GridUtil.Index(grid.size, cx, cz), d2 = d2 })
				end
			end
		end
	end
	table.sort(cells, function(a, b)
		return a.d2 < b.d2 -- carve from the centre outward
	end)
	local carveCount = math.floor(#cells * (1 - keep))
	local carved = 0
	for n = 1, carveCount do
		local cell = cells[n]
		if GridUtil.ReadHeight(state.field, cell.i) > target then
			GridUtil.WriteHeight(state.field, cell.i, math.max(0, target))
			carved += 1
		end
	end
	Log.Sum(
		SCOPE,
		`DEBUG uncovered '{best.def.id}' ({best.def.rarity}) — carved {carved}/{#cells} footprint cells, keeping {math.floor(keep * 100)}%`
	)
	return best.def.id, carved
end

function TreasureService.Tick(loadedUserIds: { [number]: boolean }, dt: number?)
	local grid = cakeCfg.grid
	local modelCfg = treasureCfg.model
	local near, revealed, collected = {}, {}, {}
	cascadeClock = math.max(0, cascadeClock - (dt or 0.5))
	pulseClock += (dt or 0.5)

	local playerRoots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and loadedUserIds[player.UserId] then
			table.insert(playerRoots, { player = player, position = (root :: BasePart).Position })
		end
	end

	local preloadUnits = GridUtil.StudsToUnits(modelCfg.preloadLeadStuds)
	local revealUnits = GridUtil.StudsToUnits(modelCfg.revealEpsilonStuds)
	local freedUnits = GridUtil.StudsToUnits(modelCfg.freedEpsilonStuds)
	local field = state.field :: buffer

	for _, find in ipairs(state.treasures) do
		-- Cheap early-out: the centre cell alone proves the surface is still far
		-- above (the common case for every deep find). cover >= centre always.
		local centre = GridUtil.ReadHeight(field, GridUtil.Index(grid.size, find.x, find.z))
		if find.state ~= "collected" and find.model ~= nil and centre <= find.topUnits + preloadUnits then
			local cover, clearFrac = coverStats(find, find.bottomUnits + freedUnits)

			if find.state == "buried" and cover <= find.topUnits + preloadUnits then
				find.state = "loaded"
				setFindEmitters(find, true)
				table.insert(near, find)
				-- Fade in a few studs early: the cake still covering it masks the
				-- fade, so the model never "pops" into existence.
				task.spawn(function()
					local elapsed = 0
					-- Bails the moment the find is collected: the collect flight
					-- owns the alpha from then on (it fades the item away).
					while elapsed < modelCfg.fadeInSeconds and find.model ~= nil and find.state ~= "collected" do
						elapsed += RunService.Heartbeat:Wait()
						setFindAlpha(find, 1 - math.min(1, elapsed / modelCfg.fadeInSeconds))
					end
					if find.model ~= nil and find.state ~= "collected" then
						setFindAlpha(find, 0)
					end
				end)
			end

			-- MONOTONIC exposure — refilling cake never re-buries a find. It also
			-- drives the sparkle: the more of the item is out, the harder it
			-- glitters (the "keep digging, it's nearly yours" pull).
			local span = math.max(1, find.topUnits - find.bottomUnits)
			local exposure = math.clamp((find.topUnits - cover) / span, 0, 1)
			exposure = math.max(exposure, clearFrac)
			if exposure > find.exposure then
				find.exposure = exposure
				if find.sparkle and find.state == "revealed" then
					find.sparkle.Rate = modelCfg.sparkleRate * (0.5 + 1.5 * exposure)
				end
			end

			if find.state == "loaded" and cover <= find.topUnits + revealUnits then
				find.state = "revealed"
				if find.sparkle then
					find.sparkle.Enabled = true
				end
				-- Rim the exposed crown so it screams "dig here". Capped: the
				-- engine only renders ~31 Highlights, and a gated find can sit
				-- half-out for a whole layer.
				if glowCount < MAX_GLOWS and find.model ~= nil then
					local glow = (highlightTemplate :: Highlight):Clone()
					glow.FillColor = find.def.color
					glow.OutlineColor = find.def.color
					glow.Parent = find.model
					find.glow = glow
					glowCount += 1
				end
				table.insert(revealed, find)
			end

			-- Rarity PULSE on an exposed-but-not-yet-freed find. `glowPulse` is 0
			-- for common on purpose: with up to 40 finds a pulse on everything is
			-- wallpaper, so only the ones worth crossing the cake for breathe —
			-- the pulse reads as "this one matters" before you can tell what it
			-- is. Cheap (a property write on at most MAX_GLOWS instances) and
			-- server-side because the Highlight lives on the server-owned model.
			if find.state == "revealed" and find.glow ~= nil then
				local strainCfg = modelCfg.strain
				local strainWindow = math.max(1e-3, modelCfg.freedCoverFraction - strainCfg.startFraction)
				local pull = math.clamp((clearFrac - strainCfg.startFraction) / strainWindow, 0, 1)
				-- FILL floods for EVERY find, rarity be damned: "this is about to
				-- come loose" is information every dig deserves. Gating it behind
				-- `glowPulse > 0` (as the first cut did) silently gave 60% of finds
				-- — berry + candy-gem carry 60 of 98 roll weight — no anticipation
				-- cue at all. Only the PULSE is a rarity signal; the strain is not.
				find.glow.FillTransparency = math.clamp(0.85 - strainCfg.fillGain * pull, 0, 1)

				local depth = (treasureCfg.rarityFx[find.def.rarity] or {}).glowPulse or 0
				if depth > 0 then
					-- STRAIN: the anticipation window (crown showing, not yet free)
					-- used to be the FLATTEST part of the dig — the find just sat
					-- there. Now the rim pulse deepens and the fill floods in as the
					-- last cake comes off, so the release is something you can SEE
					-- coming. Property writes only: deliberately NOT a pose wobble,
					-- because moving the model per tick compounds through
					-- `GetPivot()` on a PrimaryPart-less Model (it returns the
					-- recomputed AABB centre with IDENTITY rotation, so each
					-- PivotTo re-applies the rotation) — that stranded 6 finds.
					local wave = 0.5 + 0.5 * math.sin(pulseClock * modelCfg.highlightPulseHz * math.pi * 2)
					-- Depth grows as it comes loose (the pulse gets more violent).
					-- Rate is left ALONE on purpose: changing hz mid-pulse jumps
					-- the phase.
					find.glow.OutlineTransparency =
						math.clamp(0.1 + depth * (1 + strainCfg.pulseGain * pull * pull) * wave, 0, 1)
				end
			end

			-- FREED: nothing covers the item any more. Its bottom always sits
			-- above the inedible core (SpawnForCake clamps it), so every find is
			-- reachable — the layer gate only decides WHEN, which is the point:
			-- a find spanning a band boundary is freed in the NEXT layer.
			-- Collections are dealt one per cascade beat, so an auto-swept layer
			-- pops its finds out one after another instead of all at once.
			if find.state == "revealed" and clearFrac >= modelCfg.freedCoverFraction and cascadeClock <= 0 then
				local pivot = boundsOf(find.model)
				local nearest, bestDistance = nil, math.huge
				for _, entry in ipairs(playerRoots) do
					local distance = (entry.position - pivot).Magnitude
					if distance < bestDistance then
						nearest, bestDistance = entry.player, distance
					end
				end
				if nearest ~= nil then
					find.state = "collected" -- flag on the FIND (§13)
					foundCount += 1
					cascadeClock = modelCfg.cascadeSeconds
					table.insert(collected, { find = find, player = nearest, position = pivot })
					playCollect(find, nearest)
				end
			end
		end
	end

	return near, revealed, collected
end

return TreasureService
