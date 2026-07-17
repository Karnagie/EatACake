--[[
	RewardsSubs — login/playtime reward domain (R4): Daily Rewards + Time
	Rewards. Wires ClaimDailyReward / ClaimTimeReward: validates via the
	services (R3 — they return what's owed), grants via RewardGrantSubs, then
	pushes fresh state with a `granted` descriptor for the claim toast.

	SendDaily/SendTime push initial state on join (called by
	PlayerLifecycleSubs). Node/claimed lists are sent as ARRAYS (RemoteEvents
	stringify a dict's integer keys); each node carries its own day/index.

	Owns the periodic playtime flush loop: persisted `today` stays fresh so
	ProfileStore's auto-save always snapshots a near-current value.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local RewardsSubs = {}

local DailyRewardService, TimeRewardService, PersistenceService
local uDaily, uTime

local function dailyPayload(userId: number, granted)
	local state = DailyRewardService.GetState(userId)
	if not state then
		return nil
	end
	local nodes = {}
	-- Clamp to 1..daysCount: extra entries beyond the loop length would
	-- desync the client's "tomorrow" math from the server's NextDay loop.
	for day = 1, state.daysCount do
		local reward = state.days[day]
		if reward then
			local node = table.clone(reward)
			node.day = day
			table.insert(nodes, node)
		end
	end
	return { day = state.day, claimable = state.claimable, nodes = nodes, granted = granted }
end

local function timePayload(userId: number, granted)
	local state = TimeRewardService.GetState(userId)
	if not state then
		return nil
	end
	local nodes = {}
	for index = 1, state.count do
		local milestone = state.milestones[index]
		if milestone then
			local node = table.clone(milestone.reward)
			node.index = index
			node.seconds = milestone.seconds
			table.insert(nodes, node)
		end
	end
	local claimed = {}
	for index in pairs(state.claimed) do
		table.insert(claimed, index)
	end
	table.sort(claimed)
	return { secondsToday = state.secondsToday, claimed = claimed, nodes = nodes, granted = granted }
end

--API
function RewardsSubs.SendDaily(player: Player)
	if uDaily == nil then
		Log.Warn("RewardsSubs", `SendDaily({player.Name}) before Start ran — push dropped`)
		return
	end
	local payload = dailyPayload(player.UserId)
	if payload then
		uDaily:FireClient(player, payload)
	else
		Log.Warn("RewardsSubs", `SendDaily({player.Name}): profile not loaded — push dropped`)
	end
end

--API
function RewardsSubs.SendTime(player: Player)
	if uTime == nil then
		Log.Warn("RewardsSubs", `SendTime({player.Name}) before Start ran — push dropped`)
		return
	end
	local payload = timePayload(player.UserId)
	if payload then
		uTime:FireClient(player, payload)
	else
		Log.Warn("RewardsSubs", `SendTime({player.Name}): profile not loaded — push dropped`)
	end
end

function RewardsSubs.Start(data, services)
	local dailyData = data.DailyRewardsData
	local timeData = data.TimeRewardsData
	DailyRewardService = services.DailyRewardService
	TimeRewardService = services.TimeRewardService
	PersistenceService = services.PersistenceService
	uDaily = Net.Update("DailyRewardUpdate")
	uTime = Net.Update("TimeRewardUpdate")

	Net.Remote("ClaimDailyReward").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		local state = DailyRewardService.GetState(userId)
		if not state then
			return -- profile not loaded
		end
		local upcoming = state.days[state.day]
		if upcoming and not RewardGrantSubs.HasHandler(upcoming.kind) then
			-- Mistuned data (kind with no registered handler): do NOT consume
			-- the claim — the player would lose the day for nothing.
			warn(`[RewardsSubs] days[{state.day}] kind '{tostring(upcoming.kind)}' has no grant handler`)
			return
		end
		local reward, day = DailyRewardService.Claim(userId)
		if not reward then
			RewardsSubs.SendDaily(player) -- resync (already claimed today)
			return
		end
		local granted = RewardGrantSubs.Grant(player, reward, "daily")
		if granted then
			granted.day = day
		end
		uDaily:FireClient(player, dailyPayload(userId, granted))
		PersistenceService.Save(userId)
	end)

	Net.Remote("ClaimTimeReward").OnServerEvent:Connect(function(player, index)
		if type(index) ~= "number" or index ~= index then
			return
		end
		index = math.floor(index)
		local userId = player.UserId
		local state = TimeRewardService.GetState(userId)
		if not state then
			return -- profile not loaded
		end
		local milestone = state.milestones[index]
		if milestone and not RewardGrantSubs.HasHandler(milestone.reward.kind) then
			Log.Warn("RewardsSubs", `milestones[{index}] kind '{tostring(milestone.reward.kind)}' has no grant handler`)
			return
		end
		local reward = TimeRewardService.Claim(userId, index)
		if not reward then
			RewardsSubs.SendTime(player) -- resync (not reached / already claimed)
			return
		end
		local granted = RewardGrantSubs.Grant(player, reward, "time")
		if granted then
			granted.index = index
		end
		uTime:FireClient(player, timePayload(userId, granted))
		PersistenceService.Save(userId)
	end)

	-- Playtime flush loop: fold live session time into the profile so
	-- ProfileStore's ~30s auto-save persists a near-current `today`.
	task.spawn(function()
		while true do
			task.wait(timeData.flushInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				TimeRewardService.FlushSession(player.UserId)
			end
		end
	end)

	-- Config validation — deferred so it runs AFTER every subscription's
	-- Start has registered its reward kinds (bootstrap runs without yields).
	task.defer(function()
		for day = 1, dailyData.daysCount do
			local reward = dailyData.days[day]
			if type(reward) ~= "table" then
				warn(`[RewardsSubs] DailyRewardsData.days[{day}] is missing (daysCount = {dailyData.daysCount})`)
			elseif not RewardGrantSubs.HasHandler(reward.kind) then
				warn(`[RewardsSubs] DailyRewardsData.days[{day}] kind '{tostring(reward.kind)}' has no grant handler`)
			end
		end
		for day in pairs(dailyData.days) do
			if type(day) ~= "number" or day < 1 or day > dailyData.daysCount then
				warn(`[RewardsSubs] DailyRewardsData.days[{tostring(day)}] is outside 1..{dailyData.daysCount} and unreachable`)
			end
		end
		for index = 1, timeData.count do
			local milestone = timeData.milestones[index]
			if type(milestone) ~= "table" or type(milestone.seconds) ~= "number" or type(milestone.reward) ~= "table" then
				warn(`[RewardsSubs] TimeRewardsData.milestones[{index}] is missing/invalid (count = {timeData.count})`)
			elseif not RewardGrantSubs.HasHandler(milestone.reward.kind) then
				warn(`[RewardsSubs] TimeRewardsData.milestones[{index}] kind '{tostring(milestone.reward.kind)}' has no grant handler`)
			end
		end
		for index in pairs(timeData.milestones) do
			if type(index) ~= "number" or index < 1 or index > timeData.count then
				warn(`[RewardsSubs] TimeRewardsData.milestones[{tostring(index)}] is outside 1..{timeData.count} and unreachable`)
			end
		end
	end)
end

return RewardsSubs
