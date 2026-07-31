--[[
	ShopService
	Shop logic over the profile's `shop` section + the runtime gamepass
	ownership cache in ShopData (R2). ShopSubs owns all MarketplaceService
	wiring (prompts, ProcessReceipt, ownership fetches) — this service only
	answers questions and mutates state.
]]

local ShopService = {}

local profileData, shopData

function ShopService.Init(data)
	profileData = data.PlayerProfileData
	shopData = data.ShopData
end

local function section(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.shop
end

--API
function ShopService.IsOneTimeOwned(userId: number, productKey: string): boolean
	local shop = section(userId)
	return shop ~= nil and shop.oneTimePurchased[productKey] == true
end

--API
function ShopService.MarkOneTimePurchased(userId: number, productKey: string)
	local shop = section(userId)
	if shop then
		shop.oneTimePurchased[productKey] = true
	end
end

--API
-- Gamepass benefit check for game code (runtime cache, filled by ShopSubs
-- on join and after a purchase). Safe default: false until fetched.
function ShopService.OwnsPass(userId: number, passKey: string): boolean
	local owned = shopData.passOwnership[userId]
	return owned ~= nil and owned[passKey] == true
end

--API
function ShopService.SetPassOwned(userId: number, passKey: string, owned: boolean)
	local map = shopData.passOwnership[userId]
	if map == nil then
		map = {}
		shopData.passOwnership[userId] = map
	end
	map[passKey] = owned == true or nil
end

--API
function ShopService.ClearRuntime(userId: number)
	shopData.passOwnership[userId] = nil
end

--API
-- Has this exact receipt already been granted? Roblox re-delivers a receipt
-- until ProcessReceipt returns PurchaseGranted, so a server that grants and
-- then dies hands the SAME PurchaseId to the next one. Without this, every
-- consumable (gem packs, eggs, boosts) double-grants on one payment.
function ShopService.IsReceiptHandled(userId: number, purchaseId: string): boolean
	local shop = section(userId)
	if shop == nil or type(shop.receipts) ~= "table" then
		return false
	end
	for _, id in ipairs(shop.receipts) do
		if id == purchaseId then
			return true
		end
	end
	return false
end

--API
-- Record a granted receipt. MUST be called in the same no-yield stretch as the
-- grant, BEFORE the save — a save that lands without the id would let the
-- re-delivery through.
function ShopService.MarkReceiptHandled(userId: number, purchaseId: string)
	local shop = section(userId)
	if shop == nil then
		return
	end
	if type(shop.receipts) ~= "table" then
		shop.receipts = {}
	end
	table.insert(shop.receipts, purchaseId)
	local cap = shopData.receiptLedgerSize or 50
	while #shop.receipts > cap do
		table.remove(shop.receipts, 1)
	end
end

return ShopService
