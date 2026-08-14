--[[
	CakeLayersConfig — the LAYER LIBRARY and the GROUPS it is organised into.

	Split out of `CakeConfig` (2026-08-07) when layers went from 7 middle
	flavours to 40: `CakeConfig.layers` and `CakeConfig.layerGroups` are still
	the accessors every consumer reads (CakeOps, CakeFieldService, CakeRenderer,
	CakeWaxShell, LocalCakeField), so nothing outside this file changed shape.

	── WHY GROUPS ─────────────────────────────────────────────────────────
	A cake used to roll each layer's identity independently out of one flat
	`middlePool`, so eating it was a random flavour every ~1.4 min and no depth
	ever meant anything. Now a cake is a SEQUENCE OF ZONES — "the chocolate
	zone, then the jelly zone, then cheese" — each several layers deep, and the
	boundary between two zones is where a MINI-BOSS bursts out of the cake
	(features/cake-cycle.md). The wall texture (CakeWrapper) shows the whole
	stack from the side, so the next zone is something you can SEE coming.

	── SHAPE ──────────────────────────────────────────────────────────────
	`layers[id]` — one layer def. Fields are exactly the old contract plus
	`sideTexture`/`sideColor` (see below); the header of `CakeConfig.layers`
	documents each one and is still the reference.
	  sideTexture  rbxassetid IMAGE (never a decal id — a decal renders BLANK
	               on a `Texture`) for this ONE layer's cross-section. Used by
	               the outer wall's top CAP — the disc you see face-on down a
	               crater, which really is a single layer. The wall's vertical
	               bands are per GROUP, not per layer (see `groups` below).
	  sideColor    optional tint under that texture; defaults to `colors.top`.

	`groups` — ordered pool; `RollComposition` picks `composition.groups.count`
	of them per cake, in a random order, and lays them down one after another.
	  id           kebab-case, unique (docs/registries/data-keys.md)
	  nameKey      locale key for the announce banner ("CHOCOLATE ZONE!")
	  members      layer ids, in no particular order; the roller walks them with
	               no immediate repeat, so a 10-layer zone cycles its variants
	  sideTexture  the ZONE's image on the outer wall
	  sideColor    the ZONE's tint under it
	⚠ **The wall is ONE BAND PER GROUP, not per layer** (2026-08-07, by request).
	Per-layer bands drew ~28 near-identical stripes up the side and read as
	noise; four chunky zone bands say "chocolate, then sponge, then butter, then
	cream", which is exactly the thing a player needs to see coming — it is what
	the mini-boss gates are drawn on. `groupOfLayer` is the reverse index
	`CakeWrapper` uses to get from a band's LAYER id back to its zone.

	── TUNING RULE THAT MATTERS ───────────────────────────────────────────
	⚠ `hardness` and `calories` used to be free per layer because identity was
	RANDOM — a hard/rich layer averaged out inside every cake. With zones they
	do NOT average out: a whole 6-10 layer stretch now shares one value, so the
	spread became a per-ZONE swing in clear time and income. Both were therefore
	NARROWED against the pre-group values:
	  hardness  0.85-1.25 -> 0.95-1.12   (chocolate is still the hardest)
	  calories  0.122-0.237 -> 0.145-0.197, pool mean held at ~0.174 (the old
	            `middlePool` mean) so income per bite is unchanged
	Same reasoning for `walkSpeedMult`/`jumpMult`: caramel at 0.6 speed was fun
	as one layer in twenty and miserable as a zone, so the extremes are pulled
	in. Re-measure with `tools/headless-sim/pacing_scenario.lua` after touching
	`hardness`, and with `tools/balance-model/pacing.py` after `calories`.
]]

local CakeLayersConfig = {}

-- Data construction only (NOT game logic — see the CakeConfig header rule):
-- every variant of a group shares its physics and overrides only what makes it
-- a different flavour. Written out per layer this file would be ~1500 lines of
-- copy-paste, and a group whose members silently disagreed on `hardness` is the
-- exact drift this prevents.
local function variant(base, overrides)
	local def = table.clone(base)
	for key, value in pairs(overrides) do
		def[key] = value
	end
	return def
