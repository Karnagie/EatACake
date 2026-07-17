--[[
	CakeRenderer — the cake's client visual (GDD §4.5).

	Primary path: ONE MeshPart PER VISUAL BAND. Every sim layer becomes a
	dedicated EditableMesh slab (65×65 vertex grid) so each layer carries its
	OWN Material / Transparency / Reflectance / Color — translucent marmalade,
	grainy sponge, glossy caramel. On top of every edible layer sits a thin
	CRUST band (butter-skin reference) with an XZ-planar EditableImage
	texture; footstep/landing cracks are DRAWN into that texture (CrackAt).

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
	cake exactly in both modes. With render.forceFallback (or no
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
local cracksCfg = renderCfg.cracks

local SIZE = gridCfg.size
local VSIZE = SIZE + 1
local CELL = gridCfg.cell
local EPS = 0.02 -- studs: "the band still exists here" threshold
-- The loaf footprint is FIXED per game (config), so mesh faces, ring layout
-- and the band pool can be built once. +1-cell ring hosts the skirt walls.
local FOOTPRINT = CakeConfig.composition.footprint
-- core + 5 middles + frosting = 7 layer bands + up to 6 crusts.
local MAX_BANDS = 13

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
local updateCollisionColumns -- forward decl (defined with the column grid)

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
				-- crust meshes, so fallback columns/particles agree).
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

--API
-- Surface color at a height (bite particles match the layer).
function CakeRenderer.PaletteColor(hStuds: number): Color3
	local idx = math.clamp(math.floor(hStuds / renderCfg.paletteStep) + 1, 1, math.max(1, #palette))
	return palette[idx] or Color3.fromRGB(240, 220, 220)
end

local function paletteGloss(hStuds: number): number
	local idx = math.clamp(math.floor(hStuds / renderCfg.paletteStep) + 1, 1, math.max(1, #glossPalette))
	return glossPalette[idx] or 0
end

-- Rare tint applied to band colors AND crust texture fills.
local function tinted(color: Color3, rareKind: string?, hMid: number, topStuds: number): Color3
	if rareKind == "golden" then
		return color:Lerp(renderCfg.goldenTint.color, renderCfg.goldenTint.alpha)
	elseif rareKind == "rainbow" then
		local hue = (hMid / math.max(1, topStuds)) % 1
		return color:Lerp(Color3.fromHSV(hue, 0.65, 1), renderCfg.rainbowTintAlpha)
	end
	return color
end

-- ── EditableMesh implementation: one slab mesh per visual band ──────────
-- Pool entries are built ONCE (footprint-static geometry); every snapshot
-- assigns them a band range + appearance. y[] persists across cakes so
-- unchanged vertices skip their SetPosition.
type PoolEntry = {
	em: EditableMesh,
	part: MeshPart,
	image: EditableImage?, -- crust crack texture, created lazily
	vertIds: { number },
	uvIds: { number },
	normalIds: { number },
	y: { number }, -- last written vertex heights
}
type Band = {
	kind: "layer" | "crust",
	layerId: string,
	bottom: number,
	top: number,
	poolIdx: number,
	crackColor: Color3?,
}

local pool: { PoolEntry } = {}
local bands: { Band } = {}

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

-- Visual band that owns the surface at this height (crusts included).
local function surfaceBandIndexAt(hStuds: number): number
	for bi, band in ipairs(bands) do
		if hStuds <= band.top then
			return bi
		end
	end
	return #bands -- spawn noise sits above the top crust
end

-- The band projection rule (see file header).
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
		return if maxH > band.bottom + EPS then band.bottom else 0
	end
	local raw = displayH[vi]
	if raw > band.bottom + EPS then
		return math.min(raw, band.top)
	end
	return 0
end

-- Position + normal write for one vertex of one band. Normals come from the
-- BAND's own neighbor heights, so clamped slab walls shade correctly.
local function bandWrite(band: Band, vi: number)
	local pe = pool[band.poolIdx]
	local y = pe.y
	pe.em:SetPosition(pe.vertIds[vi], Vector3.new(worldX[vi], y[vi], worldZ[vi]))
	local vx = (vi - 1) % VSIZE
	local vz = (vi - 1) // VSIZE
	local hl = y[vidx(math.max(0, vx - 1), vz)]
	local hr = y[vidx(math.min(VSIZE - 1, vx + 1), vz)]
	local ht = y[vidx(vx, math.max(0, vz - 1))]
	local hb = y[vidx(vx, math.min(VSIZE - 1, vz + 1))]
	pe.em:SetNormal(pe.normalIds[vi], Vector3.new(hl - hr, 2 * CELL, ht - hb).Unit)
end

-- Project one vertex into every band; write only real moves.
local function projectVertex(vi: number)
	for _, band in ipairs(bands) do
		local pe = pool[band.poolIdx]
		local ny = bandYOf(band, vi)
		if math.abs(ny - pe.y[vi]) > 0.004 then
			pe.y[vi] = ny
			bandWrite(band, vi)
		end
	end
end

local function setupEditable(): boolean
	local startedAt = os.clock()
	local ok, err = pcall(function()
		local half = SIZE / 2
		-- Shared static vertex layout + ring classification.
		for vz = 0, VSIZE - 1 do
			for vx = 0, VSIZE - 1 do
				local vi = vidx(vx, vz)
				worldX[vi] = (vx - half) * CELL
				worldZ[vi] = (vz - half) * CELL
				targetH[vi] = 0
				displayH[vi] = 0
				oozeRate[vi] = renderCfg.lerpSpeed
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
		-- The band part pool: identical geometry, appearance set per cake.
		for pi = 1, MAX_BANDS do
			local em = AssetService:CreateEditableMesh()
			local vertIds = table.create(VSIZE * VSIZE)
			local uvIds = table.create(VSIZE * VSIZE)
			local normalIds = table.create(VSIZE * VSIZE)
			local y = table.create(VSIZE * VSIZE, 0)
			for vz = 0, VSIZE - 1 do
				for vx = 0, VSIZE - 1 do
					local vi = vidx(vx, vz)
					-- Bounds trick: create at max height so the render bounds
					-- cover every future height (culling uses CREATION geometry).
					local creationY = if isRing[vi] and ringCells[vi] == nil then 0 else gridCfg.maxHeight
					y[vi] = creationY
					vertIds[vi] = em:AddVertex(Vector3.new(worldX[vi], creationY, worldZ[vi]))
					-- STATIC planar UVs: crust textures map XZ over the grid.
					uvIds[vi] = em:AddUV(Vector2.new(vx / SIZE, vz / SIZE))
					normalIds[vi] = em:AddNormal(Vector3.yAxis)
				end
			end
			for cz = 0, SIZE - 1 do
				for cx = 0, SIZE - 1 do
					if cellHostsFaces(cx, cz) then
						local i00, i01, i10, i11 = vidx(cx, cz), vidx(cx, cz + 1), vidx(cx + 1, cz), vidx(cx + 1, cz + 1)
						local f1 = em:AddTriangle(vertIds[i00], vertIds[i01], vertIds[i10])
						local f2 = em:AddTriangle(vertIds[i10], vertIds[i01], vertIds[i11])
						em:SetFaceUVs(f1, { uvIds[i00], uvIds[i01], uvIds[i10] })
						em:SetFaceUVs(f2, { uvIds[i10], uvIds[i01], uvIds[i11] })
						em:SetFaceNormals(f1, { normalIds[i00], normalIds[i01], normalIds[i10] })
						em:SetFaceNormals(f2, { normalIds[i10], normalIds[i01], normalIds[i11] })
					end
				end
			end
			-- RenderFidelity = Precise: Automatic swaps in LODs generated from
			-- stale creation-time content; Precise renders live edits always.
			local part = AssetService:CreateMeshPartAsync(
				Content.fromObject(em),
				{ RenderFidelity = Enum.RenderFidelity.Precise }
			)
			part.Name = `CakeBand{pi}`
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false -- GDD §4.5
			part.Material = Enum.Material.SmoothPlastic
			part.Color = WHITE
			-- Both sides render: steep skirt/crater quads flip facing depending
			-- on which neighbor dropped; single-sided walls vanished at angles.
			part.DoubleSided = true
			-- Verified live: vertices render at RAW mesh coordinates relative
			-- to part.CFrame (no bbox recentering) — mesh y=0 = part Y.
			part.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y, gridCfg.origin.z)
			part.Transparency = 1 -- hidden until the first snapshot assigns bands
			part.Parent = workspace
			pool[pi] = {
				em = em,
				part = part,
				image = nil,
				vertIds = vertIds,
				uvIds = uvIds,
				normalIds = normalIds,
				y = y,
			}
		end
	end)
	if not ok then
		Log.Warn("CakeRenderer", `EditableMesh band pool failed ({err}) — falling back to part grid`)
		for _, pe in ipairs(pool) do
			pe.part:Destroy()
		end
		table.clear(pool)
		return false
	end
	Log.Info("CakeRenderer", `band pool ready — {MAX_BANDS} slab meshes in {math.floor((os.clock() - startedAt) * 1000)} ms`)
	return true
end

-- Fills a crust texture with its base skin color + subtle mottling.
local function fillCrustImage(pe: PoolEntry, fill: Color3)
	local img = pe.image :: EditableImage
	local size = crustCfg.imageSize
	local buf = buffer.create(size * size * 4)
	local noiseAmp = crustCfg.noise
	local r0, g0, b0 = fill.R, fill.G, fill.B
	for pz = 0, size - 1 do
		for px = 0, size - 1 do
			local n = math.noise(px * 0.15, pz * 0.15) * noiseAmp
			local o = (pz * size + px) * 4
			buffer.writeu8(buf, o, math.clamp(math.floor((r0 + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 1, math.clamp(math.floor((g0 + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 2, math.clamp(math.floor((b0 + n) * 255 + 0.5), 0, 255))
			buffer.writeu8(buf, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), buf)
end

-- Derives the visual band list (layers + crust skins) from the sim
-- composition and dresses the pool parts. Returns desired transparencies,
-- applied AFTER geometry is written (no flash of stale slabs).
local function assignBands(meta): { number }
	table.clear(bands)
	table.clear(wobbleBandIndices)
	local topStuds = meta.composition[#meta.composition].top
	for _, simBand in ipairs(meta.composition) do
		if simBand.id == "core" or simBand.top - simBand.bottom <= crustCfg.depth + 0.5 then
			table.insert(bands, { kind = "layer", layerId = simBand.id, bottom = simBand.bottom, top = simBand.top, poolIdx = 0 })
		else
			local skinBottom = simBand.top - crustCfg.depth
			table.insert(bands, { kind = "layer", layerId = simBand.id, bottom = simBand.bottom, top = skinBottom, poolIdx = 0 })
			table.insert(bands, { kind = "crust", layerId = simBand.id, bottom = skinBottom, top = simBand.top, poolIdx = 0 })
		end
	end
	if #bands > #pool then
		-- Composition config outgrew the pool — visible bug, not silence (R8).
		Log.Warn("CakeRenderer", `{#bands} visual bands > pool of {#pool} — extra bands not rendered; raise MAX_BANDS`)
	end
	local transparencies = {}
	for bi, band in ipairs(bands) do
		if bi > #pool then
			break
		end
		band.poolIdx = bi
		local pe = pool[bi]
		local layerDef = layersCfg[band.layerId]
		local hMid = (band.bottom + band.top) * 0.5
		local part = pe.part
		if band.kind == "layer" then
			local bodyColor = layerDef.colors.bottom:Lerp(layerDef.colors.top, 0.55)
			part.Color = tinted(bodyColor, meta.rareKind, hMid, topStuds)
			part.Material = layerDef.material or Enum.Material.SmoothPlastic
			part.Reflectance = layerDef.gloss or 0
			part.TextureContent = Content.none
			part.Name = `CakeBand{bi}_{band.layerId}`
			transparencies[bi] = layerDef.transparency or 0
			if layerDef.wobble then
				table.insert(wobbleBandIndices, bi)
			end
		else
			local crustColor = tinted(layerDef.colors.top:Lerp(WHITE, crustCfg.lighten), meta.rareKind, hMid, topStuds)
			band.crackColor = crustColor:Lerp(BLACK, cracksCfg.darken)
			part.Color = WHITE -- the texture carries the look
			part.Material = Enum.Material.SmoothPlastic
			part.Reflectance = crustCfg.gloss
			part.Name = `CakeBand{bi}_{band.layerId}_crust`
			if pe.image == nil then
				local imgOk, imgErr = pcall(function()
					pe.image = AssetService:CreateEditableImage({
						Size = Vector2.new(crustCfg.imageSize, crustCfg.imageSize),
					})
				end)
				if not imgOk then
					Log.Once("CakeRenderer", "crust-image-fail", `crust EditableImage failed ({imgErr}) — crusts render untextured, no cracks`)
				end
			end
			if pe.image ~= nil then
				fillCrustImage(pe, crustColor)
				part.TextureContent = Content.fromObject(pe.image)
			else
				part.TextureContent = Content.none
				part.Color = crustColor
			end
			transparencies[bi] = 0
		end
	end
	-- Park leftover pool parts.
	for pi = #bands + 1, #pool do
		pool[pi].part.Transparency = 1
		pool[pi].part.Name = `CakeBand{pi}_idle`
	end
	return transparencies
end

local function editableRebuild()
	buildPalette()
	local meta = fieldModule.Meta()
	if not meta then
		return
	end
	local startedAt = os.clock()
	local transparencies = assignBands(meta)
	for vz = 0, VSIZE - 1 do
		for vx = 0, VSIZE - 1 do
			local vi = vidx(vx, vz)
			targetH[vi] = vertexTarget(vx, vz)
			displayH[vi] = targetH[vi]
			oozeRate[vi] = oozeSpeedAt(targetH[vi])
		end
	end
	-- TWO passes per band: heights first, then writes — normals read
	-- NEIGHBOR heights; a single interleaved pass bakes sideways normals.
	for _, band in ipairs(bands) do
		if band.poolIdx == 0 then
			continue
		end
		local pe = pool[band.poolIdx]
		local newY = table.create(VSIZE * VSIZE)
		for vi = 1, VSIZE * VSIZE do
			newY[vi] = bandYOf(band, vi)
		end
		local oldY = pe.y
		pe.y = newY
		for vi = 1, VSIZE * VSIZE do
			if math.abs(newY[vi] - oldY[vi]) > 0.004 then
				bandWrite(band, vi)
			end
		end
	end
	for bi, band in ipairs(bands) do
		if band.poolIdx ~= 0 then
			pool[band.poolIdx].part.Transparency = transparencies[bi] or 0
		end
	end
	table.clear(active)
	table.clear(squishOff)
	table.clear(squishBandIdx)
	table.clear(ringDirty)
	Log.Info("CakeRenderer", `bands rebuilt — {#bands} slabs ({#meta.composition} layers) in {math.floor((os.clock() - startedAt) * 1000)} ms`)
end

local function editableStep(dt: number, footPos: Vector3?)
	if #bands == 0 then
		return
	end
	-- 1. Changed cells -> corner vertices get fresh targets; the invisible
	-- collision columns snap to server truth on the same drained list.
	local drained = fieldModule.DrainChanged()
	if #drained > 0 then
		updateCollisionColumns(drained)
	end
	for _, i in ipairs(drained) do
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

	-- 3. Underfoot squish (§7.2): visual only, scaled by the surface
	-- layer's squishMult (frosting pillow vs chocolate rock).
	local sq = JuiceConfig.squish
	local footVerts: { [number]: number } = {}
	if footPos then
		local fx = (footPos.X - gridCfg.origin.x) / CELL + SIZE / 2
		local fz = (footPos.Z - gridCfg.origin.z) / CELL + SIZE / 2
		local r = math.ceil(sq.radius / CELL)
		for vz = math.floor(fz) - r, math.floor(fz) + r do
			for vx = math.floor(fx) - r, math.floor(fx) + r do
				if vx >= 0 and vz >= 0 and vx < VSIZE and vz < VSIZE then
					local vi = vidx(vx, vz)
					local dx, dz = (vx - fx) * CELL, (vz - fz) * CELL
					local distSq = dx * dx + dz * dz
					if distSq < sq.radius * sq.radius then
						local def = layerDefAt(displayH[vi])
						local mult = (def and def.squishMult) or 1
						if mult > 0 then
							footVerts[vi] = -sq.depth * mult * (1 - distSq / (sq.radius * sq.radius))
						end
					end
				end
			end
		end
	end
	-- dt-based exponential so the spring-back honors sq.recover at any fps.
	local recover = 1 - math.exp(-dt / sq.recover)
	local function writeSquish(vi: number)
		local bi = surfaceBandIndexAt(displayH[vi])
		local prev = squishBandIdx[vi]
		if prev and prev ~= bi and bands[prev] and bands[prev].poolIdx ~= 0 then
			bandWrite(bands[prev], vi) -- restore the band the dent left
		end
		squishBandIdx[vi] = bi
		local band = bands[bi]
		if band == nil or band.poolIdx == 0 then
			return
		end
		local pe = pool[band.poolIdx]
		local y = math.max(pe.y[vi] + (squishOff[vi] or 0), band.bottom + 0.05)
		pe.em:SetPosition(pe.vertIds[vi], Vector3.new(worldX[vi], y, worldZ[vi]))
	end
	for vi, current in pairs(squishOff) do
		local target = footVerts[vi] or 0
		footVerts[vi] = nil
		local new = current + (target - current) * recover
		if math.abs(new) < 0.02 and target == 0 then
			squishOff[vi] = nil
			local bi = squishBandIdx[vi]
			squishBandIdx[vi] = nil
			if bi and bands[bi] and bands[bi].poolIdx ~= 0 then
				bandWrite(bands[bi], vi) -- clean restore
			end
		else
			squishOff[vi] = new
			writeSquish(vi)
		end
	end
	for vi, target in pairs(footVerts) do
		squishOff[vi] = target * 0.5
		writeSquish(vi)
	end

	-- 4. Jelly wobble: NEGATIVE-only sine (dips, never pokes above the band
	-- top into the crust above), rotating vertex slice per frame (§5).
	if #wobbleBandIndices > 0 then
		local total = VSIZE * VSIZE
		local sliceLen = total // renderCfg.wobbleSliceDiv
		for _ = 1, sliceLen do
			wobbleCursor = wobbleCursor % total + 1
			local vi = wobbleCursor
			if not active[vi] and squishOff[vi] == nil and not isRing[vi] then
				for _, bi in ipairs(wobbleBandIndices) do
					local band = bands[bi]
					local pe = pool[band.poolIdx]
					local base = pe.y[vi]
					if base > band.bottom + 0.1 then
						local vx = (vi - 1) % VSIZE
						local vz = (vi - 1) // VSIZE
						local offset = (math.sin(clock * renderCfg.wobbleSpeed + (vx + vz) * 0.7) - 1)
							* renderCfg.wobbleAmp
						local y = math.max(base + offset, band.bottom + 0.05)
						pe.em:SetPosition(pe.vertIds[vi], Vector3.new(worldX[vi], y, worldZ[vi]))
					end
				end
			end
		end
	end
end

-- ── Crust cracks ────────────────────────────────────────────────────────
local rngCrack = Random.new(os.clock() * 1e4)

--API
-- Draws a crack into the crust texture under a world position. kind =
-- "land" (radial star) | "step" (small walking crack). Returns true when
-- the position is actually on a crust skin and a crack was drawn.
function CakeRenderer.CrackAt(pos: Vector3, kind: string): boolean
	if impl ~= "editable" or #bands == 0 then
		return false
	end
	local h = fieldModule.SurfaceHeightAt(pos.X, pos.Z)
	if h == nil then
		return false
	end
	local bi = surfaceBandIndexAt(h)
	local band = bands[bi]
	if band == nil or band.kind ~= "crust" or band.poolIdx == 0 then
		return false
	end
	local pe = pool[band.poolIdx]
	local img = pe.image
	if img == nil then
		return false -- warned once at assign time
	end
	local size = crustCfg.imageSize
	local pxPerStud = size / (SIZE * CELL)
	local cx = ((pos.X - gridCfg.origin.x) / (SIZE * CELL) + 0.5) * (size - 1)
	local cz = ((pos.Z - gridCfg.origin.z) / (SIZE * CELL) + 0.5) * (size - 1)
	local linesRange = if kind == "land" then cracksCfg.landLines else cracksCfg.stepLines
	local lengthRange = if kind == "land" then cracksCfg.landLength else cracksCfg.stepLength
	local lines = rngCrack:NextInteger(linesRange[1], linesRange[2])
	local color = band.crackColor or BLACK
	for _ = 1, lines do
		local angle = rngCrack:NextNumber(0, math.pi * 2)
		local length = rngCrack:NextNumber(lengthRange[1], lengthRange[2]) * pxPerStud
		local segLen = math.max(2, cracksCfg.segmentStuds * pxPerStud)
		local x, z = cx, cz
		local walked = 0
		while walked < length do
			local step = math.min(segLen, length - walked)
			local nx = x + math.cos(angle) * step
			local nz = z + math.sin(angle) * step
			img:DrawLine(
				Vector2.new(math.clamp(x, 0, size - 1), math.clamp(z, 0, size - 1)),
				Vector2.new(math.clamp(nx, 0, size - 1), math.clamp(nz, 0, size - 1)),
				color,
				0,
				Enum.ImageCombineType.Overwrite
			)
			x, z = nx, nz
			angle += rngCrack:NextNumber(-cracksCfg.jitter, cracksCfg.jitter)
			walked += step
		end
	end
	return true
end

-- ── Column grid: collision always, visuals only in fallback mode ────────
-- visualColumns=true  -> the "keycap grid" fallback look (grooves, jitter,
--                        gloss) + collision.
-- visualColumns=false -> invisible CanCollide/CanQuery colliders under the
--                        band meshes, snapped to server truth.
local visualColumns = false
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

-- Editable mode: collision columns snap straight to server truth (no lerp
-- — you must be able to fall into the hole you just bit).
updateCollisionColumns = function(changedCells: { number })
	local touched: { [number]: boolean } = {}
	for _, i in ipairs(changedCells) do
		local x, z = GridUtil.Coords(SIZE, i)
		touched[colIndex(x // cellsPerCol, z // cellsPerCol)] = true
	end
	for ci in pairs(touched) do
		local cx = (ci - 1) % PN
		local cz = (ci - 1) // PN
		colTargetH[ci] = colTarget(cx, cz)
		colDisplayH[ci] = colTargetH[ci]
		writeColumn(ci)
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
-- Builds the renderer (band mesh pool + invisible collision columns,
-- falling back to visible columns). Called once from CakeSubsClient.Start.
-- ⚠ CreateMeshPartAsync YIELDS (13x here) — the first snapshot can arrive
-- mid-Setup, and OnSnapshot before `impl` is set is a no-op. The tail of
-- Setup re-runs the rebuild when the mirror already holds a cake (this
-- exact race once shipped a permanently WHITE cake).
function CakeRenderer.Setup(cakeFieldModule)
	fieldModule = cakeFieldModule
	if not renderCfg.forceFallback and setupEditable() then
		impl = "editable"
		visualColumns = false
	else
		impl = "parts"
		visualColumns = true
	end
	setupParts() -- column grid exists in BOTH modes (collision/fallback)
	Log.Sum("CakeRenderer", `renderer ready — implementation: {impl}`)
	if fieldModule.Meta() then
		CakeRenderer.OnSnapshot()
	end
end

--API
-- Full visual refresh (snapshot / new cake).
function CakeRenderer.OnSnapshot()
	if impl == "editable" then
		editableRebuild()
		columnsRebuild()
	elseif impl == "parts" then
		buildPalette()
		columnsRebuild()
	end
end

--API
-- Per-frame update. footPos = local character's ground point on the cake
-- (nil when off the cake) for the squish effect.
function CakeRenderer.Step(dt: number, footPos: Vector3?)
	clock += dt
	if impl == "editable" then
		editableStep(dt, footPos)
	elseif impl == "parts" then
		partsStep(dt, footPos)
	end
end

--API
function CakeRenderer.Impl(): string?
	return impl
end

return CakeRenderer
