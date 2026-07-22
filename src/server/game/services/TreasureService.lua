--[[
	TreasureService — finds buried in the cake (GDD §6.1).

	At cake spawn, finds are rolled into cells + reveal heights. As the
	surface drops past a find, a pickup spawns (cloned from a template —
	R5). Collection is proximity-based, checked server-side in the 2 Hz
	tick (no Touched races): first player near it wins — the consumed flag
	lives ON THE FIND, not on the player (GDD §13).

	R2/R3: state in CakeStateData.treasures; granting rewards + firing
	TreasureUpdate is CakeSubs' job — this service returns collect events.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local Log = require(Shared:WaitForChild("Log"))

local TreasureService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake
local treasureCfg -- CakeConfigData.treasures

local pickupTemplate: BasePart?
local pickupFolder: Folder?

function TreasureService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
	treasureCfg = data.CakeConfigData.treasures

	-- Build the ONE template all pickups clone from (R5).
	local template = Instance.new("Part")
	template.Name = "FindPickup"
	template.Shape = Enum.PartType.Ball
	template.Size = Vector3.new(2.4, 2.4, 2.4)
	template.Material = Enum.Material.Neon
	template.Anchored = true
	template.CanCollide = false
	template.CanTouch = false
	template.CanQuery = false
	template.CastShadow = false
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 3 -- 40 concurrent pickups must stay under the 200-particle budget
	sparkle.Lifetime = NumberRange.new(0.6, 1)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.Size = NumberSequence.new(0.3)
	sparkle.Parent = template
	pickupTemplate = template
end

local function weightedFind()
	local total = 0
	for _, def in ipairs(treasureCfg.finds) do
		total += def.weight
	end
	local roll = math.random() * total
	for _, def in ipairs(treasureCfg.finds) do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return treasureCfg.finds[1]
end

--API
-- Rolls the find set for the freshly built cake (call AFTER ResetCake).
function TreasureService.SpawnForCake()
	-- Drop leftovers from the previous cake.
	for _, find in ipairs(state.treasures) do
		if find.part then
			find.part:Destroy()
		end
	end
	table.clear(state.treasures)

	if not pickupFolder then
		pickupFolder = Instance.new("Folder")
		pickupFolder.Name = "CakeFinds"
		pickupFolder.Parent = workspace
	end

	local grid = cakeCfg.grid
	local spawnCfg = treasureCfg.spawn
	local count = math.clamp(math.floor(state.edibleVolume / spawnCfg.volumePerFind), spawnCfg.minFinds, spawnCfg.maxFinds)
	local topStuds = state.composition[#state.composition].top
	local floorStuds = GridUtil.UnitsToStuds(state.floorUnits)

	for k = 1, count do
		-- Random in-cake cell (rejection sampling over the round footprint).
		local x, z
		repeat
			x = math.random(0, grid.size - 1)
			z = math.random(0, grid.size - 1)
		until GridUtil.InCake(grid.size, state.footprint, x, z)
		local minH = floorStuds + 0.5
		local maxH = topStuds * (1 - spawnCfg.minDepthFraction)
		local revealStuds = minH + math.random() * (maxH - minH)
		table.insert(state.treasures, {
			def = weightedFind(),
			x = x,
			z = z,
			revealUnits = GridUtil.StudsToUnits(revealStuds),
			state = "buried",
			part = nil,
			spawnedAt = 0,
		})
	end
	Log.Info("Treasure", `{count} finds buried in cake #{state.cakeIndex}`)
end

--API
-- 2 Hz tick: reveals finds the surface has dropped to, expires stale ones,
-- detects proximity collection. `loadedUserIds` = { [userId] = true } —
-- only these players can consume a find (an unloaded collector would
-- destroy the pickup and then fail the grant). Returns two arrays:
--   spawned   — { { find } }
--   collected — { { find, player, position } }
function TreasureService.Tick(loadedUserIds: { [number]: boolean })
	local field = state.field :: buffer
	local grid = cakeCfg.grid
	local now = os.clock()
	local spawned, collected = {}, {}

	local playerRoots = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and loadedUserIds[player.UserId] then
			table.insert(playerRoots, { player = player, position = (root :: BasePart).Position })
		end
	end

	for _, find in ipairs(state.treasures) do
		if find.state == "buried" then
			local i = GridUtil.Index(grid.size, find.x, find.z)
			local h = GridUtil.ReadHeight(field, i)
			if h <= find.revealUnits + GridUtil.StudsToUnits(0.3) then
				local wx, wz = GridUtil.CellToWorld(grid, find.x, find.z)
				local part = (pickupTemplate :: BasePart):Clone()
				part.Color = find.def.color
				part.Position = Vector3.new(wx, grid.origin.y + GridUtil.UnitsToStuds(h) + 1.4, wz)
				part.Parent = pickupFolder
				find.part = part
				find.state = "spawned"
				find.spawnedAt = now
				table.insert(spawned, find)
			end
		elseif find.state == "spawned" then
			local part = find.part :: BasePart
			if now - find.spawnedAt > treasureCfg.spawn.pickupLifetime then
				find.state = "gone"
				part:Destroy()
				find.part = nil
			else
				for _, entry in ipairs(playerRoots) do
					if (entry.position - part.Position).Magnitude <= 5 then
						find.state = "collected" -- flag on the FIND (§13)
						local position = part.Position
						part:Destroy()
						find.part = nil
						table.insert(collected, { find = find, player = entry.player, position = position })
						break
					end
				end
			end
		end
	end

	return spawned, collected
end

return TreasureService
