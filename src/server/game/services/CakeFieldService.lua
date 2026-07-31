--[[
	CakeFieldService — authoritative heightfield simulation (GDD §4).

	Logic only (R2): all state lives in CakeStateData. Three jobs:
	  1. ApplyBite — remove a crater, return volume + surface layer
	  2. SettleStep — the angle-of-repose cellular automaton (§4.4), budgeted
	  3. CollectDelta / Snapshot — pack changes for CakeSubs to replicate

	The settle queue is FIFO with head pointers (O(1) pop, no table.remove).
	Volume moves between cells, never appears or disappears — the economy
	stays honest. Solid layers (repose = huge) don't flow.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local CakeOps = require(Shared:WaitForChild("CakeOps"))
local Log = require(Shared:WaitForChild("Log"))

local CakeFieldService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake

-- Layer lookup by height, precomputed per cake at 0.25-stud resolution —
-- the settle loop calls it for every processed cell, a band scan would burn
-- the budget. Index: floor(units / 25) + 1.
local layerLookup: { any } = {}
local LOOKUP_STEP_UNITS = 25

-- Per-band initial volumes (studs^3) for auto-sweep (§7.6).
local bandInitialVolume: { number } = {}

-- Explicit head/tail FIFO cursors. NEVER derive the tail from `#` — the
-- drained prefix is nil-punched, and `#` over an array with nil holes is
-- undefined in Luau (an early false "empty" would strand queued cells
-- whose dirty flags are already set, excluding them forever).
local queueHead, queueTail = 1, 0
local netHead, netTail = 1, 0

function CakeFieldService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
end

local function markSettleDirty(i: number)
	if not state.settleQueued[i] then
		state.settleQueued[i] = true
		queueTail += 1
		state.settleQueue[queueTail] = i
	end
end

local function markNetDirty(i: number)
	if not state.netDirty[i] then
		state.netDirty[i] = true
		netTail += 1
		state.netDirtyList[netTail] = i
	end
end

local function layerAtUnits(units: number)
	local idx = math.floor(units / LOOKUP_STEP_UNITS) + 1
	return layerLookup[idx] or layerLookup[#layerLookup]
end

--API
-- Rebuilds the field for a new cake. composition is bottom-up bands.
function CakeFieldService.ResetCake(composition, footprint, rareKind: string?, biome: string)
	local grid = cakeCfg.grid
	local size = grid.size
	local field = state.field :: buffer

	state.composition = composition
	state.footprint = footprint
	state.rareKind = rareKind
	state.biome = biome
	state.cakeIndex += 1
	state.floorUnits = GridUtil.StudsToUnits(composition[1].top) -- core band top
	-- Layer gate: eating starts on the TOP band (frosting); bites clamp to
	-- its bottom until it's consumed, then the active floor drops (ScanStats).
	state.activeBandIndex = #composition
	state.activeFloorUnits =
		math.max(state.floorUnits, GridUtil.StudsToUnits(composition[#composition].bottom))
	state.progress = 0

	-- Reset queues (head/tail FIFOs).
	table.clear(state.settleQueue)
	table.clear(state.settleQueued)
	table.clear(state.netDirty)
	table.clear(state.netDirtyList)
	queueHead, queueTail = 1, 0
	netHead, netTail = 1, 0
	table.clear(state.delayedSettle)
	state.repairCursor = 0

	-- Layer lookup table for the settle loop.
	table.clear(layerLookup)
	local topStuds = composition[#composition].top
	local steps = math.ceil(topStuds * GridUtil.UNITS_PER_STUD / LOOKUP_STEP_UNITS) + 1
	for s = 1, steps do
		local h = (s - 1) * LOOKUP_STEP_UNITS / GridUtil.UNITS_PER_STUD
		local layer = CakeOps.LayerAtStuds(composition, cakeCfg.layers, h)
		layerLookup[s] = layer
	end

	-- Fill heights: full cylinder at total height with gentle surface noise
	-- (stays under frosting repose so nothing avalanches at spawn).
	local topUnits = GridUtil.StudsToUnits(topStuds)
	local edibleUnits = 0
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			local i = GridUtil.Index(size, x, z)
			if GridUtil.InCake(size, footprint, x, z) then
				local noise = math.noise(x / 7, z / 7, state.cakeIndex) * 0.6
				local h = math.max(state.floorUnits, topUnits + GridUtil.StudsToUnits(math.abs(noise)) - GridUtil.StudsToUnits(0.3))
				GridUtil.WriteHeight(field, i, h)
				edibleUnits += h - state.floorUnits
			else
				GridUtil.WriteHeight(field, i, 0)
			end
		end
	end
	state.edibleVolume = GridUtil.UnitsToStuds(edibleUnits) * grid.cell * grid.cell

	-- Per-band initial volumes (flat-fill approximation is fine for the
	-- 10% auto-sweep threshold).
	table.clear(bandInitialVolume)
	local cakeArea = 0
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			if GridUtil.InCake(size, footprint, x, z) then
				cakeArea += grid.cell * grid.cell
			end
		end
	end
	for bandIdx, band in ipairs(composition) do
		bandInitialVolume[bandIdx] = (band.top - band.bottom) * cakeArea
	end

	Log.Sum(
		"CakeField",
		`cake #{state.cakeIndex} built — {footprint.hx * 2}x{footprint.hz * 2} cells, h={topStuds} studs, edible={math.floor(state.edibleVolume)} studs³, rare={rareKind or "no"}, biome={biome}`
	)
end

--API
-- The bite-radius multiplier of the band currently being eaten (the pacing
-- curve, CakeConfig.composition): a soft top band scoops wide, a dense deep one
-- only chips. Floored at sim.minBiteRadiusStuds so a bite can never miss every
-- cell centre. The CLIENT mirrors this in LocalCakeField.ScoopedRadius.
function CakeFieldService.ScoopedRadius(radiusStuds: number): number
	local band = state.composition[state.activeBandIndex]
	local scoop = (band and band.scoop) or 1
	return math.max(radiusStuds * scoop, cakeCfg.sim.minBiteRadiusStuds)
end

--API
-- Applies a bite. Returns removed volume (studs^3), the layer def at the
-- pre-bite surface of the bite point (calories + client SFX) and that band
-- (its `density` turns raw volume into FOOD — see CakeSubs).
function CakeFieldService.ApplyBite(px: number, pz: number, radiusStuds: number, depthStuds: number)
	local field = state.field :: buffer
	local grid = cakeCfg.grid
	local preH = GridUtil.SurfaceHeightAt(field, grid, state.footprint, px, pz) or 0
	local surfaceLayer, surfaceBand = CakeOps.LayerAtStuds(state.composition, cakeCfg.layers, preH)

	-- Layer gate: clamp the bite to the ACTIVE band's floor so a chomp can't
	-- cut into the layer beneath before the top one is finished. Disabled ->
	-- the absolute core floor (a single bite can slice through many layers).
	local clampFloor = if cakeCfg.layerGate.enabled then state.activeFloorUnits else state.floorUnits
	local removed, changed = CakeOps.ApplyBite(
		field, grid, state.footprint, state.composition, cakeCfg.layers,
		px, pz, CakeFieldService.ScoopedRadius(radiusStuds), depthStuds, clampFloor,
		cakeCfg.sim.biteClearRefDepth
	)

	-- The chunk rips out NOW (net-dirty immediately); the crater only
	-- starts flowing after settleDelayAfterBite — that pause is what makes
	-- it read as a BITE instead of melting.
	local size = grid.size
	local dueAt = os.clock() + cakeCfg.sim.settleDelayAfterBite
	for _, i in ipairs(changed) do
		markNetDirty(i)
		table.insert(state.delayedSettle, { i = i, dueAt = dueAt })
		local x, z = GridUtil.Coords(size, i)
		if x > 0 then table.insert(state.delayedSettle, { i = i - 1, dueAt = dueAt }) end
		if x < size - 1 then table.insert(state.delayedSettle, { i = i + 1, dueAt = dueAt }) end
		if z > 0 then table.insert(state.delayedSettle, { i = i - size, dueAt = dueAt }) end
		if z < size - 1 then table.insert(state.delayedSettle, { i = i + size, dueAt = dueAt }) end
	end

	return removed, surfaceLayer, surfaceBand
end

local neighborOffsets = {} -- filled per call: {dx, dz, di}

--API
-- One settle tick (§4.4): processes up to sim.settleBudget queued cells.
-- Returns the number of cells processed (0 = field at rest).
function CakeFieldService.SettleStep(): number
	local field = state.field :: buffer
	local size = cakeCfg.grid.size

	-- Release bite-delayed cells whose pause has elapsed into the queue.
	local delayed = state.delayedSettle
	if #delayed > 0 then
		local now = os.clock()
		local keep = {}
		for _, entry in ipairs(delayed) do
			if entry.dueAt <= now then
				markSettleDirty(entry.i)
			else
				table.insert(keep, entry)
			end
		end
		state.delayedSettle = keep
	end

	local footprint = state.footprint
	local moveFactor = cakeCfg.sim.moveFactor
	local queue = state.settleQueue
	local queued = state.settleQueued
	local budget = cakeCfg.sim.settleBudget
	local processed = 0
	-- Clean cut (Req): the settle must NOT ooze INTO the cleared zone (cells within
	-- sim.sliverSweepStuds of the active floor) — refilling cleared craters is what
	-- left thin puddles. The full side keeps its sharp cut edge (an over-repose
	-- cliff there just stops relaxing); the slope ABOVE the zone still forms the drip.
	local clearedCeil = state.activeFloorUnits + GridUtil.StudsToUnits(cakeCfg.sim.sliverSweepStuds)

	while processed < budget do
		if queueHead > queueTail then
			-- Drained: reset the FIFO storage so it doesn't grow forever.
			table.clear(queue)
			queueHead, queueTail = 1, 0
			break
		end
		local i = queue[queueHead]
		queue[queueHead] = nil
		queueHead += 1
		queued[i] = nil
		processed += 1

		local hi = GridUtil.ReadHeight(field, i)
		if hi > state.floorUnits then
			local layer = layerAtUnits(hi)
			if layer.repose ~= math.huge and layer.flowRate > 0 then
				local reposeUnits = layer.repose * GridUtil.UNITS_PER_STUD
				local x, z = GridUtil.Coords(size, i)
				local changedI = false
				for n = 1, 4 do
					local nx, nz
					if n == 1 then nx, nz = x - 1, z
					elseif n == 2 then nx, nz = x + 1, z
					elseif n == 3 then nx, nz = x, z - 1
					else nx, nz = x, z + 1 end
					if GridUtil.InBounds(size, nx, nz) and GridUtil.InCake(size, footprint, nx, nz) then
						local j = GridUtil.Index(size, nx, nz)
						local hj = GridUtil.ReadHeight(field, j)
						local d = hi - hj
						if d > reposeUnits and hj > clearedCeil then -- guard: don't refill the cleared zone
							local move = math.floor((d - reposeUnits) * moveFactor * layer.flowRate)
							if move > 0 then
								hi -= move
								GridUtil.WriteHeight(field, i, hi)
								GridUtil.WriteHeight(field, j, hj + move)
								changedI = true
								markNetDirty(j)
								markSettleDirty(j) -- the avalanche propagates
							end
						end
					end
				end
				if changedI then
					markNetDirty(i)
					-- moveFactor relaxes only PART of the excess — i itself
					-- must re-settle next tick or crater walls freeze
					-- over-repose after a single pass.
					markSettleDirty(i)
					-- i just dropped: its OTHER higher neighbors may now be
					-- over-repose relative to i — re-check them.
					if x > 0 then markSettleDirty(i - 1) end
					if x < size - 1 then markSettleDirty(i + 1) end
					if z > 0 then markSettleDirty(i - size) end
					if z < size - 1 then markSettleDirty(i + size) end
				end
			end
		end
	end

	return processed
end

--API
-- Packs pending changes into ONE delta buffer: [u16 cellIndex][u16 height]*n,
-- capped at net.maxCellsPerPacket dirty cells so the packet stays under the
-- UnreliableRemoteEvent ~900-byte drop threshold. `includeRepair` appends
-- net.repairCellsPerPacket rotating repair cells (self-healing) — the caller
-- sets it for the FIRST packet of a flush only. Returns nil when there is
-- nothing to send (callers loop up to net.maxPacketsPerFlush times).
function CakeFieldService.CollectDelta(includeRepair: boolean): buffer?
	local field = state.field :: buffer
	local net = cakeCfg.net
	local list = state.netDirtyList
	local dirtySet = state.netDirty
	local size = cakeCfg.grid.size
	local totalCells = size * size

	local dirtyCount = math.min(netTail - netHead + 1, net.maxCellsPerPacket)
	if dirtyCount < 0 then
		dirtyCount = 0
	end
	local repairCount = if includeRepair then net.repairCellsPerPacket else 0
	if dirtyCount == 0 and (repairCount == 0 or state.phase ~= "eating") then
		return nil -- nothing dirty; idle cake needs no repair traffic either
	end

	local out = buffer.create((dirtyCount + repairCount) * 4)
	local offset = 0
	for _ = 1, dirtyCount do
		local i = list[netHead]
		list[netHead] = nil
		netHead += 1
		dirtySet[i] = nil
		buffer.writeu16(out, offset, i)
		buffer.writeu16(out, offset + 2, GridUtil.ReadHeight(field, i))
		offset += 4
	end
	if netHead > netTail then
		table.clear(list)
		netHead, netTail = 1, 0
	end
	for _ = 1, repairCount do
		local i = state.repairCursor
		state.repairCursor = (state.repairCursor + 1) % totalCells
		buffer.writeu16(out, offset, i)
		buffer.writeu16(out, offset + 2, GridUtil.ReadHeight(field, i))
		offset += 4
	end
	return out
end

--API
-- Full field copy + metadata for a joining client / new cake.
function CakeFieldService.Snapshot(): (buffer, { [string]: any })
	local field = state.field :: buffer
	local copy = buffer.create(buffer.len(field))
	buffer.copy(copy, 0, field, 0)
	return copy, {
		cakeIndex = state.cakeIndex,
		footprint = state.footprint,
		composition = state.composition,
		rareKind = state.rareKind,
		biome = state.biome,
		phase = state.phase,
		progress = state.progress,
		activeBandIndex = state.activeBandIndex, -- layer gate (features/cake-sim.md)
	}
end

--API
-- 1 Hz full-field scan: progress %, auto-sweep of nearly-finished bands
-- (§7.6 — never make the player hunt the last crumb). Returns
-- { progress, topBandIndex, sweptBand: boolean }.
function CakeFieldService.ScanStats()
	local field = state.field :: buffer
	local grid = cakeCfg.grid
	local size = grid.size
	local footprint = state.footprint
	local floorUnits = state.floorUnits
	local remainingUnits = 0
	local maxH = 0

	for z = 0, size - 1 do
		for x = 0, size - 1 do
			if GridUtil.InCake(size, footprint, x, z) then
				local h = GridUtil.ReadHeight(field, GridUtil.Index(size, x, z))
				remainingUnits += math.max(0, h - floorUnits)
				if h > maxH then
					maxH = h
				end
			end
		end
	end

	local cellArea = grid.cell * grid.cell
	local remaining = GridUtil.UnitsToStuds(remainingUnits) * cellArea
	state.progress = if state.edibleVolume > 0 then math.clamp(1 - remaining / state.edibleVolume, 0, 1) else 1

	-- Which band is the current top? (highest band whose bottom is below maxH)
	local maxHStuds = GridUtil.UnitsToStuds(maxH)
	local topBandIndex = 1
	for idx = #state.composition, 1, -1 do
		if maxHStuds > state.composition[idx].bottom + 0.05 then
			topBandIndex = idx
			break
		end
	end

	-- Auto-sweep: volume left ABOVE the top band's floor < 10% of that
	-- band's initial volume -> collapse the tail to the band floor.
	local sweptBand = false
	if topBandIndex > 1 then -- never sweep the core band
		local band = state.composition[topBandIndex]
		local bandBottomUnits = GridUtil.StudsToUnits(band.bottom)
		local aboveUnits = 0
		for z = 0, size - 1 do
			for x = 0, size - 1 do
				if GridUtil.InCake(size, footprint, x, z) then
					local h = GridUtil.ReadHeight(field, GridUtil.Index(size, x, z))
					if h > bandBottomUnits then
						aboveUnits += h - bandBottomUnits
					end
				end
			end
		end
		local aboveVolume = GridUtil.UnitsToStuds(aboveUnits) * cellArea
		if aboveVolume > 0 and aboveVolume < bandInitialVolume[topBandIndex] * cakeCfg.sim.autoSweepFraction then
			for z = 0, size - 1 do
				for x = 0, size - 1 do
					if GridUtil.InCake(size, footprint, x, z) then
						local i = GridUtil.Index(size, x, z)
						local h = GridUtil.ReadHeight(field, i)
						if h > bandBottomUnits then
							GridUtil.WriteHeight(field, i, bandBottomUnits)
							markNetDirty(i)
						end
					end
				end
			end
			sweptBand = true
			Log.Info("CakeField", `auto-sweep: band '{band.id}' tail collapsed ({math.floor(aboveVolume)} studs³ forfeited)`)
		end
	end

	-- Layer gate: the active band is the current top band. When it was just
	-- auto-swept flat to its bottom it's finished, so advance to the band
	-- below in the SAME scan — otherwise the freshly-leveled floor would read
	-- as "locked" for a second and spuriously cue the player.
	local activeIndex = topBandIndex
	if sweptBand and activeIndex > 1 then
		activeIndex -= 1
	end
	if activeIndex ~= state.activeBandIndex then
		Log.Info("CakeField", `layer gate: active band -> #{activeIndex} '{state.composition[activeIndex].id}'`)
	end
	state.activeBandIndex = activeIndex
	state.activeFloorUnits =
		math.max(state.floorUnits, GridUtil.StudsToUnits(state.composition[activeIndex].bottom))

	-- Clean cut (Req): sweep EVERY tiny leftover on the active floor down to the
	-- floor. The SettleStep clearedCeil guard keeps the settle from refilling this
	-- zone, so there is no sweep-vs-settle flicker (the drip forms ABOVE the zone).
	-- Cheap (one 1 Hz scan). Deltas replicate the change to clients.
	local floorU = state.activeFloorUnits
	-- Cap each sweep distance at a fraction of the ACTIVE BAND's own thickness:
	-- an absolute stud rule swallows a thin band (see CakeConfig.sim
	-- .sweepBandFraction for the measurement). nil/0 = the old absolute rules.
	local activeBand = state.composition[activeIndex]
	local bandThickness = activeBand and (activeBand.top - activeBand.bottom) or math.huge
	local sweepFraction = cakeCfg.sim.sweepBandFraction
	local function sweepStuds(studs: number): number
		if sweepFraction == nil or sweepFraction <= 0 then
			return studs
		end
		return math.min(studs, bandThickness * sweepFraction)
	end
	local sliverCeil = floorU + GridUtil.StudsToUnits(sweepStuds(cakeCfg.sim.sliverSweepStuds))
	if sliverCeil > floorU then
		for z = 0, size - 1 do
			for x = 0, size - 1 do
				if GridUtil.InCake(size, footprint, x, z) then
					local i = GridUtil.Index(size, x, z)
					local h = GridUtil.ReadHeight(field, i)
					if h > floorU and h <= sliverCeil then
						GridUtil.WriteHeight(field, i, floorU)
						markNetDirty(i)
					end
				end
			end
		end
	end

	-- Eaten-zone cleanup sweep (user req: the eaten section should be COMPLETELY
	-- eaten — no small pieces). Snaps active-band cells that TOUCH a crater (a
	-- neighbour near the active floor) down to the floor when the cell is either
	-- (a) NEARLY CLEARED itself (within remnant.nearFloorStuds of the active
	-- floor) — the soft RIM of a bite, so the bitten footprint becomes a clean
	-- cliff instead of a ragged gradient — or (b) an ISOLATED full pillar/spike
	-- (>= minClearedNeighbors crater neighbours) / a 1-cell wall (2 OPPOSITE). A
	-- FULL cell with a crater on only ONE side is LEFT, so the clean cut edge
	-- (one side full, other floor) survives; the loaf PERIMETER survives
	-- (out-of-cake neighbours are SUPPORT, never a crater). Two-phase (collect,
	-- then apply) so a swept cell never changes a later cell's neighbour test
	-- mid-scan. The SettleStep clearedCeil guard keeps the settle from refilling
	-- the collapsed cells (no flicker). Forfeits the volume.
	-- ⚠ Rule (a) is measured from the FLOOR, not from the band TOP. Measuring it
	-- from the top (the pre-2026-07-26 `eatenEpsilonStuds`) collapsed a chunky
	-- band's cell the moment it was nicked, which forfeited ~25% of every cake
	-- and made layer clear-time independent of the bite stats — no pacing lever.
	local remnant = cakeCfg.sim.remnantSweep
	if remnant and remnant.enabled then
		local clearedCeilU = floorU + GridUtil.StudsToUnits(sweepStuds(remnant.clearedMarginStuds))
		local nearFloorU = floorU + GridUtil.StudsToUnits(sweepStuds(remnant.nearFloorStuds))
		local minCleared = remnant.minClearedNeighbors
		local collapse = {}
		for z = 0, size - 1 do
			for x = 0, size - 1 do
				if GridUtil.InCake(size, footprint, x, z) then
					local i = GridUtil.Index(size, x, z)
					local h = GridUtil.ReadHeight(field, i)
					if h > floorU then
						-- In-cake neighbour whose surface is a CRATER (near the active floor).
						local left = x > 0 and GridUtil.InCake(size, footprint, x - 1, z)
							and GridUtil.ReadHeight(field, i - 1) <= clearedCeilU
						local right = x < size - 1 and GridUtil.InCake(size, footprint, x + 1, z)
							and GridUtil.ReadHeight(field, i + 1) <= clearedCeilU
						local back = z > 0 and GridUtil.InCake(size, footprint, x, z - 1)
							and GridUtil.ReadHeight(field, i - size) <= clearedCeilU
						local front = z < size - 1 and GridUtil.InCake(size, footprint, x, z + 1)
							and GridUtil.ReadHeight(field, i + size) <= clearedCeilU
						local cleared = (left and 1 or 0) + (right and 1 or 0) + (back and 1 or 0) + (front and 1 or 0)
						if cleared > 0 then
							local thinWall = (left and right) or (back and front) -- 2 OPPOSITE
							if h <= nearFloorU or cleared >= minCleared or thinWall then
								table.insert(collapse, i)
							end
						end
					end
				end
			end
		end
		for _, i in ipairs(collapse) do
			if GridUtil.ReadHeight(field, i) > floorU then
				GridUtil.WriteHeight(field, i, floorU)
				markNetDirty(i)
			end
		end
	end

	return { progress = state.progress, topBandIndex = topBandIndex, sweptBand = sweptBand }
end

--API
-- Bottom reached = everything edible is gone (within half a stud per cell).
function CakeFieldService.IsBottomReached(): boolean
	return state.progress >= 0.995
end

--API
function CakeFieldService.SurfaceHeightAt(wx: number, wz: number): number?
	return GridUtil.SurfaceHeightAt(state.field :: buffer, cakeCfg.grid, state.footprint, wx, wz)
end

--API
-- Layer def at the surface under a world position (caramel slow, SFX).
function CakeFieldService.SurfaceLayerAt(wx: number, wz: number)
	local h = CakeFieldService.SurfaceHeightAt(wx, wz)
	if h == nil or #state.composition == 0 then
		return nil
	end
	return CakeOps.LayerAtStuds(state.composition, cakeCfg.layers, h)
end

return CakeFieldService
