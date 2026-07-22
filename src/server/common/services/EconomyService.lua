--[[
	EconomyService
	Two-currency logic over the profile's `economy` section (GDD §10):
	calories (soft, wiped on rebirth) and gems (hard, persistent).
	R2: logic only; state lives in the profile.

	R3: this service does not talk to other services and does not replicate —
	subscriptions fire CurrencyUpdate after calling it.
]]

local EconomyService = {}

local profileData

function EconomyService.Init(data)
	profileData = data.PlayerProfileData
end

local function economy(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.economy
end

local function add(section, field: string, amount: number): number
	amount = math.floor(tonumber(amount) or 0)
	if amount > 0 then
		section[field] += amount
	end
	return section[field]
end

local function trySpend(section, field: string, amount: number): (boolean, number)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or section[field] < amount then
		return false, section[field]
	end
	section[field] -= amount
	return true, section[field]
end

--API
function EconomyService.GetCalories(userId: number): number?
	local section = economy(userId)
	return section and section.calories
end

--API
function EconomyService.GetGems(userId: number): number?
	local section = economy(userId)
	return section and section.gems
end

--API
-- Adds calories (floored, negatives rejected). Returns the new balance,
-- or nil if the profile isn't loaded.
function EconomyService.AddCalories(userId: number, amount: number): number?
	local section = economy(userId)
	return section and add(section, "calories", amount)
end

--API
function EconomyService.AddGems(userId: number, amount: number): number?
	local section = economy(userId)
	return section and add(section, "gems", amount)
end

--API
function EconomyService.TrySpendCalories(userId: number, amount: number): (boolean, number?)
	local section = economy(userId)
	if not section then
		return false, nil
	end
	return trySpend(section, "calories", amount)
end

--API
function EconomyService.TrySpendGems(userId: number, amount: number): (boolean, number?)
	local section = economy(userId)
	if not section then
		return false, nil
	end
	return trySpend(section, "gems", amount)
end

--API
-- Rebirth wipe (Food Coma): calories reset to 0, gems untouched.
function EconomyService.ResetCalories(userId: number): boolean
	local section = economy(userId)
	if not section then
		return false
	end
	section.calories = 0
	return true
end

return EconomyService
