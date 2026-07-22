--[[
	RebirthSubs — "Food Coma" rebirth (R4, GDD §9): DoRebirth remote and
	the reset orchestration: spend calories -> reset upgrades -> empty the
	belly -> wipe calories -> rebirths += 1. Gems and pets survive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

-- EconomySubs is COMMON; BodySubs is GAME (absent in the lobby partition where
-- rebirth lives — its SendStomach resync is guarded). Both resolved from the
-- subscriptions registry in Start. UpgradeSubs is in the SAME lobby partition,
-- so it stays a static require.
local EconomySubs
local BodySubs
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

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function RebirthSubs.PushInitialState(player: Player)
	RebirthSubs.SendRebirth(player)
end

function RebirthSubs.Start(data, services, subscriptions)
	EconomySubs = subscriptions.EconomySubs
	BodySubs = subscriptions.BodySubs
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
		-- End any active fat-burn session first: the gym drain rewrites the belly
		-- from its captured baseline each tick, which would otherwise re-inflate
		-- the belly we're about to empty. GymService is GAME-only — in the lobby
		-- (where rebirth lives) there's never an active session, so skip it there.
		if services.GymService then
			services.GymService.EndSession(userId)
		end
		-- StomachService is COMMON so the belly (a persisted profile section) can
		-- be emptied from either place.
		services.StomachService.Burn(userId, 0, 0) -- empty the belly, bank nothing
		services.EconomyService.ResetCalories(userId)
		local rebirths = services.ProgressService.ApplyRebirth(userId)
		Log.Sum(SCOPE, `{player.Name} rebirthed -> {rebirths} (next cake may unlock '{services.ProgressService.BiomeFor(rebirths)}')`)

		RebirthSubs.SendRebirth(player)
		UpgradeSubs.SendUpgrades(player)
		EconomySubs.SendCurrency(player)
		-- Belly HUD only exists in the game place; skip the resync in the lobby.
		if BodySubs then
			BodySubs.SendStomach(player)
		end
	end)
end

return RebirthSubs
