--[[
	Profile section: quests — daily quest anchors (GDD §12.2).
	  dayIndex — UTC day the baseline belongs to (rollover re-anchors)
	  baseline — lifetime-stat snapshot at the day's first login;
	             progress = current lifetime stat - baseline[statKey]
	  claimed  — { [questId: string] = true } for today
]]

return {
	key = "quests",
	version = 1,
	defaults = {
		dayIndex = 0,
		baseline = {},
		claimed = {},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		if type(section.baseline) ~= "table" then
			section.baseline = {}
		end
		if type(section.claimed) ~= "table" then
			section.claimed = {}
		end
		if type(section.dayIndex) ~= "number" or section.dayIndex ~= section.dayIndex then
			section.dayIndex = 0
		end
		return section
	end,
}
