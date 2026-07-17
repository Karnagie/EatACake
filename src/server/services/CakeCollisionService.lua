--[[
	CakeCollisionService — coarse walkable collision for the cake (GDD §4.6).

	An 8x8 grid of invisible anchored Parts (64 total); each one's height is
	the average of its block of heightfield cells, refreshed at net.collisionHz
	by CakeSubs. The surface is nearly flat by construction (angle of repose),
	so this is enough to stand, walk and sink into scree. Never built from
	EditableMesh — runtime collision regen is what kills mobile.

	Parts are utility (invisible), not view objects — R5 does not apply.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local Log = require(Shared:WaitForChild("Log"))

local CakeCollisionService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake

function CakeCollisionService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
end

--API
-- Creates the 8x8 collision parts once (idempotent). Called from
-- CakeSubs.Start after the map exists.
function CakeCollisionService.BuildParts()
	if #state.collisionParts > 0 then
		return
	end
	local grid = cakeCfg.grid
	local n = cakeCfg.net.collisionGrid
	local blockStuds = grid.size * grid.cell / n

	local folder = Instance.new("Folder")
	folder.Name = "CakeCollision"
	folder.Parent = workspace

	for bz = 0, n - 1 do
		for bx = 0, n - 1 do
			local part = Instance.new("Part")
			part.Name = `Col_{bx}_{bz}`
			part.Anchored = true
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = false
			part.Transparency = 1
			part.CastShadow = false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.Size = Vector3.new(blockStuds, 1, blockStuds)
			part.CFrame = CFrame.new(
				grid.origin.x + (bx - n / 2 + 0.5) * blockStuds,
				grid.origin.y - 0.5,
				grid.origin.z + (bz - n / 2 + 0.5) * blockStuds
			)
			part.Parent = folder
			table.insert(state.collisionParts, part)
		end
	end
	Log.Info("CakeCollision", `built {#state.collisionParts} collision parts ({n}x{n})`)
end

--API
-- Refreshes part heights from the field (called at net.collisionHz).
function CakeCollisionService.UpdateHeights()
	local field = state.field :: buffer
	if field == nil or #state.collisionParts == 0 then
		return
	end
	local grid = cakeCfg.grid
	local size = grid.size
	local n = cakeCfg.net.collisionGrid
	local cellsPerBlock = size / n
	local blockStuds = size * grid.cell / n

	local idx = 0
	for bz = 0, n - 1 do
		for bx = 0, n - 1 do
			idx += 1
			local sum, count = 0, 0
			for z = bz * cellsPerBlock, (bz + 1) * cellsPerBlock - 1 do
				for x = bx * cellsPerBlock, (bx + 1) * cellsPerBlock - 1 do
					if GridUtil.InCake(size, state.footprint, x, z) then
						sum += GridUtil.ReadHeight(field, GridUtil.Index(size, x, z))
						count += 1
					end
				end
			end
			local part = state.collisionParts[idx]
			if count == 0 then
				-- Block fully outside the cake footprint: park it flush
				-- with the platform so nothing floats.
				part.Size = Vector3.new(blockStuds, 1, blockStuds)
				part.CFrame = CFrame.new(part.Position.X, grid.origin.y - 0.5, part.Position.Z)
			else
				local hStuds = GridUtil.UnitsToStuds(sum / count)
				local height = math.max(1, hStuds)
				part.Size = Vector3.new(blockStuds, height, blockStuds)
				part.CFrame = CFrame.new(part.Position.X, grid.origin.y + hStuds - height / 2, part.Position.Z)
			end
		end
	end
end

return CakeCollisionService
