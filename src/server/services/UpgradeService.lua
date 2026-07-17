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
-- Cost of the NEXT level, or nil when capped / unknown id / no profile.
function UpgradeService.NextCost(userId: number, id: string): number?
	local def = upgradeCfg.upgrades[id]
	local map = levels(userId)
	if not def or not map then
		return nil
	end
	local level = map[id] or 0
	if level >= def.cap then
		return nil
	end
	return math.floor(def.baseCost * def.growth ^ level)
end

--API
-- Applies one level AFTER the subscription successfully spent the cost.
-- Returns the new level, or nil if capped/invalid.
function UpgradeService.ApplyLevel(userId: number, id: string): number?
	local def = upgradeCfg.upgrades[id]
	local map = levels(userId)
	if not def or not map then
		return nil
	end
	local level = map[id] or 0
	if level >= def.cap then
		return nil
	end
	map[id] = level + 1
	return map[id]
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

--API
-- Rebirth wipe: resets the configured upgrade ids to 0.
function UpgradeService.ResetForRebirth(userId: number): boolean
	local map = levels(userId)
	if not map then
		return false
	end
	for _, id in ipairs(upgradeCfg.rebirth.resets) do
		map[id] = 0
	end
	return true
end

return UpgradeService