end

local layers = {}
local groups = {}
local groupOfLayer = {}
local rainbowGroups = {}

-- `wall` = how this whole ZONE reads from OUTSIDE the cake: the outer wall is
-- ONE band per GROUP (not per layer — user req 2026-08-07), so the side of the
-- cake says "chocolate, then sponge, then butter, then cream" rather than
-- showing 28 near-identical stripes. `texture` is the family's image, `color`
-- the tint under it. Per-LAYER `sideTexture` is still used, but only for the
-- wall's top CAP — the cross-section seen face-on down a crater, which IS a
-- single layer. See `CakeWrapper`.
local function group(id: string, nameKey: string, base, members, wall)
	local ids = {}
	for _, entry in ipairs(members) do
		local def = variant(base, entry)
		assert(layers[def.id] == nil, `duplicate cake layer id '{def.id}'`)
		layers[def.id] = def
		table.insert(ids, def.id)
	end
	local def = {
		id = id,
		nameKey = nameKey,
		members = ids,
		sideTexture = wall and wall.texture,
		sideColor = wall and wall.color,
	}
	table.insert(groups, def)
	-- Reverse index for the client: a band only carries its LAYER id, so this is
	-- how `CakeWrapper` gets from a band to the zone whose wall band it belongs
	-- to — no protocol change, the mapping is static config.
	for _, layerId in ipairs(ids) do
		groupOfLayer[layerId] = def
	end
end

-- ── The icing cap (NOT part of a group) ─────────────────────────────────
-- Always band #1 from the top, on every cake. It FLOWS (repose 1.5), which is
-- what lets a stationary Auto-Eat player keep earning while their crater
-- refills — see features/cake-sim.md. Do not fold it into a group.
layers.frosting = {
	id = "frosting",
	repose = 1.5,
	flowRate = 0.6,
	hardness = 0.85,
	calories = 0.139,
	colors = { top = Color3.fromRGB(255, 182, 220), bottom = Color3.fromRGB(246, 148, 196) },
	texture = "rbxassetid://104319784921009", -- confetti frosting/icing
	sideTexture = "rbxassetid://104319784921009",
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.08,
	oozeSpeed = 4,
	squishMult = 1.6,
	jumpMult = 1,
	sfx = "squish",
	shatterFx = false,
	wobble = false,
}

-- ── The cavity floor (never edible) ─────────────────────────────────────
layers.core = {
	id = "core",
	repose = math.huge,
	flowRate = 0,
	hardness = math.huge,
	calories = 0,
	colors = { top = Color3.fromRGB(255, 242, 214), bottom = Color3.fromRGB(246, 226, 192) },
	-- No sideTexture: the wall stops at the NEXT layer's bottom, so the core
	-- band's rim is never the outermost thing on screen.
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.05,
	oozeSpeed = 12,
	squishMult = 0,
	jumpMult = 1,
	sfx = "squish",
	shatterFx = false,
	wobble = false,
}

