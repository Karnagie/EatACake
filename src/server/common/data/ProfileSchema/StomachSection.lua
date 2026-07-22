--[[
	Profile section: stomach — belly state that survives a rejoin (GDD §8).
	  fill   — studs^3 of cake currently in the belly (0..capacity stat)
	  stored — unbanked calories waiting for a gym burn
]]

local function sanitizeNumber(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 0
	end
	return value
end

return {
	key = "stomach",
	version = 1,
	defaults = {
		fill = 0,
		stored = 0,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		section.fill = sanitizeNumber(section.fill)
		section.stored = sanitizeNumber(section.stored)
		return section
	end,
}
