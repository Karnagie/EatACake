--[[
	Profile section: social — one-time group-join reward flag.
]]

return {
	key = "social",
	version = 1,
	defaults = {
		groupRewardClaimed = false,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		section.groupRewardClaimed = section.groupRewardClaimed == true
		return section
	end,
}
