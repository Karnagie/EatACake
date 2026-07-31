--[[
	Profile section: shop — one-time purchase ledger.

	oneTimePurchased -- { [productKey: string] = true }. Generalizes Dices'
	single `boughtStarterPack` flag: ANY product with `oneTime = true` in
	ShopData is enforced through this set (Roblox dev products have no
	built-in one-time semantics — we enforce it ourselves).

	receipts -- ARRAY of the most recent handled `receiptInfo.PurchaseId`s,
	oldest first, capped at `MAX_RECEIPTS`. Roblox re-delivers a receipt until
	ProcessReceipt returns PurchaseGranted, and a server that grants and then
	dies (or whose PurchaseGranted is lost) gets the SAME PurchaseId again —
	which, for a consumable, mints the reward twice for one payment. `oneTime`
	products were already protected by `oneTimePurchased`; every gem pack, egg
	and boost was not. An ARRAY (not a set keyed by PurchaseId) because it has
	to be bounded, and bounding needs an order.

	Gamepass ownership is NOT stored here — Roblox owns it; it's checked via
	MarketplaceService and cached at runtime (ShopData.passOwnership).

	No version bump: a NEW field with a default is filled in by reconcile (P2).
]]

-- CORRUPTION CEILING, not the tuning knob. The working depth lives in
-- `ShopData.receiptLedgerSize` (R1: the shop's single tuning point) and
-- ShopService trims to it on every write; this only stops a malformed or
-- hand-edited profile from arriving with an unbounded list.
local MAX_RECEIPTS = 200

return {
	key = "shop",
	version = 1,
	defaults = {
		oneTimePurchased = {},
		receipts = {},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		if type(section.oneTimePurchased) ~= "table" then
			section.oneTimePurchased = {}
		end
		-- Rebuild rather than repair: a corrupted/oversized list must never be
		-- able to make the money path slow or wrong.
		local receipts = {}
		if type(section.receipts) == "table" then
			for _, id in ipairs(section.receipts) do
				if type(id) == "string" and id ~= "" then
					table.insert(receipts, id)
				end
			end
		end
		while #receipts > MAX_RECEIPTS do
			table.remove(receipts, 1)
		end
		section.receipts = receipts
		return section
	end,
}
