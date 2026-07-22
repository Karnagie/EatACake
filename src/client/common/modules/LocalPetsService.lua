--[[
	LocalPetsService — pets view-model (R2, logic only). Adapts PetsUpdate
	snapshots ({ collection = { { petId, rarity, copies, equipped } }, slots })
	plus Shared.config.PetConfig into data props for UIKit.PetsInspectPanel
	(grid cards, equipped map, inspector stat rows) and builds the
	player-facing egg odds line from PetConfig.rarities.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared:WaitForChild("config"):WaitForChild("PetConfig"))
local Log = require(Shared:WaitForChild("Log"))

local LocalPetsService = {}

local locale

-- config rarity id (kebab-case) -> UIKit Theme.Rarity style key
local RARITY_STYLE = {
	["common"] = "Common",
	["uncommon"] = "Uncommon",
	["rare"] = "Rare",
	["epic"] = "Epic",
	["legendary"] = "Legendary",
	["secret"] = "Secret",
}

-- inspector stat rows: fixed display order, locale key + English fallback
local STAT_DEFS = {
	{ key = "calories", labelKey = "stat-calories", fallback = "Calories" },
	{ key = "eatSpeed", labelKey = "stat-eat-speed", fallback = "Eat Speed" },
	{ key = "gems", labelKey = "stat-gems", fallback = "Gems" },
}

local MAX_STAT_ROWS = 2 -- the inspector sidebar has two stat row slots

local petsById = {}

-- "crumb-mouse" -> "Crumb Mouse"
local function prettifyId(petId: string): string
	local words = {}
	for word in string.gmatch(petId, "[^%-]+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(words, " ")
end

-- LocaleData.T returns the key itself (and warns) when the key is missing —
-- treat that, or nil, as "not localized yet" and use the fallback.
local function localize(key: string, fallback: string): string
	if locale == nil then
		return fallback
	end
	local text = locale.T(key)
	if text == nil or text == key then
		return fallback
	end
	return text
end

local function petDisplayName(def, petId: string): string
	if def ~= nil and def.nameKey ~= nil then
		return localize(def.nameKey, prettifyId(petId))
	end
	return prettifyId(petId)
end

-- bonus is a fraction (0.05 = +5%); copies merge into level N:
-- bonus * (1 + mergeBonusPerCopy * (N - 1)), shown as a whole percent
local function scaledPercent(base: number, copies: number?): number
	local scale = 1 + PetConfig.mergeBonusPerCopy * (math.max(copies or 1, 1) - 1)
	return math.floor(base * scale * 100 + 0.5)
end

-- up to MAX_STAT_ROWS rows { label, value } from the pet's bonus table,
-- largest bonuses first (ties keep STAT_DEFS order)
local function buildStatRows(def, copies: number?)
	local rows = {}
	if def == nil or def.bonus == nil then
		return rows
	end

	local scored = {}
	for order, stat in ipairs(STAT_DEFS) do
		local base = def.bonus[stat.key]
		if base ~= nil then
			table.insert(scored, { order = order, stat = stat, percent = scaledPercent(base, copies) })
		end
	end
	table.sort(scored, function(a, b)
		if a.percent ~= b.percent then
			return a.percent > b.percent
		end
		return a.order < b.order
	end)

	for index = 1, math.min(MAX_STAT_ROWS, #scored) do
		local entry = scored[index]
		rows[index] = {
			label = localize(entry.stat.labelKey, entry.stat.fallback),
			value = `+{entry.percent}%`,
		}
	end
	return rows
end

function LocalPetsService.Init(data)
	locale = data.LocaleData
	for _, def in ipairs(PetConfig.pets) do
		petsById[def.id] = def
	end
end

--API
-- (petsState?, selectedId?) -> DATA props for UIKit.PetsInspectPanel:
--   pets          array of { id, name, rarity (Theme.Rarity style key) }
--   equipped      map { [petId] = true }
--   equippedCount number of equipped pets
--   maxEquipped   petsState.slots (default PetConfig.equipSlots)
--   selectedId    passed through
--   selectedPet   { id, name, rarity, copies, stats = { { label, value } } } or nil
-- The caller adds visible/size/zIndex and the on* callbacks.
function LocalPetsService.BuildPanelProps(petsState, selectedId: string?)
	local collection = if type(petsState) == "table" then petsState.collection or {} else {}
	local slots = if type(petsState) == "table" and petsState.slots ~= nil
		then petsState.slots
		else PetConfig.equipSlots

	local pets = {}
	local equipped = {}
	local equippedCount = 0
	local selectedPet = nil

	for _, entry in ipairs(collection) do
		local def = petsById[entry.petId]
		if def == nil then
			Log.Once(
				"LocalPetsService",
				entry.petId,
				`pet '{entry.petId}' from PetsUpdate has no PetConfig entry — showing fallback card`
			)
		end

		local rarityId = if def ~= nil then def.rarity else entry.rarity
		local rarityStyle = RARITY_STYLE[rarityId] or "Common"
		local name = petDisplayName(def, entry.petId)

		table.insert(pets, {
			id = entry.petId,
			name = name,
			rarity = rarityStyle,
		})

		if entry.equipped == true then
			equipped[entry.petId] = true
			equippedCount += 1
		end

		if selectedId ~= nil and entry.petId == selectedId then
			selectedPet = {
				id = entry.petId,
				name = name,
				rarity = rarityStyle,
				copies = entry.copies or 1,
				stats = buildStatRows(def, entry.copies),
			}
		end
	end

	return {
		pets = pets,
		equipped = equipped,
		equippedCount = equippedCount,
		maxEquipped = slots,
		selectedId = selectedId,
		selectedPet = selectedPet,
	}
end

--API
-- PetRollUpdate payload ({ petId, rarity, copies, isNew }) -> props for
-- UIKit.PetRevealOverlay's `reveal` field: { petName, rarity, subText }.
function LocalPetsService.BuildReveal(roll)
	if type(roll) ~= "table" or type(roll.petId) ~= "string" then
		return nil
	end
	local def = petsById[roll.petId]
	local rarityId = if def ~= nil then def.rarity else roll.rarity
	local subText
	if roll.isNew then
		subText = localize("reveal-new", "NEW PET!")
	else
		local copies = roll.copies or 1
		if locale ~= nil then
			subText = locale.T("reveal-copies", { n = copies })
		else
			subText = `Level {copies}`
		end
	end
	return {
		petName = petDisplayName(def, roll.petId),
		rarity = RARITY_STYLE[rarityId] or "Common",
		subText = subText,
	}
end

--API
-- One-line base egg odds string computed from PetConfig.rarities weights
-- (player-facing odds disclosure), e.g. "Common 60% · Uncommon 25% · ...".
-- Zero-weight rarities are skipped.
function LocalPetsService.OddsText(): string
	local total = 0
	for _, rarity in ipairs(PetConfig.rarities) do
		total += rarity.weight
	end
	if total <= 0 then
		Log.Once("LocalPetsService", "odds-total", "PetConfig.rarities weights sum to 0 — odds text unavailable")
		return ""
	end

	local parts = {}
	for _, rarity in ipairs(PetConfig.rarities) do
		if rarity.weight > 0 then
			local percent = rarity.weight / total * 100
			local label = localize(`rarity-{rarity.id}`, RARITY_STYLE[rarity.id] or prettifyId(rarity.id))
			table.insert(parts, `{label} {string.format("%g", percent)}%`)
		end
	end

	return table.concat(parts, " · ")
end

return LocalPetsService
