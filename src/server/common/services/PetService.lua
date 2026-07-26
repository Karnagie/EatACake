--[[
	PetService — pet rolls, collection and equipping (GDD §9).

	ROLLS HAPPEN HERE, ON THE SERVER, ONLY (GDD §13): the client receives
	results, never randomness. Odds come from PetConfig verbatim — the same
	table the UI displays (policy requirement).

	Duplicates merge automatically: owned[petId] counts copies = pet level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local PetService = {}

local profileData
local petCfg

-- petId -> def and rarity -> defs index, built once in Init.
local byId: { [string]: any } = {}
local byRarity: { [string]: { any } } = {}

function PetService.Init(data)
	profileData = data.PlayerProfileData
	petCfg = data.CakeConfigData.pets
	table.clear(byId)
	table.clear(byRarity)
	for _, def in ipairs(petCfg.pets) do
		byId[def.id] = def
		byRarity[def.rarity] = byRarity[def.rarity] or {}
		table.insert(byRarity[def.rarity], def)
	end
	for _, rarity in ipairs(petCfg.rarities) do
		if not byRarity[rarity.id] or #byRarity[rarity.id] == 0 then
			Log.Warn("PetService", `rarity '{rarity.id}' has NO pets in PetConfig — rolls will reroll around it`)
		end
	end
end

local function pets(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.pets
end

-- Weighted rarity roll. weightsOverride: { [rarityId] = weight } (egg types,
-- rainbow-cake guarantee). Rarities with no pets or zero weight are skipped.
local function rollRarity(weightsOverride: { [string]: number }?): string
	local total = 0
	local entries = {}
	for _, rarity in ipairs(petCfg.rarities) do
		local weight = if weightsOverride then (weightsOverride[rarity.id] or 0) else rarity.weight
		if weight > 0 and byRarity[rarity.id] and #byRarity[rarity.id] > 0 then
			total += weight
			table.insert(entries, { id = rarity.id, weight = weight })
		end
	end
	local roll = math.random() * total
	for _, entry in ipairs(entries) do
		roll -= entry.weight
		if roll <= 0 then
			return entry.id
		end
	end
	return entries[#entries].id
end

--API
-- Rolls one pet for the player and adds it to the collection.
-- eggType: key of PetConfig.eggs (nil = "cycle" base odds).
-- minRarity: optional floor (rainbow cake "guaranteed Epic+").
-- Returns { petId, rarity, copies, isNew } or nil (profile not loaded).
function PetService.Roll(userId: number, eggType: string?, minRarity: string?)
	local section = pets(userId)
	if not section then
		return nil
	end
	local egg = petCfg.eggs[eggType or "cycle"] or petCfg.eggs.cycle
	local weights = egg.weights

	if minRarity then
		-- Zero out everything below the floor.
		local floor = {}
		local reached = false
		for _, rarity in ipairs(petCfg.rarities) do
			if rarity.id == minRarity then
				reached = true
			end
			floor[rarity.id] = if reached then (weights and weights[rarity.id] or rarity.weight) else 0
		end
		weights = floor
	end

	local rarityId = rollRarity(weights)
	local pool = byRarity[rarityId]
	local def = pool[math.random(#pool)]

	local isNew = section.owned[def.id] == nil
	section.owned[def.id] = (section.owned[def.id] or 0) + 1

	return {
		petId = def.id,
		rarity = rarityId,
		copies = section.owned[def.id],
		isNew = isNew,
	}
end

--API
-- Equips a pet. maxSlots comes from StatsService.PetSlots (VIP-aware) —
-- passed in by the subscription (R3). Returns ok + reason.
function PetService.Equip(userId: number, petId: string, maxSlots: number): (boolean, string?)
	local section = pets(userId)
	if not section then
		return false, "no-profile"
	end
	if not byId[petId] or not section.owned[petId] then
		return false, "not-owned"
	end
	if table.find(section.equipped, petId) then
		return false, "already-equipped"
	end
	if #section.equipped >= maxSlots then
		return false, "no-slots"
	end
	table.insert(section.equipped, petId)
	return true
end

--API
function PetService.Unequip(userId: number, petId: string): (boolean, string?)
	local section = pets(userId)
	if not section then
		return false, "no-profile"
	end
	local idx = table.find(section.equipped, petId)
	if not idx then
		return false, "not-equipped"
	end
	table.remove(section.equipped, idx)
	return true
end

--API
-- Collection snapshot for the client panel: array of
-- { petId, rarity, copies, equipped }.
function PetService.Collection(userId: number)
	local section = pets(userId)
	if not section then
		return nil
	end
	local out = {}
	for petId, copies in pairs(section.owned) do
		local def = byId[petId]
		if def then
			table.insert(out, {
				petId = petId,
				rarity = def.rarity,
				copies = copies,
				equipped = table.find(section.equipped, petId) ~= nil,
			})
		else
			-- A profile id with no PetConfig entry is DROPPED here, before it ever
			-- reaches the client — so this is the only place it can be reported.
			-- It means a config id was renamed or removed: those ids are DataStore
			-- keys, and every player who owned this one just lost it (R8).
			Log.Once(
				SCOPE,
				`orphan-{petId}`,
				`profile owns '{petId}' but PetConfig has no such id — squishy dropped from the collection. `
					.. `Ids are DataStore keys: restore the entry, or add a PetsSection migration that remaps it.`
			)
		end
	end
	table.sort(out, function(a, b)
		return a.petId < b.petId
	end)
	return out
end

return PetService
