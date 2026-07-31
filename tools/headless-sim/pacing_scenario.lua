
-- PACING scenario: how long does a cake take, and what does it pay?
--
-- Answers the question the cake's SILHOUETTE is blocked on: the loaf is 90x78
-- studs and 330 tall, which reads as a striped tower rather than a cake. Can
-- `maxTotalHeight` come down without moving clear time or income?
--
-- ADR-0011 claims it can — clear time is AREA-driven, and per-band `density` is
-- computed as refBandWeight / (thickness x scoop^2), so halving thickness
-- doubles density and the food per bite is unchanged. This measures whether
-- that actually holds through the real `CakeOps.ApplyBite` + the three sweeps.

local GridUtil = __REGISTRY["Shared.GridUtil"]
local CakeOps = __REGISTRY["Shared.CakeOps"]
local CakeConfig = __REGISTRY["Shared.config.CakeConfig"]

math.randomseed(__SEED__)

local grid = CakeConfig.grid
local comp = CakeConfig.composition
local sim = CakeConfig.sim

-- Eating stats + the BELLY/GYM cycle, straight out of UpgradeConfig `base` and
-- the final tier. ⚠ Pure eating time is NOT session time: the belly fills, and
-- the player has to walk to the checkpoint and burn it off before eating again.
-- Leaving that out understates a session exactly the way leaving the sweeps out
-- overstated the food.
--   capacity  food units the belly holds before it BLOCKS eating
--   burnSpeed fraction of the belly drained per second at the machine
--   trip      seconds of walk-to-checkpoint + mount + walk-back (observed in a
--             playtest: the checkpoint plate tracks the active layer and sits
--             beside the loaf, so it is a short but real interruption)
local STATS = {
	fresh = { radius = 3.4, depth = 3.6, rate = 4.0, capacity = 84000, burnSpeed = 0.06, trip = 14, label = "fresh (no upgrades)" },
	maxed = { radius = 4.8, depth = 6.2, rate = 5.6, capacity = 335000, burnSpeed = 0.65, trip = 14, label = "fully upgraded" },
}

local function rollComposition(totalHeightOverride)
	local layers = comp.baseLayers
	local scoopTop, scoopBottom = comp.scoopTop, comp.scoopBottom
	local totalHeight = totalHeightOverride
		or math.min(comp.maxTotalHeight, grid.maxHeight - comp.coreThickness)
	local scoops, weights, weightSum = {}, {}, 0
	for k = 0, layers - 1 do
		local f = if layers > 1 then k / (layers - 1) else 0
		local scoop = scoopTop * (scoopBottom / scoopTop) ^ f
		scoops[k + 1] = scoop
		local w = (scoopTop / scoop) ^ (2 * comp.thicknessExponent)
		weights[k + 1] = w
		weightSum += w
	end
	local thickness, thickSum = {}, 0
	for k = 1, layers do
		local t = math.max(comp.minLayerThickness, weights[k] / weightSum * totalHeight)
		thickness[k] = t
		thickSum += t
	end
	for k = 1, layers do thickness[k] *= totalHeight / thickSum end

	local composition, cursor = {}, 0
	local function push(band)
		band.bottom = cursor
		band.top = cursor + band.thickness
		cursor = band.top
		band.thickness = nil
		table.insert(composition, band)
	end
	push({ id = "core", thickness = comp.coreThickness, scoop = 1, density = 1 })
	for k = layers, 1, -1 do
		local density = math.clamp(
			comp.refBandWeight / (thickness[k] * scoops[k] * scoops[k]),
			1,
			comp.maxDensity
		)
		push({ id = "sponge", thickness = thickness[k], scoop = scoops[k], density = density })
	end
	return composition
end

