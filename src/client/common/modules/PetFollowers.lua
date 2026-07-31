--[[
	PetFollowers — the equipped SQUISHIES flying behind every player, rendered
	locally from the replicated "EquippedPets" attribute (csv of petIds).

	Runs in BOTH places: the per-frame Step is driven by PetsSubsClient (common),
	not by BodySubsClient — that one returns early without the game partition, so
	while it owned the step the lobby had no followers at all.

	BODY: the place-authored 3D model named by `PetConfig.model` under
	`ReplicatedStorage.Assets.Squishes` (ADR-0007 content). Each model is
	PREPARED once, lazily, into an unparented template (R5): animation-editor
	leftovers stripped, scaled to a common size, every part anchored and made
	collision/query/touch/shadow-free. Movement is `Model:PivotTo` — the
	authored models are 1-6 parts, so rigid-body welding buys nothing and DOES
	break: several of them nest parts inside other parts (`Planet Texture` under
	`Planet Texture`, `Torus` under `planete`), and a welded assembly built that
	way left every mesh sitting at its authored map coordinates while only the
	root flew. A missing/renamed model warns ONCE (R8) and falls back to the
	`PetConfig.look` primitive rather than rendering nothing.

	MOTION: a shallow arc BEHIND the player's back, trailed with an exponential
	lag so turning swings them around, bobbing out of phase, banking into the
	turn. All numbers live in `PetConfig.follow` (R1/R2).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared:WaitForChild("config"):WaitForChild("PetConfig"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "PetFollowers"

local PetFollowers = {}

local cfg
local petsById: { [string]: any } = {}
local folder: Folder?
local clock = 0

-- petId -> { model = PVInstance, pivotOffset = CFrame }
local templates: { [string]: any } = {}

type Follower = {
	model: PVInstance,
	pivotOffset: CFrame,
	slot: Vector3,
	phase: number,
	position: Vector3,
	bank: number,
	seeded: boolean,
}

-- [player] = { csv, followers, facing } — `facing` is the 0..1 idle->running
-- blend that swivels the whole formation (per player, not per squishy).
local followers: { [Player]: { csv: string, followers: { Follower }, facing: number? } } = {}

function PetFollowers.Init()
	cfg = PetConfig.follow
	for _, def in ipairs(PetConfig.pets) do
		petsById[def.id] = def
	end
	folder = Instance.new("Folder")
	folder.Name = "PetFollowers"
	folder.Parent = workspace
end

-- The authored models live in PLACE content, which may replicate slightly after
-- the client boots. Resolved lazily (never with a blocking WaitForChild — R8's
-- rule about late dependencies) so a slow replication delays the first follower
-- instead of stalling the feature.
local function squishFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild(cfg.assetsFolder) or nil
end

-- Where the model's PIVOT sits relative to its visual centre. The runtime aims
-- the CENTRE at the slot; authored pivots sit at the model's base (measured:
-- +3.3 studs of body above the pivot), so without this every squishy would fly
-- with its chin on the target point.
local function pivotOffsetOf(model: PVInstance): CFrame
	local boxCFrame = if model:IsA("Model") then (model:GetBoundingBox()) else (model :: BasePart).CFrame
	return boxCFrame:ToObjectSpace(model:GetPivot())
end

-- Fallback body when `model` cannot be resolved: the old primitive `look`, so a
-- broken/renamed asset is VISIBLE and obviously wrong instead of invisible.
local function buildPrimitive(def): BasePart
	local shape = def.look and def.look.shape
	local part = Instance.new("Part")
	if shape == "donut" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(cfg.sizeStuds * 0.45, cfg.sizeStuds, cfg.sizeStuds)
	elseif shape == "cube" then
		part.Size = Vector3.new(cfg.sizeStuds, cfg.sizeStuds, cfg.sizeStuds) * 0.8
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(cfg.sizeStuds, cfg.sizeStuds, cfg.sizeStuds) * 0.9
	end
	part.Color = (def.look and def.look.color) or Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- One-time preparation of an authored model into a flyable template.
local function prepare(def)
	local cached = templates[def.id]
	if cached ~= nil then
		return cached
	end

	local library = squishFolder()
	local source = library and def.model and library:FindFirstChild(def.model) or nil
	if source == nil then
		Log.Once(
			SCOPE,
			`no-model-{def.id}`,
			`squishy '{def.id}' model '{tostring(def.model)}' not found under ReplicatedStorage.Assets.{cfg.assetsFolder}`
				.. ` — flying the placeholder primitive instead (see docs/features/pets.md)`
		)
		-- NOT cached. `Assets` is place content, so it can simply be LATE; caching
		-- the fallback would let one replication race decide this squishy's body
		-- for the whole session, which is the opposite of what the lazy resolve
		-- above exists for. The next rebuild re-resolves and picks up the model.
		return { model = buildPrimitive(def), pivotOffset = CFrame.identity }
	end

	local model = source:Clone()

	-- Animation-editor leftovers: AnimSaves holds KeyframeSequences (a Studio
	-- save format, not a playable animation) and InitialPoses holds CFrameValues.
	-- Motor6Ds are dropped because a joint fights a per-frame PivotTo. Bones are
	-- NOT touched — skinned meshes need them for their bind pose.
	local doomed = {}
	for _, d in ipairs(model:GetDescendants()) do
		if
			d:IsA("AnimationController")
			or d:IsA("Motor6D")
			or d:IsA("KeyframeSequence")
			or d.Name == "AnimSaves"
			or d.Name == "InitialPoses"
		then
			table.insert(doomed, d)
		end
	end
	for _, d in ipairs(doomed) do
		d:Destroy()
	end

	-- Scale to a common size BEFORE the pivot offset is measured — the authored
	-- models range 7.4..20 studs tall, so unscaled they fly at wildly different
	-- sizes and the offset would be measured against the wrong body.
	local _, size = model:GetBoundingBox()
	local biggest = math.max(size.X, size.Y, size.Z)
	if biggest > 0.001 then
		model:ScaleTo(cfg.sizeStuds / biggest)
	end

	local partCount = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	if partCount == 0 then
		-- A resolved-but-empty model IS a config error, not a race, so unlike the
		-- not-found branch above this one is cached: retrying it every rebuild
		-- would re-clone and re-destroy the same empty model forever.
		Log.Once(SCOPE, `empty-model-{def.id}`, `squishy '{def.id}' model '{def.model}' has no BasePart — flying the placeholder primitive`)
		model:Destroy()
		local entry = { model = buildPrimitive(def), pivotOffset = CFrame.identity }
		templates[def.id] = entry
		return entry
	end

	local entry = { model = model, pivotOffset = pivotOffsetOf(model) }
	templates[def.id] = entry
	return entry
end

-- Slot offsets for n squishies, in the player's own object space. The arc is
-- centred on straight-behind whatever n is, so equipping a 4th does not shove
-- the other three sideways.
local function slotsFor(count: number): { Vector3 }
	local slots = {}
	for k = 1, count do
		local angle = (k - (count + 1) / 2) * cfg.spreadRadians
		table.insert(
			slots,
			Vector3.new(math.sin(angle) * cfg.radiusStuds, cfg.heightStuds, math.cos(angle) * cfg.radiusStuds)
		)
	end
	return slots
end

local function destroyAll(entry)
	for _, follower in ipairs(entry.followers) do
		follower.model:Destroy()
	end
end

local function rebuild(player: Player, csv: string, seedPosition: Vector3?)
	local entry = followers[player]
	if entry then
		destroyAll(entry)
	end
	entry = { csv = csv, followers = {} }
	followers[player] = entry
	if csv == "" then
		return
	end

	local defs = {}
	for petId in string.gmatch(csv, "[^,]+") do
		local def = petsById[petId]
		if def then
			table.insert(defs, def)
		else
			Log.Once(SCOPE, `unknown-pet-{petId}`, `equipped pet id '{petId}' is not in PetConfig — no follower rendered`)
		end
	end

	local slots = slotsFor(#defs)
	local seed = seedPosition or Vector3.new(0, -500, 0)
	for index, def in ipairs(defs) do
		local template = prepare(def)
		if template then
			local model = template.model:Clone()
			model.Name = `{player.Name}_{def.id}`
			model:PivotTo(CFrame.new(seed))
			model.Parent = folder
			table.insert(entry.followers, {
				model = model,
				pivotOffset = template.pivotOffset,
				slot = slots[index],
				phase = (index - 1) * cfg.bobPhase,
				position = seed,
				bank = 0,
				seeded = seedPosition ~= nil,
			})
		end
	end
end

--API
-- Per-frame update (connected in PetsSubsClient — COMMON, so it runs in the
-- lobby and in the game place alike).
function PetFollowers.Step(dt: number)
	if cfg == nil then
		return -- Init never ran; the bootstrap already reported that.
	end
	clock += dt
	-- Framerate-independent exponential approach.
	local followAlpha = 1 - math.exp(-cfg.followRate * dt)
	local bankAlpha = 1 - math.exp(-cfg.bankSmoothing * dt)

	for player, entry in pairs(followers) do
		if player.Parent == nil then
			destroyAll(entry)
			followers[player] = nil
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

		local csv = tostring(player:GetAttribute("EquippedPets") or "")
		local entry = followers[player]
		if not entry or entry.csv ~= csv then
			rebuild(player, csv, root and root.Position or nil)
			entry = followers[player]
		end
		if #entry.followers == 0 then
			continue
		end

		if root == nil then
			-- Dead / respawning: park out of sight instead of leaving them
			-- frozen over the corpse spot, and force a snap on the way back.
			for _, follower in ipairs(entry.followers) do
				follower.model:PivotTo(CFrame.new(0, -500, 0))
				follower.seeded = false
			end
			continue
		end

		local rootCFrame = root.CFrame
		-- Face where the PLAYER faces (flattened), not where the pet drifts —
		-- a formation reads as a formation. The 2-arg CFrame.new(pos, target)
		-- is degenerate when the two coincide, hence the flat-look guard.
		local look = rootCFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)

		-- Flying forward while running, swivelled round to look at the player
		-- while idle. Interpolated as a YAW ANGLE, never as a direction vector:
		-- the two ends are exactly opposite, so a vector lerp is degenerate
		-- (zero length) at the halfway point.
		local velocity = root.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local wantFacing = math.clamp(flatSpeed / cfg.faceForwardSpeedStuds, 0, 1)
		entry.facing = (entry.facing or 0) + (wantFacing - (entry.facing or 0)) * (1 - math.exp(-cfg.facingSmoothing * dt))
		local yaw = math.rad(cfg.yawOffsetDegrees + 180 * (1 - entry.facing))

		for _, follower in ipairs(entry.followers) do
			local target = rootCFrame * follower.slot
			if not follower.seeded or (target - follower.position).Magnitude > cfg.snapDistanceStuds then
				-- Respawn / checkpoint teleport / place handoff: appear at the
				-- slot instead of streaking across the map to reach it.
				follower.position = target
				follower.seeded = true
			else
				follower.position = follower.position:Lerp(target, followAlpha)
			end

			-- How far the squishy still is from its slot SIDEWAYS is exactly how
			-- hard it is currently cornering.
			local lag = rootCFrame:PointToObjectSpace(follower.position)
			local bank = math.clamp(
				(lag.X - follower.slot.X) * cfg.bankDegreesPerStud,
				-cfg.maxBankDegrees,
				cfg.maxBankDegrees
			)
			follower.bank += (bank - follower.bank) * bankAlpha

			local bob = math.sin(clock * cfg.bobSpeed + follower.phase) * cfg.bobStuds
			local at = follower.position + Vector3.new(0, bob, 0)
			local centre = CFrame.lookAt(at, at + flat) * CFrame.Angles(0, yaw, math.rad(follower.bank))
			follower.model:PivotTo(centre * follower.pivotOffset)
		end
	end
end

return PetFollowers
