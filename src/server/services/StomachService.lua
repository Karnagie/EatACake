--[[
	StomachService — belly logic over profile section `stomach` (GDD §8).

	Ingest: bites add volume (fill, capped at capacity) and calories
	(stored, unbanked). Glutton mode: fill at capacity -> calorie gain x2 —
	overeating is a reward, not a punishment.
	Burn: gym converts stored -> banked amount (the SUBSCRIPTION credits it
	via EconomyService — R3) and empties the belly.

	Capacity/efficiency are STATS — callers pass them in from StatsService.
]]

local StomachService = {}

local profileData
local bodyCfg

function StomachService.Init(data)
	profileData = data.PlayerProfileData
	bodyCfg = data.CakeConfigData.body
end

local function stomach(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.stomach, profile
end

--API
-- Returns { fill, stored, glutton, gained } or nil (profile not loaded).
function StomachService.Ingest(userId: number, volume: number, baseCalories: number, caloriesMult: number, capacity: number)
	local section, profile = stomach(userId)
	if not section then
		return nil
	end
	-- Glutton = the mouthful that TOPS YOU OFF earns x2 (the last-bite reward).
	-- CakeSubs blocks bites once already full, so this only ever fires on the
	-- single bite that reaches capacity — never on sustained overeating.
	local glutton = (section.fill + volume) >= capacity
	local gained = baseCalories * caloriesMult * (if glutton then bodyCfg.stomach.gluttonCaloriesMult else 1)
	section.stored += gained
	section.fill = math.min(capacity, section.fill + volume)
	if section.fill > profile.progress.biggestBelly then
		profile.progress.biggestBelly = section.fill
	end
	return {
		fill = section.fill,
		stored = section.stored,
		glutton = glutton,
		gained = gained,
	}
end

--API
function StomachService.GetState(userId: number)
	local section = stomach(userId)
	if not section then
		return nil
	end
	return { fill = section.fill, stored = section.stored }
end

--API
-- Fullness 0..1 against the passed capacity (drives morph + speed penalty).
function StomachService.Fullness(userId: number, capacity: number): number
	local section = stomach(userId)
	if not section or capacity <= 0 then
		return 0
	end
	return math.clamp(section.fill / capacity, 0, 1)
end

--API
-- Belly at (or over) capacity — the caller (CakeSubs) refuses further bites
-- while true (GDD §8: full = can't eat, gym is the release valve). A missing
-- profile reads as NOT full so a joining player is never wrongly frozen out.
function StomachService.IsFull(userId: number, capacity: number): boolean
	local section = stomach(userId)
	if not section or capacity <= 0 then
		return false
	end
	return section.fill >= capacity
end

--API
-- Converts the whole belly into bankable calories and empties it.
-- Returns the banked amount (0 if nothing stored), or nil if no profile.
-- The caller credits EconomyService.AddCalories and fires the updates.
function StomachService.Burn(userId: number, efficiency: number, bonusMult: number): number?
	local section = stomach(userId)
	if not section then
		return nil
	end
	local banked = math.floor(section.stored * efficiency * bonusMult)
	section.stored = 0
	section.fill = 0
	return banked
end

return StomachService
