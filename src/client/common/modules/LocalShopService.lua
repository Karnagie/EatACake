--[[
	LocalShopService — shop view-model (R2, logic only). Turns ShopUpdate /
	GroupRewardUpdate snapshots into UIKit.ShopPanel sections.

	Tab shape:     { id, label, sections }
	Section shape: { id, title, iconName, count, kind, items }
	  kind = "banner"    -> full-width GIVE row      (ShopBanner, green)
	       | "hero"      -> full-width bundle offer  (ShopHeroCard, gold)
	       | "card"      -> 3-across product card    (ShopCard)
	       | "smallcard" -> 4-across product card    (ShopCard, small)

	Cell colour is NOT decided here. `accent` arrives from ShopData through the
	ShopUpdate payload, because which product wears which colour is a catalogue
	decision (R1) — a key -> colour lookup table in this module would be config
	living in a service.

	Row ids keep the prefix routing ShopSubsClient expects:
	"product:<key>" / "pass:<key>" / "group".
	The ROBUX/GEM split is not carried on the cell: ShopPanel hands the click
	handler nothing but that id, so ShopSubsClient reads `currency` off the same
	ShopUpdate snapshot this module built the cells from.
]]

local LocalShopService = {}

local locale

-- A cell's price button has four states, and two of them exist because the
-- alternative is a live BUY button that does nothing:
--   unavailable — the dev-product / gamepass id is still 0, so the server would
--                 refuse the purchase with nothing shown to the player
--   unaffordable — a GEM product the player cannot pay for yet. The shelf still
--                 shows the glyph and the price (that number is the information
--                 the player needs); it is just grey and not clickable.
local function priceState(entry, gemBalance: number): string
	if entry.owned then
		return "owned"
	end
	if entry.configured == false then
		return "unavailable"
	end
	if entry.currency == "gems" and gemBalance < (tonumber(entry.priceGems) or 0) then
		return "unaffordable"
	end
	return "buy"
end

-- The buy label is the BARE amount: the shelf draws the currency glyph next to
-- it, and `price-robux` ("R$ {n}") next to that glyph rendered "⬡ R$ 199" on
-- every card. `price-gems-short` exists for exactly the same reason on the gem
-- row. OWNED / SOON are text-only, so they keep the full word.
local function priceText(entry): string
	if entry.owned then
		return locale.T("btn-owned")
	end
	if entry.configured == false then
		return locale.T("btn-soon")
	end
	if entry.currency == "gems" then
		return locale.T("price-gems-short", { n = entry.priceGems })
	end
	return locale.T("price-robux-short", { n = entry.priceRobux })
end

-- Currency glyph on any actual price, INCLUDING the unaffordable one — a grey
-- shelf reading "500" with no glyph says nothing about what is missing. OWNED /
-- SOON are text-only so the label can span the whole button.
local function priceIcon(entry): string?
	if entry.owned or entry.configured == false then
		return nil
	end
	return if entry.currency == "gems" then "UiGem" else "UiRobux"
end

local function count(list): string?
	return if #list > 0 then tostring(#list) else nil
end

-- Bundle chips for the hero cell. Defensive about shape because the payload
-- crosses a RemoteEvent: a non-array or a malformed entry must degrade to "no
-- chips", never to a nil-index error inside the render.
local function bundleOf(product): { { iconName: string, text: string } }?
	if type(product.bundle) ~= "table" then
		return nil
	end
	local chips = {}
	for _, entry in ipairs(product.bundle) do
		if type(entry) == "table" and entry.text then
			table.insert(chips, { iconName = entry.icon, text = locale.Tr(entry.text) or entry.text })
		end
	end
	return if #chips > 0 then chips else nil
end

function LocalShopService.Init(data)
	locale = data.LocaleData
end

