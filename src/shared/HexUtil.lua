--[[
	HexUtil — pure axial-hex math for honeycomb UI layout (upgrades tree).

	Sibling to GridUtil (which does the SQUARE cake grid); this one does the
	HEX grid the upgrade tree is drawn on. Canonical formulas from Red Blob
	Games "Hexagonal Grids" (https://www.redblobgames.com/grids/hexagons/).

	Convention: FLAT-TOP hexagons (horizontal top/bottom edges), stored in
	AXIAL coords (q, r). `size` = centre-to-corner radius, in the SAME units
	the caller lays the canvas out in (we use a fixed logical-pixel canvas,
	then scale it once with UIScale — see HexTreeOverlay).

	No state, no Instances — safe to require on either side.
]]

local HexUtil = {}

local SQRT3 = math.sqrt(3)

--API
-- Flat-top hex bounding box for a given centre-to-corner size.
-- width spans the two side vertices (2*size); height spans the flat edges.
function HexUtil.Dimensions(size: number): (number, number)
	return 2 * size, SQRT3 * size
end

--API
-- Axial (q, r) -> pixel centre (x, y), flat-top (redblobgames forward matrix
-- f0=3/2, f1=0, f2=√3/2, f3=√3).
function HexUtil.ToPixel(size: number, q: number, r: number): (number, number)
	local x = size * (1.5 * q)
	local y = size * (SQRT3 * (0.5 * q + r))
	return x, y
end

--API
-- Cube rounding of fractional cube coords -> nearest integer hex (returned as
-- axial q, r). Needed by FromPixel for exact hit-testing.
function HexUtil.Round(q: number, r: number): (number, number)
	local s = -q - r
	local rq, rr, rs = math.floor(q + 0.5), math.floor(r + 0.5), math.floor(s + 0.5)
	local dq, dr, ds = math.abs(rq - q), math.abs(rr - r), math.abs(rs - s)
	if dq > dr and dq > ds then
		rq = -rr - rs
	elseif dr > ds then
		rr = -rq - rs
	end
	return rq, rr
end

--API
-- Pixel (x, y) relative to hex (0,0)'s centre -> nearest axial hex (q, r).
-- Flat-top inverse matrix, then Round. For single-ImageButton hit-testing.
function HexUtil.FromPixel(size: number, x: number, y: number): (number, number)
	local q = (2 / 3 * x) / size
	local r = (-1 / 3 * x + SQRT3 / 3 * y) / size
	return HexUtil.Round(q, r)
end

-- Flat-top neighbour directions in axial coords (E, NE, NW, W, SW, SE-ish):
-- the 6 hexes sharing an edge with (q, r).
HexUtil.Directions = {
	{ q = 1, r = 0 },
	{ q = 1, r = -1 },
	{ q = 0, r = -1 },
	{ q = -1, r = 0 },
	{ q = -1, r = 1 },
	{ q = 0, r = 1 },
}

--API
-- Neighbour hex in direction 1..6.
function HexUtil.Neighbor(q: number, r: number, direction: number): (number, number)
	local d = HexUtil.Directions[direction]
	return q + d.q, r + d.r
end

--API
-- The first `count` hexes packed tightly around (0,0) in SPIRAL order: ring by
-- ring (nearest first), each ring ordered by angle. Guarantees a compact
-- gap-free honeycomb BLOB (used to pack the upgrade sub-trees so hexes touch).
function HexUtil.Spiral(count: number): { { q: number, r: number } }
	local cells = {}
	local radius = 0
	-- Grow the disc until it holds enough cells.
	while true do
		cells = {}
		for q = -radius, radius do
			for r = -radius, radius do
				local s = -q - r
				if (math.abs(q) + math.abs(r) + math.abs(s)) / 2 <= radius then
					local px, py = HexUtil.ToPixel(1, q, r)
					table.insert(cells, {
						q = q,
						r = r,
						dist = (math.abs(q) + math.abs(r) + math.abs(s)) / 2,
						angle = math.atan2(py, px),
					})
				end
			end
		end
		if #cells >= count then
			break
		end
		radius += 1
	end
	-- Ring by ring (nearest first), each ring clockwise from the top by angle.
	table.sort(cells, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.angle < b.angle
	end)
	local result = {}
	for i = 1, math.min(count, #cells) do
		result[i] = { q = cells[i].q, r = cells[i].r }
	end
	return result
end

return HexUtil
