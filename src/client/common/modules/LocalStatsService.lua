--[[
	LocalStatsService — client-side mirror of the eat stats needed for
	prediction and auto-fire pacing (GDD §4.7): bite radius/depth and eat
	rate derived from the replicated upgrade levels with the SAME
	UpgradeConfig formulas the server uses. View-model only — the server
	never trusts any of this.

	TIMED BOOSTS: the levels are not the whole story any more. A bite-radius
	boost multiplies the SERVER's radius, and the client predicts its own
	craters — so without the mirror below every predicted crater is smaller than
	the one the server actually carves, for the whole 15 minutes, and the cake
	visibly "grows back" at each delta. The multiplier arrives as the
	`BiteRadiusMult` player ATTRIBUTE (BoostSubs writes it on grant and on
	expiry); attributes replicate on their own, so this needs no remote and no
	subscription.
	The speed and capacity boosts need NO mirror here, and that asymmetry is
	deliberate rather than an omission: WalkSpeed is written authoritatively onto
	the Humanoid (which replicates), and capacity rides the existing StomachUpdate
	payload that BoostSubs re-pushes. Bite radius is the only boosted stat the
	client PREDICTS with.
]]

local Players = game:GetService("Players")
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
-- Live bite-radius BOOST multiplier, mirrored from the server through the
-- `BiteRadiusMult` player attribute. Absent (no boost, or before the first
-- write) reads as 1.
-- ⚠ Floored at 1 on purpose: a garbage attribute must never shrink the
-- prediction BELOW the plain upgrade value. Under-predicting makes the server's
-- delta snap away cake the player never saw go; over-predicting is the worse
-- one (cake visibly pops back). The floor bounds the error to the honest
-- un-boosted radius, which is the same divergence a late attribute already has.
function LocalStatsService.BiteRadiusMult(): number
	local player = Players.LocalPlayer
	if player == nil then
		return 1
	end
	local mult = tonumber(player:GetAttribute("BiteRadiusMult"))
	if mult == nil or mult ~= mult then
		return 1 -- absent, or NaN from a corrupted write
	end
	return math.max(1, mult)
end

--API
function LocalStatsService.BiteRadius(): number
	return upgradeValue("biteRadius") * LocalStatsService.BiteRadiusMult()
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
-- Calories banked per stored calorie. Mirrors StatsService.GymEfficiency EXACTLY
-- (upgrade tier only — gymEff takes no pet bonus, no pass and no boost, so there
-- is nothing to go stale here the way BiteRadiusMult can).
-- Used to answer "what will this belly be WORTH once I burn it off?", which is the
-- only honest affordability question before the player's first gym trip: calories
-- earned by eating sit in `stomach.stored` and buy nothing until they are banked.
function LocalStatsService.GymEfficiency(): number
	return upgradeValue("gymEff")
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
