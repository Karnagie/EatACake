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
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))

-- Resolved from the subscriptions registry in Start (cross-partition safe):
-- EconomySubs is COMMON (currency resync); BodySubs is GAME (absent in the
-- lobby partition this sub lives in — the RefreshBody call below is guarded).
local EconomySubs
local AnalyticsSubs -- optional retention instrumentation (features/analytics.md)
local BodySubs

local SCOPE = "UpgradeSubs"

local UpgradeSubs = {}

-- Telemetry sits BETWEEN the calorie spend and the milestone `Save` on this
-- path, so an unguarded throw here would take the player's calories, grant the
-- tier, and then skip the save that makes it durable. pcall'd, always (R8).
local function beat(player: Player, fn: () -> ())
	if AnalyticsSubs == nil then
		return
	end
	local ok, err = pcall(fn)
	if not ok then
		Log.Once(SCOPE, "upgrade-analytics", `upgrade analytics beat FAILED (telemetry only, purchase unaffected): {err}`)
	end
end

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

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function UpgradeSubs.PushInitialState(player: Player)
	UpgradeSubs.SendUpgrades(player)
end

function UpgradeSubs.Start(data, services, subscriptions)
	EconomySubs = subscriptions.EconomySubs
	AnalyticsSubs = subscriptions.AnalyticsSubs
	BodySubs = subscriptions.BodySubs
	services_ = services
	uUpgrades = Net.Update("UpgradesUpdate")

	Net.Remote("BuyUpgrade").OnServerEvent:Connect(function(player, id)
		if type(id) ~= "string" then
			-- Malformed payload (R8 — never silent, mirrors CakeSubs EatAt).
			Log.Once(SCOPE, `bad-buy-payload-{player.UserId}`, `{player.Name}: BuyUpgrade with non-string id — dropped`)
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			-- Joining: profile not ready (R8 — never silent, mirrors CakeSubs).
			Log.Once(SCOPE, `buy-preload-{userId}`, `{player.Name}: BuyUpgrade before profile load — dropped until loaded`)
			return
		end
		-- The ATTEMPT, before either gate. The gap between this and `bought` is
		-- every player who pressed buy and could not afford it — a pricing
		-- question, not a UI one, and it shows up nowhere else.
		beat(player, function()
			AnalyticsSubs.Funnel(player, "upgrades", "attempt")
		end)
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
		if BodySubs then
			BodySubs.RefreshBody(player) -- capacity / run speed may have changed (game only)
		end
		beat(player, function()
			AnalyticsSubs.Flow(player, "first-upgrade")
			AnalyticsSubs.Funnel(player, "upgrades", "bought")
			AnalyticsSubs.Funnel(player, "match", "upgrade")
			AnalyticsSubs.Event(player, "upgrade-bought", 1, { id, tostring(newLevel or "?"), "game" }, { tier = "normal" })
			-- The tree is the calorie SINK the whole economy is priced against.
			AnalyticsSubs.Economy(
				player,
				"sink",
				AnalyticsConfig.economy.currencies.calories,
				cost,
				services.EconomyService.GetCalories(userId) or 0,
				AnalyticsConfig.economy.transactions.shop,
				id
			)
		end)
		-- Milestone save: a purchase spends calories + grants a permanent tier;
		-- persist now so a crash before the ~300s autosave can't lose it.
		services.PersistenceService.Save(userId)
	end)
end

return UpgradeSubs
