--[[
	ShopSubs — the Robux shop domain (R4). The SINGLE owner of
	MarketplaceService.ProcessReceipt on the server.

	Wires:
	• RequestPurchase (key): validate key -> PromptProductPurchase. A oneTime
	  product already owned resyncs instead of prompting; devProductId = 0
	  refuses with a warning (nothing breaks).
	• ProcessReceipt: map ProductId -> key, grant via RewardGrantSubs,
	  mark oneTime, Save, PurchaseGranted. Unknown product / offline player /
	  failed grant -> NotProcessedYet (Roblox retries — money is never eaten).
	• RequestGamepass (key): validate -> PromptGamePassPurchase.
	• PromptGamePassPurchaseFinished: mark runtime ownership + resync.
	• On join (SendShop): push the full catalogue snapshot. Gamepass ownership
	  is fetched by PassOwnershipSubs (COMMON, runs in both places), which
	  re-pushes this catalogue once ownership resolves.

	ShopUpdate payload:
	  { products = ARRAY {key,label,priceRobux,section,order,oneTime,owned},
	    passes   = ARRAY {key,label,priceRobux,order,owned} }
	Prices are reference-only (dashboard is authoritative) — shown on
	buttons, never used in math.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
-- Resolved from the subscriptions registry in Start (RewardGrantSubs lives in
-- the COMMON partition; a static script.Parent require breaks once this sub
-- moves to the lobby partition — see the lobby/game split).
local RewardGrantSubs

local SCOPE = "ShopSubs"

local ShopSubs = {}

local ShopService, PersistenceService
local ShopData, profileData
local uShop

local function shopPayload(userId: number)
	local products = {}
	for key, def in pairs(ShopData.products) do
		table.insert(products, {
			key = key,
			label = def.label,
			priceRobux = def.priceRobux,
			section = def.section or "gold",
			order = def.order or 0,
			oneTime = def.oneTime == true,
			owned = def.oneTime == true and ShopService.IsOneTimeOwned(userId, key) or false,
		})
	end
	table.sort(products, function(a, b)
		if a.section ~= b.section then
			return a.section < b.section
		end
		return a.order < b.order
	end)
	local passes = {}
	for key, def in pairs(ShopData.gamepasses) do
		table.insert(passes, {
			key = key,
			label = def.label,
			priceRobux = def.priceRobux,
			order = def.order or 0,
			owned = ShopService.OwnsPass(userId, key),
		})
	end
	table.sort(passes, function(a, b)
		return a.order < b.order
	end)
	return { products = products, passes = passes }
end

--API
-- Push the catalogue + ownership snapshot (called by PlayerLifecycleSubs on
-- join and internally after purchases).
function ShopSubs.SendShop(player: Player)
	if uShop == nil then
		Log.Warn(SCOPE, `SendShop({player.Name}) before Start ran — push dropped`)
		return
	end
	uShop:FireClient(player, shopPayload(player.UserId))
end


-- Returns the validated, non-empty grants list, or nil if ANY entry can't be
-- granted. Validating the WHOLE list BEFORE granting anything is what makes
-- the grant loop all-or-nothing: a partial failure mid-loop would otherwise
-- re-mint the successful grants on every Roblox receipt retry.
local function grantableList(def): { { [string]: any } }?
	local grants = def.grants or { def.grant }
	if #grants == 0 then
		return nil
	end
	for _, reward in ipairs(grants) do
		if type(reward) ~= "table" or not RewardGrantSubs.HasHandler(reward.kind) then
			return nil
		end
		if reward.kind == "gold" and math.floor(tonumber(reward.amount) or 0) <= 0 then
			return nil
		end
	end
	return grants
end

local function grantProduct(player: Player, userId: number, key: string): boolean
	local def = ShopData.products[key]
	if not def or not profileData.Get(userId) then
		return false
	end
	local grants = grantableList(def)
	if not grants then
		Log.Warn(SCOPE, `product '{key}' has an empty/ungrantable grants list — refusing (fix ShopData)`)
		return false
	end
	-- No yields from here on: the pre-validated loop applies atomically.
	for _, reward in ipairs(grants) do
		local granted = RewardGrantSubs.Grant(player, reward, `shop:{key}`)
		if granted == nil then
			-- Should be impossible after grantableList; log loudly either way.
			Log.Warn(SCOPE, `product '{key}': pre-validated grant still declined ({tostring(reward.kind)})`)
		end
	end
	if def.oneTime then
		ShopService.MarkOneTimePurchased(userId, key)
	end
	return true
end

local function processReceipt(receiptInfo)
	local key = ShopData.KeyForProductId(receiptInfo.ProductId)
	if not key then
		-- Not one of our configured products — let Roblox retry (a later
		-- code version may handle it). R8: never silent on a money path.
		Log.Once(SCOPE, `receipt-unknown-{receiptInfo.ProductId}`, `receipt for UNKNOWN ProductId {receiptInfo.ProductId} — not in ShopData; retrying forever until configured`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local userId = receiptInfo.PlayerId
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		-- Payer isn't in THIS server (cross-server timing / rejoin churn).
		-- R8: never silent on a money path — Roblox retries on rejoin.
		Log.Once(SCOPE, `receipt-offline-{userId}`, `receipt '{key}' for {userId}: payer not in this server — NotProcessedYet (retries on rejoin)`)
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried on rejoin
	end
	-- A pending receipt can arrive BEFORE the profile loads (join with a
	-- queued receipt). Wait a bounded window instead of burning the retry.
	local deadline = os.clock() + 15
	while not PersistenceService.IsLoaded(userId) do
		if os.clock() > deadline or player.Parent ~= Players then
			Log.Info(SCOPE, `receipt '{key}' for {userId}: profile not loaded in time — NotProcessedYet (will retry)`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		task.wait(0.5)
	end
	local def = ShopData.products[key]
	if def.oneTime and ShopService.IsOneTimeOwned(userId, key) then
		-- Stray duplicate receipt for a one-time item: consume WITHOUT
		-- double-granting.
		ShopSubs.SendShop(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local ok, granted = pcall(grantProduct, player, userId, key)
	if not ok or not granted then
		-- CRITICAL: the player PAID and the grant failed. Never swallow.
		Log.Warn(SCOPE, `PAID GRANT FAILED for '{key}' (user {userId}) — returning NotProcessedYet for retry: {ok and "grant declined" or granted}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	PersistenceService.Save(userId)
	ShopSubs.SendShop(player)
	Log.Info(SCOPE, `product '{key}' granted to {player.Name} ({receiptInfo.CurrencySpent} R$)`)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function ShopSubs.PushInitialState(player: Player)
	ShopSubs.SendShop(player)
	-- Gamepass ownership is fetched by PassOwnershipSubs (COMMON — runs in both
	-- the lobby and the game place); it re-pushes this catalogue once ownership
	-- resolves. (Was ShopSubs.RefreshPassOwnership, which couldn't run in game.)
end

function ShopSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	ShopService = services.ShopService
	PersistenceService = services.PersistenceService
	ShopData = data.ShopData
	profileData = data.PlayerProfileData
	uShop = Net.Update("ShopUpdate")

	MarketplaceService.ProcessReceipt = processReceipt

	Net.Remote("RequestPurchase").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			return
		end
		local def = ShopData.products[key]
		if not def then
			return
		end
		if def.oneTime and ShopService.IsOneTimeOwned(player.UserId, key) then
			ShopSubs.SendShop(player) -- resync: hide the owned card
			return
		end
		if type(def.devProductId) ~= "number" or def.devProductId <= 0 then
			Log.Warn(SCOPE, `product '{key}' has no devProductId in ShopData — purchase refused`)
			return
		end
		MarketplaceService:PromptProductPurchase(player, def.devProductId)
	end)

	Net.Remote("RequestGamepass").OnServerEvent:Connect(function(player, key)
		if type(key) ~= "string" then
			return
		end
		local def = ShopData.gamepasses[key]
		if not def then
			return
		end
		if ShopService.OwnsPass(player.UserId, key) then
			ShopSubs.SendShop(player)
			return
		end
		if type(def.gamePassId) ~= "number" or def.gamePassId <= 0 then
			Log.Warn(SCOPE, `gamepass '{key}' has no gamePassId in ShopData — purchase refused`)
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, def.gamePassId)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
		if not wasPurchased then
			return
		end
		for key, def in pairs(ShopData.gamepasses) do
			if def.gamePassId == gamePassId then
				ShopService.SetPassOwned(player.UserId, key, true)
				ShopSubs.SendShop(player)
				Log.Info(SCOPE, `gamepass '{key}' purchased by {player.Name}`)
				return
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		ShopService.ClearRuntime(player.UserId)
	end)

	-- Config validation (after all Starts — grant kinds must be registered).
	task.defer(function()
		for key, def in pairs(ShopData.products) do
			local grants = def.grants or { def.grant }
			if #grants == 0 then
				warn(`[ShopSubs] product '{key}' has NO grant/grants — a purchase would take Robux for nothing (refused at receipt)`)
			end
			for _, reward in ipairs(grants) do
				if reward and not RewardGrantSubs.HasHandler(reward.kind) then
					warn(`[ShopSubs] product '{key}' grant kind '{tostring(reward.kind)}' has no grant handler`)
				end
			end
			if type(def.devProductId) ~= "number" or def.devProductId <= 0 then
				Log.Warn(SCOPE, `product '{key}' has devProductId = 0 — configure it on the Creator Dashboard (purchases refused until then)`)
			end
		end
		for key, def in pairs(ShopData.gamepasses) do
			if type(def.gamePassId) ~= "number" or def.gamePassId <= 0 then
				Log.Warn(SCOPE, `gamepass '{key}' has gamePassId = 0 — configure it (purchases refused until then)`)
			end
		end
	end)
end

return ShopSubs
