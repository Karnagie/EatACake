--[[
	Profile section: economy — the two currencies (GDD §10):
	  calories — soft, earned in the gym, spent on upgrades (never reset)
	  gems     — hard, persistent, from finds / rewards / Robux

	v2 migration: the template's single `gold` became `gems` (hard currency).
]]

local function sanitizeNumber(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 0
	end
	return math.floor(value)
end

return {
	key = "economy",
	version = 2,
	defaults = {
		calories = 0,
		gems = 0,
	},
	intKeySets = {},
	migrations = {
		[1] = function(section)
			section.gems = sanitizeNumber(section.gold)
			section.gold = nil
			return section
		end,
	},
	sanitize = function(section)
		section.calories = sanitizeNumber(section.calories)
		section.gems = sanitizeNumber(section.gems)
		return section
	end,
}
