--[[
	TimeRewardService
	Playtime-reward logic over the profile's `timeRewards` section (R2).
	Tracks time played DURING the current UTC day (accumulated across
	sessions) and which milestones were claimed. Both reset lazily at the day
	boundary (rolloverIfNewDay runs on every entry point, so a boundary
	crossed mid-session is handled at the next flush/claim).

	The live session anchor lives in TimeRewardsData.sessionStarts (runtime,
	never persisted — see TimeRewardsSection for why).

	R3: does NOT grant. Validates the claim, marks it, RETURNS the owed
	reward descriptor; RewardsSubs grants via RewardGrantSubs.
]]

local TimeRewardService = {}

local profileData, timeData

function TimeRewardService.Init(data)
	profileData = data.PlayerProfileData
	timeData = data.TimeRewardsData
end

local function section(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.timeRewards
end

local function rolloverIfNewDay(userId: number, time)
	local today = timeData.DayIndex()
	if time.day ~= today then
		time.day = today
		time.today = 0
		time.claimed = {}
		-- Re-anchor the live session too: without this, up to flushInterval
		-- seconds of yesterday's tail would be credited to the new day.
		if timeData.sessionStarts[userId] then
			timeData.sessionStarts[userId] = os.time()
		end
	end
end

--API
-- Anchor the session clock. Call on join, after the profile is loaded.
function TimeRewardService.BeginSession(userId: number)
	local time = section(userId)
	if not time then
		return
	end
	rolloverIfNewDay(userId, time)
	timeData.sessionStarts[userId] = os.time()
end

--API
-- Fold the current session's elapsed time into the persisted accumulator
-- and re-anchor (keeps persisted `today` fresh between auto-saves). Safe to
-- call repeatedly.
function TimeRewardService.FlushSession(userId: number)
	local time = section(userId)
	if not time then
		return
	end
	rolloverIfNewDay(userId, time)
	local start = timeData.sessionStarts[userId] or os.time()
	local delta = os.time() - start
	if delta > 0 then
		time.today += delta
	end
	timeData.sessionStarts[userId] = os.time()
end

--API
-- Call on leave: fold one last time, then drop the runtime anchor.
function TimeRewardService.EndSession(userId: number)
	TimeRewardService.FlushSession(userId)
	timeData.sessionStarts[userId] = nil
end

--API
-- Seconds played today (persisted accumulator + the live current session).
function TimeRewardService.ElapsedToday(userId: number): number
	local time = section(userId)
	if not time then
		return 0
	end
	rolloverIfNewDay(userId, time)
	local start = timeData.sessionStarts[userId] or os.time()
	return time.today + math.max(0, os.time() - start)
end

--API
-- Snapshot for the client sync.
function TimeRewardService.GetState(userId: number)
	local time = section(userId)
	if not time then
		return nil
	end
	rolloverIfNewDay(userId, time)
	return {
		secondsToday = TimeRewardService.ElapsedToday(userId),
		claimed = time.claimed,
		milestones = timeData.milestones,
		count = timeData.count,
	}
end

--API
-- Claim milestone `index`: valid if reached and not yet claimed today.
-- Marks claimed and RETURNS the reward descriptor (caller grants, R3), or
-- nil if not claimable.
function TimeRewardService.Claim(userId: number, index: number)
	local time = section(userId)
	if not time then
		return nil
	end
	local milestone = timeData.milestones[index]
	if not milestone then
		return nil
	end
	rolloverIfNewDay(userId, time)
	if time.claimed[index] then
		return nil
	end
	if TimeRewardService.ElapsedToday(userId) < milestone.seconds then
		return nil
	end
	time.claimed[index] = true
	return table.clone(milestone.reward)
end

return TimeRewardService
