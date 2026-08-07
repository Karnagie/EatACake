--[[
	UpgradeTreeConfig — the HONEYCOMB layout for the upgrades tree (R1, purely
	presentational; the server validates purchases from UpgradeConfig alone).

	Two tree shapes the client navigates with a nav-stack:
	  * "root"  — a centre LOGO hex + one CATEGORY hex per group (eating / body /
	              gym), placed at alternating neighbours so they TOUCH the logo.
	              Clicking a category drills into its sub-tree.
	  * one sub-tree per category — a centre BACK hex, then the category's stats'
	              tiers PACKED into a tight spiral blob (HexUtil.Spiral): nearest
	              cells first, so owned (bought first) cluster near the centre and
	              later tiers spiral outward. `stats` is the fill ORDER; each
	              stat's tiers occupy a contiguous arc of the blob.

	Hexes are edge-to-edge (`nodeFill` ≈ 1) — a real honeycomb, no connector
	bridges. LocalUpgradeTree auto-fits the blob into the square canvas.
]]

local UpgradeTreeConfig = {}

-- `nodeFill` = the hex sprite's fraction of its cell; 1.0 = cells touch (their
-- dark outlines meet, like the reference honeycomb). `pad` = canvas margin.
UpgradeTreeConfig.hex = {
	nodeFill = 1.0,
	pad = 0.06,
}

UpgradeTreeConfig.trees = {
	root = {
		logo = { q = 0, r = 0 },
		-- Alternating neighbours of the logo (each touches it): a tight flower.
		categories = {
			{ id = "eating", q = 0, r = -1 },
			{ id = "body", q = -1, r = 1 },
			{ id = "gym", q = 1, r = 0 },
		},
	},
	-- Sub-trees: the ordered stat list packed into a spiral (back at centre).
	eating = { stats = { "biteRadius", "biteDepth", "eatSpeed" } },
	body = { stats = { "capacity", "runSpeed" } },
	gym = { stats = { "gymEff", "burnPerTap", "burnSpeed", "instantBurn" } },
}

-- ONE GLYPH PER NODE — `Theme.Icons` registry NAMES, never asset ids (kit iron
-- rule 2; LocalUpgradeTree attaches the name, HexNode resolves it through
-- `Theme.Icon`, which warns once on a miss and draws a visible fallback).
--
-- This is a HARD requirement of the audience, not decoration: a tier hex renders
-- its name at ~34-43 px in a packed sub-tree, and a large part of this game's
-- players do not read the label at all (squint-test skill). The glyph is what
-- says which stat a hex is, so every stat and every category has one and they
-- must stay mutually distinguishable BY SHAPE — not only by colour, since a
-- whole sub-tree also shares one state colour at a time (all-gray when locked).
--
-- ⚠ `biteRadius` shipped as `UiAim` for exactly one screenshot and was changed:
-- the crosshair is two crossed red bars, and at node size it reads as an X —
-- i.e. as CANCEL, on the hex a player is being asked to buy. It is still in the
-- registry; do not bring it back here. Judge a glyph at NODE size, not in the
-- sprite folder.
--
-- The centre LOGO deliberately has NO icon: it touches the eating category, and
-- a second cake there would read as a duplicate node rather than a title.
UpgradeTreeConfig.icons = {
	stats = {
		biteRadius = "UiPunch", -- fist: a bigger, harder-hitting bite
		biteDepth = "UiHammer", -- hammer: drives DOWN through the layer
		eatSpeed = "UiBolt",
		capacity = "BadgeStorage", -- the belly is a storage box
		runSpeed = "UiShoe",
		gymEff = "UiCharts", -- calories PER burn = a yield, not a flame
		burnPerTap = "UiHand", -- one TAP of the gym button
		burnSpeed = "UiFire", -- the passive drain
		instantBurn = "UiBoom", -- the whole belly, at once
	},
	categories = {
		eating = "UiCake",
		body = "UiStrength",
		gym = "UiDumbbell",
	},
	back = "UiArrowLeft",
}

return UpgradeTreeConfig
