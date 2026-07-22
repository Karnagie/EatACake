--[[
	QuestService — daily quest logic over profile section `quests`
	(GDD §12.2). Progress = today's delta of lifetime stats in the
	`progress` section against a baseline anchored at the day's first
	read — no per-event hooks needed anywhere in the codebase.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local QuestService = {}

local profileData
local questsData

function QuestService.Init(data)
	profileData = data.PlayerProfileData
	questsData = data.QuestsData
end

-- Returns (questsSection, progressSection) with the day rolled over if due.
local function sections(userId: number)
	local profile = profileData.profiles[userId]
	if not profile then
		return nil, nil
	end
	local quests = profile.quests
	local today = questsData.DayIndex()
	if quests.dayIndex ~= today then
		quests.dayIndex = today
		quests.claimed = {}
		quests.baseline = {}
		for _, def in ipairs(questsData.quests) do
			quests.baseline[def.statKey] = profile.progress[def.statKey] or 0
		end
		Log.Info("QuestService", `daily quests re-anchored for {userId} (day {today})`)
	end
	return quests, profile.progress
end

--API
-- Today's quest rows: { { id, statKey, target, progress, claimed } }.
function QuestService.Summary(userId: number)
	local quests, progress = sections(userId)
	if not quests then
		return nil
	end
	local rows = {}
	for _, def in ipairs(questsData.quests) do
		local baseline = quests.baseline[def.statKey] or 0
		local value = math.max(0, (progress[def.statKey] or 0) - baseline)
		table.insert(rows, {
			id = def.id,
			target = def.target,
			progress = math.min(value, def.target),
			claimed = quests.claimed[def.id] == true,
			reward = def.reward,
		})
	end
	return rows
end

--API
-- Validates and consumes a claim. Returns the reward descriptor to grant,
-- or nil + reason. The SUBSCRIPTION grants it (and must check
-- RewardGrantSubs.HasHandler BEFORE calling this — never eat a claim).
function QuestService.TryClaim(userId: number, questId: string)
	local quests, progress = sections(userId)
	if not quests then
		return nil, "no-profile"
	end
	for _, def in ipairs(questsData.quests) do
		if def.id == questId then
			if quests.claimed[def.id] then
				return nil, "already-claimed"
			end
			local baseline = quests.baseline[def.statKey] or 0
			local value = (progress[def.statKey] or 0) - baseline
			if value < def.target then
				return nil, "not-done"
			end
			quests.claimed[def.id] = true
			return def.reward, nil
		end
	end
	return nil, "unknown-quest"
end

return QuestService
