--[[
	StatsService — derived player stats (GDD §10, §11): upgrade formulas ×
	pet bonuses × gamepass perks × rebirth multiplier × timed boosts.

	R3-legal by construction: reads ONLY data modules (PlayerProfileData
	profile sections, ShopData.passOwnership cache, shared configs) — no
	other service is consulted. Every consumer (CakeSubs, BodySubs, ...)
	gets its numbers from here; nothing else interprets UpgradeConfig.
]]

local StatsService = {}

local profileData
local shopData
local upgradeCfg -- CakeConfigData.upgrades (UpgradeConfig)
local petCfg
local bodyCfg
local treasureCfg

function StatsService.Init(data)
	profileData = data.PlayerProfileData
	shopData = data.ShopData
	upgradeCfg = data.CakeConfigData.upgrades
	petCfg = data.CakeConfigData.pets
	bodyCfg = data.CakeConfigData.body
	treasureCfg = data.CakeConfigData.treasures
end

local function profile(userId: number)
	return profileData.profiles[userId]
end

-- Value of the derived stat at the OWNED tier count (levels[id]); tier 0 =
-- def.base, else def.tiers[tier].value (clamped to the last tier).
local function upgradeValue(levels, id: string): number
	local def = upgradeCfg.upgrades[id]
	local tier = (levels and levels[id]) or 0
	if tier <= 0 then
		return def.base
	end
	local tiers = def.tiers
	return tiers[math.min(tier, #tiers)].value
end

local function ownsPass(userId: number, passKey: string): boolean
	local owned = shopData.passOwnership[userId]
	return owned ~= nil and owned[passKey] == true
end

-- Sum of equipped-pet bonuses for one stat key ("calories"|"eatSpeed"|"gems").
-- Capped at the CURRENT slot count: a player whose VIP lapsed keeps 5 pets
-- in `equipped` (persisted) but only the first `slots` may pay out.
local function petBonus(p, statKey: string, slots: number): number
	local total = 0
	for index, petId in ipairs(p.pets.equipped) do
		if index > slots then
			break
		end
		local copies = p.pets.owned[petId]
		if copies then
			for _, def in ipairs(petCfg.pets) do
				if def.id == petId then
					local base = def.bonus[statKey]
					if base then
						total += base * (1 + petCfg.mergeBonusPerCopy * (copies - 1))
					end
					break
				end
			end
		end
	end
	return total
end

-- Product of live boost multipliers for one stat (expired ones are pruned).
local function boostMult(p, statKey: string): number
	local mult = 1
	local now = os.time()
	local boosts = p.progress.activeBoosts
	for k = #boosts, 1, -1 do
		local boost = boosts[k]
		if boost.expiresAt <= now then
			table.remove(boosts, k)
		elseif boost.stat == statKey then
			mult *= boost.mult
		end
	end
	return mult
end

--API
function StatsService.BiteRadius(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "biteRadius") or upgradeCfg.upgrades.biteRadius.base
end

--API
function StatsService.BiteDepth(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "biteDepth") or upgradeCfg.upgrades.biteDepth.base
end

--API
-- Bites per second (pets speed the mouth up too).
function StatsService.EatRate(userId: number): number
	local p = profile(userId)
	if not p then
		return upgradeCfg.upgrades.eatSpeed.base
	end
	return upgradeValue(p.upgrades.levels, "eatSpeed") * (1 + petBonus(p, "eatSpeed", StatsService.PetSlots(userId)))
end

--API
-- Stomach capacity in studs^3 (x2 with the capacity gamepass).
function StatsService.Capacity(userId: number): number
	local p = profile(userId)
	local base = p and upgradeValue(p.upgrades.levels, "capacity") or upgradeCfg.upgrades.capacity.base
	return base * (if ownsPass(userId, "capacity2") or ownsPass(userId, "vip") then 2 else 1)
end

--API
function StatsService.GymEfficiency(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "gymEff") or upgradeCfg.upgrades.gymEff.base
end

--API
-- Fat-burn PASSIVE drain rate: fraction of the belly burned per second while
-- standing at the gym machine (the "default burning speed" upgrade).
function StatsService.BurnSpeed(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "burnSpeed") or upgradeCfg.upgrades.burnSpeed.base
end

--API
-- Fat burned per on-screen TAP, as a fraction of the belly (base 0.10).
function StatsService.BurnPerTap(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "burnPerTap") or upgradeCfg.upgrades.burnPerTap.base
end

--API
-- Fraction of the belly removed the INSTANT the gym prompt is pressed (0 = none;
-- the final tier is 1.0 = the whole belly at once).
function StatsService.InstantBurn(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "instantBurn") or upgradeCfg.upgrades.instantBurn.base
end

--API
-- Base WalkSpeed BEFORE the fullness penalty (BodySubs applies that).
function StatsService.WalkSpeed(userId: number): number
	local p = profile(userId)
	return p and upgradeValue(p.upgrades.levels, "runSpeed") or upgradeCfg.upgrades.runSpeed.base
end

--API
-- Calories multiplier: rebirth × pets × x2-calories pass / VIP × boosts.
-- Glutton x2 (§8) is NOT here — StomachService applies it against the
-- belly state at ingest time. Rare-cake mult is cake-level (CakeSubs).
function StatsService.CaloriesMult(userId: number): number
	local p = profile(userId)
	if not p then
		return 1
	end
	local mult = 1 + upgradeCfg.rebirth.multPerLevel * p.progress.rebirths
	mult *= 1 + petBonus(p, "calories", StatsService.PetSlots(userId))
	if ownsPass(userId, "x2calories") or ownsPass(userId, "vip") then
		mult *= 2
	end
	mult *= boostMult(p, "calories")
	return mult
end

--API
function StatsService.GemsMult(userId: number): number
	local p = profile(userId)
	if not p then
		return 1
	end
	local mult = 1 + petBonus(p, "gems", StatsService.PetSlots(userId))
	if ownsPass(userId, "x2gems") or ownsPass(userId, "vip") then
		mult *= 2
	end
	mult *= boostMult(p, "gems")
	return mult
end

--API
function StatsService.HasAutoEat(userId: number): boolean
	return ownsPass(userId, "autoeat") or ownsPass(userId, "vip")
end

--API
function StatsService.HasAutoGym(userId: number): boolean
	return ownsPass(userId, "autogym") or ownsPass(userId, "vip")
end

--API
function StatsService.PetSlots(userId: number): number
	return if ownsPass(userId, "vip") then petCfg.equipSlotsVip else petCfg.equipSlots
end

--API
-- Adds a timed boost (from finds / dev products). Stacks refresh duration
-- if the same id is already live. Returns false if the profile is missing.
function StatsService.GrantBoost(userId: number, boostId: string): boolean
	local p = profile(userId)
	local def = treasureCfg.boosts[boostId]
	if not p or not def then
		return false
	end
	local boosts = p.progress.activeBoosts
	for _, boost in ipairs(boosts) do
		if boost.id == boostId then
			boost.expiresAt = os.time() + def.duration
			return true
		end
	end
	table.insert(boosts, { id = boostId, stat = def.stat, mult = def.mult, expiresAt = os.time() + def.duration })
	return true
end

return StatsService