--API
-- (shop?, group?, gems?) -> TABS array for UIKit.ShopPanel.
-- `gems` is the player's BALANCE (not the gem section): a gem-priced card can
-- only decide between "buy" and "unaffordable" if it knows what the player has.
function LocalShopService.BuildTabs(shop, group, gems)
	local featured, gemPacks, boosts, passes, free = {}, {}, {}, {}, {}
	local gemBalance = if type(gems) == "number" then gems else 0

	if type(shop) == "table" then
		for _, product in ipairs(shop.products or {}) do
			local cell = {
				id = `product:{product.key}`,
				label = locale.Tr(product.label) or product.key,
				subText = if product.desc then locale.Tr(product.desc) else "",
				iconName = product.icon,
				accent = product.accent,
				premium = product.premium == true,
				priceText = priceText(product),
				priceIcon = priceIcon(product),
				state = priceState(product, gemBalance),
				best = product.best == true,
			}
			if product.best then
				cell.ribbonText = locale.T("ribbon-best-value")
				cell.ribbonVariant = "BestValue"
			end
			if product.section == "featured" then
				cell.bundle = bundleOf(product)
				if product.oneTime and not product.owned then
					cell.ribbonText = locale.T("ribbon-one-time")
					cell.ribbonVariant = "Limited"
				end
				table.insert(featured, cell)
			elseif product.section == "gems" then
				table.insert(gemPacks, cell)
			else
				table.insert(boosts, cell)
			end
		end
		for _, pass in ipairs(shop.passes or {}) do
			table.insert(passes, {
				id = `pass:{pass.key}`,
				label = locale.Tr(pass.label) or pass.key,
				subText = if pass.desc then locale.Tr(pass.desc) else "",
				iconName = pass.icon,
				accent = pass.accent,
				premium = pass.premium == true,
				priceText = priceText(pass),
				priceIcon = priceIcon(pass),
				-- Passes are Robux-only, so the balance never changes their state.
				state = priceState(pass, gemBalance),
			})
		end
	end

	if type(group) == "table" and group.configured then
		table.insert(free, {
			id = "group",
			label = locale.T("label-group-reward"),
			subText = if group.status == "not-in-group"
				then locale.T("sub-group-join-first")
				else locale.T("sub-group-reward"),
			iconName = "UiFriend",
			priceText = if group.claimed then locale.T("btn-owned") else locale.T("btn-free"),
			state = if group.claimed then "owned" else "buy",
			accent = "free",
		})
	end

	-- FOUR TABS, not one 5.6-screen scroll. Featured opens the shop because it
	-- holds the two things a player can act on immediately — the free group
	-- reward and the one-time starter offer — and a shop that opens on a price
	-- converts worse than one that opens on something you can take right now.
	--
	-- Passes get the BIG card (3 across), boosts and gems the small one (4
	-- across). Not a style choice: it is the only split where every row is full
	-- (6 passes = 2x3, 4 boosts = 1x4, 4 packs = 1x4) instead of ending in a lone
	-- orphan cell, and the permanent perks earning the larger cell is the
	-- hierarchy the shop wants anyway.
	--
	-- ShopPanel drops a tab whose sections are all empty, so an unconfigured
	-- group reward or an empty category never opens onto a blank window.
	return {
		{
			id = "featured",
			label = locale.T("shop-tab-featured"),
			sections = {
				{
					id = "free",
					title = locale.T("shop-section-free"),
					iconName = "UiGift",
					kind = "banner",
					items = free,
				},
				{
					id = "featured",
					title = locale.T("shop-section-featured"),
					iconName = "UiStar",
					kind = "hero",
					items = featured,
				},
			},
		},
		{
			id = "passes",
			label = locale.T("shop-tab-passes"),
			sections = {
				{
					id = "passes",
					title = locale.T("shop-section-passes"),
					iconName = "UiVerified",
					count = count(passes),
					kind = "card",
					items = passes,
				},
			},
		},
		{
			id = "boosts",
			label = locale.T("shop-tab-boosts"),
			sections = {
				{
					-- Section id renamed with its contents: it held eggs AND
					-- boosts, and it holds no eggs any more. The id is the React
					-- key stem and the empty-section log id, so a stale name here
					-- makes both lie.
					id = "boosts",
					title = locale.T("shop-section-boosts"),
					iconName = "UiBoost",
					count = count(boosts),
					kind = "smallcard",
					items = boosts,
				},
			},
		},
		{
			id = "gems",
			label = locale.T("shop-tab-gems"),
			sections = {
				{
					id = "gems",
					title = locale.T("shop-section-gems"),
					iconName = "UiGem",
					count = count(gemPacks),
					kind = "smallcard",
					items = gemPacks,
				},
			},
		},
	}
end

return LocalShopService