-- ── CHOCOLATE — hard shell: cliffs, never flows, shatters when bitten ────
group("chocolate", "zone-chocolate", {
	repose = math.huge,
	flowRate = 0,
	hardness = 1.12,
	calories = 0.197,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.15,
	oozeSpeed = 12, -- nothing flows anyway; bite edits snap
	squishMult = 0,
	jumpMult = 1,
	sfx = "crack",
	shatterFx = true, -- client: shard burst on bite
	wobble = false,
}, {
	{
		id = "chocolate",
		colors = { top = Color3.fromRGB(96, 58, 34), bottom = Color3.fromRGB(66, 38, 22) },
		texture = "rbxassetid://18310304910",
		sideTexture = "rbxassetid://18310304910",
	},
	{
		id = "chocolate-white",
		colors = { top = Color3.fromRGB(245, 232, 205), bottom = Color3.fromRGB(222, 204, 168) },
		texture = "rbxassetid://18903274127",
		sideTexture = "rbxassetid://18903274127",
		gloss = 0.2,
	},
	{
		-- A SPREAD, not a slab: the one chocolate that oozes and squishes.
		id = "chocolate-nutella",
		colors = { top = Color3.fromRGB(112, 68, 42), bottom = Color3.fromRGB(78, 44, 26) },
		texture = "rbxassetid://432607338",
		sideTexture = "rbxassetid://432607338",
		repose = 4,
		flowRate = 0.15,
		hardness = 1.0,
		oozeSpeed = 2,
		squishMult = 0.7,
		gloss = 0.3,
		sfx = "stretch",
		shatterFx = false,
	},
	{
		id = "chocolate-dubai",
		colors = { top = Color3.fromRGB(126, 158, 74), bottom = Color3.fromRGB(88, 112, 48) },
		texture = "rbxassetid://18902649024", -- pistachio frosting
		sideTexture = "rbxassetid://18902649024",
		hardness = 1.1,
	},
}, {
	-- ZONE WALL: a solid dark chocolate slab. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://107288734071589",
	color = Color3.fromRGB(96, 58, 34),
})

-- ── JELLY — see-through marmalade: translucent, jiggles, springy ─────────
group("jelly", "zone-jelly", {
	repose = 4.5,
	flowRate = 0.2,
	hardness = 1.05,
	calories = 0.181,
	-- Glass: wet refraction on high quality, plastic-smooth on low. KNOWN
	-- engine tradeoff: semi-transparent Glass hides TRANSPARENT things behind
	-- it (particles) on high quality; opaque layers below render fine.
	material = Enum.Material.Glass,
	transparency = 0.45,
	gloss = 0.15,
	oozeSpeed = 6,
	squishMult = 1.3,
	jumpMult = 1.12,
	bounce = 0.16,
	walkSpeedMult = 0.9,
	sfx = "blorp",
	shatterFx = false,
	wobble = true, -- client: sine wave over surface vertices
}, {
	{
		id = "jelly",
		colors = { top = Color3.fromRGB(238, 58, 88), bottom = Color3.fromRGB(196, 30, 62) },
		sideTexture = "rbxassetid://15142269976", -- red jelly
	},
	{
		id = "jelly-lime",
		colors = { top = Color3.fromRGB(130, 222, 90), bottom = Color3.fromRGB(96, 180, 60) },
		sideTexture = "rbxassetid://7185243377", -- green jelly
	},
	{
		id = "jelly-berry",
		colors = { top = Color3.fromRGB(150, 90, 220), bottom = Color3.fromRGB(110, 60, 175) },
		sideTexture = "rbxassetid://71141528046438",
	},
	{
		id = "jelly-orange",
		colors = { top = Color3.fromRGB(255, 150, 50), bottom = Color3.fromRGB(220, 110, 25) },
		sideTexture = "rbxassetid://15142269976",
		sideColor = Color3.fromRGB(255, 168, 70),
	},
}, {
	-- ZONE WALL: translucent red marmalade. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://125831243898226",
	color = Color3.fromRGB(222, 52, 84),
})

