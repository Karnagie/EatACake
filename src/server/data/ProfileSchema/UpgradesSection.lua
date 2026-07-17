--[[
	Profile section: upgrades — level per upgrade id (GDD §10).
	Ids and caps live in Shared/config/UpgradeConfig; UpgradeService clamps
	on purchase, sanitize only repairs corrupt values.
]]

return {
	key = "upgrades",
	version = 1,
	defaults = {
		levels = {
			capacity = 0,
			biteRadius = 0,
			biteDepth = 0,
			eatSpeed = 0,
			gymEff = 0,
			runSpeed = 0,
		},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		for id, level in pairs(section.levels) do
			if type(level) ~= "number" or level ~= level or level == math.huge or level < 0 then
				section.levels[id] = 0
			else
				section.levels[id] = math.floor(level)
			end
		end
		return section
	end,
}
