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

return UpgradeTreeConfig
