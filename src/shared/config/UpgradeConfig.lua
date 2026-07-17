--[[
	UpgradeConfig — the six calorie-bought upgrades (GDD §10).

	cost(level) = baseCost * growth^level  (level = CURRENT level, 0-based:
	the first purchase costs baseCost). The first 3-4 purchases are priced
	so a new player buys something every 10-20 s (§10 onboarding curve).

	Effects are consumed by StatsService only — nothing else interprets
	these tables. `stat` values below are the derived-stat formulas:
	  base + add * level        (additive)
	  base * (1 + pct * level)  (percent)
]]

local UpgradeConfig = {}

UpgradeConfig.order = { "capacity", "biteRadius", "biteDepth", "eatSpeed", "gymEff", "runSpeed" }

UpgradeConfig.upgrades = {
	capacity = {
		id = "capacity",
		nameKey = "upgrade-capacity",
		baseCost = 50,
		growth = 1.15,
		cap = 40,
		-- stomach volume in studs^3 of eaten cake
		base = 150,
		add = 50,
	},
	biteRadius = {
		id = "biteRadius",
		nameKey = "upgrade-bite-radius",
		baseCost = 75,
		growth = 1.18,
		cap = 18,
		-- studs: 3 -> 12
		base = 3,
		add = 0.5,
	},
	biteDepth = {
		id = "biteDepth",
		nameKey = "upgrade-bite-depth",
		baseCost = 60,
		growth = 1.16,
		cap = 40,
		-- studs at crater center, +8% per level
		base = 1.2,
		pct = 0.08,
	},
	eatSpeed = {
		id = "eatSpeed",
		nameKey = "upgrade-eat-speed",
		baseCost = 60,
		growth = 1.16,
		cap = 40,
		-- bites per second, +6% per level
		base = 4,
		pct = 0.06,
	},
	gymEff = {
		id = "gymEff",
		nameKey = "upgrade-gym-eff",
		baseCost = 100,
		growth = 1.2,
		cap = 30,
		-- calories per stored calorie, +5% per level
		base = 1,
		pct = 0.05,
	},
	runSpeed = {
		id = "runSpeed",
		nameKey = "upgrade-run-speed",
		baseCost = 120,
		growth = 1.22,
		cap = 15,
		-- WalkSpeed
		base = 16,
		add = 2,
	},
}

-- Rebirth ("Food Coma", GDD §9): resets calories + these upgrade levels,
-- grants a permanent +25% calories multiplier per rebirth level.
UpgradeConfig.rebirth = {
	resets = { "capacity", "biteRadius", "biteDepth", "eatSpeed", "gymEff", "runSpeed" },
	multPerLevel = 0.25,
	-- Cost of rebirth N (0-based): base * growth^N calories.
	baseCost = 25000,
	growth = 2.2,
	biomes = { "factory", "donut", "candy" }, -- biome index = rebirth level + 1 (capped)
}

return UpgradeConfig
