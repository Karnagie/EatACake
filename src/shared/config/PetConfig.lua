--[[
	PetConfig — pet pool, rarity odds and egg types (GDD §9).

	ODDS ARE PLAYER-FACING: the UI must display them verbatim (Roblox policy
	for paid random rewards; good practice for free ones). PetService is the
	ONLY consumer of the weights — rolls happen on the server, never on the
	client (GDD §13).

	Duplicates merge automatically: owning N copies = pet level N, bonus is
	scaled by (1 + mergeBonusPerCopy * (N - 1)).
]]

local PetConfig = {}

-- Displayed as percentages in the reveal / egg UI. Must sum to 100.
PetConfig.rarities = {
	{ id = "common", weight = 60, color = Color3.fromRGB(178, 178, 178) },
	{ id = "uncommon", weight = 25, color = Color3.fromRGB(96, 208, 96) },
	{ id = "rare", weight = 10, color = Color3.fromRGB(80, 150, 255) },
	{ id = "epic", weight = 4, color = Color3.fromRGB(190, 90, 255) },
	{ id = "legendary", weight = 0.9, color = Color3.fromRGB(255, 190, 40) },
	{ id = "secret", weight = 0.1, color = Color3.fromRGB(255, 70, 120) },
}

-- bonus values are PERCENT (0.05 = +5%), aggregated over equipped pets by
-- StatsService. look = simple primitive look for the client follower
-- (shape: "ball"|"cube"|"donut", color) — replace with real models later.
PetConfig.pets = {
	-- common
	{ id = "crumb-mouse", nameKey = "pet-crumb-mouse", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(190, 160, 130) } },
	{ id = "sugar-chick", nameKey = "pet-sugar-chick", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(255, 230, 120) } },
	{ id = "jelly-slug", nameKey = "pet-jelly-slug", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(220, 90, 110) } },
	-- uncommon
	{ id = "frosting-cat", nameKey = "pet-frosting-cat", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(255, 200, 225) } },
	{ id = "cocoa-pup", nameKey = "pet-cocoa-pup", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(120, 75, 45) } },
	{ id = "candy-crab", nameKey = "pet-candy-crab", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(255, 120, 90) } },
	-- rare
	{ id = "caramel-fox", nameKey = "pet-caramel-fox", rarity = "rare", bonus = { calories = 0.2, eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(220, 140, 50) } },
	{ id = "waffle-owl", nameKey = "pet-waffle-owl", rarity = "rare", bonus = { eatSpeed = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(235, 190, 110) } },
	-- epic
	{ id = "gummy-dragon", nameKey = "pet-gummy-dragon", rarity = "epic", bonus = { calories = 0.35, gems = 0.1 }, look = { shape = "donut", color = Color3.fromRGB(120, 230, 120) } },
	{ id = "eclair-unicorn", nameKey = "pet-eclair-unicorn", rarity = "epic", bonus = { eatSpeed = 0.3, calories = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(240, 220, 255) } },
	-- legendary
	{ id = "golden-whale", nameKey = "pet-golden-whale", rarity = "legendary", bonus = { calories = 0.6, eatSpeed = 0.25, gems = 0.25 }, look = { shape = "donut", color = Color3.fromRGB(255, 200, 40) } },
	-- secret
	{ id = "void-muffin", nameKey = "pet-void-muffin", rarity = "secret", bonus = { calories = 1.0, eatSpeed = 0.5, gems = 0.5 }, look = { shape = "donut", color = Color3.fromRGB(40, 20, 60) } },
}

PetConfig.mergeBonusPerCopy = 0.2
PetConfig.equipSlots = 3
PetConfig.equipSlotsVip = 5 -- with the VIP gamepass

-- Egg types: rarity odds overrides (nil weight = use base). Lucky/Mega are
-- dev products (see ShopData); "cycle" is the FREE end-of-cake roll.
PetConfig.eggs = {
	cycle = { nameKey = "egg-cycle" }, -- base odds
	lucky = {
		nameKey = "egg-lucky",
		weights = { common = 35, uncommon = 30, rare = 20, epic = 10, legendary = 4, secret = 1 },
	},
	mega = {
		nameKey = "egg-mega",
		-- guaranteed Rare+
		weights = { common = 0, uncommon = 0, rare = 70, epic = 24, legendary = 5, secret = 1 },
	},
	epic7 = {
		nameKey = "egg-epic7",
		-- day-7 daily streak: guaranteed Epic+ (GDD §12.2)
		weights = { common = 0, uncommon = 0, rare = 0, epic = 90, legendary = 9, secret = 1 },
	},
}

return PetConfig
