--[[
	UpgradeSubs — upgrade purchases (R4, GDD §10): BuyUpgrade remote,
	spend-then-apply orchestration (EconomyService + UpgradeService), level
	pushes. Costs are recomputed client-side from UpgradeConfig — only
	levels travel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local EconomySubs = require(script.Parent.EconomySubs)
local BodySubs = require(script.Parent.BodySubs)

local SCOPE = "UpgradeSubs"

local UpgradeSubs = {}

local services_
local uUpgrades

--API
function UpgradeSubs.SendUpgrades(player: Player)
	if uUpgrades == nil then
		Log.Warn(SCOPE, `SendUpgrades({player.Name}) before Start ran — push dropped`)
		return
	end
	local levels = services_.UpgradeService.Levels(player.UserId)
	if levels == nil then
		Log.Warn(SCOPE, `SendUpgrades({player.Name}): profile not loaded — push dropped`)
		return
	end
	uUpgrades:FireClient(player, { levels = levels })
end

function UpgradeSubs.Start(data, services)
	services_ = services
	uUpgrades = Net.Update("UpgradesUpdate")

	Net.Remote("BuyUpgrade").OnServerEvent:Connect(function(player, id)
		if type(id) ~= "string" then
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			return
		end
		local cost = services.UpgradeService.NextCost(userId, id)
		if cost == nil then
			-- Capped or unknown id: resync the client panel, don't spend.
			UpgradeSubs.SendUpgrades(player)
			return
		end
		local ok = services.EconomyService.TrySpendCalories(userId, cost)
		if not ok then
			EconomySubs.SendCurrency(player) -- stale client balance: resync
			return
		end
		local newLevel = services.UpgradeService.ApplyLevel(userId, id)
		if newLevel == nil then
			-- Can't happen after the NextCost gate (no yields between), but
			-- never eat the player's calories silently if it ever does.
			services.EconomyService.AddCalories(userId, cost)
			Log.Warn(SCOPE, `{player.Name}: ApplyLevel({id}) failed AFTER spend — refunded {cost}`)
		end
		UpgradeSubs.SendUpgrades(player)
		EconomySubs.SendCurrency(player)
		BodySubs.RefreshBody(player) -- capacity / run speed may have changed
	end)
end

return UpgradeSubs
