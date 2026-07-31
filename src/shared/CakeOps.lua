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
-- Removes a bite centered at world (px, pz). Req 2 CLEAN CUT: each cell in the
-- radius is cleared TOWARD floorUnits by a fraction that is 1 at the center
-- (scoops fully to the layer floor) and tapers to 0 at the rim, eased by the
-- layer hardness and the bite strength (depthStuds / clearRefDepth). So one side
-- of a layer clears completely while the other stays full — a clean cut edge —
-- rather than a shallow paraboloid dent that strands hard-to-eat crumbs. Heights
-- never go below floorUnits (the active-band / core floor).
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
	floorUnits: number,
	clearRefDepth: number
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
				-- The cell the bite POINT sits in always counts: a small scoop
				-- (dense deep band) can otherwise fall between cell centres and
				-- remove nothing at all (CakeConfig.sim.minBiteRadiusStuds).
				if distSq <= radiusStuds * radiusStuds or (x == cx and z == cz) then
					local i = GridUtil.Index(size, x, z)
					local h = GridUtil.ReadHeight(field, i)
					if h > floorUnits then
						local falloff = 1 - distSq / (radiusStuds * radiusStuds) -- 1 center → 0 rim
						if falloff <= 0 then
							-- only reachable for the FORCED centre cell, when the
							-- scoop is smaller than the distance to that cell's
							-- centre; give it a small but real bite.
							falloff = 0.15
						end
						local layer = CakeOps.LayerAtStuds(composition, layersCfg, GridUtil.UnitsToStuds(h))
						if layer.hardness ~= math.huge then
							-- Clear the cell TOWARD the floor (clean cut), not a shallow
							-- paraboloid: strength = biteDepth/clearRefDepth (1 at base →
							-- center scoops fully); clearFrac tapers to 0 at the rim and is
							-- eased by hardness (chocolate takes a few bites).
							local strength = if clearRefDepth > 0 then depthStuds / clearRefDepth else 1
							local clearFrac = math.clamp(falloff * strength / layer.hardness, 0, 1)
							local deltaUnits = math.floor((h - floorUnits) * clearFrac)
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
