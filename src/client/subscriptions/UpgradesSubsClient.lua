--[[
	UpgradesSubsClient — upgrade levels consumer (R4): UpgradesUpdate feeds
	LocalStatsService (bite prediction/auto-fire pacing) + the AppRoot
	upgrades panel; panel buys flow back through the BuyUpgrade remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local UpgradesSubsClient = {}

function UpgradesSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local LocalStatsService = modules.LocalStatsService
	local rBuy = Net.Remote("BuyUpgrade")

	Net.Update("UpgradesUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.levels) ~= "table" then
			return
		end
		LocalStatsService.SetLevels(payload.levels)
		AppRoot.Set({ upgrades = payload.levels })
	end)

	AppRoot.SetCallbacks({
		onBuyUpgrade = function(id: string)
			rBuy:FireServer(id)
		end,
	})
end

return UpgradesSubsClient
