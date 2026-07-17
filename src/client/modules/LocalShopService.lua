--[[
	LocalShopService — shop view-model (R2, logic only). Turns ShopUpdate /
	GroupRewardUpdate snapshots into UIKit.ShopPanel sections. Row ids are
	routed by prefix in ShopSubsClient: "product:<key>" / "pass:<key>" /
	"group".
]]

local LocalShopService = {}

local locale

function LocalShopService.Init(data)
	locale = data.LocaleData
end

--API
-- (shop?, group?) -> sections array for UIKit.ShopPanel.
function LocalShopService.BuildSections(shop, group)
	local featured, gold, passes, free = {}, {}, {}, {}

	if type(shop) == "table" then
		for _, product in ipairs(shop.products or {}) do
			local row = {
				id = `product:{product.key}`,
				label = locale.Tr(product.label) or product.key,
				subText = "",
				buttonText = if product.owned
					then locale.T("btn-owned")
					else locale.T("price-robux", { n = product.priceRobux }),
				owned = product.owned,
			}
			if product.section == "featured" then
				table.insert(featured, row)
			else
				table.insert(gold, row)
			end
		end
		for _, pass in ipairs(shop.passes or {}) do
			table.insert(passes, {
				id = `pass:{pass.key}`,
				label = locale.Tr(pass.label) or pass.key,
				subText = "",
				buttonText = if pass.owned
					then locale.T("btn-owned")
					else locale.T("price-robux", { n = pass.priceRobux }),
				owned = pass.owned,
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
			buttonText = if group.claimed then locale.T("btn-owned") else locale.T("btn-free"),
			owned = group.claimed,
		})
	end

	return {
		{ title = locale.T("shop-section-featured"), rows = featured },
		{ title = locale.T("shop-section-passes"), rows = passes },
		{ title = locale.T("shop-section-gold"), rows = gold },
		{ title = locale.T("shop-section-free"), rows = free },
	}
end

return LocalShopService