-- ── BUTTER — rich soft slab: deepest dents, slow greasy creep ────────────
group("butter", "zone-butter", {
	repose = 3.2,
	flowRate = 0.25,
	hardness = 1.0,
	calories = 0.189,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.22,
	oozeSpeed = 3,
	squishMult = 1.5,
	jumpMult = 1,
	walkSpeedMult = 0.95,
	sfx = "squish",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "butter",
		colors = { top = Color3.fromRGB(255, 226, 140), bottom = Color3.fromRGB(236, 202, 105) },
		sideTexture = "rbxassetid://5386064531",
	},
	{
		id = "butter-peanut",
		colors = { top = Color3.fromRGB(206, 150, 78), bottom = Color3.fromRGB(176, 120, 55) },
		sideTexture = "rbxassetid://101432680152451",
		sfx = "stretch",
	},
	{
		id = "butter-honey",
		colors = { top = Color3.fromRGB(240, 190, 90), bottom = Color3.fromRGB(215, 160, 60) },
		sideTexture = "rbxassetid://18902696838",
		gloss = 0.32,
	},
	{
		id = "butter-salted",
		colors = { top = Color3.fromRGB(250, 240, 200), bottom = Color3.fromRGB(230, 218, 175) },
		sideTexture = "rbxassetid://5386064531",
	},
}, {
	-- ZONE WALL: a thick pale butter slab. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://128135991482186",
	color = Color3.fromRGB(250, 220, 135),
})

-- ── CHEESE — dense and chewy: barely flows, drags the feet ───────────────
group("cheese", "zone-cheese", {
	repose = 3.8,
	flowRate = 0.12,
	hardness = 1.06,
	calories = 0.194,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.18,
	oozeSpeed = 2,
	squishMult = 0.9,
	jumpMult = 0.95,
	walkSpeedMult = 0.9,
	sfx = "stretch",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "cheesecake",
		colors = { top = Color3.fromRGB(250, 222, 150), bottom = Color3.fromRGB(230, 196, 115) },
		sideTexture = "rbxassetid://18902662835",
	},
	{
		id = "cheese-cream",
		colors = { top = Color3.fromRGB(255, 248, 230), bottom = Color3.fromRGB(238, 228, 200) },
		sideTexture = "rbxassetid://432607604",
	},
	{
		id = "cheese-mascarpone",
		colors = { top = Color3.fromRGB(252, 240, 215), bottom = Color3.fromRGB(234, 216, 180) },
		sideTexture = "rbxassetid://18902662835",
		sideColor = Color3.fromRGB(252, 240, 215),
		squishMult = 1.2,
	},
	{
		id = "cheese-blue",
		colors = { top = Color3.fromRGB(222, 226, 205), bottom = Color3.fromRGB(190, 196, 165) },
		sideTexture = "rbxassetid://85021510700546",
	},
}, {
	-- ZONE WALL: baked cheesecake. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://108857814627485",
	color = Color3.fromRGB(248, 220, 150),
})

-- ── JAM — sticky and glossy: slow creep, slippery-slow boots ─────────────
group("jam", "zone-jam", {
	repose = 5.0,
	flowRate = 0.1,
	hardness = 1.05,
	calories = 0.185,
	material = Enum.Material.SmoothPlastic,
	transparency = 0.15,
	gloss = 0.4,
	oozeSpeed = 1.4,
	squishMult = 1.1,
	jumpMult = 0.9,
	walkSpeedMult = 0.85,
	sfx = "blorp",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "jam-strawberry",
		colors = { top = Color3.fromRGB(225, 40, 60), bottom = Color3.fromRGB(185, 20, 42) },
		sideTexture = "rbxassetid://1249078209",
	},
	{
		id = "jam-apricot",
		colors = { top = Color3.fromRGB(250, 160, 60), bottom = Color3.fromRGB(222, 124, 30) },
		sideTexture = "rbxassetid://6302878736",
	},
	{
		id = "jam-blueberry",
		colors = { top = Color3.fromRGB(90, 70, 180), bottom = Color3.fromRGB(62, 46, 140) },
		sideTexture = "rbxassetid://115991175913833",
		sideColor = Color3.fromRGB(120, 100, 210),
	},
	{
		id = "jam-cherry",
		colors = { top = Color3.fromRGB(180, 25, 50), bottom = Color3.fromRGB(140, 12, 34) },
		sideTexture = "rbxassetid://1249078209",
		sideColor = Color3.fromRGB(190, 40, 62),
	},
}, {
	-- ZONE WALL: glossy red preserve. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://122001732351946",
	color = Color3.fromRGB(215, 45, 62),
})

