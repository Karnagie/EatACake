--[[
	CakeRenderer — the cake's client visual (GDD §4.5).

	Primary path: render the CURRENT + NEXT edible band as EditableMesh slabs (2
	slabs — assignWindowBands/windowFor), not every layer. The layer gate forbids
	eating below the active band's floor, so the band below is a flat floor seen
	through craters and everything under IT is never exposed — that ungenerated
	bulk is hidden by the textured CakeWrapper wall (a plain Part, not a mesh).
	This caps the slab vertex budget at TWO regardless of how many / how tall the
	layers are. The window slides DOWN as each layer finishes (rewindow, driven by
	the layer-gate activeBandIndex). Each slab is the heightfield clamped to its
	band and carries its OWN Material / Transparency / Reflectance and an OPTIONAL
	image texture (layer.texture — frosting/chocolate/filling); a layer without a
	texture renders a SOLID body Color, with the CakeWaxShell web on top. The parts
	FALLBACK (no EditableMesh) draws the whole cake as the keycap column grid.

	CRUNCHY BUTTER (reference: the "Crunchy Butter" ASMR games — a thin hard wax
	crust over soft butter). This file owns the SOFT SQUISH: the mesh dents
	softly under the foot (fractureOffsetAt: `-sinkDepth·falloff`, §7.2 squish
	loop), springs back; deeper on a landing (CrackAt). The slabs render the
	layer BODY color — the pale crust look is the always-visible CakeWaxShell
	module (a Voronoi wax web that cracks underfoot), so the darker body shows
	through the wax gaps. Purely visual and local.

	MEMORY BUDGET (the reason for the pool shape): a DYNAMIC EditableMesh
	reserves the worst-case budget (60k verts) regardless of content — ~8
	fit a desktop client, fewer on laptops. So the pool is built by cloning
	ONE temporary dynamic scratch mesh via CreateEditableMeshAsync
	{FixedSize=true} (fixed clones cost their ACTUAL complexity, still allow
	SetPosition/SetNormal; probe-verified: source vertex/normal/uv ids stay
	valid on the clone), then the scratch is destroyed. Slabs are created
	LAZILY per composition (typically 5-6) with only footprint-hosted
	vertices. Degradation ladder when creation still fails:
	  per-layer slabs -> ONE slab + height-palette texture -> part grid.
	CreateEditableMesh/Image return NIL (no throw) on budget exhaustion —
	every creation is nil-checked and warned (R8).

	Band projection rule (per vertex, raw = shared display height):
	  raw > band.bottom + EPS  ->  y = min(raw, band.top)   (slab surface)
	  else                     ->  y = 0                     (eaten through:
	  the quad drops to the grid floor, hidden inside/below the opaque core
	  slab — NEVER a floating film over a crater)
	  ring verts (outside the footprint) seal the skirt at band.bottom while
	  any nearby cake is above it, so the outer wall shows stacked layer
	  bands; they drop to 0 once the rim is eaten below the band.

	BITE FEEL: target drops over render.snapDropStuds SNAP; refills/settling
	ooze toward server truth at the SURFACE LAYER's oozeSpeed (honey-slow
	caramel vs pouring cotton). Jelly wobble is a negative-only sine on the
	jelly band; underfoot squish (§7.2) scales with the layer's squishMult.

	Collision: an INVISIBLE 32×32 column grid always exists (CanCollide +
	CanQuery, snapped to server truth) — walking and bite raycasts match the
	cake exactly in every mode. With render.forceFallback (or no
	EditableMesh) the same columns become the VISIBLE "keycap" fallback.

	The mirror (LocalCakeField) is injected via Setup from CakeSubsClient.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridUtil = require(Shared:WaitForChild("GridUtil"))
local Log = require(Shared:WaitForChild("Log"))
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local CakeRenderer = {}

local gridCfg = CakeConfig.grid
local renderCfg = CakeConfig.render
local layersCfg = CakeConfig.layers
local crustCfg = renderCfg.crust
local fractureCfg = renderCfg.fracture
-- Slab UVs tile the layer textures this many times across the loaf (sharper than
-- stretching once; Req 2). 1 = old stretch-once. Baked into the scratch UVs, so
-- single (palette) mode must NOT use a per-cell image (it would tile wrongly).
local LAYER_TEX_TILES = renderCfg.layerTextureTiles or 1

local SIZE = gridCfg.size
local VSIZE = SIZE + 1
local CELL = gridCfg.cell
local EPS = 0.02 -- studs: "the band still exists here" threshold
-- The loaf footprint is FIXED per game (config), so mesh faces, ring layout
-- and the vertex host set can be built once.
local FOOTPRINT = CakeConfig.composition.footprint
-- Safety ceiling on the slab pool. The renderer now only ever renders the
-- CURRENT + NEXT edible band (2 slabs — assignWindowBands), so the pool grows to
-- 2 and this cap just backstops a bug. The bulk below is the CakeWrapper wall.
local MAX_LAYER_MESHES = 8

-- A cell hosts mesh faces iff its 3x3 neighborhood touches the footprint —
-- the SAME rule as vertexTarget, so every raised boundary vertex is
-- surrounded by faces on all sides (an analytic ring test left corner slits).
local function cellHostsFaces(cx: number, cz: number): boolean
	for dz = -1, 1 do
		for dx = -1, 1 do
			local nx, nz = cx + dx, cz + dz
			if GridUtil.InBounds(SIZE, nx, nz) and GridUtil.InCake(SIZE, FOOTPRINT, nx, nz) then
				return true
			end
		end
	end
	return false
end

local fieldModule -- LocalCakeField, injected
local impl -- "editable" | "parts" | nil (setup failed)
local updateCollisionNearPlayer -- forward decl: radius-limited collision update (Task 4 feel + Task 2 perf)
-- Declared HERE (before editableRebuild closes over it) — a later `local`
-- would silently make the rebuild write a global (the upvalue trap).
local visualColumns = false -- keycap fallback look vs invisible colliders

-- ── Shared display state ────────────────────────────────────────────────
local palette: { Color3 } = {}
local wobbleBands: { { bottom: number, top: number } } = {} -- fallback SFX/columns
local clock = 0

local glossPalette: { number } = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function buildPalette()
	table.clear(palette)
	table.clear(glossPalette)
	table.clear(wobbleBands)
	local meta = fieldModule.Meta()
	if not meta then
		return
	end
	local top = meta.composition[#meta.composition].top
	local paletteMax = math.ceil(top / renderCfg.paletteStep) + 1
	for k = 1, paletteMax do
		local h = (k - 1) * renderCfg.paletteStep
		-- Find the band + in-band gradient.
		local color = Color3.new(1, 1, 1)
		local gloss = 0
		for idx, band in ipairs(meta.composition) do
			if h <= band.top or idx == #meta.composition then
				local layer = layersCfg[band.id]
				local t = math.clamp((h - band.bottom) / math.max(0.01, band.top - band.bottom), 0, 1)
				color = layer.colors.bottom:Lerp(layer.colors.top, t)
				gloss = layer.gloss or 0
				-- Crust skin at the top of every edible band (matches the
				-- layer textures, so fallback columns/particles agree).
				if band.id ~= "core" and band.top - h <= crustCfg.depth then
					color = color:Lerp(WHITE, crustCfg.lighten)
					gloss = math.max(gloss, crustCfg.gloss)
				end
				break
			end
		end
		-- Rare-cake tint (§5): saturated butter-gold / hue rainbow.
		if meta.rareKind == "golden" then
			color = color:Lerp(renderCfg.goldenTint.color, renderCfg.goldenTint.alpha)
			gloss = math.max(gloss, 0.15)
		elseif meta.rareKind == "rainbow" then
			local hue = (h / math.max(1, top)) % 1
			color = color:Lerp(Color3.fromHSV(hue, 0.65, 1), renderCfg.rainbowTintAlpha)
		end
		palette[k] = color
		glossPalette[k] = gloss
	end
	for _, band in ipairs(meta.composition) do
		if layersCfg[band.id].wobble then
			table.insert(wobbleBands, { bottom = band.bottom, top = band.top })
		end
	end
end

local function paletteIndex(hStuds: number): number
	return math.clamp(math.floor(hStuds / renderCfg.paletteStep) + 1, 1, math.max(1, #palette))
end

--API
-- Surface color at a height (bite particles match the layer).
function CakeRenderer.PaletteColor(hStuds: number): Color3
	return palette[paletteIndex(hStuds)] or Color3.fromRGB(240, 220, 220)
end

local function paletteGloss(hStuds: number): number
	local idx = math.clamp(math.floor(hStuds / renderCfg.paletteStep) + 1, 1, math.max(1, #glossPalette))
	return glossPalette[idx] or 0
end

-- Rare tint applied to band colors AND texture fills.
local function tinted(color: Color3, rareKind: string?, hMid: number, topStuds: number): Color3
	if rareKind == "golden" then
		return color:Lerp(renderCfg.goldenTint.color, renderCfg.goldenTint.alpha)
	elseif rareKind == "rainbow" then
		local hue = (hMid / math.max(1, topStuds)) % 1
		return color:Lerp(Color3.fromHSV(hue, 0.65, 1), renderCfg.rainbowTintAlpha)
	end
	return color
end

-- ── EditableMesh implementation: one slab mesh per layer ────────────────
-- Pool entries are FixedSize clones of one scratch mesh (footprint-static
-- geometry); every snapshot assigns them a band range + appearance. y[]
-- persists across cakes so unchanged vertices skip their SetPosition.
type PoolEntry = {
	em: EditableMesh, -- FixedSize clone: attribute edits OK, topology frozen
	part: MeshPart,
	image: EditableImage?, -- layer texture (crust + cracks), created lazily
	imageFailed: boolean?, -- budget said no — solid color, warned once
	vertIds: { number }, -- vi -> id (sparse: hosted verts only)
	uvIds: { number },
	normalIds: { number },
	y: { number }, -- last written vertex heights
}
type Band = {
	layerId: string,
	bottom: number,
	top: number,
	poolIdx: number,
	sink: number, -- eaten-through tuck depth under the local surface
	single: boolean?, -- palette mode: this one band renders the whole cake
	bodyColor: Color3?,
}

local pool: { PoolEntry } = {}
local bands: { Band } = {}
local singleMode = false
-- Which activeBandIndex the current 2-slab window reflects (layer gate). The
-- window slides down when this diverges from LocalCakeField.ActiveBandIndex().
local renderedActiveIndex = 0

local worldX: { number } = {} -- local-space x per vertex (mesh space)
local worldZ: { number } = {}
local targetH: { number } = {} -- raw server-truth surface height (studs)
local displayH: { number } = {} -- raw displayed surface height (oozes to target)
local oozeRate: { number } = {} -- per-vertex 1/s lerp (surface layer's oozeSpeed)
local active: { [number]: boolean } = {} -- vertices still lerping
local isRing: { [number]: boolean } = {} -- no in-footprint cell in the 2x2 window
local ringCells: { [number]: { number }? } = {} -- ring vert -> nearby in-footprint cells
local ringDirty: { [number]: boolean } = {}
local squishOff: { [number]: number } = {} -- vi -> current dent offset (<= 0)
local squishBandIdx: { [number]: number } = {} -- which band the dent was written to
local wobbleCursor = 0
local wobbleBandIndices: { number } = {} -- band indices with layer.wobble

-- Footprint-hosted geometry (built once): cells with faces + their corners.
local hostedVertList: { number } = {} -- vi in AddVertex order (id map order)
local vertHosted: { [number]: boolean } = {}
local hostedCellList: { number } = {} -- 0-based cell indices with faces
local creationY: { number } = {} -- vi -> creation height (bounds trick)

-- Per-band texture caches: repaint a cell's pixel block only on transitions.
local crustState: { { [number]: boolean } } = {} -- bandIdx -> ci -> is crust
local palCache: { [number]: number } = {} -- single mode: ci -> palette index
local scratchImgBuf: buffer? = nil -- reused full-repaint pixel buffer

-- Surface-cover lookup for the eaten-through tuck (see bandYOf): sim band
-- tops + an override bottom when that layer is TRANSLUCENT (jelly) — tucked
-- sheets must sit below the see-through volume, not inside it.
local coverTops: { number } = {}
local coverBottoms: { [number]: number } = {}

local function surfaceCoverY(raw: number): number
	for k, top in ipairs(coverTops) do
		if raw <= top then
			return coverBottoms[k] or raw
		end
	end
	return raw
end

local rebuilding = false
local snapshotPending = false

local function vidx(vx: number, vz: number): number
	return vz * VSIZE + vx + 1 -- 1-based for Lua tables
end

-- Average of the adjacent IN-FOOTPRINT cells only. Boundary vertices thus
-- keep FULL cake height and the skirt drops straight down at the ring —
-- averaging in out-of-footprint zeros used to leave ragged floating spikes.
local function vertexTarget(vx: number, vz: number): number
	local sum, count = 0, 0
	for dz = -1, 0 do
		for dx = -1, 0 do
			local cx, cz = vx + dx, vz + dz
			if GridUtil.InBounds(SIZE, cx, cz) and GridUtil.InCake(SIZE, FOOTPRINT, cx, cz) then
				sum += fieldModule.ReadHeightStuds(GridUtil.Index(SIZE, cx, cz))
				count += 1
			end
		end
	end
	return if count > 0 then sum / count else 0
end

local function layerDefAt(hStuds: number)
	local meta = fieldModule.Meta()
	if not meta then
		return nil
	end
	for _, band in ipairs(meta.composition) do
		if hStuds <= band.top then
			return layersCfg[band.id]
		end
	end
	return layersCfg[meta.composition[#meta.composition].id]
end

local function oozeSpeedAt(hStuds: number): number
	local def = layerDefAt(hStuds)
	return (def and def.oozeSpeed) or renderCfg.lerpSpeed
end

-- Visual band that owns the surface at this height.
local function surfaceBandIndexAt(hStuds: number): number
	for bi, band in ipairs(bands) do
		if hStuds <= band.top then
			return bi
		end
	end
	return #bands -- spawn noise sits above the top band
end

-- The band projection rule (see file header). Eaten-through columns TUCK
-- the band's sheet `band.sink` studs under the local surface cover — a
-- FixedSize mesh can't delete faces and dropping to 0 hung tall curtain
-- quads through lower layers on side cuts.
local function bandYOf(band: Band, vi: number): number
	if isRing[vi] then
		local cells = ringCells[vi]
		if cells == nil then
			return 0
		end
		local maxH = 0
		for _, ci in ipairs(cells) do
			local h = fieldModule.ReadHeightStuds(ci)
			if h > maxH then
				maxH = h
			end
		end
		if maxH > band.bottom + EPS then
			return band.bottom -- skirt seal: outer wall shows stacked bands
		end
		return math.max(0, surfaceCoverY(maxH) - band.sink)
	end
	local raw = displayH[vi]
	if raw > band.bottom + EPS then
		return math.min(raw, band.top)
	end
	return math.max(0, surfaceCoverY(raw) - band.sink)
end

-- Normal-only refresh for one vertex of one band, from the BAND's own
-- neighbor heights (clamped slab walls shade correctly). Split from
-- bandWrite so stale-neighbor refreshes never touch squish/wobble offsets.
local function bandNormalOnly(band: Band, vi: number)
	local pe = pool[band.poolIdx]
	local nid = pe.normalIds[vi]
	if nid == nil then
		return
	end
	local y = pe.y
	local vx = (vi - 1) % VSIZE
	local vz = (vi - 1) // VSIZE
	local hl = y[vidx(math.max(0, vx - 1), vz)]
	local hr = y[vidx(math.min(VSIZE - 1, vx + 1), vz)]
	local ht = y[vidx(vx, math.max(0, vz - 1))]
	local hb = y[vidx(vx, math.min(VSIZE - 1, vz + 1))]
	pe.em:SetNormal(nid, Vector3.new(hl - hr, 2 * CELL, ht - hb).Unit)
end

-- Position + normal write for one vertex of one band.
local function bandWrite(band: Band, vi: number)
	local pe = pool[band.poolIdx]
	local vid = pe.vertIds[vi]
	if vid == nil then
		return -- not a hosted vertex (belt & suspenders)
	end
	pe.em:SetPosition(vid, Vector3.new(worldX[vi], pe.y[vi], worldZ[vi]))
	bandNormalOnly(band, vi)
end

-- Vertices projectVertex wrote this frame — their UNMOVED neighbors need a
-- normal-only refresh (their shading still assumes the pre-bite slope).
local movedVerts: { [number]: boolean } = {}
local refreshedNeighbors: { [number]: boolean } = {} -- per-frame dedup

-- Project one vertex into every band; write only real moves.
local function projectVertex(vi: number)
	for _, band in ipairs(bands) do
		local pe = pool[band.poolIdx]
		local ny = bandYOf(band, vi)
		if math.abs(ny - pe.y[vi]) > 0.004 then
			pe.y[vi] = ny
			bandWrite(band, vi)
			movedVerts[vi] = true
		end
	end
end

-- Static vertex layout, ring classification and the hosted set. No meshes
-- are created here — the pool grows lazily per composition (ensurePool).
local function buildStaticLayout()
	local half = SIZE / 2
	for vz = 0, VSIZE - 1 do
		for vx = 0, VSIZE - 1 do
			local vi = vidx(vx, vz)
			worldX[vi] = (vx - half) * CELL
			worldZ[vi] = (vz - half) * CELL
			targetH[vi] = 0
			displayH[vi] = 0
			oozeRate[vi] = renderCfg.lerpSpeed
			creationY[vi] = 0
			local inFootprint = false
			for dz = -1, 0 do
				for dx = -1, 0 do
					local cx, cz = vx + dx, vz + dz
					if GridUtil.InBounds(SIZE, cx, cz) and GridUtil.InCake(SIZE, FOOTPRINT, cx, cz) then
						inFootprint = true
					end
				end
			end
			isRing[vi] = not inFootprint
			if not inFootprint then
				-- Nearby in-footprint cells (4x4 window) — the skirt seal
				-- reads their heights to decide bottom vs dropped.
				local cells = {}
				for dz = -2, 1 do
					for dx = -2, 1 do
						local cx, cz = vx + dx, vz + dz
						if GridUtil.InBounds(SIZE, cx, cz) and GridUtil.InCake(SIZE, FOOTPRINT, cx, cz) then
							table.insert(cells, GridUtil.Index(SIZE, cx, cz))
						end
					end
				end
				ringCells[vi] = if #cells > 0 then cells else nil
			end
		end
	end
	-- Hosted cells + their corner vertices (everything else never gets a
	-- mesh vertex — unreferenced verts only burn budget).
	local hostedCellSet: { [number]: boolean } = {}
	for cz = 0, SIZE - 1 do
		for cx = 0, SIZE - 1 do
			if cellHostsFaces(cx, cz) then
				local ci = GridUtil.Index(SIZE, cx, cz)
				hostedCellSet[ci] = true
				table.insert(hostedCellList, ci)
				for dz = 0, 1 do
					for dx = 0, 1 do
						local vi = vidx(cx + dx, cz + dz)
						if not vertHosted[vi] then
							vertHosted[vi] = true
							table.insert(hostedVertList, vi)
							-- Bounds trick: create at max height so render
							-- bounds cover every future height (culling uses
							-- CREATION-time geometry).
							creationY[vi] = gridCfg.maxHeight
						end
					end
				end
			end
		end
	end
	-- Smooth loaf outline: the discrete footprint STAIRCASE pleats the
	-- skirt at the rounded corners (accordion look). Ring verts and partial
	-- boundary verts are projected horizontally onto the ANALYTIC rounded
	-- rect expanded by half a cell — straight edges land exactly on the
	-- collision-cell boundary, corner arcs become smooth, and the outer
	-- ring collapses onto the outline (degenerate outside quads vanish).
	-- Render-only: heights/collision keep the cell staircase (<1 cell off
	-- at corner arcs).
	local cornerR = (FOOTPRINT.corner + 0.5) * CELL
	local rectX = (FOOTPRINT.hx + 0.5) * CELL - cornerR
	local rectZ = (FOOTPRINT.hz + 0.5) * CELL - cornerR
	for _, vi in ipairs(hostedVertList) do
		local partial = isRing[vi]
		if not partial then
			local vx = (vi - 1) % VSIZE
			local vz = (vi - 1) // VSIZE
			for dz = -1, 0 do
				for dx = -1, 0 do
					local cx, cz = vx + dx, vz + dz
					if not (GridUtil.InBounds(SIZE, cx, cz) and GridUtil.InCake(SIZE, FOOTPRINT, cx, cz)) then
						partial = true
					end
				end
			end
		end
		if partial then
			local x, z = worldX[vi], worldZ[vi]
			local qx = math.clamp(x, -rectX, rectX)
			local qz = math.clamp(z, -rectZ, rectZ)
			local dx, dz = x - qx, z - qz
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist > 1e-3 then
				worldX[vi] = qx + dx / dist * cornerR
				worldZ[vi] = qz + dz / dist * cornerR
			end
		end
	end
end

-- Grows the pool to `want` slabs (≤ MAX_LAYER_MESHES) by cloning ONE
-- temporary dynamic scratch mesh into FixedSize meshes. Returns the pool
-- size actually reached — the caller degrades when it falls short.
local function ensurePool(want: number): number
	if want > MAX_LAYER_MESHES then
		Log.Warn("CakeRenderer", `composition wants {want} slabs > MAX_LAYER_MESHES {MAX_LAYER_MESHES} — raise the cap`)
		want = MAX_LAYER_MESHES
	end
	if #pool >= want then
		return #pool
	end
	local startedAt = os.clock()

	-- 1. The dynamic scratch: worst-case budget reservation, alive only for
	-- the duration of this grow. Returns NIL (no throw) when over budget.
	local scratch: EditableMesh? = nil
	pcall(function()
		scratch = AssetService:CreateEditableMesh()
	end)
	if scratch == nil then
		Log.Once("CakeRenderer", "scratch-budget", `EditableMesh memory budget exhausted — cannot build slab meshes (pool at {#pool})`)
		return #pool
	end

	local vertIds: { number } = {}
	local uvIds: { number } = {}
	local normalIds: { number } = {}
	local okBuild, errBuild = pcall(function()
		local em = scratch :: EditableMesh
		for _, vi in ipairs(hostedVertList) do
			vertIds[vi] = em:AddVertex(Vector3.new(worldX[vi], creationY[vi], worldZ[vi]))
			-- STATIC planar UVs (map XZ over the grid), TILED LAYER_TEX_TILES× so layer
				-- textures read SHARP instead of stretched-once (Req 2).
			local vx = (vi - 1) % VSIZE
			local vz = (vi - 1) // VSIZE
			uvIds[vi] = em:AddUV(Vector2.new(vx / SIZE * LAYER_TEX_TILES, vz / SIZE * LAYER_TEX_TILES))
			normalIds[vi] = em:AddNormal(Vector3.yAxis)
		end
		for _, ci in ipairs(hostedCellList) do
			local cx, cz = GridUtil.Coords(SIZE, ci)
			local i00, i01, i10, i11 = vidx(cx, cz), vidx(cx, cz + 1), vidx(cx + 1, cz), vidx(cx + 1, cz + 1)
			local f1 = em:AddTriangle(vertIds[i00], vertIds[i01], vertIds[i10])
			local f2 = em:AddTriangle(vertIds[i10], vertIds[i01], vertIds[i11])
			em:SetFaceUVs(f1, { uvIds[i00], uvIds[i01], uvIds[i10] })
			em:SetFaceUVs(f2, { uvIds[i10], uvIds[i01], uvIds[i11] })
			em:SetFaceNormals(f1, { normalIds[i00], normalIds[i01], normalIds[i10] })
			em:SetFaceNormals(f2, { normalIds[i10], normalIds[i01], normalIds[i11] })
		end
	end)
	if not okBuild then
		Log.Warn("CakeRenderer", `scratch mesh build failed ({errBuild}) — pool stays at {#pool}`)
		scratch:Destroy()
		return #pool
	end

	-- 2. FixedSize clones (cost = actual complexity) + their MeshParts.
	-- Probe-verified: the source's vertex/normal ids remain valid on every
	-- clone, so the id tables above serve all slabs from this scratch.
	while #pool < want do
		local pi = #pool + 1
		local fixed: EditableMesh? = nil
		pcall(function()
			fixed = AssetService:CreateEditableMeshAsync(Content.fromObject(scratch :: EditableMesh), { FixedSize = true })
		end)
		if fixed == nil then
			Log.Once("CakeRenderer", "clone-budget", `EditableMesh budget hit at slab {pi}/{want} — degrading (see next warn)`)
			break
		end
		local part: MeshPart? = nil
		local okPart, errPart = pcall(function()
			-- RenderFidelity = Precise: Automatic swaps in LODs generated
			-- from stale creation-time content; Precise renders live edits.
			part = AssetService:CreateMeshPartAsync(
				Content.fromObject(fixed :: EditableMesh),
				{ RenderFidelity = Enum.RenderFidelity.Precise }
			)
		end)
		if not okPart or part == nil then
			Log.Once("CakeRenderer", "part-budget", `CreateMeshPartAsync failed at slab {pi}/{want} ({errPart}) — degrading`);
			(fixed :: EditableMesh):Destroy()
			break
		end
		local p = part :: MeshPart
		p.Name = `CakeLayer{pi}`
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false -- GDD §4.5
		p.Material = Enum.Material.SmoothPlastic
		p.Color = WHITE
		-- Both sides render: steep skirt/crater quads flip facing depending
		-- on which neighbor dropped; single-sided walls vanished at angles.
		p.DoubleSided = true
		-- Verified live: vertices render at RAW mesh coordinates relative
		-- to part.CFrame (no bbox recentering) — mesh y=0 = part Y.
		p.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y, gridCfg.origin.z)
		p.Transparency = 1 -- hidden until a snapshot assigns bands
		p.Parent = workspace
		pool[pi] = {
			em = fixed :: EditableMesh,
			part = p,
			image = nil,
			imageFailed = nil,
			vertIds = vertIds,
			uvIds = uvIds,
			normalIds = normalIds,
			y = table.clone(creationY),
		}
	end

	-- 3. The scratch's worst-case reservation is freed; clones stay alive.
	scratch:Destroy()
	Log.Info("CakeRenderer", `slab pool: {#pool}/{want} FixedSize meshes ({#hostedVertList} verts each) in {math.floor((os.clock() - startedAt) * 1000)} ms`)
	return #pool
end

-- Lazily creates a pool entry's texture. CreateEditableImage returns NIL
-- on budget exhaustion (no throw) — nil-check, never trust pcall alone.
local function ensureImage(pe: PoolEntry): EditableImage?
	if pe.image ~= nil then
		return pe.image
	end
	if pe.imageFailed then
		return nil
	end
	local img: EditableImage? = nil
	pcall(function()
		img = AssetService:CreateEditableImage({
			Size = Vector2.new(crustCfg.imageSize, crustCfg.imageSize),
		})
	end)
	if img == nil then
		pe.imageFailed = true
		Log.Once("CakeRenderer", "image-budget", "EditableImage budget exhausted — layer renders solid color, no crust texture / cracks")
		return nil
	end
	pe.image = img
	return img
end

-- Shared base-film mottle so every path that repaints a crust cell (the full
-- band paint AND the fracture groove) uses the identical noise — a divergence
-- would leave a silent seam where a groove heals.
local function filmNoiseAt(px: number, pz: number): number
	return math.noise(px * 0.15, pz * 0.15) * crustCfg.noise
end

-- Pixel block of one cell inside the XZ-planar texture.
local function cellPixelRect(ci: number): (number, number, number, number)
	local sizePx = crustCfg.imageSize
	local cx, cz = GridUtil.Coords(SIZE, ci)
	local px0 = cx * sizePx // SIZE
	local pz0 = cz * sizePx // SIZE
	local px1 = (cx + 1) * sizePx // SIZE
	local pz1 = (cz + 1) * sizePx // SIZE
	return px0, pz0, px1 - px0, pz1 - pz0
end

-- Full texture repaint for one band + reset of its transition cache.
-- Multi mode: crust fill (mottled) where the cell surface is within
-- crust.depth of the band top, flat body color below. Single mode: the
-- whole height palette per cell (crust lightening is baked into it).
local function paintBandImage(bandIdx: number)
	local band = bands[bandIdx]
	if band.layerId == "core" then
		return -- inedible floor: solid color part, no texture wanted
	end
	local pe = pool[band.poolIdx]
	-- Only single (palette) mode creates an image; multi-band pe.image is nil
	-- (flat body Color, no texture) — the guard below makes this a no-op then.
	local img = if pe.imageFailed then nil else pe.image
	if img == nil then
		return
	end
	local sizePx = crustCfg.imageSize
	if scratchImgBuf == nil then
		scratchImgBuf = buffer.create(sizePx * sizePx * 4)
	end
	local buf = scratchImgBuf :: buffer

	-- Per-cell colors first (0-based ci -> 1-based arrays).
	local cellR: { number } = table.create(SIZE * SIZE, 0)
	local cellG: { number } = table.create(SIZE * SIZE, 0)
	local cellB: { number } = table.create(SIZE * SIZE, 0)
	local cellNoise: { boolean } = table.create(SIZE * SIZE, false)
	if band.single then
		table.clear(palCache)
	else
		crustState[bandIdx] = {}
	end
	local state = crustState[bandIdx]
	for ci = 0, SIZE * SIZE - 1 do
		local h = fieldModule.ReadHeightStuds(ci)
		local color
		if band.single then
			local idx = paletteIndex(h)
			palCache[ci] = idx
			color = palette[idx] or WHITE
		else
			-- The slabs render the layer BODY (darker) everywhere: the pale
			-- CRUST look is now the always-visible CakeWaxShell riding on top, so
			-- where its plates crack the darker body shows in the gaps.
			state[ci] = h > band.top - crustCfg.depth
			color = band.bodyColor
			cellNoise[ci + 1] = false
		end
		cellR[ci + 1] = color.R
		cellG[ci + 1] = color.G
		cellB[ci + 1] = color.B
	end

	for pz = 0, sizePx - 1 do
		local czBase = (pz * SIZE // sizePx) * SIZE
		local rowBase = pz * sizePx
		for px = 0, sizePx - 1 do
			local c = czBase + (px * SIZE // sizePx) + 1
			local n = if cellNoise[c] then filmNoiseAt(px, pz) else 0
			local o = (rowBase + px) * 4
			buffer.writeu8(buf, o, math.clamp(math.floor((cellR[c] + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 1, math.clamp(math.floor((cellG[c] + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 2, math.clamp(math.floor((cellB[c] + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(sizePx, sizePx), buf)
end

-- Cell changed: repaint its pixel block in every band whose look flips
-- (wax eaten through -> body; single mode: palette step crossed). The
-- Overwrite also erases any open crack on the eaten cell — intended.
local function updateCellPixels(ci: number)
	for bi, band in ipairs(bands) do
		local pe = pool[band.poolIdx]
		local img = pe.image
		if img == nil then
			continue
		end
		local h = fieldModule.ReadHeightStuds(ci)
		if band.single then
			local idx = paletteIndex(h)
			if palCache[ci] ~= idx then
				palCache[ci] = idx
				local px, pz, w, hh = cellPixelRect(ci)
				img:DrawRectangle(Vector2.new(px, pz), Vector2.new(w, hh), palette[idx] or WHITE, 0, Enum.ImageCombineType.Overwrite)
			end
		else
			local isCrust = h > band.top - crustCfg.depth
			local state = crustState[bi]
			if state ~= nil and state[ci] ~= isCrust then
				state[ci] = isCrust
				local px, pz, w, hh = cellPixelRect(ci)
				local color = band.bodyColor -- slab is body; crust is the CakeWaxShell on top
				img:DrawRectangle(Vector2.new(px, pz), Vector2.new(w, hh), color :: Color3, 0, Enum.ImageCombineType.Overwrite)
			end
		end
	end
end

-- ── Soft butter squish (the mesh dents; the wax web is CakeWaxShell) ────
-- Per-vertex downward offset of the soft squish under the foot: a round dent,
-- deepest at the foot (`-sinkDepth·falloff`), zero at the rim. Returns nil
-- outside the zone or on a rock layer (squishMult 0). `fx,fz` = foot in
-- grid-vertex coords; `depthMult` deepens a landing dent.
local function fractureOffsetAt(vi: number, fx: number, fz: number, radius: number, depthMult: number): number?
	local vx = (vi - 1) % VSIZE
	local vz = (vi - 1) // VSIZE
	local dx, dz = (vx - fx) * CELL, (vz - fz) * CELL
	local distSq = dx * dx + dz * dz
	if distSq >= radius * radius then
		return nil
	end
	local def = layerDefAt(displayH[vi])
	if def == nil or (def.squishMult or 0) <= 0 then
		return nil -- rock crust (chocolate): doesn't squish
	end
	local w = 1 - distSq / (radius * radius) -- 1 at the foot, 0 at the rim
	return -fractureCfg.sinkDepth * depthMult * w * w -- round soft dent
end

-- The rendered window: the active (top edible) band + the one directly BELOW it,
-- bottom-up — so both the CURRENT and the NEXT layer are visible (the next layer
-- shows through craters cleared to the active floor). The textured CakeWrapper
-- wall covers the cake below the NEXT band. Near the core there is only one band.
local function windowFor(activeIndex: number, topCount: number): { number }
	activeIndex = math.clamp(activeIndex, 1, math.max(1, topCount))
	if activeIndex <= 1 then
		return { 1 }
	end
	return { activeIndex - 1, activeIndex }
end

-- Assigns pooled slabs to ONLY the windowed sim bands (`windowIdx`, bottom-up)
-- and dresses the parts. The perf win: 2 slabs instead of N, so more / taller
-- layers no longer grow the vertex budget. coverTops/coverBottoms stay built
-- from the FULL composition (the eaten-through tuck needs every band's top).
-- Grows the pool lazily on the FIRST call (may YIELD; later window shifts reuse
-- it — no yield). Returns desired transparencies (applied AFTER geometry is
-- written — no flash of stale slabs), or nil when not even one slab exists.
local function assignWindowBands(meta, windowIdx: { number }): { number }?
	table.clear(bands)
	table.clear(wobbleBandIndices)
	table.clear(crustState)
	-- Surface-cover lookup for the eaten-through tuck: translucent layers
	-- (jelly) hide tucked sheets below their BOTTOM, opaque ones just under
	-- the surface. Built from ALL bands, not just the windowed ones.
	table.clear(coverTops)
	table.clear(coverBottoms)
	for k, simBand in ipairs(meta.composition) do
		coverTops[k] = simBand.top
		local layerDef = layersCfg[simBand.id]
		if (layerDef.transparency or 0) > 0 then
			coverBottoms[k] = simBand.bottom
		end
	end
	local topStuds = meta.composition[#meta.composition].top
	local want = #windowIdx
	local have = ensurePool(want)
	if have == 0 then
		return nil
	end
	singleMode = have < want
	local transparencies = {}
	if singleMode then
		-- Budget ladder step 2: ONE flat-colored slab renders the WHOLE cake (the
		-- tiled layer UVs rule out a per-cell palette image). It seals the sides
		-- down to the floor, so the CakeWrapper behind it is occluded — no double wall.
		Log.Once("CakeRenderer", "single-mode", `budget allows {have}/{want} slabs — single flat-color mesh mode (no per-layer materials)`)
		bands[1] = { layerId = "palette", bottom = 0, top = topStuds, poolIdx = 1, sink = renderCfg.hideSink.base, single = true }
		local pe = pool[1]
		local part = pe.part
		part.Name = "CakeLayer1_palette"
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.1
		-- Flat tinted color, NOT a per-cell palette image: the slab UVs are now
		-- TILED for the layer textures (LAYER_TEX_TILES), which would repeat a
		-- palette image wrongly. Single mode is a rare weak-device fallback, so a
		-- flat slab is an acceptable further degradation.
		part.TextureContent = Content.none
		part.Color = tinted(layersCfg.frosting.colors.top, meta.rareKind, topStuds, topStuds)
		transparencies[1] = 0
	else
		for wi, simIdx in ipairs(windowIdx) do
			local simBand = meta.composition[simIdx]
			local layerDef = layersCfg[simBand.id]
			local hMid = (simBand.bottom + simBand.top) * 0.5
			local bodyColor = tinted(layerDef.colors.bottom:Lerp(layerDef.colors.top, 0.55), meta.rareKind, hMid, topStuds)
			local band: Band = {
				layerId = simBand.id,
				bottom = simBand.bottom,
				top = simBand.top,
				poolIdx = wi,
				sink = renderCfg.hideSink.base + renderCfg.hideSink.perBand * simIdx,
				bodyColor = bodyColor,
			}
			bands[wi] = band
			local pe = pool[wi]
			local part = pe.part
			part.Name = `CakeLayer{wi}_{simBand.id}`
			part.Material = layerDef.material or Enum.Material.SmoothPlastic
			part.Reflectance = layerDef.gloss or 0
			-- The ACTIVE (topmost windowed) band keeps its real transparency —
			-- see-through jelly shows the opaque band rendered directly below it. A
			-- LOWER window band is the solid FLOOR with NOTHING rendered behind it
			-- (only the perimeter CakeWrapper), so force it OPAQUE: a translucent
			-- lower band (jelly under the active layer) would otherwise reveal the
			-- ungenerated hollow interior through the crater floor.
			transparencies[wi] = if wi == #windowIdx then (layerDef.transparency or 0) else 0
			-- Task 3: a textured layer (frosting/chocolate/filling) shows its photo
			-- mapped over the top surface (the slab's planar XZ UVs, TILED
			-- LAYER_TEX_TILES× so it reads sharp — Req); others keep the flat body Color
			-- as before. Affordable: only 2 slabs, a static texture REFERENCE (no
			-- per-cell EditableImage paint — the mobile trap that got per-band cut).
			-- ⚠ Tiling UVs + Content.fromUri on a FixedSize mesh is the same path the
			-- WALL abandoned (it showed no texture) — VERIFY it displays in Studio.
			if layerDef.texture then
				part.TextureContent = Content.fromUri(layerDef.texture)
				part.Color = WHITE
			else
				part.TextureContent = Content.none
				part.Color = bodyColor
			end
			if layerDef.wobble then
				table.insert(wobbleBandIndices, wi)
			end
		end
	end
	-- Park leftover pool parts.
	for pi = #bands + 1, #pool do
		pool[pi].part.Transparency = 1
		pool[pi].part.Name = `CakeLayer{pi}_idle`
	end
	return transparencies
end

-- Two-pass slab write for the current `bands` (heights first, then writes —
-- normals read NEIGHBOR heights; a single interleaved pass bakes sideways
-- normals), then paint + transparencies + squish restore. Shared by a full
-- rebuild and a lightweight window shift.
local function writeBandsGeometry(transparencies: { number })
	for _, band in ipairs(bands) do
		local pe = pool[band.poolIdx]
		local newY = table.create(VSIZE * VSIZE, 0)
		for _, vi in ipairs(hostedVertList) do
			newY[vi] = bandYOf(band, vi)
		end
		local oldY = pe.y
		pe.y = newY
		for _, vi in ipairs(hostedVertList) do
			if math.abs(newY[vi] - oldY[vi]) > 0.004 then
				bandWrite(band, vi)
			end
		end
	end
	for bi in ipairs(bands) do
		paintBandImage(bi)
	end
	for bi, band in ipairs(bands) do
		pool[band.poolIdx].part.Transparency = transparencies[bi] or 0
	end
	-- Squish offsets were written straight into the meshes without touching
	-- pe.y — the diff above skips any dented vertex whose band height didn't
	-- change, so force-restore them before dropping the dent state.
	for vi in pairs(squishOff) do
		for _, band in ipairs(bands) do
			bandWrite(band, vi)
		end
	end
	table.clear(active)
	table.clear(squishOff)
	table.clear(squishBandIdx)
	table.clear(ringDirty)
	table.clear(movedVerts)
end

local function editableRebuild()
	buildPalette()
	local meta = fieldModule.Meta()
	if not meta then
		return
	end
	local startedAt = os.clock()
	local activeIndex = fieldModule.ActiveBandIndex()
	-- may yield on the FIRST call (mesh-pool creation)
	local transparencies = assignWindowBands(meta, windowFor(activeIndex, #meta.composition))
	if transparencies == nil then
		-- Budget ladder step 3: no EditableMesh at all — the collision
		-- columns become the visible keycap grid.
		impl = "parts"
		visualColumns = true
		Log.Warn("CakeRenderer", "no EditableMesh budget — falling back to visible part grid")
		return
	end
	for _, vi in ipairs(hostedVertList) do
		local vx = (vi - 1) % VSIZE
		local vz = (vi - 1) // VSIZE
		targetH[vi] = vertexTarget(vx, vz)
		displayH[vi] = targetH[vi]
		oozeRate[vi] = oozeSpeedAt(targetH[vi])
	end
	writeBandsGeometry(transparencies)
	renderedActiveIndex = activeIndex
	Log.Info("CakeRenderer", `bands rebuilt — {#bands} slabs (window @active #{activeIndex} of {#meta.composition} layers{if singleMode then ", palette mode" else ""}) in {math.floor((os.clock() - startedAt) * 1000)} ms`)
end

-- Layer gate advanced (a layer finished): slide the rendered window DOWN one
-- band. Re-dresses the 2 pooled slabs and re-clamps them to the LIVE surface —
-- no mesh creation, no surface re-init (displayH is the live oozing surface),
-- so it's cheap and fires only once per layer. Called from editableStep when
-- LocalCakeField.ActiveBandIndex() diverges from renderedActiveIndex.
local function rewindow(activeIndex: number)
	local meta = fieldModule.Meta()
	if not meta then
		return
	end
	local transparencies = assignWindowBands(meta, windowFor(activeIndex, #meta.composition))
	if transparencies == nil then
		-- Unreachable once the pool exists (#pool ≥ 2 → ensurePool never returns 0),
		-- but never fail silently (R8): keep the current slabs, warn once.
		Log.Once("CakeRenderer", "rewindow-nobudget", `rewindow to active #{activeIndex} got no slab budget — keeping the current window`)
		return
	end
	writeBandsGeometry(transparencies)
	renderedActiveIndex = activeIndex
	local idx = math.clamp(activeIndex, 1, #meta.composition)
	Log.Info("CakeRenderer", `layer window -> active #{activeIndex} '{meta.composition[idx].id}'`)
end

local function editableStep(dt: number, footPos: Vector3?, overCakePos: Vector3?)
	if #bands == 0 then
		return
	end
	-- Layer gate advanced (a layer finished, activeBandIndex dropped) → slide the
	-- rendered 2-slab window DOWN. Cheap (2-slab re-dress, no mesh creation);
	-- fires once per layer. Skipped in single-palette mode (one slab = whole cake).
	if not singleMode then
		local activeIndex = fieldModule.ActiveBandIndex()
		if activeIndex >= 1 and activeIndex ~= renderedActiveIndex then
			rewindow(activeIndex)
		end
	end
	-- 1. Changed cells -> corner vertices get fresh targets + texture block
	-- updates; the invisible collision columns snap to server truth on the
	-- same drained list.
	local drained = fieldModule.DrainChanged()
	-- Collision follows the player (radius-limited, Task 2 perf) — resizing every
	-- oozing column across the cake spiked physics. The mesh below still uses
	-- `drained` to update the VISUAL surface everywhere (cheap Luau, no physics).
	-- Centred on `overCakePos` (the player's XZ over the loaf at ANY depth), NOT
	-- `footPos` (which is nil when BURIED, ΔY≥tolerance) — otherwise a buried
	-- player's columns would freeze and never rise back (Task 2 review fix).
	updateCollisionNearPlayer(dt, overCakePos)
	for _, i in ipairs(drained) do
		updateCellPixels(i)
		local cx, cz = GridUtil.Coords(SIZE, i)
		for dz = -1, 2 do
			for dx = -1, 2 do
				local vx, vz = cx + dx, cz + dz
				if vx >= 0 and vz >= 0 and vx < VSIZE and vz < VSIZE then
					local vi = vidx(vx, vz)
					if dx >= 0 and dx <= 1 and dz >= 0 and dz <= 1 then
						local newTarget = vertexTarget(vx, vz)
						targetH[vi] = newTarget
						oozeRate[vi] = oozeSpeedAt(newTarget)
						-- BITE FEEL: a big DROP is a chunk ripped out — snap.
						if displayH[vi] - newTarget > renderCfg.snapDropStuds then
							displayH[vi] = newTarget
						end
						active[vi] = true
					elseif isRing[vi] and ringCells[vi] ~= nil then
						-- Rim change: the skirt seal re-reads its neighborhood.
						ringDirty[vi] = true
					end
				end
			end
		end
	end
	for vi in pairs(ringDirty) do
		projectVertex(vi)
	end
	table.clear(ringDirty)

	-- 2. Ooze actives toward targets at the SURFACE LAYER's speed (honey
	-- creep vs pouring cotton), then project into every band slab.
	for vi in pairs(active) do
		local d = targetH[vi] - displayH[vi]
		if math.abs(d) < 0.005 then
			displayH[vi] = targetH[vi]
			active[vi] = nil
		else
			displayH[vi] += d * math.min(1, oozeRate[vi] * dt)
		end
		projectVertex(vi)
	end

	-- 2b. Crater-rim shading: neighbors of moved vertices didn't move, so
	-- their normals still assume the old slope — refresh normals only.
	if next(movedVerts) ~= nil then
		for vi in pairs(movedVerts) do
			local vx = (vi - 1) % VSIZE
			local vz = (vi - 1) // VSIZE
			for n = 1, 4 do
				local nx, nz
				if n == 1 then
					nx, nz = vx - 1, vz
				elseif n == 2 then
					nx, nz = vx + 1, vz
				elseif n == 3 then
					nx, nz = vx, vz - 1
				else
					nx, nz = vx, vz + 1
				end
				if nx >= 0 and nz >= 0 and nx < VSIZE and nz < VSIZE then
					local nvi = vidx(nx, nz)
					if vertHosted[nvi] and not movedVerts[nvi] and not refreshedNeighbors[nvi] then
						refreshedNeighbors[nvi] = true
						for _, band in ipairs(bands) do
							bandNormalOnly(band, nvi)
						end
					end
				end
			end
		end
		table.clear(movedVerts)
		table.clear(refreshedNeighbors)
	end

	-- 3. Butter-slab FRACTURE buckle (§7.2): the crust caves + breaks under
	-- the foot (signed per-vertex offsets — sink at the center, ridges along
	-- the cracks; see fractureOffsetAt). Reverting, visual only; rock layers
	-- (squishMult 0) don't buckle.
	local frac = fractureCfg
	local footVerts: { [number]: number } = {}
	if footPos then
		local fx = (footPos.X - gridCfg.origin.x) / CELL + SIZE / 2
		local fz = (footPos.Z - gridCfg.origin.z) / CELL + SIZE / 2
		local r = math.ceil(frac.radius / CELL)
		for vz = math.floor(fz) - r, math.floor(fz) + r do
			for vx = math.floor(fx) - r, math.floor(fx) + r do
				if vx >= 0 and vz >= 0 and vx < VSIZE and vz < VSIZE then
					local vi = vidx(vx, vz)
					local off = fractureOffsetAt(vi, fx, fz, frac.radius, 1)
					if off ~= nil then
						footVerts[vi] = off
					end
				end
			end
		end
	end
	-- Springy butter: quick press-IN, satisfying spring-BACK (fps-independent).
	local up = 1 - math.exp(-dt * frac.riseRate)
	local down = 1 - math.exp(-dt * frac.healRate)
	local function writeSquish(vi: number)
		local bi = surfaceBandIndexAt(displayH[vi])
		local prev = squishBandIdx[vi]
		if prev and prev ~= bi and bands[prev] then
			bandWrite(bands[prev], vi) -- restore the band the offset left
		end
		squishBandIdx[vi] = bi
		local band = bands[bi]
		if band == nil then
			return
		end
		local pe = pool[band.poolIdx]
		local vid = pe.vertIds[vi]
		if vid == nil then
			return
		end
		-- displayH just above band.bottom (within EPS) means the band's own
		-- sheet is DROPPED here (pe.y = 0) — offsetting it would teleport the
		-- vertex up to band.bottom and spike a quad tens of studs tall.
		if pe.y[vi] <= band.bottom + EPS then
			return
		end
		-- Sink-only offset (≤ 0), clamped at the band floor.
		local y = math.max(pe.y[vi] + (squishOff[vi] or 0), band.bottom + 0.05)
		pe.em:SetPosition(vid, Vector3.new(worldX[vi], y, worldZ[vi]))
	end
	for vi, current in pairs(squishOff) do
		local target = footVerts[vi] or 0
		footVerts[vi] = nil
		-- Approach the buckle at riseRate while under the foot, spring back at
		-- healRate once it leaves (target 0).
		local rate = if target ~= 0 then up else down
		local new = current + (target - current) * rate
		if math.abs(new) < 0.02 and target == 0 then
			squishOff[vi] = nil
			local bi = squishBandIdx[vi]
			squishBandIdx[vi] = nil
			if bi and bands[bi] then
				bandWrite(bands[bi], vi) -- clean restore
			end
		else
			squishOff[vi] = new
			writeSquish(vi)
		end
	end
	for vi, target in pairs(footVerts) do
		squishOff[vi] = target * up -- newly pressed vertex: start easing in
		writeSquish(vi)
	end

	-- 4. Jelly wobble: NEGATIVE-only sine (dips, never pokes above the band
	-- top into the crust), rotating vertex slice per frame (§5). Multi-band
	-- mode only — the single palette slab has no jelly-owned vertices.
	if not singleMode and #wobbleBandIndices > 0 then
		local total = VSIZE * VSIZE
		local sliceLen = total // renderCfg.wobbleSliceDiv
		for _ = 1, sliceLen do
			wobbleCursor = wobbleCursor % total + 1
			local vi = wobbleCursor
			if not active[vi] and squishOff[vi] == nil and not isRing[vi] then
				for _, bi in ipairs(wobbleBandIndices) do
					local band = bands[bi]
					local pe = pool[band.poolIdx]
					local vid = pe.vertIds[vi]
					local base = pe.y[vi]
					if vid ~= nil and base > band.bottom + 0.1 then
						local vx = (vi - 1) % VSIZE
						local vz = (vi - 1) // VSIZE
						local offset = (math.sin(clock * renderCfg.wobbleSpeed + (vx + vz) * 0.7) - 1)
							* renderCfg.wobbleAmp
						local y = math.max(base + offset, band.bottom + 0.05)
						pe.em:SetPosition(vid, Vector3.new(worldX[vi], y, worldZ[vi]))
					end
				end
			end
		end
	end

end

-- ── Butter squish: landing stomp ────────────────────────────────────────

--API
-- A hard landing STOMPS a deeper, wider squish dent around a world position
-- (seeded into squishOff, eased back by the squish loop's spring). Returns true
-- when the surface there really is crust — the caller gates the crunch
-- SFX/particles/ceremony (the wax web that cracks is CakeWaxShell).
function CakeRenderer.CrackAt(pos: Vector3, kind: string): boolean
	if impl ~= "editable" or #bands == 0 or singleMode then
		return false -- the crust deform needs the slab meshes (multi-band)
	end
	local h = fieldModule.SurfaceHeightAt(pos.X, pos.Z)
	if h == nil then
		return false
	end
	local bi = surfaceBandIndexAt(h)
	local band = bands[bi]
	if band == nil or band.layerId == "core" or h <= band.top - crustCfg.depth then
		return false -- surface is layer body, not crust
	end
	-- Deeper geometry stomp: seed squishOff on the surface vertices around the
	-- impact (the squish loop eases it back to the standing press / 0).
	local fx = (pos.X - gridCfg.origin.x) / CELL + SIZE / 2
	local fz = (pos.Z - gridCfg.origin.z) / CELL + SIZE / 2
	local sRad = fractureCfg.landRadius
	local sVerts = math.ceil(sRad / CELL)
	for vz = math.floor(fz) - sVerts, math.floor(fz) + sVerts do
		for vx = math.floor(fx) - sVerts, math.floor(fx) + sVerts do
			if vx >= 0 and vz >= 0 and vx < VSIZE and vz < VSIZE then
				local vi = vidx(vx, vz)
				local off = fractureOffsetAt(vi, fx, fz, sRad, fractureCfg.landDepthMult)
				if off ~= nil then
					local cur = squishOff[vi] or 0
					squishOff[vi] = if off < cur then off else cur
				end
			end
		end
	end
	return true
end

-- ── Column grid: collision always, visuals only in fallback mode ────────
-- visualColumns=true  -> the "keycap grid" fallback look (grooves, jitter,
--                        gloss) + collision.
-- visualColumns=false -> invisible CanCollide/CanQuery colliders under the
--                        slab meshes, snapped to server truth.
-- (visualColumns itself is declared above the rebuild that flips it.)
local columns: { Part } = {}
local colTargetH: { number } = {}
local colDisplayH: { number } = {}
local colJitter: { number } = {} -- deterministic -1..1 shade noise
local colActive: { [number]: boolean } = {}
local colSquish: { [number]: number } = {} -- visual dent under the character (<= 0)
local PN = 0 -- fallback grid size
local cellsPerCol = 0
local colStuds = 0

local DARK = Color3.fromRGB(40, 22, 14)

local function colIndex(cx: number, cz: number): number
	return cz * PN + cx + 1
end

local function setupParts()
	PN = renderCfg.fallbackGrid
	cellsPerCol = SIZE / PN
	colStuds = SIZE * CELL / PN
	local gap = renderCfg.fallback.gap
	local folder = Instance.new("Folder")
	folder.Name = "CakeColumns"
	local template = Instance.new("Part")
	template.Anchored = true
	template.CastShadow = false
	template.CanCollide = false
	template.CanQuery = true -- bite raycasts hit exact column tops
	template.CanTouch = false
	template.Transparency = 1 -- invisible colliders under the mesh; the
	-- fallback look flips visible columns per-write (visualColumns)
	template.Material = Enum.Material.SmoothPlastic
	template.TopSurface = Enum.SurfaceType.Smooth
	template.BottomSurface = Enum.SurfaceType.Smooth
	template.Size = Vector3.new(colStuds - gap, 0.1, colStuds - gap)
	for cz = 0, PN - 1 do
		for cx = 0, PN - 1 do
			local part = template:Clone()
			part.Name = `C{cx}_{cz}`
			part.CFrame = CFrame.new(
				gridCfg.origin.x + (cx - PN / 2 + 0.5) * colStuds,
				gridCfg.origin.y,
				gridCfg.origin.z + (cz - PN / 2 + 0.5) * colStuds
			)
			part.Parent = folder
			local ci = colIndex(cx, cz)
			columns[ci] = part
			colTargetH[ci] = 0
			colDisplayH[ci] = 0
			-- Deterministic per-column shade (keycap color variation).
			colJitter[ci] = math.noise(cx * 0.53 + 11.7, cz * 0.53 + 4.2) * 2
		end
	end
	template:Destroy()
	folder.Parent = workspace
end

local function colTarget(cx: number, cz: number): number
	local meta = fieldModule.Meta()
	if not meta then
		return 0
	end
	local sum, count = 0, 0
	for dz = 0, cellsPerCol - 1 do
		for dx = 0, cellsPerCol - 1 do
			local x, z = cx * cellsPerCol + dx, cz * cellsPerCol + dz
			if GridUtil.InCake(SIZE, meta.footprint, x, z) then
				sum += fieldModule.ReadHeightStuds(GridUtil.Index(SIZE, x, z))
				count += 1
			end
		end
	end
	return if count > 0 then sum / count else 0
end

local function writeColumn(ci: number)
	local part = columns[ci]
	local h = colDisplayH[ci] + (colSquish[ci] or 0)
	if h < renderCfg.fallback.minVisibleHeight then
		part.Size = Vector3.new(part.Size.X, 0.1, part.Size.Z)
		part.CFrame = CFrame.new(part.Position.X, gridCfg.origin.y, part.Position.Z)
		part.Transparency = 1
		part.CanCollide = false
	else
		part.CanCollide = true
		part.Size = Vector3.new(part.Size.X, h, part.Size.Z)
		part.CFrame = CFrame.new(part.Position.X, gridCfg.origin.y + h / 2, part.Position.Z)
		if visualColumns then
			part.Transparency = 0
			local color = CakeRenderer.PaletteColor(h)
			local j = colJitter[ci] * renderCfg.fallback.colorJitter
			if j >= 0 then
				color = color:Lerp(WHITE, j)
			else
				color = color:Lerp(DARK, -j)
			end
			part.Color = color
			part.Reflectance = paletteGloss(h)
		end
	end
end

-- Editable mode: refresh ONLY the collision columns within
-- `collision.updateRadiusStuds` of the local player each frame (Task 2 perf).
-- Eating + the settle automaton ooze change cells across the WHOLE cake;
-- resizing every affected CanCollide column per frame re-indexes the physics
-- broadphase and spiked the frame to 60+ ms. The player only collides with
-- nearby columns, so distant ones keep their last size until the player nears
-- them (this scan corrects them then). Per column: a DROP snaps (fall into the
-- hole you just bit); a RISE is rate-limited (cake oozing back doesn't punt you
-- up — stay buried, jump to climb out, Task 4).
updateCollisionNearPlayer = function(dt: number, footPos: Vector3?)
	if footPos == nil then
		return -- off the cake: leave the columns as-is (nothing stands on them)
	end
	local r = renderCfg.collision.updateRadiusStuds
	local fcx = (footPos.X - gridCfg.origin.x) / colStuds + PN / 2 - 0.5
	local fcz = (footPos.Z - gridCfg.origin.z) / colStuds + PN / 2 - 0.5
	local cr = math.ceil(r / colStuds)
	local rise = renderCfg.collision.riseRate * dt
	local x0 = math.max(0, math.floor(fcx) - cr)
	local x1 = math.min(PN - 1, math.floor(fcx) + cr)
	local z0 = math.max(0, math.floor(fcz) - cr)
	local z1 = math.min(PN - 1, math.floor(fcz) + cr)
	for cz = z0, z1 do
		for cx = x0, x1 do
			local ci = colIndex(cx, cz)
			local target = colTarget(cx, cz)
			local cur = colDisplayH[ci]
			local newH
			if target <= cur or cur + rise >= target then
				newH = target -- DROP snaps; a rise reaching target this frame lands
			else
				newH = cur + rise -- rate-limited rise
			end
			-- Only resize the part (physics broadphase) when it moved meaningfully.
			if math.abs(newH - cur) > 0.02 then
				colTargetH[ci] = target
				colDisplayH[ci] = newH
				writeColumn(ci)
			end
		end
	end
end

local function columnsRebuild()
	for cz = 0, PN - 1 do
		for cx = 0, PN - 1 do
			local ci = colIndex(cx, cz)
			colTargetH[ci] = colTarget(cx, cz)
			colDisplayH[ci] = colTargetH[ci]
			writeColumn(ci)
		end
	end
	table.clear(colActive)
	table.clear(colSquish)
end

local function partsStep(dt: number, footPos: Vector3?)
	for _, i in ipairs(fieldModule.DrainChanged()) do
		local x, z = GridUtil.Coords(SIZE, i)
		local ci = colIndex(x // cellsPerCol, z // cellsPerCol)
		colTargetH[ci] = colTarget(x // cellsPerCol, z // cellsPerCol)
		colActive[ci] = true
	end
	local alpha = math.min(1, renderCfg.lerpSpeed * dt)
	for ci in pairs(colActive) do
		local d = colTargetH[ci] - colDisplayH[ci]
		if math.abs(d) < 0.01 then
			colDisplayH[ci] = colTargetH[ci]
			colActive[ci] = nil
		else
			colDisplayH[ci] += d * alpha
		end
		writeColumn(ci)
	end

	-- Underfoot squish (§7.2, reference "butter dents under you"):
	-- columns near the character sink visually and spring back. Display
	-- only — the mirror/simulation never see it.
	local sq = JuiceConfig.squish
	local footCols: { [number]: number } = {}
	if footPos then
		local fx = (footPos.X - gridCfg.origin.x) / colStuds + PN / 2 - 0.5
		local fz = (footPos.Z - gridCfg.origin.z) / colStuds + PN / 2 - 0.5
		local r = math.max(1, math.ceil(sq.radius / colStuds))
		for cz = math.floor(fz) - r, math.floor(fz) + r do
			for cx = math.floor(fx) - r, math.floor(fx) + r do
				if cx >= 0 and cz >= 0 and cx < PN and cz < PN then
					local dx, dz = (cx - fx) * colStuds, (cz - fz) * colStuds
					local distSq = dx * dx + dz * dz
					if distSq < sq.radius * sq.radius then
						footCols[colIndex(cx, cz)] = -sq.depth * (1 - distSq / (sq.radius * sq.radius))
					end
				end
			end
		end
	end
	local recover = 1 - math.exp(-dt / sq.recover)
	for ci, current in pairs(colSquish) do
		local target = footCols[ci] or 0
		footCols[ci] = nil
		local new = current + (target - current) * recover
		if math.abs(new) < 0.02 and target == 0 then
			colSquish[ci] = nil
		else
			colSquish[ci] = new
		end
		writeColumn(ci)
	end
	for ci, target in pairs(footCols) do
		colSquish[ci] = target * 0.5
		writeColumn(ci)
	end
end

-- ── Public interface ────────────────────────────────────────────────────

--API
-- Builds the renderer (static layout + invisible collision columns; slab
-- meshes are created lazily on the first snapshot, sized to the actual
-- composition). Called once from CakeSubsClient.Start.
function CakeRenderer.Setup(cakeFieldModule)
	fieldModule = cakeFieldModule
	if renderCfg.forceFallback then
		impl = "parts"
		visualColumns = true
	else
		buildStaticLayout()
		impl = "editable"
		visualColumns = false
	end
	setupParts() -- column grid exists in ALL modes (collision/fallback)
	Log.Sum("CakeRenderer", `renderer ready — implementation: {impl} (slabs lazy per composition)`)
	if fieldModule.Meta() then
		CakeRenderer.OnSnapshot()
	end
end

--API
-- Full visual refresh (snapshot / new cake). May YIELD on the editable
-- path (lazy mesh creation) — guarded against overlapping snapshots; a
-- snapshot arriving mid-rebuild re-runs after the current one finishes.
function CakeRenderer.OnSnapshot()
	if impl == "editable" then
		if rebuilding then
			snapshotPending = true
			return
		end
		rebuilding = true
		-- pcall: an unhandled throw here would leave `rebuilding` stuck true
		-- and freeze the renderer forever with no ongoing warn (R8).
		local ok, err = pcall(editableRebuild) -- may flip impl to "parts" on budget exhaustion
		columnsRebuild()
		rebuilding = false
		if not ok then
			Log.Warn("CakeRenderer", `rebuild FAILED ({err}) — cake visuals stale until the next snapshot`)
		end
		if snapshotPending then
			snapshotPending = false
			CakeRenderer.OnSnapshot()
		end
	elseif impl == "parts" then
		buildPalette()
		columnsRebuild()
	end
end

--API
-- Per-frame update.
--   footPos     = ground point when CLOSE to the surface (ΔY < tolerance) — the
--                 cosmetic squish/wax; nil when off/above/buried.
--   overCakePos = the player's surface point whenever they're over the loaf at
--                 ANY depth (nil only off the footprint) — the collision-scan
--                 centre, so a BURIED player's columns still rise back (Task 2).
function CakeRenderer.Step(dt: number, footPos: Vector3?, overCakePos: Vector3?)
	clock += dt
	if impl == "editable" then
		if rebuilding then
			return -- mid-rebuild: mirror keeps accumulating, rebuild snaps all
		end
		editableStep(dt, footPos, overCakePos)
	elseif impl == "parts" then
		partsStep(dt, footPos)
	end
end

--API
function CakeRenderer.Impl(): string?
	return impl
end

return CakeRenderer
