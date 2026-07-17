--[[
	TreasureConfig — finds buried in the cake (GDD §6.1).

	Treasures are rolled at cake spawn, each pinned to a cell + a reveal
	height. When the surface at that cell drops to the reveal height the
	find pops out (server spawns the pickup, client gets FX). Rewards are
	reward descriptors granted through RewardGrantSubs (ADR-0002).

	weight — relative roll weight. reward kinds: gems / boost / egg / pet.
]]

local TreasureConfig = {}

TreasureConfig.finds = {
	{ id = "berry", nameKey = "find-berry", weight = 40, reward = { kind = "gems", amount = 2 }, color = Color3.fromRGB(200, 40, 80) },
	{ id = "candy-gem", nameKey = "find-candy-gem", weight = 20, reward = { kind = "gems", amount = 5 }, color = Color3.fromRGB(90, 200, 255) },
	{ id = "charm", nameKey = "find-charm", weight = 12, reward = { kind = "gems", amount = 8 }, color = Color3.fromRGB(255, 215, 120) },
	{ id = "bolt", nameKey = "find-bolt", weight = 6, reward = { kind = "gems", amount = 10 }, color = Color3.fromRGB(140, 140, 150) },
	{ id = "whisk", nameKey = "find-whisk", weight = 6, reward = { kind = "gems", amount = 10 }, color = Color3.fromRGB(200, 200, 210) },
	{ id = "lost-phone", nameKey = "find-lost-phone", weight = 3, reward = { kind = "gems", amount = 25 }, color = Color3.fromRGB(40, 40, 45) }, -- Drain the Lake easter egg
	{ id = "golden-slice", nameKey = "find-golden-slice", weight = 5, reward = { kind = "boost", boostId = "golden-slice" }, color = Color3.fromRGB(255, 200, 30) },
	{ id = "capsule", nameKey = "find-capsule", weight = 4, reward = { kind = "egg", eggType = "cycle" }, color = Color3.fromRGB(255, 120, 200) },
	{ id = "trapped-pet", nameKey = "find-trapped-pet", weight = 2, reward = { kind = "egg", eggType = "lucky" }, color = Color3.fromRGB(120, 255, 180) },
}

-- Finds per cake scale with cake volume; every player can collect every
-- find is WRONG — a find is consumed by whoever touches it first (flag on
-- the find, not on the player — GDD §13).
TreasureConfig.spawn = {
	volumePerFind = 2500, -- studs^3 of cake per one find
	minFinds = 8,
	maxFinds = 40,
	minDepthFraction = 0.1, -- no finds in the top 10% (first seconds stay clean)
	pickupLifetime = 45, -- seconds before an uncollected find despawns
}

-- Boosts grantable by finds / dev products. mult applies to the named stat.
TreasureConfig.boosts = {
	["golden-slice"] = { nameKey = "boost-golden-slice", stat = "calories", mult = 2, duration = 60 },
	["boost-15m"] = { nameKey = "boost-15m", stat = "calories", mult = 2, duration = 900 },
}

return TreasureConfig
