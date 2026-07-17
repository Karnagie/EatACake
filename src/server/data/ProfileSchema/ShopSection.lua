--[[
	Profile section: shop — one-time purchase ledger.

	oneTimePurchased -- { [productKey: string] = true }. Generalizes Dices'
	single `boughtStarterPack` flag: ANY product with `oneTime = true` in
	ShopData is enforced through this set (Roblox dev products have no
	built-in one-time semantics — we enforce it ourselves).

	Gamepass ownership is NOT stored here — Roblox owns it; it's checked via
	MarketplaceService and cached at runtime (ShopData.passOwnership).
]]

return {
	key = "shop",
	version = 1,
	defaults = {
		oneTimePurchased = {},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		if type(section.oneTimePurchased) ~= "table" then
			section.oneTimePurchased = {}
		end
		return section
	end,
}
