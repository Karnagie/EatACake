--[[
	CakeOps — pure bite math over a heightfield (GDD §4.3).

	Shared so the CLIENT can locally predict its own bite with EXACTLY the
	same math the server applies authoritatively (§4.7) — divergence is then
	limited to float noise and is overwritten by the next delta anyway.

	composition = array of bands, bottom-up:
	  { { id = "sponge", bottom = 3, top = 15 }, ... }  (studs)
	layersCfg = CakeConfig.layers.
]]

local GridUtil = require(script.Parent.GridUtil)

local CakeOps = {}

--API
-- Layer band at a given surface height (studs). Heights at/below the first
-- band belong to it; above the last band -> the last band (frosting).
function CakeOps.LayerAtStuds(composition, layersCfg, hStuds: number)
	for _, band in ipairs(composition) do
		if hStuds <= band.top then
			return layersCfg[band.id], band
		end
	end
	local last = composition[#composition]
	return layersCfg[last.id], last
end

--API
-- Removes a bite crater centered at world (px, pz).
-- Δ per cell = depth * (1 - (d/R)^2) / hardness(layer at that cell).
-- Heights never go below floorUnits (the core cavity floor).
-- Returns:
--   removed  — volume in studs^3 (already includes cell area)
--   changed  — array of 0-based cell indices whose height changed
function CakeOps.ApplyBite(
	field: buffer,
	gridCfg,
	footprint,
	composition,
	layersCfg,
	px: number,
	pz: number,
	radiusStuds: number,
	depthStuds: number,
	floorUnits: number
): (number, { number })
	local size = gridCfg.size
	local cell = gridCfg.cell
	local cx, cz = GridUtil.WorldToCell(gridCfg, px, pz)
	local rCells = math.ceil(radiusStuds / cell)
	local removedUnits = 0
	local changed = {}

	for z = cz - rCells, cz + rCells do
		for x = cx - rCells, cx + rCells do
			if GridUtil.InBounds(size, x, z) and GridUtil.InCake(size, footprint, x, z) then
				local wx, wz = GridUtil.CellToWorld(gridCfg, x, z)
				local dx, dz = wx - px, wz - pz
				local distSq = dx * dx + dz * dz
				if distSq <= radiusStuds * radiusStuds then
					local i = GridUtil.Index(size, x, z)
					local h = GridUtil.ReadHeight(field, i)
					if h > floorUnits then
						local falloff = 1 - distSq / (radiusStuds * radiusStuds)
						local layer = CakeOps.LayerAtStuds(composition, layersCfg, GridUtil.UnitsToStuds(h))
						if layer.hardness ~= math.huge then
							local deltaUnits = math.floor(
								depthStuds * falloff / layer.hardness * GridUtil.UNITS_PER_STUD
							)
							if deltaUnits > 0 then
								local newH = math.max(floorUnits, h - deltaUnits)
								if newH ~= h then
									GridUtil.WriteHeight(field, i, newH)
									removedUnits += h - newH
									table.insert(changed, i)
								end
							end
						end
					end
				end
			end
		end
	end

	return GridUtil.UnitsToStuds(removedUnits) * cell * cell, changed
end

--API
-- Calories for a removed bite volume, weighting by the layer at the bite
-- point's PRE-BITE surface height (one lookup — per-cell layer split isn't
-- worth the cost; bands are thick relative to bite depth).
function CakeOps.CaloriesFor(volumeStuds3: number, layer): number
	return volumeStuds3 * (layer.calories or 0)
end

return CakeOps
