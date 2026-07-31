--[[
	Profile section: progress — rebirths, lifetime stats and active boosts.
	  rebirths     — LEGACY. The rebirth system was removed 2026-07-26; the field
	                 stays (always 0) so no version bump/migration was needed.
	  activeBoosts — array of { id, stat, mult, expiresAt (unix) }; offline
	                 time counts down (standard for timed boosts)
	  lifetime*    — leaderboard fodder
	  foundKinds   — set of buried-find ids ever collected { [findId] = true }.
	                 Drives the FIRST-DISCOVERY moment (features/treasures.md):
	                 the first time you ever dig up each of the 9 kinds is called
	                 out, the 40th berry of the cake is not. STRING keys, so no
	                 `intKeySets` entry — and a NEW field with a default needs no
	                 version bump, reconcile fills it (P2).
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
		foundKinds = {},
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
		if type(section.foundKinds) ~= "table" then
			section.foundKinds = {}
		else
			-- Only `[string] = true` survives — a hand-edited or corrupted profile
			-- must not turn a discovery set into arbitrary data.
			local clean = {}
			for id, value in pairs(section.foundKinds) do
				if type(id) == "string" and value == true then
					clean[id] = true
				end
			end
			section.foundKinds = clean
		end
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