-- ── SPONGE — TRAMPOLINE: springy pores, you jump higher and bounce ───────
group("sponge", "zone-sponge", {
	repose = 3.0,
	flowRate = 0.35,
	hardness = 1.0,
	calories = 0.151,
	material = Enum.Material.Sand, -- grainy crumb pores
	transparency = 0,
	gloss = 0.02,
	oozeSpeed = 2.5,
	squishMult = 1.0,
	jumpMult = 1.4,
	bounce = 0.3, -- landing restitution: a gentle boing
	sfx = "crumble",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "sponge",
		colors = { top = Color3.fromRGB(250, 198, 95), bottom = Color3.fromRGB(226, 168, 70) },
		sideTexture = "rbxassetid://16776919382",
	},
	{
		id = "sponge-chocolate",
		colors = { top = Color3.fromRGB(150, 96, 58), bottom = Color3.fromRGB(118, 72, 40) },
		sideTexture = "rbxassetid://170617913",
	},
	{
		id = "sponge-honey",
		colors = { top = Color3.fromRGB(232, 180, 105), bottom = Color3.fromRGB(206, 152, 78) },
		sideTexture = "rbxassetid://16290984795",
	},
	{
		id = "sponge-red-velvet",
		colors = { top = Color3.fromRGB(200, 60, 70), bottom = Color3.fromRGB(166, 40, 50) },
		sideTexture = "rbxassetid://137628720064387",
		sideColor = Color3.fromRGB(210, 80, 88),
	},
}, {
	-- ZONE WALL: open vanilla crumb. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://92412866129588",
	color = Color3.fromRGB(246, 196, 100),
})

-- ── CREAM — soft oozy custard: eats easily, creeps back, pillowy ─────────
group("cream", "zone-cream", {
	repose = 2.5,
	flowRate = 0.4,
	hardness = 0.98,
	calories = 0.16,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.12,
	oozeSpeed = 5,
	squishMult = 1.4,
	jumpMult = 1,
	sfx = "squish",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "filling",
		colors = { top = Color3.fromRGB(255, 224, 150), bottom = Color3.fromRGB(238, 198, 120) },
		texture = "rbxassetid://432607426", -- custard/cream filling
		sideTexture = "rbxassetid://432607426",
	},
	{
		id = "cream-whipped",
		colors = { top = Color3.fromRGB(255, 252, 246), bottom = Color3.fromRGB(240, 236, 228) },
		sideTexture = "rbxassetid://18902662835",
	},
	{
		id = "cream-condensed",
		colors = { top = Color3.fromRGB(255, 232, 180), bottom = Color3.fromRGB(238, 208, 145) },
		sideTexture = "rbxassetid://13304044697",
		gloss = 0.28,
	},
	{
		id = "cream-vanilla",
		colors = { top = Color3.fromRGB(255, 244, 214), bottom = Color3.fromRGB(240, 226, 188) },
		sideTexture = "rbxassetid://18902662835",
		sideColor = Color3.fromRGB(255, 244, 214),
	},
}, {
	-- ZONE WALL: custard/cream filling. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://89651860076408",
	color = Color3.fromRGB(255, 232, 175),
})

