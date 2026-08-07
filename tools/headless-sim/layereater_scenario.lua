-- LAYER EATER scenario: does the PAID one-shot layer clear actually do what the
-- product promises, and can it be made to take money for nothing?
--
-- This exists because the feature cannot be exercised end-to-end in Studio until
-- the 9 R$ dev product is created on the Creator Dashboard — a receipt is the
-- only way to reach the grant handler. So the two things that decide whether the
-- purchase is honest are measured HERE, against the real `CakeFieldService`:
--
--   1. one purchase removes exactly ONE band, and reports the volume it removed
--      (that volume is what the buyer is paid for, so an over- or under-report is
--      a pricing bug);
--   2. TWO purchases inside the SAME 1 Hz window remove TWO different bands.
--      That is the race the adversarial review found: `activeBandIndex` refreshes
--      at 1 Hz, so a second buyer used to target the band the first one had just
--      flattened, get `removed = 0`, and receive nothing for 9 R$.
--
-- Plus the guard that keeps the offer honest in the other direction:
--   3. `TopBandFill` reports what is LEFT of the top band, which is what the
--      readiness predicate refuses below (`layerEaterMinRemainingFraction`).

local GridUtil = __REGISTRY["Shared.GridUtil"]
local CakeConfig = __REGISTRY["Shared.config.CakeConfig"]
local CakeStateData = __REGISTRY["__CakeStateData"]
local CakeConfigData = __REGISTRY["__CakeConfigData"]
local CakeFieldService = __REGISTRY["__CakeFieldService"]

math.randomseed(__SEED__)

local comp = CakeConfig.composition
local grid = CakeConfig.grid

local failures, checks = 0, 0
local function check(label: string, ok: boolean, detail: string?)
	checks += 1
	if not ok then
		failures += 1
		print(`  FAIL  {label}{detail and (" — " .. detail) or ""}`)
	else
		print(`  ok    {label}{detail and (" — " .. detail) or ""}`)
	end
end

-- Same composition roll the pacing scenario uses (the real one lives in
-- CakeCycleService, which drags in half the server; this is the arithmetic).
local function rollComposition()
	local layers = comp.baseLayers
	local scoopTop, scoopBottom = comp.scoopTop, comp.scoopBottom
	local totalHeight = math.min(comp.maxTotalHeight, grid.maxHeight - comp.coreThickness)
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
	for k = 1, layers do
		thickness[k] *= totalHeight / thickSum
	end
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
		local density = math.clamp(comp.refBandWeight / (thickness[k] * scoops[k] * scoops[k]), 1, comp.maxDensity)
		push({ id = "sponge", thickness = thickness[k], scoop = scoops[k], density = density })
	end
	return composition
end

CakeStateData.Init()
CakeFieldService.Init({ CakeStateData = CakeStateData, CakeConfigData = CakeConfigData })

local composition = rollComposition()
local footprint = comp.footprint
CakeFieldService.ResetCake(composition, footprint, nil, "factory")

local topIndex = #composition
print(`\ncake: {topIndex} bands, top band '{composition[topIndex].id}' spans {string.format("%.2f", composition[topIndex].bottom)}..{string.format("%.2f", composition[topIndex].top)} studs`)

local cellArea = grid.cell * grid.cell
local cakeCells = 0
for z = 0, grid.size - 1 do
	for x = 0, grid.size - 1 do
		if GridUtil.InCake(grid.size, footprint, x, z) then
			cakeCells += 1
		end
	end
end

-- Volume standing above `bottomStuds`, measured off the LIVE field. The
-- assertions below compare against this rather than against a band's nominal
-- thickness, because they are not the same number: `ResetCake` seeds the surface
-- with noise and 0.3 studs BELOW the nominal top, so a brand-new cake's topmost
-- band is already ~5% short of its nominal volume (measured: fill 0.949). That
-- is correct behaviour, not a defect — but it means `TopBandFill` never reads
-- 1.0, which anyone tuning `layerEaterMinRemainingFraction` needs to know.
local function volumeAbove(bottomStuds: number): number
	local field = CakeStateData.field
	local bottomUnits = GridUtil.StudsToUnits(bottomStuds)
	local units = 0
	for z = 0, grid.size - 1 do
		for x = 0, grid.size - 1 do
			if GridUtil.InCake(grid.size, footprint, x, z) then
				local h = GridUtil.ReadHeight(field, GridUtil.Index(grid.size, x, z))
				if h > bottomUnits then
					units += h - bottomUnits
				end
			end
		end
	end
	return GridUtil.UnitsToStuds(units) * cellArea
end

-- ── 1. a fresh cake reports a near-full top band ────────────────────────
print("\n[1] fresh cake")
local fill, index = CakeFieldService.TopBandFill()
check("TopBandFill index == the top band", index == topIndex, `got {index}, want {topIndex}`)
check("TopBandFill is near-full on an untouched band (never exactly 1.0 — see above)",
	fill > 0.9 and fill <= 1.0, `got {string.format("%.3f", fill)}`)

