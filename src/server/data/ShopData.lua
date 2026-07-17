--[[
	ShopData
	The Robux shop catalogue (R1) — the SINGLE tuning point for the shop.

	products[key] = {
		devProductId, -- Creator Dashboard developer-product id. 0 = not
		              -- configured: purchase refused with a warning.
		priceRobux,   -- reference only; the dashboard price is authoritative
		label,        -- display name (client localizes via LocaleData.Tr)
		order,        -- sort order inside its section
		section,      -- "featured" | "gold" (client grouping)
		oneTime,      -- enforced via profile.shop.oneTimePurchased (we
		              -- enforce one-time-ness, Roblox does not)
		grant/grants, -- reward descriptor(s) granted on a paid receipt
	}

	gamepasses[key] = { gamePassId, priceRobux, label, order }
	Ownership is Roblox-side; checked on join + after purchase prompt and
	cached in passOwnership (runtime). Game code reads benefits via
	ShopService.OwnsPass(userId, key).

	IDS ARE PER GAME: create dev products / passes on the game's universe and
	fill the ids here. Gotcha from Dices: when uploading product icons via
	Open Cloud, the multipart file part MUST be named `imageFile`.
]]

local ShopData = {}

ShopData.products = {
	-- GDD §11 dev products. Gem packs use rawAmount (no GemsMult on paid
	-- gems — the multiplier is an in-game earn perk, not a pack booster).
	["starterpack"] = {
		devProductId = 0,
		priceRobux = 99,
		label = "Starter Pack (-50%)",
		order = 1,
		section = "featured",
		oneTime = true,
		grants = {
			{ kind = "gems", amount = 200, rawAmount = true },
			{ kind = "boost", boostId = "boost-15m" },
			{ kind = "egg", eggType = "lucky" },
		},
	},
	["lucky-egg"] = {
		devProductId = 0,
		priceRobux = 99,
		label = "Lucky Egg",
		order = 2,
		section = "featured",
		grant = { kind = "egg", eggType = "lucky" },
	},
	["mega-egg"] = {
		devProductId = 0,
		priceRobux = 399,
		label = "Mega Egg (Rare+)",
		order = 3,
		section = "featured",
		grant = { kind = "egg", eggType = "mega" },
	},
	["instant-burn"] = {
		devProductId = 0,
		priceRobux = 25,
		label = "Instant Fat Burn",
		order = 4,
		section = "featured",
		grant = { kind = "burn" },
	},
	["boost-15m"] = {
		devProductId = 0,
		priceRobux = 49,
		label = "x2 Calories (15 min)",
		order = 5,
		section = "featured",
		grant = { kind = "boost", boostId = "boost-15m" },
	},
	["gems-s"] = {
		devProductId = 0,
		priceRobux = 100,
		label = "+100 Gems",
		order = 1,
		section = "gems",
		grant = { kind = "gems", amount = 100, rawAmount = true },
	},
	["gems-m"] = {
		devProductId = 0,
		priceRobux = 400,
		label = "+450 Gems",
		order = 2,
		section = "gems",
		grant = { kind = "gems", amount = 450, rawAmount = true },
	},
	["gems-l"] = {
		devProductId = 0,
		priceRobux = 900,
		label = "+1,050 Gems",
		order = 3,
		section = "gems",
		grant = { kind = "gems", amount = 1050, rawAmount = true },
	},
	["gems-xl"] = {
		devProductId = 0,
		priceRobux = 2000,
		label = "+2,500 Gems",
		order = 4,
		section = "gems",
		grant = { kind = "gems", amount = 2500, rawAmount = true },
	},
}

-- GDD §11 gamepasses. Perks are read via StatsService (ownership cache):
-- x2calories/x2gems -> multipliers, autoeat -> client auto-fire allowed,
-- autogym -> background burns, capacity2 -> x2 stomach, vip -> all of the
-- above + 5 pet slots.
ShopData.gamepasses = {
	["x2calories"] = { gamePassId = 0, priceRobux = 199, label = "x2 Calories", order = 1 },
	["x2gems"] = { gamePassId = 0, priceRobux = 299, label = "x2 Gems", order = 2 },
	["autoeat"] = { gamePassId = 0, priceRobux = 399, label = "Auto-Eat", order = 3 },
	["autogym"] = { gamePassId = 0, priceRobux = 349, label = "Auto-Gym", order = 4 },
	["capacity2"] = { gamePassId = 0, priceRobux = 249, label = "x2 Stomach", order = 5 },
	["vip"] = { gamePassId = 0, priceRobux = 799, label = "VIP", order = 6 },
}

-- Built in Init(): devProductId -> product key (ProcessReceipt lookup).
ShopData.byProductId = {}

-- [userId: number] = { [passKey: string] = true } — runtime gamepass
-- ownership cache (checked on join / after purchase; cleared on leave).
ShopData.passOwnership = {}

function ShopData.Init()
	table.clear(ShopData.byProductId)
	table.clear(ShopData.passOwnership)
	for key, def in pairs(ShopData.products) do
		if type(def.devProductId) == "number" and def.devProductId > 0 then
			ShopData.byProductId[def.devProductId] = key
		end
	end
end

--API
function ShopData.KeyForProductId(productId: number): string?
	return ShopData.byProductId[productId]
end

return ShopData
