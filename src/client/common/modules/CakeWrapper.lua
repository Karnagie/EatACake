--[[
	CakeWrapper — the textured OUTER WALL of the cake (Req 1 rework).

	CakeRenderer draws the current + next edible layer as slabs; this wall hides the
	cake BELOW them. It is a plain anchored Part (CYLINDER) — NOT an EditableMesh —
	sized to the round cake, standing from the cake base up to the BOTTOM of the NEXT
	layer (composition[activeIndex-1].bottom) and shrinking as each layer is
	cleared. It wears a RANDOM cake photo (render.wrapper.textures, one per cake by
	cakeIndex) as TILING `Texture` instances on its curved side + top cap — a crater
	cleared to the next-layer floor shows the cap, not a void.

	Why a Part, not the earlier EditableMesh: cheaper (one Part, no mesh budget, no
	async build) and the `Texture` path RELIABLY displays + tiles the image, which
	the MeshPart `TextureContent`-from-URI approach did not (tiling UVs on a
	FixedSize mesh showed no texture).

	⚠ ROUND VIA A RING OF FLAT BLOCK SEGMENTS (2026-08-03, when the cake became
	round). Three primitives were built side by side in Studio and looked at; only
	the ring survives, and the reason is `Texture` tiling:
	  · `Shape = Enum.PartType.Cylinder` — axis is LOCAL X, so standing it upright
	    takes `CFrame.Angles(0, 0, pi/2)`, which rotates the face UV frames with
	    it. The cake photo lies on its SIDE (cream layers become vertical columns).
	  · `CylinderMesh` — fixes the rotation (mesh axis is the part's own Y), but a
	    part carrying a mesh maps its Decals/Textures through the MESH's UVs, so
	    **`StudsPerTileU/V` is silently IGNORED**: the image is stretched ONCE over
	    the whole cylinder. Measured: 55 -> 20 -> 5 rendered pixel-identical. That
	    also means the photo would re-stretch every time the wall shrinks a layer.
	  · **Flat Block segments** — a real block face, so tiling behaves exactly as
	    it did on the original 4-sided Block wall (verified against a Block control
	    in the same shot). Each segment carries `OffsetStudsU` = its cumulative
	    width so the tiling phase runs CONTINUOUSLY around the ring instead of
	    resetting at every seam. Costs `wrapCfg.segments` parts and shows mild
	    facet shading — the price of keeping `tileStuds` a real knob.
	The TOP CAP is the one place a `CylinderMesh` is still right: it is a flat disc
	seen only through a crater, so a single mapped photo reads as a cross-section
	and no tiling is wanted. Don't "simplify" the side back into one cylinder.

	This used to be a Block sized to the rounded-rect loaf, which poked ~6 studs
	at the 4 corners. Against a DISC a Block would poke R*(sqrt(2)-1) ~ 19 studs
	and the cake would read square from the side — the shape is the point now, so
	the cylinder is not cosmetic polish.

	Local + visual, CanCollide/CanQuery = false (bite raycasts hit the collision
	columns, never this). Driven from CakeSubsClient: Setup(mirror), OnSnapshot()
	(pick the per-cake texture), Step(dt) (track the top-layer bottom). Reads
	LocalCakeField for composition + activeBandIndex.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local Log = require(Shared:WaitForChild("Log"))

local CakeWrapper = {}

local gridCfg = CakeConfig.grid
local wrapCfg = CakeConfig.render.wrapper
local FOOTPRINT = CakeConfig.composition.footprint
local CELL = gridCfg.cell

-- Cake diameter — match the slab's outline radius ((corner+0.5)·cell), which is
-- exactly what CakeRenderer projects its rim verts onto, so the wall meets the
-- slab edge with no lip either way.
local DIAMETER = (FOOTPRINT.corner + 0.5) * CELL * 2
local RADIUS = DIAMETER * 0.5
local SEGMENTS = wrapCfg.segments
-- Chord (the flat face width) and the ring radius to the chord's MIDPOINT, so the
-- segment's two ends land exactly ON the circle rather than inside or outside it.
local SEG_W = 2 * RADIUS * math.sin(math.pi / SEGMENTS)
local SEG_INSET = RADIUS * math.cos(math.pi / SEGMENTS)
local SEG_OVERLAP = 1.02 -- widen each face a hair so neighbours can't show a hairline gap
local PARKED_Y = -1000 -- world Y to hide the wall when there's nothing below to cover

local fieldModule
local segments: { Part } = {}
local cap: Part? = nil
local textures: { Texture } = {}
local built = false
local lastTopStuds = -1 -- dirty check for the wall height
local chosenTexture: string? = nil

--API
function CakeWrapper.Setup(localCakeField)
	fieldModule = localCakeField
end

-- Deterministic per-cake texture pick (no Math.random — cakeIndex drives it).
local function pickTexture(cakeIndex: number): string
	local list = wrapCfg.textures
	return list[(cakeIndex % #list) + 1]
end

local function applyTexture()
	if chosenTexture == nil then
		return
	end
	for _, tex in ipairs(textures) do
		tex.Texture = chosenTexture :: string
	end
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

-- Builds the ring segments + the top cap once. Synchronous (no async / no
-- EditableMesh budget) — procedural functional parts, like the collision columns.
local function build()
	if built then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "CakeWrapper"

	local faceW = SEG_W * SEG_OVERLAP
	for i = 0, SEGMENTS - 1 do
		local p = newWallPart(`WrapperSeg{i}`)
		p.Size = Vector3.new(faceW, 1, wrapCfg.segmentThickness)
		p.Parent = folder
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Back -- +Z local, which the CFrame below points outward
		tex.StudsPerTileU = wrapCfg.tileStuds
		tex.StudsPerTileV = wrapCfg.tileStuds
		-- Continue the tiling PHASE around the ring instead of restarting it on
		-- every segment (which would chop the photo into `SEGMENTS` vertical
		-- slices). Offset by the cumulative FACE width, not arc length, so the
		-- phase is exactly continuous across each seam.
		tex.OffsetStudsU = i * faceW
		tex.Parent = p
		table.insert(textures, tex)
		table.insert(segments, p)
	end

	-- Top cap: a flat disc, so a crater cleared to the next-layer floor shows cake
	-- and not a void. A CylinderMesh is CORRECT here (unlike the side) — the disc
	-- is seen face-on through a crater, and one mapped photo reads as a
	-- cross-section; there is no wrap to tile around.
	local c = newWallPart("WrapperCap")
	c.Size = Vector3.new(DIAMETER, wrapCfg.capThickness, DIAMETER)
	c.Parent = folder
	Instance.new("CylinderMesh").Parent = c
	local capTex = Instance.new("Texture")
	capTex.Face = Enum.NormalId.Top
	capTex.StudsPerTileU = DIAMETER
	capTex.StudsPerTileV = DIAMETER
	capTex.Parent = c
	table.insert(textures, capTex)
	cap = c

	folder.Parent = workspace
	built = true
	applyTexture()
	Log.Info(
		"CakeWrapper",
		`wrapper wall built — {SEGMENTS}-segment ring ⌀{math.floor(DIAMETER)} + cap, tile={wrapCfg.tileStuds}, texture={chosenTexture or "none"}`
	)
end

-- Places every segment + the cap for a wall of `topStuds` height, or parks the
-- whole ring off-screen when `topStuds` is nil.
local function place(topStuds: number?)
	local baseY = gridCfg.origin.y
	for i, p in ipairs(segments) do
		if topStuds == nil then
			p.CFrame = CFrame.new(gridCfg.origin.x, baseY + PARKED_Y, gridCfg.origin.z)
		else
			local ang = (i - 0.5) / SEGMENTS * math.pi * 2
			p.Size = Vector3.new(SEG_W * SEG_OVERLAP, topStuds, wrapCfg.segmentThickness)
			p.CFrame = CFrame.new(gridCfg.origin.x, baseY + topStuds / 2, gridCfg.origin.z)
				* CFrame.Angles(0, -ang, 0)
				* CFrame.new(0, 0, SEG_INSET)
		end
	end
	local c = cap
	if c ~= nil then
		if topStuds == nil then
			c.CFrame = CFrame.new(gridCfg.origin.x, baseY + PARKED_Y, gridCfg.origin.z)
		else
			c.CFrame = CFrame.new(gridCfg.origin.x, baseY + topStuds - wrapCfg.capThickness / 2, gridCfg.origin.z)
		end
	end
end

--API
-- New cake / snapshot: pick this cake's texture, (build once), reset the height.
function CakeWrapper.OnSnapshot()
	local meta = if fieldModule then fieldModule.Meta() else nil
	if meta == nil then
		return
	end
	chosenTexture = pickTexture(meta.cakeIndex)
	lastTopStuds = -1 -- new composition → re-place the wall next Step
	if not built then
		build()
	end
	applyTexture()
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

--API
-- Park the wall off-screen — the parts/fallback renderer draws the WHOLE cake as
-- visible keycap columns, so the wall would just occlude them (and clip at the
-- top cap). Called by CakeSubsClient when the renderer isn't in editable mode.
function CakeWrapper.Hide()
	if built then
		place(nil)
		lastTopStuds = -1 -- re-place if we ever return to editable
	end
end

--API
-- Per-frame: lazy-build, then resize the wall to the current top-layer bottom.
-- The top only actually moves on a layer transition, so this is a dirty check.
function CakeWrapper.Step(dt: number)
	if fieldModule == nil then
		return
	end
	local meta = fieldModule.Meta()
	if meta == nil then
		return
	end
	if not built then
		build()
	end
	local topStuds = wrapperTopStuds(meta)
	if math.abs(topStuds - lastTopStuds) <= 0.01 then
		return
	end
	lastTopStuds = topStuds
	-- Only the core remains — nothing below the top layer to hide. Park the ring
	-- off-screen (a Texture renders even on a Transparency=1 part).
	place(if topStuds <= 0.05 then nil else topStuds)
end

return CakeWrapper
