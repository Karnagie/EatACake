--[[
	ShopSubsClient — shop + group-reward consumers (R4).

	ShopUpdate -> AppRoot.shop; GroupRewardUpdate -> AppRoot.group (the group
	row lives in the shop's Free section). Row activation routes by id
	prefix: "product:<key>" -> RequestPurchase, "pass:<key>" ->
	RequestGamepass, "group" -> ClaimGroupReward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local ShopSubsClient = {}

function ShopSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rPurchase = Net.Remote("RequestPurchase")
	local rGamepass = Net.Remote("RequestGamepass")
	local rGroup = Net.Remote("ClaimGroupReward")

	AppRoot.SetCallbacks({
		onShopActivated = function(rowId)
			if type(rowId) ~= "string" then
				return
			end
			local productKey = string.match(rowId, "^product:(.+)$")
			if productKey then
				rPurchase:FireServer(productKey)
				-- The Robux prompt is about to take over the screen: cue the
				-- handoff, not the sale (ProcessReceipt owns the outcome).
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
		AppRoot.Set({
			shop = {
				products = if type(payload.products) == "table" then payload.products else {},
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
