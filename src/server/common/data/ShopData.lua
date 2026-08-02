--[[
	ShopData
	The shop catalogue (R1) — the SINGLE tuning point for the shop.

	TWO CURRENCIES. Most products are Robux dev products; the BOOSTS row is
	bought with in-game GEMS and therefore has no Creator Dashboard id at all.
	`currency` is what tells the two apart everywhere (payload, boot report,
	purchase path) — read it through ShopData.IsGemProduct, never by testing for
	a missing devProductId, or a Robux product whose id is simply still 0 gets
	treated as a gem product.

	products[key] = {
		currency,     -- nil/"robux" = Creator Dashboard dev product (default),
		              -- "gems" = bought with the in-game hard currency. A gem
		              -- product needs NO devProductId and is never counted as
		              -- "not on sale"; its equivalent misconfiguration is a
		              -- missing priceGems.
		priceGems,    -- gem products only: the AUTHORITATIVE price (unlike
		              -- priceRobux, this one is charged by our own server)
		devProductId, -- Creator Dashboard developer-product id. 0 = not
		              -- configured: purchase refused with a warning, and the UI
		              -- renders a disabled "SOON" price (never a live BUY button
		              -- whose purchase silently does nothing).
		priceRobux,   -- reference only; the dashboard price is authoritative
		label,        -- display name (client localizes via LocaleData.Tr)
		desc,         -- ONE line saying what the player actually gets. Not
		              -- decoration: without it a row reads "Auto-Eat / R$ 399"
		              -- and nothing in the game explains the perk.
		              -- LENGTH IS A HARD CONSTRAINT, not a style note.
		              -- `TextScaled` fits BOTH axes, so on a narrow cell the
		              -- WIDTH binds and long copy shrinks to unreadable rather
		              -- than truncating: ~22 chars on the big pass card (246px
		              -- perk zone), ~15 on the small egg/gem card (176px).
		              -- "One squishy, better odds" rendered at ~8px; it is now
		              -- "Better odds".
		icon,         -- Theme.Icons key (UIKit/Icons.lua) — the art on the cell
		order,        -- sort order inside its section
		accent,       -- Theme.ShopCardAccents key ("Blue"|"Common"|"Uncommon"|
		              -- "Rare"|"Epic"|"Legendary"|"Secret") — the CARD colour.
		              -- Data, not style: the shop is colour-coded per product
		              -- the way the genre does it, and which product is which
		              -- colour is a catalogue decision (R1). Unknown key = the
		              -- default accent + a one-shot warn, never a grey wall.
		bundle,       -- featured/hero only: ARRAY of { icon, text } spelling out
		              -- what a bundle contains, one chip per grant. The chip zone
		              -- is 90 nominal px wide at four chips — copy over ~8
		              -- characters renders under 15px (see Theme.ShopHeroItem).
		section,      -- "featured" | "gems" | "boosts" (client grouping;
		              -- "featured" renders as the hero card)
		best,         -- true on the one pack that carries the BEST VALUE ribbon
		premium,      -- true = the card wears the gold halo + gold frame. Reserve
		              -- it for the flagship of a section; a halo on everything is
		              -- a halo on nothing.
		oneTime,      -- enforced via profile.shop.oneTimePurchased (we
		              -- enforce one-time-ness, Roblox does not)
		grant/grants, -- reward descriptor(s) granted on a paid receipt
	}

	gamepasses[key] = { gamePassId, priceRobux, label, desc, icon, order }
	Ownership is Roblox-side; checked on join + after purchase prompt and
	cached in passOwnership (runtime). Game code reads benefits via
	ShopService.OwnsPass(userId, key).

	IDS ARE PER GAME. The 11 here are LIVE on universe 10593425705 (2026-07-31),
	created and audited by `tools/monetization/`; the ledger of ids that can
	never be deleted is `tools/monetization/id_map.json`.
	⚠ A DEVELOPER PRODUCT IS CREATE-ONCE: no delete endpoint and no update
	endpoint, so its name/description/price are permanent. A gamepass can be
	re-PATCHed and retired (isForSale=false) — that is the only undo there is.
	Product icons cannot be set over the API at all (the old note here claimed a
	multipart part named `imageFile`; that was carried from Dices and is
	unsupported) — set them by hand in the Creator Dashboard. Pass icons DO
	work, via a part named `File`. Details: docs/recipes/publish-readiness.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "ShopData"

local ShopData = {}

ShopData.products = {
	-- GDD §11 dev products. Gem packs use rawAmount (no GemsMult on paid
	-- gems — the multiplier is an in-game earn perk, not a pack booster).
	["starterpack"] = {
		devProductId = 3612534258,
		priceRobux = 99,
		label = "Starter Pack",
		-- The hero cell spells the contents out in `bundle`, so `desc` is the
		-- PITCH, not the inventory — and the pitch is the DEAL, quantified
		-- (genre audit 2026-08-01: starter packs live or die on a value
		-- multiplier the player can scan; "the best way to start" merchandised
		-- nothing). x4 is real: 200 gems alone ≈ 200 R$ at the baseline
		-- gem-pack rate, plus three 500-gem boosts, for 99 R$.
		desc = "Over x4 the value",
		icon = "UiMoreGift",
		order = 1,
		accent = "Legendary",
		section = "featured",
		oneTime = true,
		-- What the hero card SHOWS, one chip per grant below. Kept next to the
		-- grants deliberately: the two lists must be edited together or the
		-- offer advertises something it does not deliver.
		-- Copy is SHORT because the row went from three chips to four: the text
		-- zone is 90 nominal px, so these render at 26 / 20 / 24 / 15 px
		-- respectively (Theme.ShopHeroItem carries the arithmetic). "200" drops
		-- the word "Gems" for the same reason the price shelf drops "R$" — the
		-- chip already draws the gem glyph beside it.
		bundle = {
			{ icon = "UiGem", text = "200" },
			{ icon = "UiBoost", text = "x2 Cal" },
			{ icon = "UiStrength", text = "Bite+" },
			{ icon = "PassSpeed", text = "x2 Speed" },
		},
		grants = {
			{ kind = "gems", amount = 200, rawAmount = true },
			{ kind = "boost", boostId = "boost-15m" },
			{ kind = "boost", boostId = "bite-15m" },
			{ kind = "boost", boostId = "speed-15m" },
		},
	},

	-- ===== BOOSTS — the GEM row ============================================
	-- Four 15-minute boosts, one per stat the run cares about, all at the SAME
	-- price: 500 gems. That number is the pacing rule, not a feel: one solo cake
	-- pays ~496 gems (40 finds against TreasureConfig.finds), so a full cake
	-- buys exactly one boost — the player always chooses WHICH boost rather
	-- than stacking the lot.
	--
	-- ACCENTS. Four rungs of the kit's existing rarity ladder, deliberately
	-- skipping Legendary: gold is the gem row's family colour AND the hero's, so
	-- a boost in gold would make three sections bleed into one. Within the row
	-- each accent is tied to what the boost DOES, which is the only assignment
	-- that survives someone re-ordering the cards:
	--   calories -> Uncommon (teal)  — unchanged from the shipped card
	--   bite     -> Rare (green)     — the kit's "more/positive" hue
	--   speed    -> Blue             — the base hue, and PassSpeed art is blue
	--   capacity -> Epic (magenta)   — near the capacity2 pass's Secret violet,
	--                                  so the two read as the same perk family
	--                                  without being mistaken for each other
	--
	-- LABEL LENGTHS are a layout constraint on the small card's 176x28 title
	-- zone, exactly as `desc` is on the perk line below it. At the kit's measured
	-- Fredoka advance (~0.75 x font size per glyph) that zone renders N
	-- characters at 176 / (0.75 N) px, capped at 28:
	--   "x2 Speed" (8)        28px      "x2 Stomach" (10)  23.5px
	--   "x2 Calories" (11)    21.3px    "Extra Bite" (10)  23.5px
	-- The boosts were requested as "Extra Bite Size" and "x2 Stomach Capacity".
	-- "Extra Bite Size" (15) renders at 15.6px — SMALLER than its own 16px perk
	-- line, which inverts the card's hierarchy — so both are shortened to the
	-- 10-character forms above, which sit level with "x2 Stomach" and read as the
	-- same names rather than different ones. ONE name per perk everywhere (locale
	-- keys `boost-bite` / `boost-capacity`): the daily card and the hero chip are
	-- narrower than this title zone, not wider, so a long form there would only
	-- move the problem.
	["boost-15m"] = {
		currency = "gems",
		priceGems = 500,
		label = "x2 Calories",
		desc = "x2 cals (15m)",
		icon = "UiBoost",
		order = 1,
		accent = "Uncommon",
		section = "boosts",
		grant = { kind = "boost", boostId = "boost-15m" },
	},
	["boost-bite"] = {
		currency = "gems",
		priceGems = 500,
		label = "Extra Bite",
		desc = "+40% bite (15m)",
		icon = "UiStrength",
		order = 2,
		accent = "Rare",
		section = "boosts",
		grant = { kind = "boost", boostId = "bite-15m" },
	},
	["boost-speed"] = {
		currency = "gems",
		priceGems = 500,
		label = "x2 Speed",
		desc = "x2 speed (15m)",
		icon = "PassSpeed",
		order = 3,
		accent = "Blue",
		section = "boosts",
		grant = { kind = "boost", boostId = "speed-15m" },
	},
	["boost-capacity"] = {
		currency = "gems",
		priceGems = 500,
		label = "x2 Stomach",
		desc = "x2 belly (15m)",
		icon = "PassStorageX2",
		order = 4,
		accent = "Epic",
		section = "boosts",
		grant = { kind = "boost", boostId = "capacity-15m" },
	},
	["gems-s"] = {
		devProductId = 3612534244,
		priceRobux = 100,
		label = "100 Gems",
		desc = "Starter stash",
		icon = "GemPackS",
		order = 1,
		accent = "Legendary",
		section = "gems",
		grant = { kind = "gems", amount = 100, rawAmount = true },
	},
	["gems-m"] = {
		devProductId = 3612534248,
		priceRobux = 400,
		label = "450 Gems",
		desc = "+12% bonus",
		icon = "GemPackM",
		order = 2,
		accent = "Legendary",
		section = "gems",
		grant = { kind = "gems", amount = 450, rawAmount = true },
	},
	["gems-l"] = {
		devProductId = 3612534252,
		priceRobux = 900,
		label = "1,050 Gems",
		desc = "+17% bonus",
		icon = "GemPackL",
		order = 3,
		accent = "Legendary",
		section = "gems",
		-- 1,050 gems for 900 R$ = 1.17 gems/R$ vs 1.25 on XL... the ribbon goes
		-- on the pack with the best RATE, which is XL. Kept here as a comment so
		-- the flag is never moved by feel.
		grant = { kind = "gems", amount = 1050, rawAmount = true },
	},
	["gems-xl"] = {
		devProductId = 3612534255,
		priceRobux = 2000,
		label = "2,500 Gems",
		desc = "+25% bonus",
		icon = "GemPackXL",
		order = 4,
		accent = "Legendary",
		section = "gems",
		best = true, -- 1.25 gems/R$ — the best rate in the row
		premium = true,
		grant = { kind = "gems", amount = 2500, rawAmount = true },
	},
}

-- GDD §11 gamepasses. Perks are read via StatsService (ownership cache):
-- x2calories/x2gems -> multipliers, autoeat -> client auto-fire allowed,
-- autogym -> background burns, capacity2 -> x2 stomach, vip -> all of the
-- above + 5 pet slots.
ShopData.gamepasses = {
	["x2calories"] = {
		gamePassId = 1933472819,
		priceRobux = 199,
		label = "x2 Calories",
		desc = "All cals x2",
		icon = "PassCashX2",
		order = 1,
		accent = "Epic",
	},
	["x2gems"] = {
		gamePassId = 1930993460,
		priceRobux = 299,
		label = "x2 Gems",
		desc = "Gem finds x2",
		icon = "PassGemX2",
		order = 2,
		accent = "Uncommon",
	},
	["autoeat"] = {
		gamePassId = 1933322816,
		priceRobux = 399,
		label = "Auto-Eat",
		desc = "Eats for you",
		icon = "PassAutoClick",
		order = 3,
		accent = "Blue",
	},
	["autogym"] = {
		gamePassId = 1932437169,
		priceRobux = 349,
		label = "Auto-Gym",
		desc = "Trains for you",
		icon = "PassAutoRebirth",
		order = 4,
		accent = "Rare",
	},
	["capacity2"] = {
		gamePassId = 1931927238,
		priceRobux = 249,
		label = "x2 Stomach",
		desc = "Double capacity",
		icon = "PassStorageX2",
		order = 5,
		accent = "Secret",
	},
	["vip"] = {
		gamePassId = 1934984583,
		priceRobux = 799,
		label = "VIP",
		desc = "Perks + 5 slots",
		icon = "PassVip",
		order = 6,
		accent = "Legendary",
		premium = true,
	},
}

-- How many recently-granted receipt ids the profile remembers, so a
-- re-delivered receipt can never double-grant a consumable. Deep enough that a
-- receipt cannot resurface after this many other purchases by the same player,
-- shallow enough to stay cheap in the profile.
ShopData.receiptLedgerSize = 50

-- RequestGemPurchase rate limit, as a BURST BUCKET rather than a flat cooldown:
-- at most `gemPurchaseBurst` fires per `gemPurchaseWindowSeconds` per player.
--
-- The gem remote answers EVERY refusal with a full catalogue re-push (so a stale
-- client corrects itself) and warns loudly on a Robux key (so tampering is
-- countable), which a client firing on Heartbeat turns into a weapon against the
-- server it is on. But a flat cooldown is the wrong shape: the four boosts are
-- four adjacent cards at the same price, none of them one-time, so buying two in
-- quick succession is NORMAL — and a per-player cooldown drops the second one
-- silently while the client has already played its press feedback for both. The
-- player would end up with one boost, believing they bought two.
-- A burst of 5 is far more than any human tapping can produce and still clamps a
-- spammer to 5/second instead of one per frame.
ShopData.gemPurchaseWindowSeconds = 1
ShopData.gemPurchaseBurst = 5

-- Built in Init(): devProductId -> product key (ProcessReceipt lookup).
ShopData.byProductId = {}

-- [userId: number] = { [passKey: string] = true } — runtime gamepass
-- ownership cache (checked on join / after purchase; cleared on leave).
ShopData.passOwnership = {}

--API
-- Is this product bought with in-game GEMS? The one predicate the payload, the
-- boot report and the two purchase remotes all read, so they cannot drift into
-- disagreeing about what a gem product is. Declared above Init because Init
-- uses it.
function ShopData.IsGemProduct(def): boolean
	return type(def) == "table" and def.currency == "gems"
end

function ShopData.Init()
	table.clear(ShopData.byProductId)
	table.clear(ShopData.passOwnership)
	for key, def in pairs(ShopData.products) do
		-- A gem product has NO devProductId, so it can never land in this map or
		-- trip the duplicate-id warn below. The guard is the `> 0` test rather
		-- than IsGemProduct on purpose: a Robux product whose id is still 0 must
		-- stay out of the map too.
		if type(def.devProductId) == "number" and def.devProductId > 0 then
			-- A copy-pasted id used to be last-writer-wins over `pairs` — the
			-- shop would sell the wrong product, non-deterministically, with
			-- nothing in the console. On the money path that is the worst class
			-- of bug there is, and it costs one comparison to make it loud (R8).
			local clash = ShopData.byProductId[def.devProductId]
			if clash ~= nil then
				Log.Warn(
					SCOPE,
					`DUPLICATE devProductId {def.devProductId} on '{key}' and '{clash}' — one of them will sell the other's `
						.. `contents. Fix ShopData before going live.`
				)
			end
			ShopData.byProductId[def.devProductId] = key
		end
	end
	local seenPass = {}
	for key, def in pairs(ShopData.gamepasses) do
		if type(def.gamePassId) == "number" and def.gamePassId > 0 then
			local clash = seenPass[def.gamePassId]
			if clash ~= nil then
				Log.Warn(SCOPE, `DUPLICATE gamePassId {def.gamePassId} on '{key}' and '{clash}' — ownership will be wrong for both.`)
			end
			seenPass[def.gamePassId] = key
		end
	end
end

--API
function ShopData.KeyForProductId(productId: number): string?
	return ShopData.byProductId[productId]
end

return ShopData
