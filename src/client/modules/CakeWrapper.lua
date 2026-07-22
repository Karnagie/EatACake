--[[
	CakeWrapper — the textured OUTER WALL of the cake (Req 1 rework).

	CakeRenderer draws the current + next edible layer as slabs; this wall hides the
	cake BELOW them. It is a plain anchored Part (Block) — NOT an EditableMesh —
	sized to the loaf, standing from the cake base up to the BOTTOM of the NEXT
	layer (composition[activeIndex-1].bottom) and shrinking as each layer is
	cleared. It wears a RANDOM cake photo (render.wrapper.textures, one per cake by
	cakeIndex) as TILING `Texture` instances on its four sides + top cap — a crater
	cleared to the next-layer floor shows the cap, not a void.

	Why a Part, not the earlier EditableMesh: cheaper (one Part, no mesh budget, no
	async build) and the `Texture` path RELIABLY displays + tiles the image, which
	the MeshPart `TextureContent`-from-URI approach did not (tiling UVs on a
	FixedSize mesh showed no texture). The rounded loaf corners aren't matched
	(a Block has square corners — a ~6-stud poke at the 4 corners, below the
	rounded top layer); the trade is reliability + performance for exact corners.

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

-- Loaf bounding box — match the slab's straight-edge extent ((hx/hz+0.5)·cell·2),
-- so the wall's flat sides line up with the slab's straight edges (corners poke).
local SIZE_X = (FOOTPRINT.hx + 0.5) * CELL * 2
local SIZE_Z = (FOOTPRINT.hz + 0.5) * CELL * 2
-- The four sides + the top cap (bottom is never seen). Textured; tiled.
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }
local PARKED_Y = -1000 -- world Y to hide the wall when there's nothing below to cover

local fieldModule
local part: Part? = nil
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

-- Builds the wall Part + its tiling face Textures once. Synchronous (no async /
-- no EditableMesh budget) — a single procedural functional part, like the
-- collision columns / cake spawn pad.
local function build()
	if built then
		return
	end
	local p = Instance.new("Part")
	p.Name = "CakeWrapper"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = wrapCfg.gloss
	p.Color = wrapCfg.color -- warm cake tint; shows if the texture is missing / transparent
	p.Size = Vector3.new(SIZE_X, 1, SIZE_Z)
	p.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y + PARKED_Y, gridCfg.origin.z)
	for _, face in ipairs(FACES) do
		local tex = Instance.new("Texture")
		tex.Face = face
		tex.StudsPerTileU = wrapCfg.tileStuds
		tex.StudsPerTileV = wrapCfg.tileStuds
		tex.Parent = p
		table.insert(textures, tex)
	end
	p.Parent = workspace
	part = p
	built = true
	applyTexture()
	Log.Info("CakeWrapper", `wrapper wall built — Part {math.floor(SIZE_X)}x{math.floor(SIZE_Z)}, texture={chosenTexture or "none"}`)
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
	if part ~= nil then
		part.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y + PARKED_Y, gridCfg.origin.z)
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
	local p = part :: Part
	if topStuds <= 0.05 then
		-- Only the core remains — nothing below the top layer to hide. Park the
		-- wall off-screen (a Texture renders even on a Transparency=1 part).
		p.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y + PARKED_Y, gridCfg.origin.z)
	else
		p.Size = Vector3.new(SIZE_X, topStuds, SIZE_Z)
		p.CFrame = CFrame.new(gridCfg.origin.x, gridCfg.origin.y + topStuds / 2, gridCfg.origin.z)
	end
end

return CakeWrapper
