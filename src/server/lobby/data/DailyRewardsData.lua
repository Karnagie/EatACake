--[[
	DailyRewardsData
	The "Daily Rewards" login track (R1): one claim per UTC day. The streak
	NEVER resets on a missed day and LOOPS back to Day 1 after the final day.

	Each day's reward is a REWARD DESCRIPTOR (the game-wide loot grammar,
	see RewardGrantSubs / ADR-0002):
	  { kind = "gems", amount = n }
	  -- per-game kinds (items, cases, exp...) are registered by their
	  -- features in RewardGrantSubs and can be used here freely.

	This table is the SINGLE tuning point per game — the client shows day N
	at the authored `Node_<N>` of DailyRewardsGui.
]]

local DailyRewardsData = {}

DailyRewardsData.daysCount = 7

-- day (1..daysCount) -> reward descriptor. Day 7 = guaranteed Epic+ pet
-- (GDD §12.2 — the streak's headline prize) and is deliberately untouched.
--
-- GEM AMOUNTS ARE A RATIO, NOT A FEEL. The old week paid 90 gems against a
-- cake worth ~196; the find table now pays ~496 per solo cake, so leaving the
-- old numbers in place would have quietly devalued the login track to a fifth
-- of its former weight. 250 across the week holds the original ratio (~0.5 of
-- a cake) — which is also half of one 500-gem boost, so a full week of logins
-- is a real step toward one rather than a rounding error.
--
-- The two BOOST days spend the track's variety budget on the boosts a new
-- player has no other way to try: bigger bites (day 2, while the tree is still
-- empty) and x2 calories (day 5, once there is a run worth doubling).
DailyRewardsData.days = {
	[1] = { kind = "gems", amount = 25 },
	[2] = { kind = "boost", boostId = "bite-15m" }, -- Extra Bite Size
	[3] = { kind = "gems", amount = 50 },
	[4] = { kind = "gems", amount = 75 },
	[5] = { kind = "boost", boostId = "boost-15m" }, -- x2 Calories
	[6] = { kind = "gems", amount = 100 },
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
