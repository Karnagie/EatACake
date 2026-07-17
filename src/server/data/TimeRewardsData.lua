--[[
	TimeRewardsData
	The "Time Rewards" track (R1): playtime milestones claimed as a player
	accumulates time in-game DURING the current UTC day. Accrued time and the
	claimed set reset every 24h (lazy rollover in TimeRewardService).

	milestones[index] = { seconds = threshold, reward = descriptor }
	(reward descriptors: the game-wide loot grammar, ADR-0002; template ships
	gold-only — per-game kinds work once registered in RewardGrantSubs).

	Tuning intent inherited from Dices: put an early milestone INSIDE the
	first 5 minutes, not on the boundary. This table is the SINGLE tuning
	point per game.

	sessionStarts is RUNTIME state (R1: state lives in data modules): the
	os.time() anchor of each player's current session. Deliberately NOT in
	the profile — with schema-driven persistence everything in the profile is
	saved, and a saved anchor would corrupt `today` after a crash.
]]

local TimeRewardsData = {}

-- index -> { seconds, reward }. Playtime pacing per GDD §2 (D1 hooks).
TimeRewardsData.milestones = {
	[1] = { seconds = 60, reward = { kind = "gems", amount = 5 } }, -- 1:00
	[2] = { seconds = 240, reward = { kind = "gems", amount = 10 } }, -- 4:00
	[3] = { seconds = 600, reward = { kind = "boost", boostId = "golden-slice" } }, -- 10:00
	[4] = { seconds = 900, reward = { kind = "gems", amount = 20 } }, -- 15:00
	[5] = { seconds = 1800, reward = { kind = "egg", eggType = "cycle" } }, -- 30:00
	[6] = { seconds = 3600, reward = { kind = "egg", eggType = "lucky" } }, -- 60:00
}

TimeRewardsData.count = 6

-- Seconds between periodic session flushes (RewardsSubs loop) — keeps the
-- persisted accumulator fresh for ProfileStore's auto-save.
TimeRewardsData.flushInterval = 60

-- [userId: number] = os.time() anchor of the current session (runtime only).
TimeRewardsData.sessionStarts = {}

local SECONDS_PER_DAY = 86400

function TimeRewardsData.Init()
	table.clear(TimeRewardsData.sessionStarts)
end

--API
-- Current UTC day index (whole days since the epoch). A change means a new
-- day -> the playtime accumulator + claimed set reset.
function TimeRewardsData.DayIndex(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

return TimeRewardsData
