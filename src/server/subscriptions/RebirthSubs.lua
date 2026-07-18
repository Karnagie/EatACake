--[[
	RebirthSubs — "Food Coma" rebirth (R4, GDD §9): DoRebirth remote and
	the reset orchestration: spend calories -> reset upgrades -> empty the
	belly -> wipe calories -> rebirths += 1. Gems and pets survive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local EconomySubs = require(script.Parent.EconomySubs)
local BodySubs = require(script.Parent.BodySubs)
local UpgradeSubs = require(script.Parent.UpgradeSubs)

local SCOPE = "RebirthSubs"

local RebirthSubs = {}

local services_
local uRebirth

--API
function RebirthSubs.SendRebirth(player: Player)
	if uRebirth == nil then
		Log.Warn(SCOPE, `SendRebirth({player.Name}) before Start ran — push dropped`)
		return
	end
	local summary = services_.ProgressService.Summary(player.UserId)
	if summary == nil then
		Log.Warn(SCOPE, `SendRebirth({player.Name}): profile not loaded — push dropped`)
		return
	end
	uRebirth:FireClient(player, summary)
end

function RebirthSubs.Start(data, services)
	services_ = services
	uRebirth = Net.Update("RebirthUpdate")

	Net.Remote("DoRebirth").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			-- Joining: profile not ready (R8 — never silent, mirrors CakeSubs).
			Log.Once(SCOPE, `rebirth-preload-{userId}`, `{player.Name}: DoRebirth before profile load — dropped until loaded`)
			return
		end
		local cost = services.ProgressService.RebirthCost(userId)
		if cost == nil then
			return
		end
		local ok = services.EconomyService.TrySpendCalories(userId, cost)
		if not ok then
			RebirthSubs.SendRebirth(player) -- stale client: resync cost/state
			return
		end
		services.UpgradeService.ResetForRebirth(userId)
		services.StomachService.Burn(userId, 0, 0) -- empty the belly, bank nothing
		services.EconomyService.ResetCalories(userId)
		local rebirths = services.ProgressService.ApplyRebirth(userId)
		Log.Sum(SCOPE, `{player.Name} rebirthed -> {rebirths} (next cake may unlock '{services.ProgressService.BiomeFor(rebirths)}')`)

		RebirthSubs.SendRebirth(player)
		UpgradeSubs.SendUpgrades(player)
		EconomySubs.SendCurrency(player)
		BodySubs.SendStomach(player)
	end)
end

return RebirthSubs
