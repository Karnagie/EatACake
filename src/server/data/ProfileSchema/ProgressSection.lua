--[[
	Profile section: progress — rebirths, lifetime stats and active boosts.
	  rebirths     — Food Coma count; +25% calories each (UpgradeConfig.rebirth)
	  activeBoosts — array of { id, stat, mult, expiresAt (unix) }; offline
	                 time counts down (standard for timed boosts)
	  lifetime*    — leaderboard / quest fodder
]]

local function sanitizeNumber(value: any): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value < 0 then
		return 0
	end
	return value
end

return {
	key = "progress",
	version = 1,
	defaults = {
		rebirths = 0,
		activeBoosts = {},
		lifetimeCalories = 0,
		cakesEaten = 0,
		findsCollected = 0,
		biggestBelly = 0,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		section.rebirths = math.floor(sanitizeNumber(section.rebirths))
		section.lifetimeCalories = sanitizeNumber(section.lifetimeCalories)
		section.cakesEaten = math.floor(sanitizeNumber(section.cakesEaten))
		section.findsCollected = math.floor(sanitizeNumber(section.findsCollected))
		section.biggestBelly = sanitizeNumber(section.biggestBelly)
		if type(section.activeBoosts) ~= "table" then
			section.activeBoosts = {}
		end
		local now = os.time()
		local alive = {}
		for _, boost in ipairs(section.activeBoosts) do
			if type(boost) == "table" and type(boost.expiresAt) == "number" and boost.expiresAt > now then
				table.insert(alive, boost)
			end
		end
		section.activeBoosts = alive
		return section
	end,
}
