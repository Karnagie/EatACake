--[[
	UpgradeService — upgrade level logic over profile section `upgrades`
	(GDD §10). Costs/caps come from UpgradeConfig. R3: SPENDING calories is
	EconomyService's job — UpgradeSubs orchestrates spend-then-apply.
]]

local UpgradeService = {}

local profileData
local upgradeCfg

function UpgradeService.Init(data)
	profileData = data.PlayerProfileData
	upgradeCfg = data.CakeConfigData.upgrades
end

local function levels(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.upgrades.levels
end

--API
function UpgradeService.GetLevel(userId: number, id: string): number?
	local map = levels(userId)
	return map and (map[id] or 0)
end

--API
-- Cost of the NEXT tier, or nil when maxed / unknown id / no profile.
function UpgradeService.NextCost(userId: number, id: string): number?
	local def = upgradeCfg.upgrades[id]
	local map = levels(userId)
	if not def or not map then
		return nil
	end
	local nextTier = def.tiers[(map[id] or 0) + 1]
	if nextTier == nil then
		return nil -- capped (no further tier)
	end
	return nextTier.cost
end

--API
-- Applies one tier AFTER the subscription successfully spent the cost.
-- Returns the new tier count, or nil if maxed/invalid.
function UpgradeService.ApplyLevel(userId: number, id: string): number?
	local def = upgradeCfg.upgrades[id]
	local map = levels(userId)
	if not def or not map then
		return nil
	end
	local tier = map[id] or 0
	if def.tiers[tier + 1] == nil then
		return nil -- capped
	end
	map[id] = tier + 1
	return map[id]
end

--API
-- Drops every upgrade back to tier 0. The tree is RUN-scoped (ADR-0013): a run
-- starts with a base eater and buys the whole tree back inside one cake, so this
-- fires on every profile load — entering the lobby AND arriving in a match.
-- Returns false if the profile isn't loaded (nothing was reset).
function UpgradeService.ResetTiers(userId: number): boolean
	local map = levels(userId)
	if not map then
		return false
	end
	-- Clear by ITERATING the stored map, not just the config ids: a retired id
	-- left in an old profile would otherwise keep a tier count forever.
	for id in pairs(map) do
		map[id] = 0
	end
	for id in pairs(upgradeCfg.upgrades) do
		map[id] = 0
	end
	return true
end

--API
-- Full level map (for the client panel push).
function UpgradeService.Levels(userId: number): { [string]: number }?
	local map = levels(userId)
	if not map then
		return nil
	end
	local copy = {}
	for id in pairs(upgradeCfg.upgrades) do
		copy[id] = map[id] or 0
	end
	return copy
end

return UpgradeService
