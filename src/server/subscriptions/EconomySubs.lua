--[[
	EconomySubs — economy domain replication (R4).
	SendCurrency(player) pushes both balances (calories + gems) in one
	CurrencyUpdate. Earn/spend flows of other features call it themselves
	after coordinating EconomyService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local EconomySubs = {}

local EconomyService
local uCurrency

--API
function EconomySubs.SendCurrency(player: Player)
	if uCurrency == nil then
		Log.Warn("EconomySubs", `SendCurrency({player.Name}) before Start ran — push dropped`)
		return
	end
	local calories = EconomyService.GetCalories(player.UserId)
	local gems = EconomyService.GetGems(player.UserId)
	if calories ~= nil and gems ~= nil then
		uCurrency:FireClient(player, { calories = calories, gems = gems })
	else
		Log.Warn("EconomySubs", `SendCurrency({player.Name}): profile not loaded — push dropped`)
	end
end

function EconomySubs.Start(data, services)
	EconomyService = services.EconomyService
	uCurrency = Net.Update("CurrencyUpdate")
end

return EconomySubs
