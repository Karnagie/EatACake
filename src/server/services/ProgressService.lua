--[[
	ProgressService — lifetime stats + rebirth ("Food Coma") logic over
	profile section `progress` (GDD §9). R3: spending the rebirth cost and
	resetting upgrades belong to EconomyService / UpgradeService — the
	subscription orchestrates; this service owns only the progress section.
]]

local ProgressService = {}

local profileData
local upgradeCfg -- CakeConfigData.upgrades (rebirth block)

function ProgressService.Init(data)
	profileData = data.PlayerProfileData
	upgradeCfg = data.CakeConfigData.upgrades
end

local function progress(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.progress
end

--API
-- Increments a lifetime stat (lifetimeCalories, cakesEaten, findsCollected).
function ProgressService.AddStat(userId: number, key: string, amount: number)
	local section = progress(userId)
	if section and type(section[key]) == "number" then
		section[key] += amount
	end
end

--API
function ProgressService.GetRebirths(userId: number): number?
	local section = progress(userId)
	return section and section.rebirths
end

--API
-- Cost of the player's NEXT rebirth in calories.
function ProgressService.RebirthCost(userId: number): number?
	local section = progress(userId)
	if not section then
		return nil
	end
	return math.floor(upgradeCfg.rebirth.baseCost * upgradeCfg.rebirth.growth ^ section.rebirths)
end

--API
-- Biome unlocked at the player's rebirth level.
function ProgressService.BiomeFor(rebirths: number): string
	local biomes = upgradeCfg.rebirth.biomes
	return biomes[math.clamp(rebirths + 1, 1, #biomes)]
end

--API
-- Applies the rebirth AFTER the subscription spent the cost and reset the
-- upgrades. Returns the new rebirth count.
function ProgressService.ApplyRebirth(userId: number): number?
	local section = progress(userId)
	if not section then
		return nil
	end
	section.rebirths += 1
	return section.rebirths
end

--API
-- Snapshot for the client (rebirth panel + leaderboards).
function ProgressService.Summary(userId: number)
	local section = progress(userId)
	if not section then
		return nil
	end
	return {
		rebirths = section.rebirths,
		lifetimeCalories = section.lifetimeCalories,
		cakesEaten = section.cakesEaten,
		findsCollected = section.findsCollected,
		biggestBelly = section.biggestBelly,
		nextCost = ProgressService.RebirthCost(userId),
		biome = ProgressService.BiomeFor(section.rebirths),
	}
end

return ProgressService
