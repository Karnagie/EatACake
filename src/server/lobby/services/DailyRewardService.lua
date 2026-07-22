--[[
	DailyRewardService
	Daily-login reward logic over the profile's `dailyRewards` section
	(R2: logic only). One claim per UTC day; the streak NEVER resets on a
	missed day and LOOPS back to Day 1 after the final day.

	R3: this service does NOT grant the reward. It validates + advances the
	streak and RETURNS the owed reward descriptor; RewardsSubs grants it via
	RewardGrantSubs.
]]

local DailyRewardService = {}

local profileData, dailyData

function DailyRewardService.Init(data)
	profileData = data.PlayerProfileData
	dailyData = data.DailyRewardsData
end

local function section(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.dailyRewards
end

--API
-- Is today's daily reward available (a new UTC day since the last claim)?
-- `~=` (not `<`) is deliberate: a future-dated lastClaimDay (cross-server
-- clock skew / corrupt data) self-heals on the next real day instead of
-- soft-locking the feature forever.
function DailyRewardService.IsClaimable(userId: number): boolean
	local daily = section(userId)
	if not daily then
		return false
	end
	return daily.lastClaimDay ~= dailyData.DayIndex()
end

--API
-- Snapshot for the client sync: current day position + claimability + the
-- reward table (day -> descriptor).
function DailyRewardService.GetState(userId: number)
	local daily = section(userId)
	if not daily then
		return nil
	end
	return {
		day = daily.day,
		claimable = DailyRewardService.IsClaimable(userId),
		days = dailyData.days,
		daysCount = dailyData.daysCount,
	}
end

--API
-- Claim today's reward: grants day `day`, stamps today, advances the loop.
-- RETURNS (reward descriptor, day) — the caller grants (R3) — or nil if
-- already claimed today / profile not loaded.
function DailyRewardService.Claim(userId: number)
	local daily = section(userId)
	if not daily or not DailyRewardService.IsClaimable(userId) then
		return nil
	end
	local day = daily.day
	local reward = dailyData.days[day]
	if not reward then
		-- days table shrank below the stored position — recover to day 1
		daily.day = 1
		return nil
	end
	daily.lastClaimDay = dailyData.DayIndex()
	daily.day = dailyData.NextDay(day)
	-- Clone: never hand the live config table to callers (a handler mutating
	-- its `granted` return must not corrupt DailyRewardsData for everyone).
	return table.clone(reward), day
end

return DailyRewardService
