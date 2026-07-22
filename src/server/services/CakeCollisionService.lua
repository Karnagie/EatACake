--[[
	CakeCollisionService — coarse SAFETY-NET collision for the cake (GDD §4.6).

	A grid of invisible anchored Parts (net.collisionGrid², refreshed at
	net.collisionHz by CakeSubs). PRECISE walking collision is the client
	renderer's fine 32×32 columns (CakeRenderer); these coarse slabs only exist
	so a player is never left with NO floor (join before the client columns
	build, a client whose renderer failed, etc.). Never built from EditableMesh
	— runtime collision regen is what kills mobile.

	Each slab sits at the MINIMUM height of its in-cake block (Task 4), NOT the
	average: min-of-4×4 ≤ every fine 2×2 client column in that block, so the
	slab can NEVER poke above the fine columns and block a player from descending
	into a fresh crater (the old average left them floating waist-deep above bites
	/ juddering as the two grids disagreed). The player always rests on the fine
	columns; these just catch a fall when those columns aren't there yet.

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
-- Creates the collision safety-net parts once (net.collisionGrid², idempotent). Called from
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
	local col = cakeCfg.render.collision -- shared rise-rate cap (Task 4)

	local idx = 0
	for bz = 0, n - 1 do
		for bx = 0, n - 1 do
			idx += 1
			local minUnits, count = math.huge, 0
			for z = bz * cellsPerBlock, (bz + 1) * cellsPerBlock - 1 do
				for x = bx * cellsPerBlock, (bx + 1) * cellsPerBlock - 1 do
					if GridUtil.InCake(size, state.footprint, x, z) then
						local h = GridUtil.ReadHeight(field, GridUtil.Index(size, x, z))
						if h < minUnits then
							minUnits = h
						end
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
				-- MIN of the block (see header): stays at/under every fine client
				-- column so it never blocks a descent into a crater.
				local targetHStuds = GridUtil.UnitsToStuds(minUnits)
				-- Rate-limit the RISE to match the client columns (Task 4): a
				-- wide/fast refill mustn't punt a player who happens to rest on this
				-- coarse slab (the client fine columns are held low by the same cap,
				-- so an un-capped slab would poke above and shove). Drops snap (fall
				-- into craters / join fall-catch); a huge jump (new cake) snaps.
				local curHStuds = part.Position.Y + part.Size.Y / 2 - grid.origin.y
				local hStuds
				local rise = targetHStuds - curHStuds
				if rise <= 0 or rise > col.slabSnapStuds then
					hStuds = targetHStuds
				else
					hStuds = math.min(targetHStuds, curHStuds + col.riseRate / cakeCfg.net.collisionHz)
				end
				local height = math.max(1, hStuds)
				part.Size = Vector3.new(blockStuds, height, blockStuds)
				part.CFrame = CFrame.new(part.Position.X, grid.origin.y + hStuds - height / 2, part.Position.Z)
			end
		end
	end
end

return CakeCollisionService
