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
	local tier = levels[id] or 0
	if tier <= 0 then
		return def.base
	end
	local tiers = def.tiers
	return tiers[math.min(tier, #tiers)].value
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
-- Next-tier cost for the upgrades tree (same table as the server); nil = maxed.
function LocalStatsService.NextCost(id: string): number?
	local def = UpgradeConfig.upgrades[id]
	if not def then
		return nil
	end
	local nextTier = def.tiers[(levels[id] or 0) + 1]
	return nextTier and nextTier.cost or nil
end

--API
-- Owned tier count for an upgrade id (0 = none).
function LocalStatsService.Level(id: string): number
	return levels[id] or 0
end

return LocalStatsService
