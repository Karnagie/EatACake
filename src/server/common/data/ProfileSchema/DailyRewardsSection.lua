--[[
	Profile section: dailyRewards — daily-login reward track state.

	day          -- current position in the 1..daysCount loop (next day to claim)
	lastClaimDay -- UTC day index (whole days since epoch) of the last claim; 0 = never

	Design (inherited from Dices): the streak NEVER resets on a missed day and
	LOOPS back to Day 1 after the final day. Reward table + loop length live in
	data/DailyRewardsData.lua.
]]

return {
	key = "dailyRewards",
	version = 1,
	defaults = {
		day = 1,
		lastClaimDay = 0,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		local day = section.day
		-- NaN (day ~= day) and infinities reset too (non-finite numbers
		-- break DataStore JSON encoding). Upper bound self-heals in
		-- DailyRewardService.Claim (days[day] == nil -> reset to 1).
		if type(day) ~= "number" or day ~= day or day == math.huge or day < 1 then
			section.day = 1
		else
			section.day = math.floor(day)
		end
		local last = section.lastClaimDay
		if type(last) ~= "number" or last ~= last or last == math.huge or last < 0 then
			section.lastClaimDay = 0
		else
			section.lastClaimDay = math.floor(last)
		end
		return section
	end,
}
