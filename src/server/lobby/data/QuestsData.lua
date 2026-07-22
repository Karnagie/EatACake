--[[
	QuestsData — daily quest catalogue (R1, GDD §12.2): 3 quests per UTC
	day, progress measured as TODAY'S DELTA of a lifetime stat (baseline
	anchored at the first login of the day — zero extra hooks anywhere).

	quests[k] = { id, statKey (progress section field), target, reward }
]]

local QuestsData = {}

QuestsData.quests = {
	{ id = "eat-cakes", statKey = "cakesEaten", target = 2, reward = { kind = "gems", amount = 10 } },
	{ id = "burn-calories", statKey = "lifetimeCalories", target = 10000, reward = { kind = "gems", amount = 15 } },
	{ id = "collect-finds", statKey = "findsCollected", target = 5, reward = { kind = "egg", eggType = "cycle" } },
}

local SECONDS_PER_DAY = 86400

--API
function QuestsData.DayIndex(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

return QuestsData
