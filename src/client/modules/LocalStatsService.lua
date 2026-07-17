--[[
	LocalStatsService — client-side mirror of the eat stats needed for
	prediction and auto-fire pacing (GDD §4.7): bite radius/depth and eat
	rate derived from the replicated upgrade levels with the SAME
	UpgradeConfig formulas the server uses. View-model only — the server
	never trusts any of this.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpgradeConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("UpgradeConfig")
)

local LocalStatsService = {}

local levels: { [string]: number } = {}

local function upgradeValue(id: string): number
	local def = UpgradeConfig.upgrades[id]
	local level = levels[id] or 0
	if def.add then
		return def.base + def.add * level
	end
	return def.base * (1 + (def.pct or 0) * level)
end

--API
-- Fed by UpgradesSubsClient on every UpgradesUpdate.
function LocalStatsService.SetLevels(newLevels: { [string]: number })
	levels = newLevels or {}
end

--API
function LocalStatsService.Levels(): { [string]: number }
	return levels
end

--API
function LocalStatsService.BiteRadius(): number
	return upgradeValue("biteRadius")
end

--API
function LocalStatsService.BiteDepth(): number
	return upgradeValue("biteDepth")
end

--API
-- Bites per second for the hold-to-eat auto-fire (pet eat-speed bonuses
-- are ignored here on purpose: firing slightly UNDER the server's rate
-- cap is safe; over it, bites get dropped).
function LocalStatsService.EatRate(): number
	return upgradeValue("eatSpeed")
end

--API
-- Next-level cost for the upgrades panel (same formula as the server).
function LocalStatsService.NextCost(id: string): number?
	local def = UpgradeConfig.upgrades[id]
	if not def then
		return nil
	end
	local level = levels[id] or 0
	if level >= def.cap then
		return nil
	end
	return math.floor(def.baseCost * def.growth ^ level)
end

return LocalStatsService