-- ── CANDY — almost LIQUID: spectacular avalanches, light feet ────────────
group("candy", "zone-candy", {
	repose = 0.5,
	flowRate = 0.95,
	hardness = 0.95,
	calories = 0.145,
	material = Enum.Material.Fabric,
	transparency = 0,
	gloss = 0.03,
	oozeSpeed = 9, -- visibly pours
	squishMult = 1.2,
	jumpMult = 1.05,
	walkSpeedMult = 1.15,
	sfx = "pshhh",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "cotton",
		colors = { top = Color3.fromRGB(255, 176, 224), bottom = Color3.fromRGB(158, 196, 255) },
		sideTexture = "rbxassetid://113375456705299",
	},
	{
		id = "cotton-blue",
		colors = { top = Color3.fromRGB(150, 200, 255), bottom = Color3.fromRGB(110, 165, 235) },
		sideTexture = "rbxassetid://113375456705299",
		sideColor = Color3.fromRGB(150, 200, 255),
	},
	{
		id = "marshmallow",
		colors = { top = Color3.fromRGB(255, 245, 240), bottom = Color3.fromRGB(238, 222, 215) },
		sideTexture = "rbxassetid://70971440596659",
		repose = 1.6, -- pillowy, holds a shape better than spun sugar
		flowRate = 0.5,
		squishMult = 1.5,
		bounce = 0.22,
	},
	{
		id = "marshmallow-grape",
		colors = { top = Color3.fromRGB(200, 150, 235), bottom = Color3.fromRGB(168, 116, 205) },
		sideTexture = "rbxassetid://132815160582661",
		repose = 1.6,
		flowRate = 0.5,
		squishMult = 1.5,
		bounce = 0.22,
	},
}, {
	-- ZONE WALL: spun sugar. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://129212637516857",
	color = Color3.fromRGB(255, 180, 220),
})

-- ── CARAMEL — STICKY HONEY: slowest visible creep, boots glued ───────────
group("caramel", "zone-caramel", {
	repose = 5.5,
	flowRate = 0.07,
	hardness = 1.1,
	calories = 0.192,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.35, -- wet glaze
	oozeSpeed = 0.8, -- honey-slow flow
	squishMult = 0.6,
	jumpMult = 0.85,
	walkSpeedMult = 0.75,
	sfx = "stretch",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "caramel",
		colors = { top = Color3.fromRGB(230, 150, 42), bottom = Color3.fromRGB(190, 110, 22) },
		sideTexture = "rbxassetid://116117864674647",
	},
	{
		id = "caramel-salted",
		colors = { top = Color3.fromRGB(210, 130, 45), bottom = Color3.fromRGB(172, 96, 26) },
		sideTexture = "rbxassetid://116117864674647",
		sideColor = Color3.fromRGB(210, 130, 45),
	},
	{
		id = "toffee",
		colors = { top = Color3.fromRGB(170, 96, 36), bottom = Color3.fromRGB(136, 70, 22) },
		sideTexture = "rbxassetid://845255656",
		hardness = 1.12,
		sfx = "crack",
		shatterFx = true,
	},
	{
		id = "caramel-coffee",
		colors = { top = Color3.fromRGB(140, 96, 60), bottom = Color3.fromRGB(108, 70, 42) },
		sideTexture = "rbxassetid://845275420",
	},
}, {
	-- ZONE WALL: wet caramel. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://112471440209620",
	color = Color3.fromRGB(226, 148, 45),
})

-- ── CRUMB — loose sand: pours fast, soft steps ───────────────────────────
group("crumb", "zone-crumb", {
	repose = 1.0,
	flowRate = 0.85,
	hardness = 0.97,
	calories = 0.147,
	material = Enum.Material.Sand,
	transparency = 0,
	gloss = 0,
	oozeSpeed = 7,
	squishMult = 1.1,
	jumpMult = 1,
	sfx = "shhh",
	shatterFx = false,
	wobble = false,
}, {
	{
		id = "crumb",
		colors = { top = Color3.fromRGB(164, 112, 64), bottom = Color3.fromRGB(132, 88, 50) },
		sideTexture = "rbxassetid://16272228746",
	},
	{
		id = "crumb-cookie",
		colors = { top = Color3.fromRGB(70, 58, 54), bottom = Color3.fromRGB(48, 40, 38) },
		sideTexture = "rbxassetid://109100549141423",
	},
	{
		id = "crumb-biscuit",
		colors = { top = Color3.fromRGB(208, 168, 110), bottom = Color3.fromRGB(180, 140, 86) },
		sideTexture = "rbxassetid://6483198455",
	},
	{
		id = "crumb-cereal",
		colors = { top = Color3.fromRGB(196, 142, 72), bottom = Color3.fromRGB(166, 116, 54) },
		sideTexture = "rbxassetid://16272228746",
	},
}, {
	-- ZONE WALL: loose biscuit crumb. The outer wall is one band per GROUP, so this is
	-- what the whole zone looks like from outside the cake.
	texture = "rbxassetid://132204542550913",
	color = Color3.fromRGB(168, 116, 68),
})

