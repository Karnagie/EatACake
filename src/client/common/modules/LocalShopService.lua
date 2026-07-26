--[[
	LocalShopService — shop view-model (R2, logic only). Turns ShopUpdate /
	GroupRewardUpdate snapshots into UIKit.ShopPanel sections.

	Section shape: { id, title, iconName, count, kind, items }
	  kind = "banner" -> full-width hero cell (ShopBanner)
	       | "tile"   -> 3-across grid       (ShopTile)
	       | "pack"   -> 4-across grid       (ShopPackCard)

	Row ids keep the prefix routing ShopSubsClient expects:
	"product:<key>" / "pass:<key>" / "group".
]]

local LocalShopService = {}

local locale

-- A cell's price button has exactly three states, and the third one is why this
-- function exists: an unconfigured dev-product / gamepass id used to render a
-- live BUY button whose purchase the server refused with nothing shown to the
-- player.
local function priceState(entry): string
	if entry.owned then
		return "owned"
	end
	if entry.configured == false then
		return "unavailable"
	end
	return "buy"
end

local function priceText(entry): string
	if entry.owned then
		return locale.T("btn-owned")
	end
	if entry.configured == false then
		return locale.T("btn-soon")
	end
	return locale.T("price-robux", { n = entry.priceRobux })
end

-- Robux glyph only on an actual price; OWNED / SOON are text-only so the label
-- can span the whole button.
local function priceIcon(entry): string?
	if entry.owned or entry.configured == false then
		return nil
	end
	return "UiRobux"
end

local function count(list): string?
	return if #list > 0 then tostring(#list) else nil
end

function LocalShopService.Init(data)
	locale = data.LocaleData
end

--API
-- (shop?, group?) -> sections array for UIKit.ShopPanel.
function LocalShopService.BuildSections(shop, group)
	local featured, gems, eggs, passes, free = {}, {}, {}, {}, {}

	if type(shop) == "table" then
		for _, product in ipairs(shop.products or {}) do
			local cell = {
				id = `product:{product.key}`,
				label = locale.Tr(product.label) or product.key,
				subText = if product.desc then locale.Tr(product.desc) else "",
				iconName = product.icon,
				priceText = priceText(product),
				priceIcon = priceIcon(product),
				state = priceState(product),
				best = product.best == true,
			}
			if product.best then
				cell.ribbonText = locale.T("ribbon-best-value")
				cell.ribbonVariant = "BestValue"
			end
			if product.section == "featured" then
				cell.accent = "paid"
				if product.oneTime and not product.owned then
					cell.ribbonText = locale.T("ribbon-one-time")
					cell.ribbonVariant = "Limited"
				end
				table.insert(featured, cell)
			elseif product.section == "gems" then
				table.insert(gems, cell)
			else
				table.insert(eggs, cell)
			end
		end
		for _, pass in ipairs(shop.passes or {}) do
			table.insert(passes, {
				id = `pass:{pass.key}`,
				label = locale.Tr(pass.label) or pass.key,
				subText = if pass.desc then locale.Tr(pass.desc) else "",
				iconName = pass.icon,
				priceText = priceText(pass),
				priceIcon = priceIcon(pass),
				state = priceState(pass),
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

	-- FREE first, then the paid hero. A shop that opens on a price converts
	-- worse than one that opens on something the player can take right now, and
	-- the group reward is also the cheapest social hook available.
	return {
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
			kind = "banner",
			items = featured,
		},
		{
			id = "passes",
			title = locale.T("shop-section-passes"),
			iconName = "UiVerified",
			count = count(passes),
			kind = "tile",
			items = passes,
		},
		{
			id = "eggs",
			title = locale.T("shop-section-eggs"),
			iconName = "Egg1",
			count = count(eggs),
			kind = "tile",
			items = eggs,
		},
		{
			id = "gems",
			title = locale.T("shop-section-gems"),
			iconName = "UiGem",
			count = count(gems),
			kind = "pack",
			items = gems,
		},
	}
end

return LocalShopService
