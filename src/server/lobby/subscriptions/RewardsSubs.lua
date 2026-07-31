--[[
	RewardsSubs — login reward domain (R4): Daily Rewards. Wires
	ClaimDailyReward: validates via the service (R3 — it returns what's owed),
	grants via RewardGrantSubs, then pushes fresh state with a `granted`
	descriptor for the claim toast.

	SendDaily pushes initial state on join (called by PlayerLifecycleSubs).
	The node list is sent as an ARRAY (RemoteEvents stringify a dict's integer
	keys); each node carries its own day.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
-- Resolved from the subscriptions registry in Start (RewardGrantSubs lives in
-- the COMMON partition; a static script.Parent require breaks once this sub
-- moves to the lobby partition — see the lobby/game split).
local RewardGrantSubs

local RewardsSubs = {}

local DailyRewardService, PersistenceService
local uDaily
local boostDefs -- TreasureConfig.boosts (see grantable)

local SCOPE = "RewardsSubs"

-- Can this descriptor actually be paid out? `HasHandler` alone is not enough for
-- a `boost`: StatsService.GrantBoost answers an unknown boostId with `false`, so
-- a typo'd id passes the handler check, CONSUMES the day, and grants nothing.
-- DailyRewardsData shipped `boostId = "golden-slice"` — a FIND id — once already.
local function grantable(reward): (boolean, string?)
	if type(reward) ~= "table" then
		return false, "not a table"
	end
	if not RewardGrantSubs.HasHandler(reward.kind) then
		return false, `kind '{tostring(reward.kind)}' has no grant handler`
	end
	if reward.kind == "boost" and boostDefs ~= nil and boostDefs[tostring(reward.boostId)] == nil then
		return false, `boostId '{tostring(reward.boostId)}' is not a TreasureConfig.boosts def`
	end
	return true
end

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
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function RewardsSubs.PushInitialState(player: Player)
	RewardsSubs.SendDaily(player)
end

function RewardsSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	local dailyData = data.DailyRewardsData
	DailyRewardService = services.DailyRewardService
	PersistenceService = services.PersistenceService
	boostDefs = data.CakeConfigData and data.CakeConfigData.treasures and data.CakeConfigData.treasures.boosts
	if boostDefs == nil then
		Log.Warn(SCOPE, "TreasureConfig.boosts missing — a boost day with a typo'd id will consume the claim and grant nothing")
	end
	uDaily = Net.Update("DailyRewardUpdate")

	Net.Remote("ClaimDailyReward").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		local state = DailyRewardService.GetState(userId)
		if not state then
			return -- profile not loaded
		end
		local upcoming = state.days[state.day]
		if upcoming ~= nil then
			local ok, why = grantable(upcoming)
			if not ok then
				-- Mistuned data: do NOT consume the claim — the player would lose
				-- the day for nothing.
				Log.Warn(SCOPE, `days[{state.day}] cannot be granted ({tostring(why)}) — claim REFUSED rather than consumed`)
				return
			end
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

	-- Config validation — deferred so it runs AFTER every subscription's
	-- Start has registered its reward kinds (bootstrap runs without yields).
	task.defer(function()
		for day = 1, dailyData.daysCount do
			local reward = dailyData.days[day]
			if type(reward) ~= "table" then
				Log.Warn(SCOPE, `DailyRewardsData.days[{day}] is missing (daysCount = {dailyData.daysCount})`)
			else
				local ok, why = grantable(reward)
				if not ok then
					Log.Warn(SCOPE, `DailyRewardsData.days[{day}] is not grantable: {tostring(why)} — that day would refuse to claim`)
				end
			end
		end
		for day in pairs(dailyData.days) do
			if type(day) ~= "number" or day < 1 or day > dailyData.daysCount then
				Log.Warn(SCOPE, `DailyRewardsData.days[{tostring(day)}] is outside 1..{dailyData.daysCount} and unreachable`)
			end
		end
	end)
end

return RewardsSubs
