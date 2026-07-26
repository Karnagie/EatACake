--[[
	PetConfig — the SQUISHY roster, rarity odds and egg types (GDD §9).

	"Pets" are squishies: squishy toys shaped like food. The module name, the
	remote names and every `id` below keep the pet-* naming ON PURPOSE — an `id`
	is a DataStore key inside the profile's `pets.owned` map, so renaming one
	orphans a player's collection. Only DISPLAY names changed; ids are forever.
	Adding a NEW id is safe and needs no migration (it is simply absent from
	everyone's `owned` map) — which is how this roster grew from 12 to 30.

	ODDS ARE PLAYER-FACING: the UI must display them verbatim (Roblox policy
	for paid random rewards; good practice for free ones). PetService is the
	ONLY consumer of the weights — rolls happen on the server, never on the
	client (GDD §13). Adding squishies to a tier does NOT change that tier's
	odds; it splits the tier's share across more entries.

	Duplicates merge automatically: owning N copies = pet level N, bonus is
	scaled by (1 + mergeBonusPerCopy * (N - 1)).

	`icon` is a Theme.Icons key (src/shared/UIKit/Icons.lua), named explicitly
	instead of derived from the id, so a typo warns instead of silently
	rendering the fallback glyph.
]]

local PetConfig = {}

-- Displayed as percentages in the reveal / egg UI. Must sum to 100.
-- Colour is NOT here: Theme.Rarity is the single source of rarity colour, and
-- this second palette disagreed with it (it called Common grey while the kit
-- drew Common blue). Verified unused — PetService and LocalPetsService read
-- only `.id` and `.weight`.
PetConfig.rarities = {
	{ id = "common", weight = 60 },
	{ id = "uncommon", weight = 25 },
	{ id = "rare", weight = 10 },
	{ id = "epic", weight = 4 },
	{ id = "legendary", weight = 0.9 },
	{ id = "secret", weight = 0.1 },
}

-- bonus values are PERCENT (0.05 = +5%), aggregated over equipped pets by
-- StatsService. look = simple primitive look for the client follower
-- (shape: "ball"|"cube"|"donut", color) — replace with real models later.
-- The primary stat ROTATES within each tier (calories -> eatSpeed -> gems) so
-- no tier is a dead end for a build and Equip-Best always has a real choice.
PetConfig.pets = {
	-- ===== common — the pick-and-mix shelf =====
	{ id = "crumb-mouse", nameKey = "pet-crumb-mouse", icon = "SqIceCup", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(190, 160, 130) } },
	{ id = "sugar-chick", nameKey = "pet-sugar-chick", icon = "SqIceCupWink", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(255, 230, 120) } },
	{ id = "jelly-slug", nameKey = "pet-jelly-slug", icon = "SqIceCupCalm", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(220, 90, 110) } },
	{ id = "berry-gummy", nameKey = "pet-berry-gummy", icon = "SqAquaDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(228, 62, 82) } },
	{ id = "lime-gummy", nameKey = "pet-lime-gummy", icon = "SqMintDrop", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(120, 220, 110) } },
	{ id = "lemon-gummy", nameKey = "pet-lemon-gummy", icon = "SqBlushPink", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(250, 220, 90) } },
	{ id = "loop-pop", nameKey = "pet-loop-pop", icon = "SqOceanDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(255, 150, 200) } },

	-- ===== uncommon — the bakery counter =====
	{ id = "frosting-cat", nameKey = "pet-frosting-cat", icon = "SqLilacDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "donut", color = Color3.fromRGB(255, 200, 225) } },
	{ id = "cocoa-pup", nameKey = "pet-cocoa-pup", icon = "SqSunsetDrop", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(120, 75, 45) } },
	{ id = "candy-crab", nameKey = "pet-candy-crab", icon = "SqStoneLoaf", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(255, 120, 90) } },
	{ id = "top-muffin", nameKey = "pet-top-muffin", icon = "SqPeachGlow", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(196, 150, 105) } },
	{ id = "flake-crescent", nameKey = "pet-flake-crescent", icon = "SqCreamWink", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(235, 190, 120) } },
	{ id = "blue-drop", nameKey = "pet-blue-drop", icon = "SqMintGlow", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(110, 190, 255) } },
	{ id = "peppermint-stick", nameKey = "pet-peppermint-stick", icon = "SqGrapeDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(255, 255, 255) } },

	-- ===== rare — the patisserie =====
	{ id = "caramel-fox", nameKey = "pet-caramel-fox", icon = "SqPlumSparkle", rarity = "rare", bonus = { calories = 0.2, eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(220, 140, 50) } },
	{ id = "waffle-owl", nameKey = "pet-waffle-owl", icon = "SqStrawHat", rarity = "rare", bonus = { eatSpeed = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(235, 190, 110) } },
	{ id = "rose-macaron", nameKey = "pet-rose-macaron", icon = "SqLeafSprout", rarity = "rare", bonus = { gems = 0.2, calories = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(255, 170, 200) } },
	{ id = "sky-macaron", nameKey = "pet-sky-macaron", icon = "SqBonsaiPot", rarity = "rare", bonus = { calories = 0.2, gems = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(150, 205, 255) } },
	{ id = "swirl-roll", nameKey = "pet-swirl-roll", icon = "SqSkyBeam", rarity = "rare", bonus = { eatSpeed = 0.2, calories = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(210, 150, 90) } },
	{ id = "stack-cakes", nameKey = "pet-stack-cakes", icon = "SqPastelArc", rarity = "rare", bonus = { gems = 0.2, eatSpeed = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(225, 175, 105) } },

	-- ===== epic — the diner (savoury food in a cake game: the joke tier, and
	-- the one players screenshot) =====
	{ id = "gummy-dragon", nameKey = "pet-gummy-dragon", icon = "SqCoolShades", rarity = "epic", bonus = { calories = 0.35, gems = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(120, 230, 120) } },
	{ id = "eclair-unicorn", nameKey = "pet-eclair-unicorn", icon = "SqBonsaiTwist", rarity = "epic", bonus = { eatSpeed = 0.35, calories = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(240, 220, 255) } },
	{ id = "slice-supreme", nameKey = "pet-slice-supreme", icon = "SqEmberDrop", rarity = "epic", bonus = { gems = 0.35, eatSpeed = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(230, 140, 70) } },
	{ id = "crunch-taco", nameKey = "pet-crunch-taco", icon = "SqVisorVoid", rarity = "epic", bonus = { calories = 0.35, eatSpeed = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(240, 200, 110) } },
	{ id = "triple-scoop", nameKey = "pet-triple-scoop", icon = "SqStormCloud", rarity = "epic", bonus = { eatSpeed = 0.35, gems = 0.15 }, look = { shape = "ball", color = Color3.fromRGB(255, 210, 230) } },

	-- ===== legendary — the showpiece shelf =====
	{ id = "golden-whale", nameKey = "pet-golden-whale", icon = "SqCrownGold", rarity = "legendary", bonus = { calories = 0.5, eatSpeed = 0.3, gems = 0.2 }, look = { shape = "donut", color = Color3.fromRGB(255, 200, 40) } },
	{ id = "the-cake", nameKey = "pet-the-cake", icon = "SqHaloCup", rarity = "legendary", bonus = { eatSpeed = 0.5, gems = 0.3, calories = 0.2 }, look = { shape = "cube", color = Color3.fromRGB(255, 235, 205) } },
	{ id = "cloud-floss", nameKey = "pet-cloud-floss", icon = "SqRainbowDrop", rarity = "legendary", bonus = { gems = 0.5, calories = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(255, 170, 235) } },
	{ id = "ruby-berry", nameKey = "pet-ruby-berry", icon = "SqVoidCup", rarity = "legendary", bonus = { calories = 0.5, gems = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(240, 60, 80) } },

	-- ===== secret =====
	{ id = "void-muffin", nameKey = "pet-void-muffin", icon = "SqDevilWing", rarity = "secret", bonus = { calories = 1.0, eatSpeed = 0.5, gems = 0.5 }, look = { shape = "donut", color = Color3.fromRGB(40, 20, 60) } },

	-- ===== costumed set (added with the render pack; new ids need no
	-- migration, they are simply absent from every existing profile) =====
	{ id = "snow-drop", nameKey = "pet-snow-drop", icon = "SqSnowDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(236, 244, 250) } },
	{ id = "stripe-shell", nameKey = "pet-stripe-shell", icon = "SqStripeShell", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(230, 240, 250) } },
	{ id = "butter-cup", nameKey = "pet-butter-cup", icon = "SqButterCup", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(250, 220, 90) } },
	{ id = "lavender-drop", nameKey = "pet-lavender-drop", icon = "SqLavenderDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(216, 196, 240) } },
	{ id = "lime-glow", nameKey = "pet-lime-glow", icon = "SqLimeGlow", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(200, 240, 120) } },
	{ id = "amber-drop", nameKey = "pet-amber-drop", icon = "SqAmberDrop", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(250, 190, 120) } },
	{ id = "blossom", nameKey = "pet-blossom", icon = "SqBlossom", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(255, 170, 200) } },
	{ id = "sombrero", nameKey = "pet-sombrero", icon = "SqSombrero", rarity = "rare", bonus = { calories = 0.2, eatSpeed = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(240, 210, 130) } },
	{ id = "viking-helm", nameKey = "pet-viking-helm", icon = "SqVikingHelm", rarity = "rare", bonus = { eatSpeed = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(190, 160, 120) } },
	{ id = "green-blade", nameKey = "pet-green-blade", icon = "SqGreenBlade", rarity = "rare", bonus = { gems = 0.2, calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(120, 220, 110) } },
	{ id = "suit", nameKey = "pet-suit", icon = "SqSuit", rarity = "rare", bonus = { calories = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(60, 70, 100) } },
	{ id = "officer", nameKey = "pet-officer", icon = "SqOfficer", rarity = "epic", bonus = { calories = 0.35, gems = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(60, 90, 180) } },
	{ id = "firefighter", nameKey = "pet-firefighter", icon = "SqFirefighter", rarity = "epic", bonus = { eatSpeed = 0.35, calories = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(220, 60, 60) } },
	{ id = "hazard-core", nameKey = "pet-hazard-core", icon = "SqHazardCore", rarity = "epic", bonus = { gems = 0.35, eatSpeed = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(230, 200, 60) } },
	{ id = "ember-rage", nameKey = "pet-ember-rage", icon = "SqEmberRage", rarity = "epic", bonus = { calories = 0.35, eatSpeed = 0.15 }, look = { shape = "ball", color = Color3.fromRGB(255, 130, 40) } },
	{ id = "alien", nameKey = "pet-alien", icon = "SqAlien", rarity = "legendary", bonus = { gems = 0.5, calories = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(170, 230, 120) } },
	{ id = "nebula-drop", nameKey = "pet-nebula-drop", icon = "SqNebulaDrop", rarity = "legendary", bonus = { calories = 0.5, eatSpeed = 0.3, gems = 0.2 }, look = { shape = "donut", color = Color3.fromRGB(150, 90, 220) } },
	{ id = "galaxy-ring", nameKey = "pet-galaxy-ring", icon = "SqGalaxyRing", rarity = "secret", bonus = { calories = 1.0, eatSpeed = 0.5, gems = 0.5 }, look = { shape = "donut", color = Color3.fromRGB(20, 10, 40) } },
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
