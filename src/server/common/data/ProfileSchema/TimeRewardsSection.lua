--[[
	Profile section: timeRewards — playtime-today reward track state.

	day     -- UTC day index the accumulator belongs to (0 = never played)
	today   -- seconds played today from ENDED/flushed session parts
	claimed -- { [milestoneIndex: number] = true } claimed today (intKeySets!)

	Both `today` and `claimed` reset at the UTC day boundary (lazy rollover in
	TimeRewardService). The CURRENT session's start timestamp is deliberately
	NOT here: with schema-driven persistence everything in the profile is
	saved, and a persisted session anchor would corrupt `today` after a crash.
	It lives in TimeRewardsData.sessionStarts (runtime state, R1).
]]

return {
	key = "timeRewards",
	version = 1,
	defaults = {
		day = 0,
		today = 0,
		claimed = {},
	},
	intKeySets = { "claimed" },
	migrations = {},
	sanitize = function(section)
		local day = section.day
		if type(day) ~= "number" or day ~= day or day == math.huge or day < 0 then
			section.day = 0
		else
			section.day = math.floor(day)
		end
		local today = section.today
		if type(today) ~= "number" or today ~= today or today == math.huge or today < 0 then
			section.today = 0
		else
			section.today = math.floor(today)
		end
		-- Keep only { [n: number] = true } entries (runs AFTER intKeySets
		-- normalization, so stringified ints are already numbers again;
		-- anything else would crash table.sort in the payload builder).
		local claimed = {}
		if type(section.claimed) == "table" then
			for key, value in pairs(section.claimed) do
				if type(key) == "number" and key == key and value == true then
					claimed[key] = true
				end
			end
		end
		section.claimed = claimed
		return section
	end,
}
