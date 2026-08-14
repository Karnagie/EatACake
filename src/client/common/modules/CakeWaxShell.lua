--[[
	CakeWaxShell — the optional wax coating over the WHOLE cake, as a web
	of organic wax pieces (reference: the "Crunchy Butter" ASMR games).

	The wax is a permanent VORONOI WEB (irregular pieces, not tiles) that coats
	the whole top and rides the deforming surface. Under the foot the local
	pieces SQUISH DOWN (they dent with the surface) and, because they dent, they
	CRACK — each piece pulls in toward its own centre so gaps open and the CAKE
	LAYER shows through; it heals as the dent recovers. The coating tints to the
	CURRENT top layer's own colour, a touch brighter (glazeColor, req 1). Where a
	HOLE is eaten through the cake — a crater `hideDepth` below the outermost
	remaining layer — the wax there DISAPPEARS, revealing the body/wall in the hole
	(req 3); an even, hole-less drop keeps the coating and rides the surface down.
	When a whole layer clears, the surface (maxH) drops to the next layer and the
	wax re-coats it, retinted. The wax never spawns or follows: only the local
	denting/cracking + this hide/reveal are dynamic.

	ONE MeshPart holds the whole web (dynamic EditableMesh reserves worst-case
	budget → build one scratch, FixedSize-clone, destroy the scratch; the clone
	still takes SetPosition). Each Voronoi CELL owns its vertices (duplicated) so
	pieces separate; it rides the surface by re-reading the mirror heights and
	hides where the cake is eaten. Create* returns NIL on budget exhaustion
	(nil-checked; on failure the wax just doesn't appear, R8). Local + visual.

	Driven from CakeSubsClient's render step: Step(dt, footPos). Snapshot metadata
	can disable it entirely (`waxEnabled = false`, selectable rainbow). The mirror
	(LocalCakeField) is injected via Setup.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local Log = require(Shared:WaitForChild("Log"))

local CakeWaxShell = {}

local gridCfg = CakeConfig.grid
local waxCfg = CakeConfig.render.wax
local layersCfg = CakeConfig.layers
local FOOTPRINT = CakeConfig.composition.footprint
local SIZE = gridCfg.size
local CELL = gridCfg.cell
local HALF = SIZE / 2
local WHITE = Color3.new(1, 1, 1)
local HIDE = -400 -- world Y where eaten wax verts hide

type Cell = {
	vids: { number }, -- BOUNDARY vertices (on the exact Voronoi edge → neighbours MEET)
	restX: { number },
	restZ: { number },
	vc: { number }, -- grid cell index per boundary vertex (its own surface height)
	tc: { number }, -- grid cell at each fan-TRIANGLE centre (area sample for the straddle hide)
	cvid: number, -- CENTRE vertex (raised → each piece is a low DOME; the grooves
	-- between domes are the always-visible "web" seams, no cake gap)
	cx: number,
	cz: number,
	ci: number, -- grid cell at the centroid (surface height + eaten test)
	tdx: number, -- unit tilt direction (the piece tips along it when pressed)
	tdz: number,
	dent: number, -- 0 flat .. 1 fully pressed (drives squish + tilt + spread)
	wH: number, -- last-written centroid height (dirty check)
	wDent: number, -- last-written dent (dirty check)
	wHidden: boolean, -- last-written hidden state (dirty check)
}

local fieldModule
local part: MeshPart? = nil
local em: EditableMesh? = nil
local cells: { Cell } = {}
local built = false
local buildFailed = false
local building = false -- guards the async build against re-entry mid-yield
-- Previous frame's OUTERMOST REMAINING layer height (studs): drives BOTH the
-- coating tint and the HIDE threshold (a piece hides when its own surface has
-- dropped hideDepth below this — i.e. a hole was eaten through). 1-frame lag,
-- like the tint always had; starts 0 so nothing hides until the first real max.
local lastMaxH = 0
-- Cake this coating's hide-reference was last valid for; a new cake resets
-- lastMaxH so a fresh (possibly shorter) cake doesn't read as all-holes for a
-- lag frame (a 1-frame full-coating flash).
local lastCakeIndex = -1

--API
function CakeWaxShell.Setup(localCakeField)
	fieldModule = localCakeField
end

-- world XZ -> grid cell index (clamped into the field).
-- ⚠ Pass `fallback` for any sample that can land on the RIM. Cells outside the
-- footprint hold height 0 (CakeFieldService.ResetCake), so a boundary vertex that
-- samples one gets written at the cake BASE while the rest of its piece rides the
-- surface — two fan triangles stretched ~170 studs down the side, a wax streamer.
-- The wax outline is inset from the footprint, but it is an ANALYTIC curve while
-- InCake is a cell staircase, so short stretches of it do overhang an out-of-cake
-- cell. On the loaf only the 4 corner arcs could do this (the two long straight
-- edges were exactly cell-aligned); the ROUND cake makes the entire rim an arc,
-- which is what turned a latent case into a reachable one.
local function cellAt(x: number, z: number, fallback: number?): number
	local gx = math.clamp(math.floor(x / CELL + HALF), 0, SIZE - 1)
	local gz = math.clamp(math.floor(z / CELL + HALF), 0, SIZE - 1)
	if fallback ~= nil and not GridUtil.InCake(SIZE, FOOTPRINT, gx, gz) then
		return fallback
	end
	return GridUtil.Index(SIZE, gx, gz)
end

-- Sutherland–Hodgman clip of a convex polygon by { p : dot(p-thru, nrm) <= 0 }.
local function clip(poly: { Vector2 }, thru: Vector2, nrm: Vector2): { Vector2 }
	local out: { Vector2 } = {}
	local n = #poly
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		local da, db = (a - thru):Dot(nrm), (b - thru):Dot(nrm)
		if da <= 0 then
			table.insert(out, a)
		end
		if (da <= 0) ~= (db <= 0) then
			table.insert(out, a + (b - a) * (da / (da - db)))
		end
	end
	return out
end

-- Builds the wax web: Voronoi cells over the footprint, one FixedSize mesh.
-- Runs in a task.spawn (Step sets `building` before spawning) so the yielding
-- async mesh creation NEVER blocks the RenderStepped callback, and re-entry is
-- blocked (a second Step during the yield sees `building` and doesn't respawn).
local function ensureBuilt()
	if built or buildFailed then
		return
	end
	local rng = Random.new(20240718)
	-- Jittered seed points over the footprint (organic pieces, ~plateStuds apart).
	local seeds: { Vector2 } = {}
	local stepStuds = waxCfg.plateStuds
	local ext = math.max(FOOTPRINT.hx, FOOTPRINT.hz) * CELL + stepStuds
	local n = math.ceil(ext * 2 / stepStuds)
	for gz = 0, n do
		for gx = 0, n do
			local x = -ext + gx * stepStuds + rng:NextNumber(-0.42, 0.42) * stepStuds
			local z = -ext + gz * stepStuds + rng:NextNumber(-0.42, 0.42) * stepStuds
			if GridUtil.InCake(SIZE, FOOTPRINT, math.clamp(math.floor(x / CELL + HALF), 0, SIZE - 1), math.clamp(math.floor(z / CELL + HALF), 0, SIZE - 1)) then
				table.insert(seeds, Vector2.new(x, z))
			end
		end
	end
	if #seeds == 0 then
		buildFailed = true
		Log.Once("CakeWaxShell", "seeds", "no wax seed points in the footprint — wax disabled")
		return
	end

	local scratch: EditableMesh? = nil
	pcall(function()
		scratch = AssetService:CreateEditableMesh()
	end)
	if scratch == nil then
		buildFailed = true
		Log.Once("CakeWaxShell", "budget", "EditableMesh budget exhausted — wax web disabled")
		return
	end
	local m = scratch :: EditableMesh
	-- FixedSize meshes cull from CREATION-time bounds, so birth the shell at the
	-- FULL cake height (like the slabs' creationY = maxHeight and CakeWrapper): the
	-- wax rides the surface DOWNWARD as it's eaten (mesh-local y ~maxHeight at spawn
	-- → ~0 at the core), so a full-height birth keeps every runtime vertex BELOW
	-- the creation box — verts only ever move DOWN within bounds, the proven-safe
	-- direction. (Was 0.75·maxHeight, which let the 3× cake's spawn surface ride
	-- ~57 studs ABOVE the box — a cull/pop risk at the tall top.)
	local birthY = gridCfg.origin.y + gridCfg.maxHeight
	local boundR = ext * 1.1

	-- Loaf outline (the same rounded rect as the slab, inset a touch) as a CCW
	-- convex polygon; every wax piece is clipped to it so the web stops CLEANLY
	-- inside the cake edge instead of overhanging the skirt with jagged pieces.
	local rectX = (FOOTPRINT.hx - FOOTPRINT.corner) * CELL
	local rectZ = (FOOTPRINT.hz - FOOTPRINT.corner) * CELL
	local cornerR = (FOOTPRINT.corner + 0.5) * CELL - waxCfg.edgeInset
	local outline: { Vector2 } = {}
	local corners = { { rectX, rectZ, 0 }, { -rectX, rectZ, math.pi / 2 }, { -rectX, -rectZ, math.pi }, { rectX, -rectZ, math.pi * 1.5 } }
	-- ⚠ On the ROUND cake `rectX == rectZ == 0`, so all four "corner" centres
	-- collapse to the origin and the four quarter-arcs concatenate into ONE circle
	-- — which is what makes a disc work here at all. Two consequences:
	--   · each seam angle (90/180/270/360°) is emitted TWICE. A duplicate makes a
	--     zero-length edge → zero normal → a clip plane that silently does nothing.
	--     It happened to be harmless; dedupe so every plane is a real one.
	--   · the outline is a polygon inscribed in the circle, so the effective
	--     `edgeInset` is larger at the chord midpoints than at the vertices. 8 steps
	--     per quarter (11.25°) keeps that sag under ~0.22 studs.
	local ARC_STEPS = 8
	for _, cn in ipairs(corners) do
		for k = 0, ARC_STEPS do
			local a = cn[3] + k / ARC_STEPS * (math.pi / 2)
			local p = Vector2.new(cn[1] + math.cos(a) * cornerR, cn[2] + math.sin(a) * cornerR)
			local prev = outline[#outline]
			if prev == nil or (p - prev).Magnitude > 1e-4 then
				outline[#outline + 1] = p
			end
		end
	end
	if #outline > 1 and (outline[#outline] - outline[1]).Magnitude <= 1e-4 then
		outline[#outline] = nil -- closing point duplicates the first
	end
	local nOut = #outline

	local ok = pcall(function()
		local uv = m:AddUV(Vector2.new(0.5, 0.5))
		local nUp = m:AddNormal(Vector3.yAxis)
		for i, s in ipairs(seeds) do
			-- Voronoi cell = bounding octagon clipped by the bisectors to neighbours.
			local poly: { Vector2 } = {}
			for k = 0, 7 do
				local a = k / 8 * math.pi * 2
				poly[#poly + 1] = s + Vector2.new(math.cos(a), math.sin(a)) * boundR
			end
			for j, o in ipairs(seeds) do
				if j ~= i and (o - s).Magnitude < stepStuds * 3 then
					poly = clip(poly, (s + o) / 2, o - s)
					if #poly < 3 then
						break
					end
				end
			end
			-- Clip to the loaf outline (each CCW edge → outward normal (dz,-dx)).
			if #poly >= 3 then
				for ei = 1, nOut do
					local a = outline[ei]
					local b = outline[ei % nOut + 1]
					poly = clip(poly, a, Vector2.new(b.Y - a.Y, -(b.X - a.X)))
					if #poly < 3 then
						break
					end
				end
			end
			if #poly >= 3 then
				local cx, cz = 0, 0
				for _, v in ipairs(poly) do
					cx += v.X
					cz += v.Y
				end
				cx /= #poly
				cz /= #poly
				-- Boundary verts on the EXACT Voronoi edge → neighbours meet with
				-- no gap; a raised CENTRE vert domes each piece (visible seams).
				-- The piece's own centre cell is always in-cake (seeds are rejected
				-- otherwise), so it is the safe fallback for rim samples — a vertex
				-- that overhangs the staircase rides its piece instead of the base.
				local ciCentre = cellAt(cx, cz)
				local vids, rx, rz, vc = {}, {}, {}, {}
				for _, v in ipairs(poly) do
					vids[#vids + 1] = m:AddVertex(Vector3.new(v.X, birthY, v.Y))
					rx[#rx + 1] = v.X
					rz[#rz + 1] = v.Y
					vc[#vc + 1] = cellAt(v.X, v.Y, ciCentre)
				end
				local cvid = m:AddVertex(Vector3.new(cx, birthY, cz))
				local nB = #vids
				for k = 1, nB do
					local f = m:AddTriangle(cvid, vids[k], vids[k % nB + 1]) -- fan from centre
					m:SetFaceUVs(f, { uv, uv, uv })
					m:SetFaceNormals(f, { nUp, nUp, nUp })
				end
				-- Grid cell at each fan-triangle centre ((centroid + two adjacent boundary
				-- verts) / 3) — sampled per frame so a piece whose AREA spans a crater hides.
				local tc = {}
				for k = 1, nB do
					local nx, nz = rx[k % nB + 1], rz[k % nB + 1]
					-- Same fallback: an out-of-cake triangle centre reads height 0, which
					-- is always < hideBelow, so the piece would hide FOREVER — a fixed
					-- bald patch in the coating rather than a spike.
					tc[k] = cellAt((cx + rx[k] + nx) / 3, (cz + rz[k] + nz) / 3, ciCentre)
				end
				local ta = rng:NextNumber(0, math.pi * 2)
				cells[#cells + 1] = { vids = vids, restX = rx, restZ = rz, vc = vc, tc = tc, cvid = cvid, cx = cx, cz = cz, ci = ciCentre, tdx = math.cos(ta), tdz = math.sin(ta), dent = 0, wH = -1, wDent = -1, wHidden = false }
			end
		end
	end)
	if not ok or #cells == 0 then
		buildFailed = true
		scratch:Destroy()
		table.clear(cells)
		Log.Once("CakeWaxShell", "geom", "wax web geometry build failed — disabled")
		return
	end

	local fixed: EditableMesh? = nil
	pcall(function()
		fixed = AssetService:CreateEditableMeshAsync(Content.fromObject(m), { FixedSize = true })
	end)
	scratch:Destroy()
	if fixed == nil then
		buildFailed = true
		table.clear(cells)
		Log.Once("CakeWaxShell", "clone", "wax web FixedSize clone failed (budget) — disabled")
		return
	end
	local pt: MeshPart? = nil
	local okPart = pcall(function()
		pt = AssetService:CreateMeshPartAsync(Content.fromObject(fixed :: EditableMesh), { RenderFidelity = Enum.RenderFidelity.Precise })
	end)
	if not okPart or pt == nil then
		buildFailed = true;
		(fixed :: EditableMesh):Destroy()
		table.clear(cells)
		Log.Once("CakeWaxShell", "part", "wax web MeshPart create failed — disabled")
		return
	end
	local p = pt :: MeshPart
	p.Name = "CakeWaxShell"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.DoubleSided = true
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = waxCfg.gloss
	p.Color = WHITE
	p.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y, gridCfg.origin.z)
	p.Parent = workspace
	part = p
	em = fixed
	built = true
	Log.Info("CakeWaxShell", `wax web built — {#cells} Voronoi pieces (1 mesh)`)
end

-- Surface layer band at a height, from the composition (for wax colour + the
-- eaten test). Returns (bandTop, layerId) of the band that owns `h`.
local function surfaceBand(h: number): (number, string)
	local meta = fieldModule.Meta()
	if meta == nil then
		return 0, "frosting"
	end
	local top = meta.composition[#meta.composition]
	for _, band in ipairs(meta.composition) do
		if h <= band.top + 0.01 then
			return band.top, band.id
		end
	end
	return top.top, top.id
end

-- Glaze colour for a layer (user req 1): the layer's OWN top colour, only
-- SLIGHTLY brighter — keep the hue/saturation, lift the brightness toward full
-- value by a fraction of the remaining headroom (so it always brightens, even a
-- near-white layer, without the old ×val clamp flattening bright layers). The
-- wax on each layer thus clearly reads as THAT layer's colour, a touch brighter.
local function glazeColor(id: string): Color3
	local h, s, v = Color3.toHSV(layersCfg[id].colors.top)
	local sat = math.clamp(s * waxCfg.satBoost, 0, 1)
	local val = math.clamp(v + (1 - v) * waxCfg.valBrighten, 0, 1)
	return Color3.fromHSV(h, sat, val)
end

--API
-- Per-frame: ride the surface, dent + crack the pieces under the foot, hide
-- eaten pieces. The dent (0..1 per piece) drives BOTH the squish and the crack.
function CakeWaxShell.Step(dt: number, footPos: Vector3?)
	if buildFailed or fieldModule == nil then
		return
	end
	local meta = fieldModule.Meta()
	if meta == nil then
		return
	end
	if meta.waxEnabled == false then
		if part ~= nil then
			part.Transparency = 1
		end
		return
	end
	if part ~= nil then
		part.Transparency = 0
	end
	if not built then
		-- Build OFF the render thread (task.spawn): the async mesh creation
		-- yields, and doing it inline here would stall the rest of CakeSubsClient's
		-- render step. `building` blocks re-spawn + re-entry; pcall guards against
		-- a throw leaving `building` stuck true.
		if not building then
			building = true
			task.spawn(function()
				local ok, err = pcall(ensureBuilt)
				if not ok then
					buildFailed = true
					Log.Warn("CakeWaxShell", `wax build threw ({err}) — wax disabled`)
				end
			end)
		end
		return
	end
	local mesh = em :: EditableMesh
	local frac = CakeConfig.render.fracture
	local up = 1 - math.exp(-frac.riseRate * dt)
	local down = 1 - math.exp(-frac.healRate * dt)
	local rad = waxCfg.crackRadius
	local sink = frac.sinkDepth
	local gap = waxCfg.gap
	local lift = waxCfg.lift
	local tiltAmp = math.tan(math.rad(waxCfg.tilt))
	local dome = waxCfg.dome
	-- Foot in GRID space (centroids are grid-relative; origin.xz is 0 today but
	-- subtract it so a repositioned loaf still lines the dent up with the foot).
	local fx = if footPos then footPos.X - gridCfg.origin.x else nil
	local fz = if footPos then footPos.Z - gridCfg.origin.z else nil

	-- Coating COLOUR follows the OUTERMOST REMAINING layer (the tallest un-eaten
	-- piece), NOT the foot — so standing in a crater on a lower layer doesn't
	-- re-tint the un-eaten areas. Uses last frame's max (1-frame lag).
	-- New cake: reset the hide reference (nothing hides on the fresh cake's first
	-- frame; it re-converges next frame like the initial build).
	if meta.cakeIndex ~= lastCakeIndex then
		lastCakeIndex = meta.cakeIndex
		lastMaxH = 0
	end
	local maxH = 0
	-- HIDE where a HOLE is eaten through the cake (user req 3): a piece hides when
	-- its own surface has dropped `hideDepth` BELOW the outermost remaining layer
	-- (a real crater), revealing the cake body / wall in the hole. An even, hole-
	-- less drop (the whole layer lowered together) stays coated and rides down, so
	-- the coating still follows the surface — it only VANISHES at holes. When a
	-- whole layer clears, maxH drops to the next layer and the wax re-coats it,
	-- retinted (each layer keeps its own wax colour, req 1).
	-- (Superseded the ride-to-active-floor "coat every layer" rule, which made the
	-- wax follow craters all the way down and never disappear — see cake-sim.md.)
	local hideBelow = lastMaxH - waxCfg.hideDepth
	local vhs = {} -- reused per-piece scratch: boundary-vertex surface heights

	for _, c in ipairs(cells) do
		-- Dent target from the foot (falloff); ramp/spring at the fracture rates.
		local target = 0
		if fx ~= nil then
			local d = (c.cx - fx) ^ 2 + (c.cz - fz) ^ 2
			if d < rad * rad then
				target = 1 - math.sqrt(d) / rad
			end
		end
		if target > c.dent then
			c.dent += (target - c.dent) * up
		else
			c.dent += (target - c.dent) * down
		end
		local dent = c.dent

		local hC = fieldModule.ReadHeightStuds(c.ci)
		-- Read the boundary-vertex surface heights (needed to ride the surface).
		for k = 1, #c.vids do
			vhs[k] = fieldModule.ReadHeightStuds(c.vc[k])
		end
		-- STRADDLE hide: sample the surface at each fan-TRIANGLE centre (c.tc) — the
		-- piece AREA, not just its verts. A piece whose area spans a crater (even with
		-- all its VERTS still on the rim, so it would otherwise hang a flat wax SHELF
		-- over the eaten edge) hides as a whole, so the wax recedes cleanly from the
		-- crater (user req: no leftover pieces at the eaten edge).
		local minArea = hC
		for k = 1, #c.tc do
			local ht = fieldModule.ReadHeightStuds(c.tc[k])
			if ht < minArea then minArea = ht end
		end
		local eaten = hC < hideBelow or hC < 0.5 or minArea < hideBelow
		if not eaten and hC > maxH then
			maxH = hC -- tallest un-eaten piece → the outermost remaining layer
		end

		-- Dirty skip: a resting piece whose height + hidden state are unchanged
		-- needs no re-write (avoids ~84k idle SetPosition/s dirtying the mesh).
		if
			dent < 0.001
			and c.wDent < 0.001
			and eaten == c.wHidden
			and (eaten or math.abs(hC - c.wH) < 0.01)
		then
			continue
		end

		if eaten then
			mesh:SetPosition(c.cvid, Vector3.new(c.cx, HIDE, c.cz))
			for _, vid in ipairs(c.vids) do
				mesh:SetPosition(vid, Vector3.new(c.restX[1], HIDE, c.restZ[1]))
			end
		else
			-- At rest the BOUNDARY verts sit exactly on the surface (neighbours
			-- meet, no cake gap) and the raised CENTRE domes the piece. When
			-- pressed the piece DENTS down, TILTS (one edge up) and SPREADS in
			-- toward the centre, so the cracks (and cake) open only here.
			local shrink = math.min(0.85, gap * dent)
			local tiltMag = tiltAmp * dent
			mesh:SetPosition(c.cvid, Vector3.new(c.cx, hC + lift + dome - sink * dent, c.cz))
			for k = 1, #c.vids do
				local rx0, rz0 = c.restX[k], c.restZ[k]
				local hV = vhs[k] -- this vertex's own surface height (read above)
				local yTilt = ((rx0 - c.cx) * c.tdx + (rz0 - c.cz) * c.tdz) * tiltMag
				local x = rx0 + (c.cx - rx0) * shrink
				local z = rz0 + (c.cz - rz0) * shrink
				mesh:SetPosition(c.vids[k], Vector3.new(x, hV + lift - sink * dent + yTilt, z))
			end
		end
		c.wH = hC
		c.wDent = dent
		c.wHidden = eaten
	end

	-- Tint the whole coating to the current outermost remaining layer.
	if maxH > 0 then
		if part ~= nil then
			local _, id = surfaceBand(maxH)
			part.Color = glazeColor(id)
		end
	end
	-- Feed this frame's max into next frame's hide threshold + tint (1-frame lag).
	lastMaxH = maxH
end

return CakeWaxShell