-- ── SELECTABLE RAINBOW CAKE — fixed, soft colour terraces ─────────────
-- These seven groups are deliberately NOT inserted into `groups`: the classic
-- cake draws randomly from that pool, while cake-rainbow must always read as
-- one ordered ROYGBIV spectrum (red at the top through violet at the base). Each group
-- has exactly ONE layer id, so every band in that zone is the same colour.
--
-- The material is regular/opaque SmoothPlastic. The stepped pyramid must hold
-- its authored silhouette, so the heightfield material itself does not flow;
-- softness is the heavy client-side underfoot dent (`squishMult`). An empty
-- sideTexture is intentional: CakeWrapper renders the zone as flat colour
-- rather than falling back to a cake photograph.
local rainbowBase = {
	repose = math.huge,
	flowRate = 0,
	hardness = 0.9,
	calories = 0.174,
	material = Enum.Material.SmoothPlastic,
	transparency = 0,
	gloss = 0.08,
	oozeSpeed = 12,
	squishMult = 2.6,
	jumpMult = 0.95,
	bounce = 0.05,
	sfx = "squish",
	shatterFx = false,
	wobble = false,
}

local rainbowSpecs = {
	{ id = "rainbow-red", nameKey = "zone-rainbow-red", top = Color3.fromRGB(245, 55, 70), bottom = Color3.fromRGB(195, 25, 45) },
	{ id = "rainbow-orange", nameKey = "zone-rainbow-orange", top = Color3.fromRGB(255, 145, 45), bottom = Color3.fromRGB(220, 85, 25) },
	{ id = "rainbow-yellow", nameKey = "zone-rainbow-yellow", top = Color3.fromRGB(255, 225, 55), bottom = Color3.fromRGB(220, 175, 20) },
	{ id = "rainbow-green", nameKey = "zone-rainbow-green", top = Color3.fromRGB(65, 205, 95), bottom = Color3.fromRGB(25, 150, 60) },
	{ id = "rainbow-blue", nameKey = "zone-rainbow-blue", top = Color3.fromRGB(55, 145, 245), bottom = Color3.fromRGB(30, 85, 195) },
	{ id = "rainbow-indigo", nameKey = "zone-rainbow-indigo", top = Color3.fromRGB(82, 79, 214), bottom = Color3.fromRGB(51, 45, 159) },
	{ id = "rainbow-violet", nameKey = "zone-rainbow-violet", top = Color3.fromRGB(174, 78, 232), bottom = Color3.fromRGB(119, 45, 180) },
}

for _, spec in ipairs(rainbowSpecs) do
	local layer = variant(rainbowBase, {
		id = spec.id,
		colors = { top = spec.top, bottom = spec.bottom },
		sideTexture = "",
		sideColor = spec.top,
	})
	assert(layers[layer.id] == nil, `duplicate cake layer id '{layer.id}'`)
	layers[layer.id] = layer
	local groupDef = {
		id = spec.id,
		nameKey = spec.nameKey,
		members = { spec.id },
		sideTexture = "",
		sideColor = spec.top,
	}
	table.insert(rainbowGroups, groupDef)
	groupOfLayer[spec.id] = groupDef
end

CakeLayersConfig.layers = layers
CakeLayersConfig.groups = groups
CakeLayersConfig.rainbowGroups = rainbowGroups
-- layer id -> its group def. `CakeWrapper` walks a band's LAYER id back to
-- the zone it belongs to; frosting and core are deliberately absent (neither
-- is in a group).
CakeLayersConfig.groupOfLayer = groupOfLayer

return CakeLayersConfig
