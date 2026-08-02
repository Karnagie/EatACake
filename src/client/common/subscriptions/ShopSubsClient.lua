--[[
	ShopSubsClient — shop + group-reward consumers (R4).

	ShopUpdate -> AppRoot.shop; GroupRewardUpdate -> AppRoot.group (the group
	row lives in the shop's Free section). Row activation routes by id
	prefix: "product:<key>" -> RequestPurchase or RequestGemPurchase depending
	on the product's CURRENCY, "pass:<key>" -> RequestGamepass, "group" ->
	ClaimGroupReward.

	The currency lookup is rebuilt from every ShopUpdate rather than carried on
	the cell: ShopPanel passes the row ID and nothing else to onActivated, so a
	`currency` field on the view-model cell could never reach this handler.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local ShopSubsClient = {}

function ShopSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	-- Optional (features/analytics.md). Which CARD a player taps only exists
	-- on the client until the server is asked for a purchase, and the taps
	-- that never become a request are the interesting ones.
	local Analytics = modules.LocalAnalyticsService
	local rPurchase = Net.Remote("RequestPurchase")
	local rGemPurchase = Net.Remote("RequestGemPurchase")
	local rGamepass = Net.Remote("RequestGamepass")
	local rGroup = Net.Remote("ClaimGroupReward")

	-- product key -> currency, refreshed by every ShopUpdate below. Empty until
	-- the first payload lands, which is also when the shop first has cells to
	-- click, so an unknown key here means a Robux product and never a gem one.
	local currencyByKey: { [string]: string? } = {}

	AppRoot.SetCallbacks({
		onShopTabChanged = function(tabId)
			if Analytics and type(tabId) == "string" then
				Analytics.Track("shop", "tab", tabId, { urgent = true })
			end
		end,
		onShopActivated = function(rowId)
			if type(rowId) ~= "string" then
				return
			end
			if Analytics then
				Analytics.Track("shop", "card", rowId, { urgent = true })
			end
			local productKey = string.match(rowId, "^product:(.+)$")
			if productKey then
				if currencyByKey[productKey] == "gems" then
					rGemPurchase:FireServer(productKey)
				else
					rPurchase:FireServer(productKey)
				end
				-- Cue the REQUEST, not the sale: on the Robux route the prompt is
				-- about to take over the screen (ProcessReceipt owns the outcome),
				-- and on the gem route the server can still refuse. Either way the
				-- result arrives as a ShopUpdate/CurrencyUpdate, not as this click.
				SoundPool.Play("purchaseStart")
				return
			end
			local passKey = string.match(rowId, "^pass:(.+)$")
			if passKey then
				rGamepass:FireServer(passKey)
				SoundPool.Play("purchaseStart")
				return
			end
			if rowId == "group" then
				rGroup:FireServer()
			end
		end,
	})

	Net.Update("ShopUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local products = if type(payload.products) == "table" then payload.products else {}
		-- Rebuilt, not merged: a product dropped from the catalogue must stop
		-- routing to the gem remote the moment it stops being sold.
		table.clear(currencyByKey)
		for _, product in ipairs(products) do
			if type(product) == "table" and type(product.key) == "string" then
				currencyByKey[product.key] = product.currency
			end
		end
		AppRoot.Set({
			shop = {
				products = products,
				passes = if type(payload.passes) == "table" then payload.passes else {},
			},
		})
	end)

	Net.Update("GroupRewardUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		AppRoot.Set({
			group = {
				configured = payload.configured == true,
				claimed = payload.claimed == true,
				groupId = payload.groupId,
				status = payload.status,
			},
		})
		-- CELEBRATION HOOK: payload.status == "granted" with payload.granted
		-- descriptor — toast/particles when the FX layer lands. Sound is wired.
		if payload.status == "granted" then
			SoundPool.Play("purchaseOk")
		end
	end)
end

return ShopSubsClient
