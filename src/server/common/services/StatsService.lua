--[[
	StatsService — derived player stats (GDD §10, §11): upgrade formulas ×
	pet bonuses × gamepass perks × timed boosts.

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

-- Drops boosts whose timer has run out and returns the live ones.
-- ⚠ LOAD-BEARING SIDE EFFECT: reading is deliberately IMPURE. Nothing else
-- scans `activeBoosts` at runtime (the section's sanitize only runs at profile
-- load), so this prune is what actually RETIRES an expired boost — including
-- the one BoostSubs' sweep relies on to notice an expiry. Do not "clean this
-- up" into a pure read.
local function pruneExpired(p)
	local boosts = p.progress.activeBoosts
	local now = os.time()
	for k = #boosts, 1, -1 do
		if boosts[k].expiresAt <= now then
			table.remove(boosts, k)
		end
	end
	return boosts
end

-- Product of live boost multipliers for one stat (expired ones are pruned).
local function boostMult(p, statKey: string): number
	local mult = 1
	for _, boost in ipairs(pruneExpired(p)) do
		-- The multiplier comes from the ENTRY, never from TreasureConfig.boosts:
		-- a live boost keeps working (and expires normally) after its def is
		-- removed from the catalogue.
		if boost.stat == statKey then
			mult *= boost.mult
		end
	end
	return mult
end

--API
-- Bite SCOOP radius in studs, BEFORE the band's `scoop` multiplier
-- (CakeFieldService.ScoopedRadius applies that). The client PREDICTS craters
-- from its own copy of this number, so the boost term below must be mirrored
-- there — BoostSubs does it through the `BiteRadiusMult` player attribute.
function StatsService.BiteRadius(userId: number): number
	local p = profile(userId)
	if not p then
		return upgradeCfg.upgrades.biteRadius.base
	end
	return upgradeValue(p.upgrades.levels, "biteRadius") * boostMult(p, "biteRadius")
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
	if ownsPass(userId, "capacity2") or ownsPass(userId, "vip") then
		base *= 2
	end
	if p then
		-- AFTER the pass, so the two STACK multiplicatively (x2 pass + x2 boost
		-- = x4) instead of the boost quietly replacing a 399 R$ perk.
		base *= boostMult(p, "capacity")
	end
	return base
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
-- Base WalkSpeed BEFORE the fullness penalty (BodySubs applies that). Written
-- onto the Humanoid, so a speed boost only lands when something calls
-- BodySubs.RefreshBody — BoostSubs does that on grant AND on expiry.
function StatsService.WalkSpeed(userId: number): number
	local p = profile(userId)
	if not p then
		return upgradeCfg.upgrades.runSpeed.base
	end
	return upgradeValue(p.upgrades.levels, "runSpeed") * boostMult(p, "walkSpeed")
end

--API
-- Calories multiplier: pets × x2-calories pass / VIP × boosts. (The rebirth
-- term is gone with the rebirth system, 2026-07-26.)
-- Glutton x2 (§8) is NOT here — StomachService applies it against the
-- belly state at ingest time. Rare-cake mult is cake-level (CakeSubs).
function StatsService.CaloriesMult(userId: number): number
	local p = profile(userId)
	if not p then
		return 1
	end
	local mult = 1 + petBonus(p, "calories", StatsService.PetSlots(userId))
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
-- Live boost multiplier for ONE stat key (calories | gems | biteRadius |
-- walkSpeed | capacity); 1 when nothing boosts it. Public because the stats
-- that are PUSHED or APPLIED once — bite radius (mirrored to the client),
-- WalkSpeed, capacity — need a subscription to re-apply them, and that
-- subscription must not re-derive the boost maths itself.
function StatsService.BoostMult(userId: number, statKey: string): number
	local p = profile(userId)
	if not p then
		return 1
	end
	return boostMult(p, statKey)
end

--API
-- Stable fingerprint of the player's LIVE boost set ("id@expiresAt" per boost,
-- sorted, joined). A boost EXPIRING fires no event, so BoostSubs polls this and
-- compares it to the last value: it changes on a grant, on a refresh (the
-- expiry moves) and on an expiry, and on nothing else. Cheap by design — the
-- common case (no boosts) returns a constant and allocates nothing.
-- ⚠ Reading also PRUNES (see pruneExpired): this call is what retires an
-- expired boost, so the sweep both detects and effects the expiry.
function StatsService.BoostSignature(userId: number): string
	local p = profile(userId)
	if not p then
		return ""
	end
	local boosts = pruneExpired(p)
	if #boosts == 0 then
		return ""
	end
	local parts = table.create(#boosts)
	for _, boost in ipairs(boosts) do
		table.insert(parts, `{boost.id}@{boost.expiresAt}`)
	end
	table.sort(parts) -- order in the array is grant order; the signature must not be
	return table.concat(parts, "|")
end

--API
-- Adds a timed boost (finds / daily rewards / the gem shop). A second grant of a
-- LIVE boost EXTENDS it — the remaining time is kept and the new duration added.
-- Returns false if the profile is missing or the id names no def.
--
-- ⚠ It used to RESET (`expiresAt = now + duration`), which quietly ate the
-- purchase: claim the Day-2 Extra Bite Size, buy the same boost a minute later
-- for 500 gems — one whole cleared cake by this game's balance rule — and the
-- player gained 60 seconds. Nothing in the UI shows a boost is running, so there
-- was no way to notice before paying. Extending cannot lose time by construction,
-- which is why it is the safe default rather than a refusal.
function StatsService.GrantBoost(userId: number, boostId: string): boolean
	local p = profile(userId)
	local def = treasureCfg.boosts[boostId]
	if not p or not def then
		return false
	end
	local now = os.time()
	local boosts = p.progress.activeBoosts
	for _, boost in ipairs(boosts) do
		if boost.id == boostId then
			-- max(expiresAt, now) so an entry that expired between the last prune
			-- and this call starts a fresh full duration instead of adding onto a
			-- timestamp already in the past.
			boost.expiresAt = math.max(boost.expiresAt, now) + def.duration
			-- Re-stamp stat/mult: a live entry carries the values it was granted
			-- with (that is what lets a deleted def expire cleanly), so a retuned
			-- def would otherwise not reach a player holding the old one.
			boost.stat = def.stat
			boost.mult = def.mult
			return true
		end
	end
	table.insert(boosts, { id = boostId, stat = def.stat, mult = def.mult, expiresAt = now + def.duration })
	return true
end

--API
-- Unix time at which the SOONEST live boost expires, or nil if none are running.
-- BoostSubs schedules its re-apply on this instead of waiting for the next sweep
-- tick: the server retires a boost the moment os.time() passes expiresAt, so a
-- purely periodic refresh leaves the client mirroring a multiplier the server has
-- already dropped (bite prediction carves craters bigger than the authoritative
-- delta for that window, and over-prediction is the visible failure).
function StatsService.NextBoostExpiry(userId: number): number?
	local p = profile(userId)
	if not p then
		return nil
	end
	local soonest
	for _, boost in ipairs(p.progress.activeBoosts) do
		if soonest == nil or boost.expiresAt < soonest then
			soonest = boost.expiresAt
		end
	end
	return soonest
end

return StatsService