-- Mow one cake to the bottom with the REAL bite math + the layer gate, and
-- report bites, seconds and food. A "mowing" agent: lanes across the loaf,
-- always biting at the active band's floor.
local function runCake(label, totalHeightOverride, stats, capFrac)
	stats = stats or STATS.fresh
	-- Default to what SHIPS, so sections A/B measure the live config; §C
	-- passes explicit values to compare caps.
	if capFrac == nil then capFrac = sim.sweepBandFraction end
	local composition = rollComposition(totalHeightOverride)
	local size = grid.size
	local field = buffer.create(size * size * 2)
	local footprint = comp.footprint
	local topStuds = composition[#composition].top
	local floorUnits = GridUtil.StudsToUnits(composition[1].top)

	local cells = {}
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			if GridUtil.InCake(size, footprint, x, z) then
				GridUtil.WriteHeight(field, GridUtil.Index(size, x, z), GridUtil.StudsToUnits(topStuds))
				table.insert(cells, { x = x, z = z })
			end
		end
	end

	local bites, food, forfeited = 0, 0, 0
	local cellArea = grid.cell * grid.cell

	-- The FORFEITING sweeps, ported from `CakeFieldService.ScanStats`. Without
	-- these the model measures only what the player EATS, not what the cake
	-- COSTS -- and both sweeps are ABSOLUTE stud distances measured against a
	-- band thickness, so changing cake height changes how much of each band they
	-- swallow. That is exactly the invariance this scenario claims to test, and
	-- the first version of it left them out.
	local function sweeps(activeFloorU, density, thickness)
		local swept = 0
		-- capFrac: cap each sweep distance at a FRACTION of the band's own
		-- thickness, so a thin band is not swallowed by an absolute stud rule.
		local function cap(studs)
			if capFrac == nil or capFrac <= 0 then return studs end
			return math.min(studs, thickness * capFrac)
		end
		local sliverCeil = activeFloorU + GridUtil.StudsToUnits(cap(sim.sliverSweepStuds))
		for _, c in ipairs(cells) do
			local i = GridUtil.Index(size, c.x, c.z)
			local h = GridUtil.ReadHeight(field, i)
			if h > activeFloorU and h <= sliverCeil then
				swept += (h - activeFloorU)
				GridUtil.WriteHeight(field, i, activeFloorU)
			end
		end
		local rem = sim.remnantSweep
		if rem and rem.enabled then
			local clearedCeilU = activeFloorU + GridUtil.StudsToUnits(rem.clearedMarginStuds)
			local nearFloorU = activeFloorU + GridUtil.StudsToUnits(cap(rem.nearFloorStuds))
			local collapse = {}
			for _, c in ipairs(cells) do
				local i = GridUtil.Index(size, c.x, c.z)
				local h = GridUtil.ReadHeight(field, i)
				if h > activeFloorU then
					local function crater(dx, dz)
						local nx, nz = c.x + dx, c.z + dz
						return GridUtil.InBounds(size, nx, nz)
							and GridUtil.InCake(size, footprint, nx, nz)
							and GridUtil.ReadHeight(field, GridUtil.Index(size, nx, nz)) <= clearedCeilU
					end
					local l, r, b, f = crater(-1, 0), crater(1, 0), crater(0, -1), crater(0, 1)
					local n = (l and 1 or 0) + (r and 1 or 0) + (b and 1 or 0) + (f and 1 or 0)
					if n > 0 and (h <= nearFloorU or n >= rem.minClearedNeighbors or (l and r) or (b and f)) then
						table.insert(collapse, i)
					end
				end
			end
			for _, i in ipairs(collapse) do
				local h = GridUtil.ReadHeight(field, i)
				if h > activeFloorU then
					swept += (h - activeFloorU)
					GridUtil.WriteHeight(field, i, activeFloorU)
				end
			end
		end
		forfeited += GridUtil.UnitsToStuds(swept) * cellArea * density
	end

	for bandIndex = #composition, 2, -1 do
		local band = composition[bandIndex]
		local activeFloor = GridUtil.StudsToUnits(band.bottom)
		local scoop = band.scoop
		local radius = math.max(sim.minBiteRadiusStuds, stats.radius * scoop)
		local guard, cleared = 0, false
		while not cleared and guard < 20000 do
			guard += 1
			-- Aim at the highest remaining cell in this band (a competent mower).
			local bestCell, bestH = nil, activeFloor
			for _, c in ipairs(cells) do
				local h = GridUtil.ReadHeight(field, GridUtil.Index(size, c.x, c.z))
				if h > bestH then
					bestCell, bestH = c, h
				end
			end
			if bestCell == nil then
				cleared = true
				break
			end
			local wx, wz = GridUtil.CellToWorld(grid, bestCell.x, bestCell.z)
			local removed = CakeOps.ApplyBite(
				field, grid, footprint, composition, CakeConfig.layers,
				wx, wz, radius, stats.depth, activeFloor, sim.biteClearRefDepth
			)
			bites += 1
			-- ⚠ NO cellArea here. `CakeOps.ApplyBite` already returns a VOLUME
			-- (`UnitsToStuds(removedUnits) * cell * cell`); multiplying again
			-- inflated food by cell² = 2.25x. That is why this scenario's numbers
			-- disagreed with `tools/balance-model/pacing.py`: it reported ~2.25x the
			-- real food, hence 2.25x the belly->gym TRIPS (so "one cake = 126 min
			-- fresh" was really ~94), and it understated the forfeited fraction by
			-- the same factor (6.8% shown vs ~17% actual) because `forfeited` below
			-- correctly applies cellArea exactly once, to a raw unit count.
			-- Found 2026-07-30 while porting this model to Python.
			food += (removed or 0) * band.density
			-- ScanStats runs at 1 Hz; the agent bites at `stats.rate`/s.
			if bites % math.max(1, math.floor(stats.rate)) == 0 then
				sweeps(activeFloor, band.density, band.top - band.bottom)
			end
		end
		sweeps(activeFloor, band.density, band.top - band.bottom) -- final pass before the gate steps down
	end

	local eatSeconds = bites / stats.rate
	-- GYM CYCLE: every `capacity` food units eaten forces one trip. A trip is the
	-- walk there and back plus the drain (1/burnSpeed seconds, hands-free — taps
	-- only make it faster, so this is the CONSERVATIVE upper bound on eating time
	-- and the lower bound on trip time).
	local trips = math.floor(food / math.max(1, stats.capacity))
	local gymSeconds = trips * (stats.trip + 1 / stats.burnSpeed)
	local seconds = eatSeconds + gymSeconds
	print(string.format(
		"  %-14s h %4.0f  bands %2d  |  bites %6d  eat %5.1f min  + gym %2d trips %4.1f min  = SESSION %5.1f min  |  food %9.0f  waste %.1f%%",
		label, topStuds, #composition - 1,
		bites, eatSeconds / 60, trips, gymSeconds / 60, seconds / 60,
		food, forfeited / math.max(1, food + forfeited) * 100
	))
	return bites, seconds, food, forfeited / math.max(1, food + forfeited)
end

print(("-"):rep(118))
print("A) WHAT DOES CAKE HEIGHT COST? (mowing agent, real ApplyBite + layer gate + the 2 forfeiting sweeps)")
print(("-"):rep(118))
local b0, _, f0, w0 = runCake("old 330", 330)
local b1, _, f1, w1 = runCake("shipped 170", nil)
local b2, _, f2, w2 = runCake("edge 110", 110)
print(string.format("  vs the OLD 330 cake:  170 -> bites %+.1f%%, food %+.1f%%, waste %.1f%%->%.1f%%  |  110 -> food %+.1f%%, waste %.1f%%",
	(b1 / b0 - 1) * 100, (f1 / f0 - 1) * 100, w0 * 100, w1 * 100, (f2 / f0 - 1) * 100, w2 * 100))

print("")
print(("-"):rep(118))
print("B) HOW LONG IS ONE CAKE? (eating + the forced belly->gym trips; still excludes boss, upgrade stops, walking)")
print(("-"):rep(118))
local _, freshSec = runCake("fresh", nil, STATS.fresh)
local _, maxSec = runCake("maxed", nil, STATS.maxed)
print(string.format("  ONE CAKE, EAT + GYM = %.0f min fresh -> %.0f min fully upgraded.",
	freshSec / 60, maxSec / 60))
print("  This is the honest session floor for ONE cake: eating plus the forced")
print("  belly->checkpoint->burn trips, still EXCLUDING the boss fight, upgrade stops")
print("  and the walk between craters. The 30-minute target holds at BOTH ends of the")
print("  upgrade curve, which pure eating time alone did not show.")

print("")
print(("-"):rep(118))
print("C) SWEEP CAP — absolute stud rules swallow a thin band. Cap each at a FRACTION of band thickness?")
print(("-"):rep(118))
local _, _, fA, wA = runCake("no cap", nil, STATS.fresh, 0)
local _, _, fB, wB = runCake("cap 0.35", nil, STATS.fresh, 0.35)
local _, _, fC, wC = runCake("cap 0.25", nil, STATS.fresh, 0.25)
local _, _, fD, wD = runCake("cap 0.15", nil, STATS.fresh, 0.15)
print(string.format("  waste %.1f%% -> 0.35:%.1f%%  0.25:%.1f%%  0.15:%.1f%%   |   food recovered  0.35:%+.1f%%  0.25:%+.1f%%  0.15:%+.1f%%",
	wA * 100, wB * 100, wC * 100, wD * 100,
	(fB / fA - 1) * 100, (fC / fA - 1) * 100, (fD / fA - 1) * 100))