-- ── 2. ONE purchase removes exactly ONE band ────────────────────────────
print("\n[2] one purchase")
local standing = volumeAbove(composition[topIndex].bottom)
local removed, band, layer = CakeFieldService.ClearActiveBand()
check("removed > 0", removed > 0, `{math.floor(removed)} studs³`)
check("band returned", band ~= nil and band.id == composition[topIndex].id)
check("layer def returned (it prices the calories)", layer ~= nil and layer.calories ~= nil)
-- EXACT: the buyer is paid for this number, so it must equal what was standing.
local err = math.abs(removed - standing) / standing
check("removed == the volume that was actually standing (the buyer's price)", err < 0.001,
	`removed {math.floor(removed)} vs standing {math.floor(standing)} ({string.format("%.4f", err * 100)}% off)`)

-- The surface must now sit exactly at the band's bottom, everywhere.
local field = CakeStateData.field
local bottomUnits = GridUtil.StudsToUnits(composition[topIndex].bottom)
local above = 0
for z = 0, grid.size - 1 do
	for x = 0, grid.size - 1 do
		if GridUtil.InCake(grid.size, footprint, x, z) then
			if GridUtil.ReadHeight(field, GridUtil.Index(grid.size, x, z)) > bottomUnits then
				above += 1
			end
		end
	end
end
check("no cell left standing above the cleared band", above == 0, `{above} cells still up`)

-- ── 3. THE RACE: a second purchase in the SAME 1 Hz window ──────────────
-- No ScanStats between them, so `activeBandIndex` is deliberately STALE — this
-- is exactly the state two receipts arriving together produce.
print("\n[3] second purchase before the 1 Hz scan (the race)")
local staleIndex = CakeStateData.activeBandIndex
check("activeBandIndex is still stale (proves the race is reproduced)", staleIndex == topIndex,
	`activeBandIndex {staleIndex}, real top is now {topIndex - 1}`)
local standing2 = volumeAbove(composition[topIndex - 1].bottom)
local removed2, band2 = CakeFieldService.ClearActiveBand()
check("second purchase removes a REAL band, not nothing", removed2 > 0, `{math.floor(removed2)} studs³`)
check("...and it is the NEXT band down", band2 ~= nil and band2.bottom == composition[topIndex - 1].bottom)
check("second removal == what was standing on THAT band",
	math.abs(removed2 - standing2) / standing2 < 0.001,
	`removed {math.floor(removed2)} vs standing {math.floor(standing2)}`)

-- ── 4. the 1 Hz scan agrees with what we cleared ────────────────────────
print("\n[4] ScanStats catches up")
local stats = CakeFieldService.ScanStats()
check("ScanStats topBandIndex == the band below the two cleared",
	stats.topBandIndex == topIndex - 2, `got {stats.topBandIndex}, want {topIndex - 2}`)
check("layer gate advanced to it", CakeStateData.activeBandIndex == topIndex - 2,
	`activeBandIndex {CakeStateData.activeBandIndex}`)

-- ── 5. a HALF-EATEN band pays for what is LEFT, and TopBandFill sees it ──
print("\n[5] partially eaten band")
local activeIdx = CakeStateData.activeBandIndex
local activeBand = composition[activeIdx]
local floorU = CakeStateData.activeFloorUnits
-- Carve the band down over roughly half the disc by writing the field directly
-- (a bite loop would take thousands of iterations for the same state).
local carved = 0
for z = 0, grid.size - 1 do
	for x = 0, grid.size - 1 do
		if GridUtil.InCake(grid.size, footprint, x, z) and x < grid.size / 2 then
			local i = GridUtil.Index(grid.size, x, z)
			if GridUtil.ReadHeight(field, i) > floorU then
				GridUtil.WriteHeight(field, i, floorU)
				carved += 1
			end
		end
	end
end
local fillAfter, idxAfter = CakeFieldService.TopBandFill()
check("TopBandFill still names the same band", idxAfter == activeIdx, `got {idxAfter}, want {activeIdx}`)
check("TopBandFill dropped to roughly half", fillAfter > 0.35 and fillAfter < 0.65,
	`{string.format("%.1f", fillAfter * 100)}% left after carving {carved} cells`)
local removed3 = CakeFieldService.ClearActiveBand()
local expected3 = (activeBand.top - activeBand.bottom) * cakeCells * cellArea
check("a half-eaten band pays for the REMAINDER, not the whole layer",
	removed3 < expected3 * 0.7 and removed3 > 0,
	`removed {math.floor(removed3)} of a full {math.floor(expected3)}`)

-- ── 6. the core band is never sellable ──────────────────────────────────
print("\n[6] cake eaten to the core")
for z = 0, grid.size - 1 do
	for x = 0, grid.size - 1 do
		if GridUtil.InCake(grid.size, footprint, x, z) then
			GridUtil.WriteHeight(field, GridUtil.Index(grid.size, x, z), GridUtil.StudsToUnits(composition[1].top))
		end
	end
end
local coreFill, coreIdx = CakeFieldService.TopBandFill()
check("TopBandFill reports the core band", coreIdx <= 1, `got index {coreIdx}`)
check("TopBandFill is 0 there, so readiness refuses", coreFill == 0, `got {coreFill}`)
local removedCore = CakeFieldService.ClearActiveBand()
check("ClearActiveBand refuses the core band", removedCore == 0, `got {removedCore}`)

print(`\n=== {checks - failures}/{checks} checks passed ===`)
if failures > 0 then
	error(`{failures} check(s) FAILED`)
end
