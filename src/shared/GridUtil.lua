--[[
	GridUtil — pure math over the cake heightfield grid (GDD §4.2).

	The field is a flat u16 buffer: index i = z * size + x (0-based),
	value = height in fixed-point units (1 unit = 0.01 studs). Both sides
	use THIS module for every grid<->world conversion so the client
	prediction and the server simulation can never disagree on geometry.

	No state, no Instances — safe to require anywhere.
]]

local GridUtil = {}

GridUtil.UNITS_PER_STUD = 100 -- u16 fixed point: 1 unit = 0.01 studs

--API
function GridUtil.Index(size: number, x: number, z: number): number
	return z * size + x -- 0-based cell coords -> 0-based buffer index
end

--API
function GridUtil.Coords(size: number, i: number): (number, number)
	return i % size, math.floor(i / size)
end

--API
function GridUtil.ReadHeight(field: buffer, i: number): number
	return buffer.readu16(field, i * 2)
end

--API
function GridUtil.WriteHeight(field: buffer, i: number, units: number)
	buffer.writeu16(field, i * 2, units)
end

--API
function GridUtil.StudsToUnits(studs: number): number
	return math.clamp(math.floor(studs * GridUtil.UNITS_PER_STUD + 0.5), 0, 65535)
end

--API
function GridUtil.UnitsToStuds(units: number): number
	return units / GridUtil.UNITS_PER_STUD
end

--API
-- Cell center in world XZ. gridCfg = CakeConfig.grid.
function GridUtil.CellToWorld(gridCfg, x: number, z: number): (number, number)
	local half = gridCfg.size * 0.5
	return gridCfg.origin.x + (x - half + 0.5) * gridCfg.cell,
		gridCfg.origin.z + (z - half + 0.5) * gridCfg.cell
end

--API
-- World XZ -> cell coords (unclamped; caller checks InBounds/InCake).
function GridUtil.WorldToCell(gridCfg, wx: number, wz: number): (number, number)
	local half = gridCfg.size * 0.5
	return math.floor((wx - gridCfg.origin.x) / gridCfg.cell + half),
		math.floor((wz - gridCfg.origin.z) / gridCfg.cell + half)
end

--API
function GridUtil.InBounds(size: number, x: number, z: number): boolean
	return x >= 0 and z >= 0 and x < size and z < size
end

--API
-- Whether the cell is inside the cake footprint — a rounded RECTANGLE
-- ("loaf cake", Drain-the-Lake scale): footprint = { hx, hz, corner }
-- in cells (half-length, half-width, corner radius).
function GridUtil.InCake(size: number, footprint, x: number, z: number): boolean
	local half = (size - 1) * 0.5
	local qx = math.max(math.abs(x - half) - (footprint.hx - footprint.corner), 0)
	local qz = math.max(math.abs(z - half) - (footprint.hz - footprint.corner), 0)
	return qx * qx + qz * qz <= footprint.corner * footprint.corner
		and math.abs(x - half) <= footprint.hx
		and math.abs(z - half) <= footprint.hz
end

--API
-- Surface height (studs) at a world position, bilinear over cell centers.
-- Returns nil when the position's own cell is outside the grid or the
-- round footprint. Rim samples that fall outside the footprint reuse the
-- center cell's height instead of 0 — blending void zeros would report
-- 25-50% of the true surface at the cake edge (wrong layer payouts).
function GridUtil.SurfaceHeightAt(field: buffer, gridCfg, footprint, wx: number, wz: number): number?
	local size = gridCfg.size
	local cx, cz = GridUtil.WorldToCell(gridCfg, wx, wz)
	if not GridUtil.InBounds(size, cx, cz) or not GridUtil.InCake(size, footprint, cx, cz) then
		return nil
	end
	local centerH = GridUtil.ReadHeight(field, GridUtil.Index(size, cx, cz))

	local half = size * 0.5
	local fx = (wx - gridCfg.origin.x) / gridCfg.cell + half - 0.5
	local fz = (wz - gridCfg.origin.z) / gridCfg.cell + half - 0.5
	local x0, z0 = math.floor(fx), math.floor(fz)
	local tx, tz = fx - x0, fz - z0
	local function sample(x, z): number
		if not GridUtil.InBounds(size, x, z) or not GridUtil.InCake(size, footprint, x, z) then
			return centerH
		end
		return GridUtil.ReadHeight(field, GridUtil.Index(size, x, z))
	end
	local h00, h10 = sample(x0, z0), sample(x0 + 1, z0)
	local h01, h11 = sample(x0, z0 + 1), sample(x0 + 1, z0 + 1)
	local top = h00 + (h10 - h00) * tx
	local bot = h01 + (h11 - h01) * tx
	return GridUtil.UnitsToStuds(top + (bot - top) * tz)
end

return GridUtil
