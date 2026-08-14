--[[
	CakeWrapper — the textured OUTER WALL of the cake, ONE RING PER FLAVOUR ZONE.

	CakeRenderer draws the current + next edible layer as slabs; this wall hides
	the cake BELOW them. It stands from the cake base up to the BOTTOM of the
	NEXT layer (`composition[activeIndex - 1].bottom`); the topmost ring SHRINKS
	as layers inside it are eaten and only disappears when its whole zone is gone.
	Each zone reads its own composition footprint. Narrower upper zones therefore
	use smaller rings, while pooled horizontal caps expose the wider shoulders
	below them as a stepped pyramid.

	⚠ REWORKED 2026-08-07 (user req: "players should be able to look at the side
	of the cake and see which layers are coming next"). It used to be ONE ring
	wearing ONE cake photo tiled up the whole wall, so the side of a 28-layer cake
	said nothing about what was inside it.
	⚠ The first fix went one step too far — a ring per BAND drew ~28 near-identical
	stripes and read as noise, not as information. The wall is now one ring per
	flavour ZONE (`CakeLayersConfig.groups[].sideTexture/sideColor`, resolved from
	a band's layer id through `groupOfLayer`): four chunky bands saying
	"chocolate, then sponge, then butter, then cream". That is the thing the player
	actually needs to see coming, because it is what the MINI-BOSS GATES are drawn
	on (features/cake-cycle.md) — and it costs ~100 parts instead of ~560.

	WHY BLOCK SEGMENTS, STILL (2026-08-03, unchanged and load-bearing):
	  · `Shape = Cylinder` — axis is LOCAL X, so standing it upright takes
	    `CFrame.Angles(0, 0, pi/2)`, which rotates the face UV frames with it and
	    lays the texture on its side.
	  · `CylinderMesh` — a part carrying a MESH maps its Textures through the
	    MESH's UVs and **silently ignores `StudsPerTileU/V`** (55 / 20 / 5
	    rendered pixel-identical). Per-band tiling would be impossible.
	  · **Flat Block segments** — a real block face, so tiling behaves. Each
	    segment sets `OffsetStudsU` to its cumulative width so the tiling phase
	    runs CONTINUOUSLY around the ring instead of restarting at every seam.
	The TOP CAP keeps its `CylinderMesh`: it is a flat disc seen face-on through
	a crater, where one mapped photo is exactly right — and it is the one place
	the PER-LAYER `sideTexture` is still used, because a crater really does expose
	a single layer.

	COST + POOLING: `wrapper.bandSegments` (20) parts per ring, and a ring per
	zone (`composition.groups.count`, 4) plus a little headroom. Rings are created
	ONCE, on demand, and then only re-placed — a finished zone parks its ring
	off-screen rather than destroying it, so a 40-minute cake never allocates a
	part after its first minute. 20 segments puts the facet sag at 0.58 studs on
	the 93.3-stud disc.

	Local + visual, CanCollide/CanQuery = false (bite raycasts hit the collision
	columns, never this). Driven from CakeSubsClient: Setup(mirror), OnSnapshot(),
	Step(dt). Reads LocalCakeField for composition + activeBandIndex.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local CakeLayersConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeLayersConfig"))
local Log = require(Shared:WaitForChild("Log"))

local CakeWrapper = {}

local gridCfg = CakeConfig.grid
local wrapCfg = CakeConfig.render.wrapper
local layersCfg = CakeConfig.layers
-- layer id -> its flavour GROUP. A band only carries its layer id, so this is
-- how a wall ring finds out which zone it is drawing.
local groupOfLayer = CakeLayersConfig.groupOfLayer
local CELL = gridCfg.cell

-- Cake diameter — match the slab's outline radius ((corner+0.5)·cell), which is
-- exactly what CakeRenderer projects its rim verts onto, so the wall meets the
-- slab edge with no lip either way.
local SEGMENTS = math.max(3, wrapCfg.bandSegments or wrapCfg.segments or 20)
-- Chord (the flat face width) and the ring radius to the chord's MIDPOINT, so the
-- segment's two ends land exactly ON the circle rather than inside or outside it.
local SEG_OVERLAP = 1.02 -- widen each face a hair so neighbours can't show a hairline gap
local PARKED_Y = -1000 -- world Y to hide a ring when its layer is gone

-- All shipped footprints are discs (`hx == hz == corner`). Return the exact
-- rendered diameter plus one faceted wall segment's chord geometry.
local function footprintGeometry(footprint): (number, number, number)
	local diameter = (footprint.corner + 0.5) * CELL * 2
	local radius = diameter * 0.5
	local segmentWidth = 2 * radius * math.sin(math.pi / SEGMENTS)
	local faceWidth = segmentWidth * SEG_OVERLAP
	local segmentInset = radius * math.cos(math.pi / SEGMENTS)
	return diameter, faceWidth, segmentInset
end

type Ring = { parts: { Part }, textures: { Texture } }

local fieldModule
local folder: Folder?
local rings: { Ring } = {}
local cap: Part? = nil
local capTexture: Texture? = nil
local terraceCaps: { Part } = {}
local terraceCapTextures: { Texture } = {}
local hidden = false
local stepped = false -- one-shot "the wall got a live snapshot" breadcrumb (R8)
-- Dirty check: the wall only changes on a new cake or a layer clear.
local lastCakeIndex = -1
local lastActiveIndex = -1

-- The image ONE LAYER shows in cross-section — used by the top CAP, which is
-- the only part of the wall that really is a single layer. Falls back to the
-- generic cake photo so a layer whose art is still missing reads as CAKE, never
-- as flat plastic (R8: the miss is announced once, not swallowed).
local function layerTextureFor(bandId: string): string?
	local layer = layersCfg[bandId]
	local texture = layer and layer.sideTexture
	if texture ~= nil then
		return texture
	end
	local fallback = wrapCfg.textures and wrapCfg.textures[1]
	if layer ~= nil and bandId ~= "core" then
		Log.Once(
			"CakeWrapper",
			`no-side-texture-{bandId}`,
			`layer '{bandId}' has no sideTexture -- the wall CAP shows the generic cake photo for it `
				.. `(add one in CakeLayersConfig so a crater reads as that layer)`
		)
	end
	return fallback
end

local function layerColorFor(bandId: string): Color3
	local layer = layersCfg[bandId]
	if layer == nil then
		return wrapCfg.color
	end
	return layer.sideColor or (layer.colors and layer.colors.top) or wrapCfg.color
end

-- The image + tint a whole ZONE shows on the wall. `bandId` is any layer of that
-- zone; frosting and core belong to no group, so those fall back to the layer's
-- own look (the frosting cap is above the wall top in practice, and the core is
-- 3 studs at the very base).
local function zoneTextureFor(bandId: string): (string?, Color3)
	local group = groupOfLayer and groupOfLayer[bandId]
	if group == nil then
		return layerTextureFor(bandId), layerColorFor(bandId)
	end
	if group.sideTexture == nil then
		Log.Once(
			"CakeWrapper",
			`no-zone-texture-{group.id}`,
			`flavour group '{group.id}' has no wall texture -- the outer wall shows the generic cake `
				.. `photo for that whole zone (add one in CakeLayersConfig's group(..., wall) argument)`
		)
	end
	return group.sideTexture or (wrapCfg.textures and wrapCfg.textures[1]),
		group.sideColor or layerColorFor(bandId)
end

--API
function CakeWrapper.Setup(localCakeField)
	fieldModule = localCakeField
end

local function newWallPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = wrapCfg.gloss
	p.Color = wrapCfg.color -- warm cake tint; shows if the texture is missing / transparent
	return p
end

local function ensureFolder(): Folder
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "CakeWrapper"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

-- Builds ring #index on demand (never destroyed afterwards — see POOLING).
local function ensureRing(index: number): Ring?
	local existing = rings[index]
	if existing then
		return existing
	end
	local maxRings = wrapCfg.maxBands or 12
	if index > maxRings then
		Log.Once(
			"CakeWrapper",
			"ring-pool-exhausted",
			`the cake has more flavour ZONES than render.wrapper.maxBands ({maxRings}) -- the deepest `
				.. `zones show no wall. Raise it above composition.groups.count`
		)
		return nil
	end
	local parent = ensureFolder()
	local ring: Ring = { parts = {}, textures = {} }
	for i = 0, SEGMENTS - 1 do
		local p = newWallPart(`Zone{index}Seg{i}`)
		p.Size = Vector3.new(1, 1, wrapCfg.segmentThickness)
		p.CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Back -- +Z local, which the CFrame below points outward
		tex.StudsPerTileU = wrapCfg.bandTileStuds or 26
		tex.StudsPerTileV = 1
		-- Continue the tiling PHASE around the ring instead of restarting it on
		-- every segment (which would chop the image into SEGMENTS vertical
		-- slices). Offset by the cumulative FACE width, not arc length, so the
		-- phase is exactly continuous across each seam.
		tex.OffsetStudsU = 0
		tex.Parent = p
		p.Parent = parent
		table.insert(ring.parts, p)
		table.insert(ring.textures, tex)
	end
	rings[index] = ring
	return ring
end

local function parkRing(ring: Ring)
	for _, p in ipairs(ring.parts) do
		if p.Position.Y ~= PARKED_Y then
			p.CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
		end
	end
end

local function placeRing(ring: Ring, bandId: string, bottomStuds: number, topStuds: number, footprint)
	local overlap = wrapCfg.bandOverlapStuds or 0.08
	local height = math.max(0.05, topStuds - bottomStuds) + overlap
	local centreY = gridCfg.origin.y + (bottomStuds + topStuds) * 0.5
	local texture, colour = zoneTextureFor(bandId)
	local _, faceWidth, segmentInset = footprintGeometry(footprint)
	-- A ZONE ring is tall (tens of studs), so its texture TILES up it rather
	-- than stretching once. `bandTileStudsY` is the knob for how tall one row is.
	--
	-- ⚠ Whole-row snapping is CONDITIONAL, and that is the fix for a real bug.
	-- Snapping unconditionally (`round(height / tile)`) squashed every zone
	-- SHORTER than one tile down to its own height: the 3.4-stud candy cap read
	-- 87% vertically compressed, the 16.9-stud sponge 35%. A partial row at the
	-- top of a band is far less visible than a distorted image, so the snap only
	-- applies once the band is tall enough for the correction to stay small.
	local tileV = math.max(1, wrapCfg.bandTileStudsY or wrapCfg.bandTileStuds or 45)
	local rowsExact = height / tileV
	if rowsExact >= 1.5 then
		tileV = height / math.max(1, math.floor(rowsExact + 0.5))
	end
	for i, p in ipairs(ring.parts) do
		local ang = (i - 0.5) / SEGMENTS * math.pi * 2
		p.Size = Vector3.new(faceWidth, height, wrapCfg.segmentThickness)
		p.CFrame = CFrame.new(gridCfg.origin.x, centreY, gridCfg.origin.z)
			* CFrame.Angles(0, -ang, 0)
			* CFrame.new(0, 0, segmentInset)
		p.Color = colour
		local tex = ring.textures[i]
		tex.StudsPerTileU = math.max(1, wrapCfg.bandTileStuds or 26)
		tex.StudsPerTileV = tileV
		tex.OffsetStudsU = (i - 1) * faceWidth
		tex.Texture = texture or ""
	end
end

local function ensureCap(): Part
	if cap then
		return cap :: Part
	end
	local c = newWallPart("WrapperCap")
	c.Size = Vector3.new(1, wrapCfg.capThickness, 1)
	Instance.new("CylinderMesh").Parent = c
	local tex = Instance.new("Texture")
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = 1
	tex.StudsPerTileV = 1
	tex.Parent = c
	c.Parent = ensureFolder()
	cap = c
	capTexture = tex
	return c
end

local function ensureTerraceCap(index: number): (Part, Texture)
	local existing = terraceCaps[index]
	if existing then
		return existing, terraceCapTextures[index]
	end
	-- Clone the already-built cap template (R5) so terrace expansion does not
	-- hand-author another visual tree.
	local c = ensureCap():Clone()
	c.Name = `TerraceCap{index}`
	local tex = c:FindFirstChildWhichIsA("Texture") :: Texture
	c.Parent = ensureFolder()
	terraceCaps[index] = c
	terraceCapTextures[index] = tex
	return c, tex
end

local function placeCap(c: Part, texture: Texture, bandId: string, topStuds: number, footprint)
	local diameter = footprintGeometry(footprint)
	c.Size = Vector3.new(diameter, wrapCfg.capThickness, diameter)
	c.CFrame = CFrame.new(
		gridCfg.origin.x,
		gridCfg.origin.y + topStuds - wrapCfg.capThickness * 0.5,
		gridCfg.origin.z
	)
	c.Color = layerColorFor(bandId)
	texture.Texture = layerTextureFor(bandId) or ""
	texture.StudsPerTileU = diameter
	texture.StudsPerTileV = diameter
end

-- Studs (above the cake base) the wall top sits at = the BOTTOM of the NEXT
-- rendered layer (composition[activeIndex-1].bottom): the renderer draws the
-- current + next layer, so the wall covers everything below BOTH. 0 when the
-- window already reaches the core (nothing left below to hide).
-- Reads the layer-gate index directly (not CakeRenderer's rendered index): safe
-- because a band advance never coincides with a renderer rebuild YIELD — the
-- renderer only yields growing the pool on the FIRST cake, when activeBandIndex
-- is still at the top and hasn't advanced — so the wall can't shrink ahead of the
-- slab and briefly expose a side-ring void.
local function wrapperTopStuds(meta): number
	local activeIndex = math.clamp(fieldModule.ActiveBandIndex(), 1, #meta.composition)
	if activeIndex < 2 then
		return 0
	end
	return meta.composition[activeIndex - 1].bottom
end

-- Collapses the bottom-up band list into ZONE SPANS: one entry per flavour
-- group, `{bottom, top, id}` where `id` is any layer of that zone (the wall
-- texture is the ZONE's, so which member does not matter). Bands carry `group`;
-- a composition without it (an old snapshot) degenerates to ONE span, i.e. the
-- pre-2026-08-07 single-ring wall, which is a safe fallback rather than a crash.
local function zoneSpans(composition)
	local byGroup, order = {}, {}
	for _, band in ipairs(composition) do
		local key = band.group or 1
		local span = byGroup[key]
		if span == nil then
			span = {
				bottom = band.bottom,
				top = band.top,
				id = band.id,
				footprint = band.footprint,
			}
			byGroup[key] = span
			table.insert(order, span)
		else
			span.bottom = math.min(span.bottom, band.bottom)
			span.top = math.max(span.top, band.top)
			-- Prefer a member the group index actually knows, so the CORE band
			-- (which belongs to no group but carries the deepest zone's index)
			-- cannot decide the deepest zone's look.
			if groupOfLayer and groupOfLayer[band.id] then
				span.id = band.id
				span.footprint = band.footprint or span.footprint
			end
		end
	end
	table.sort(order, function(a, b)
		return a.bottom < b.bottom
	end)
	return order
end

-- Re-places every ring for the current wall height. Cheap enough to run whole
-- (SEGMENTS x zones property writes, ~30 times per cake) and much harder to get
-- wrong than an incremental diff.
local function refresh(meta)
	local topStuds = wrapperTopStuds(meta)
	local composition = meta.composition
	local spans = zoneSpans(composition)
	local drawn = 0
	local topBandId: string? = nil
	local topBandFootprint = meta.footprint
	for index, span in ipairs(spans) do
		if span.bottom >= topStuds - 1e-3 then
			break
		end
		local ring = ensureRing(index)
		if ring == nil then
			break
		end
		-- The TOPMOST live zone is clamped to the wall top, so its ring shrinks
		-- layer by layer and only disappears once the whole zone is eaten.
		placeRing(ring, span.id, span.bottom, math.min(span.top, topStuds), span.footprint or meta.footprint)
		drawn = index
	end
	for index = drawn + 1, #rings do
		parkRing(rings[index])
	end

	-- Every narrower zone exposes the shoulder of the wider zone below it. Draw
	-- those horizontal terrace caps as stacked discs; the smaller/higher zones
	-- cover each disc's centre, leaving exactly the visible annulus.
	local terraceDrawn = 0
	for index = 1, #spans - 1 do
		local lower = spans[index]
		local upper = spans[index + 1]
		if lower.top > topStuds + 1e-3 then
			break
		end
		local lowerFootprint = lower.footprint or meta.footprint
		local upperFootprint = upper.footprint or meta.footprint
		local lowerDiameter = footprintGeometry(lowerFootprint)
		local upperDiameter = footprintGeometry(upperFootprint)
		if lowerDiameter > upperDiameter + 0.05 then
			terraceDrawn += 1
			local terrace, texture = ensureTerraceCap(terraceDrawn)
			placeCap(terrace, texture, lower.id, lower.top, lowerFootprint)
		end
	end
	for index = terraceDrawn + 1, #terraceCaps do
		terraceCaps[index].CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
	end

	-- The CAP is per LAYER, not per zone: it is the disc seen down a crater, and
	-- that really is one layer — the one directly under the band being eaten.
	for index = #composition, 1, -1 do
		if composition[index].bottom < topStuds - 1e-3 then
			topBandId = composition[index].id
			topBandFootprint = composition[index].footprint or meta.footprint
			break
		end
	end

	local c = ensureCap()
	if topStuds <= 0.05 then
		c.CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
	elseif topBandId ~= nil and capTexture ~= nil then
		-- The cap is the cross-section seen down a crater: it must show the
		-- TOP band of the wall, i.e. the layer directly under the one being eaten.
		placeCap(c, capTexture, topBandId, topStuds, topBandFootprint)
	end
end

local function parkAll()
	for _, ring in ipairs(rings) do
		parkRing(ring)
	end
	if cap then
		(cap :: Part).CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
	end
	for _, terrace in ipairs(terraceCaps) do
		terrace.CFrame = CFrame.new(gridCfg.origin.x, PARKED_Y, gridCfg.origin.z)
	end
end

--API
-- New cake / snapshot: force a full re-place next Step (the composition, and so
-- every band's height and texture, has changed).
function CakeWrapper.OnSnapshot()
	lastCakeIndex = -1
	lastActiveIndex = -1
end

--API
-- Park the wall off-screen — the parts/fallback renderer draws the WHOLE cake as
-- visible keycap columns, so the wall would just occlude them (and clip at the
-- top cap). Called by CakeSubsClient when the renderer isn't in editable mode.
function CakeWrapper.Hide()
	if hidden then
		return
	end
	hidden = true
	parkAll()
	lastCakeIndex = -1
	lastActiveIndex = -1
end

--API
-- Per-frame: rebuild the band stack when the cake or the layer gate moved. The
-- wall only actually changes on a new cake and on a layer clear, so this is a
-- dirty check on (cakeIndex, activeBandIndex).
function CakeWrapper.Step(dt: number)
	-- R8: every early return says WHY. These were silent, and when the wall
	-- failed to appear there was nothing in the console to distinguish "never
	-- stepped" from "stepped but had no composition" — which cost a whole
	-- debugging round.
	if fieldModule == nil then
		Log.Once("CakeWrapper", "no-setup", "Step ran before Setup(mirror) -- the outer wall will never build")
		return
	end
	local meta = fieldModule.Meta()
	if meta == nil then
		Log.Once("CakeWrapper", "no-meta", "no cake snapshot yet -- the outer wall waits (normal before the first snapshot)")
		return
	end
	if type(meta.composition) ~= "table" or #meta.composition == 0 then
		Log.Once("CakeWrapper", "no-composition", "the cake snapshot carries no composition -- the outer wall cannot be built")
		return
	end
	if not stepped then
		stepped = true
		Log.Info("CakeWrapper", "first Step with a live snapshot -- building the zone wall")
	end
	hidden = false
	local activeIndex = fieldModule.ActiveBandIndex()
	if meta.cakeIndex == lastCakeIndex and activeIndex == lastActiveIndex then
		return
	end
	local first = lastCakeIndex ~= meta.cakeIndex
	lastCakeIndex = meta.cakeIndex
	lastActiveIndex = activeIndex
	refresh(meta)
	if first then
		local spans = zoneSpans(meta.composition)
		local baseDiameter = footprintGeometry(meta.footprint)
		local topFootprint = (#spans > 0 and spans[#spans].footprint) or meta.footprint
		local topDiameter = footprintGeometry(topFootprint)
		Log.Info(
			"CakeWrapper",
			`wall rebuilt — {#spans} zone(s) over {#meta.composition} bands, `
				.. `{SEGMENTS}-segment rings ⌀{math.floor(topDiameter)}→{math.floor(baseDiameter)}, {#rings} ring(s) + {#terraceCaps} terrace cap(s) pooled`
		)
	end
end

return CakeWrapper
