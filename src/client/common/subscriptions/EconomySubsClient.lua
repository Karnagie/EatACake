--[[
	EconomySubsClient — currency consumer (R4).
	CurrencyUpdate ({ calories, gems }) -> AppRoot HUD pills.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local EconomySubsClient = {}

function EconomySubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot

	Net.Update("CurrencyUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			AppRoot.Set({
				calories = tonumber(payload.calories) or 0,
				gems = tonumber(payload.gems) or 0,
			})
		end
	end)
end

return EconomySubsClient
