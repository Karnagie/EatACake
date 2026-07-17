--[[
	DailyRewardsData
	The "Daily Rewards" login track (R1): one claim per UTC day. The streak
	NEVER resets on a missed day and LOOPS back to Day 1 after the final day.

	Each day's reward is a REWARD DESCRIPTOR (the game-wide loot grammar,
	see RewardGrantSubs / ADR-0002):
	  { kind = "gold", amount = n }
	  -- per-game kinds (items, cases, exp...) are registered by their
	  -- features in RewardGrantSubs and can be used here freely.

	This table is the SINGLE tuning point per game — the client shows day N
	at the authored `Node_<N>` of DailyRewardsGui.
]]

local DailyRewardsData = {}

DailyRewardsData.daysCount = 7

-- day (1..daysCount) -> reward descriptor. Day 7 = guaranteed Epic+ pet
-- (GDD §12.2 — the streak's headline prize).
DailyRewardsData.days = {
	[1] = { kind = "gems", amount = 10 },
	[2] = { kind = "gems", amount = 15 },
	[3] = { kind = "boost", boostId = "golden-slice" },
	[4] = { kind = "gems", amount = 25 },
	[5] = { kind = "egg", eggType = "cycle" },
	[6] = { kind = "gems", amount = 40 },
	[7] = { kind = "egg", eggType = "epic7" },
}

local SECONDS_PER_DAY = 86400

--API
-- The current UTC day index (whole days since the epoch). One claim allowed
-- per distinct day index.
function DailyRewardsData.DayIndex(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

--API
-- The next day in the 1..daysCount loop.
function DailyRewardsData.NextDay(day: number): number
	return (day % DailyRewardsData.daysCount) + 1
end

return DailyRewardsData
