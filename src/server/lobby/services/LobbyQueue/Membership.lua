--[[
	LobbyQueue.Membership -- internal admission, removal, leader/session rotation,
	and occupancy reconciliation for LobbyQueueService. State stays in
	LobbyQueueData; shared transitions live in Core.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local Core = require(script.Parent.Core)

local Membership = {}
local queueData

function Membership.Init(data)
	queueData = data
end

function Membership.GetQueueForPlayer(player: Player)
	local queueId = queueData["player-queue-by-user-id"][player.UserId]
	return queueId and Core.GetQueue(queueId) or nil
end

function Membership.GetOpenPayload(queueId: number): { [string]: any }?
	local queue = Core.GetQueue(queueId)
	if queue == nil or queue["session-key"] == "" then
		return nil
	end
	return {
		sessionKey = queue["session-key"],
		currentPlayers = #queue.members,
		maxPlayers = queue["max-players"],
	}
end

function Membership.GetSelectorOwners(): { Player }
	local owners = {}
	for _, queue in ipairs(queueData.queues) do
		if queue.state == "configuring" or queue.state == "failed" then
			local leader = Core.LeaderPlayer(queue)
			if leader then
				table.insert(owners, leader)
			end
		end
	end
	return owners
end

function Membership.Admit(queueId: number, player: Player)
	local queue = Core.GetQueue(queueId)
	if queue == nil then
		Log.Once("LobbyQueue", `admit-missing-{queueId}`, `admission targeted missing queue {queueId}`)
		return { admitted = false, reason = "missing-queue" }
	end
	if queue["blocked-until-exit"][player.UserId] then
		return { admitted = false, reason = "blocked-until-exit" }
	end
	if player:GetAttribute("Teleporting") == true then
		return Core.BusyResult(queue, player, "teleporting")
	end

	local currentQueueId = queueData["player-queue-by-user-id"][player.UserId]
	if currentQueueId == queueId then
		return { admitted = false, reason = "already-admitted" }
	elseif currentQueueId ~= nil then
		return Core.BusyResult(queue, player, "other-queue")
	end
	if queue.state == "teleporting" then
		return Core.BusyResult(queue, player, "teleporting")
	end
	if #queue.members >= queue["max-players"] then
		return Core.BusyResult(queue, player, "full")
	end

	table.insert(queue.members, player)
	queue["member-set"][player.UserId] = true
	queueData["player-queue-by-user-id"][player.UserId] = queueId
	queue["exit-since"][player.UserId] = nil
	if queue["leader-user-id"] == nil then
		queue["leader-user-id"] = player.UserId
		queue.difficulty = nil
		queue["max-players"] = Core.Config().maxPlayers
		queue.state = "configuring"
		queue["countdown-ends-at"] = nil
		Core.NextSession(queue)
	end

	Core.Refresh(queue)
	Log.Info("LobbyQueue", `{player.Name} admitted to queue {queueId} ({#queue.members}/{queue["max-players"]})`)
	-- `player`/`leader` are carried on the effect purely so the subscription
	-- layer can instrument the admission (docs/features/analytics.md). The
	-- service stays free of the analytics dependency (R2/R3).
	local result = {
		admitted = true,
		queueId = queueId,
		player = player,
		leader = queue["leader-user-id"] == player.UserId,
	}
	if queue.state == "configuring" or queue.state == "failed" then
		local effect = Core.OpenEffect(queue)
		result.openPlayer = effect.openPlayer
		result.openQueueId = effect.openQueueId
	end
	return result
end

function Membership.Remove(player: Player, blockUntilExit: boolean?)
	local queueId = queueData["player-queue-by-user-id"][player.UserId]
	local queue = queueId and Core.GetQueue(queueId) or nil
	if queue == nil then
		if queueId ~= nil then
			Log.Warn("LobbyQueue", `{player.Name} mapped to missing queue {queueId}; stale membership cleared`)
			queueData["player-queue-by-user-id"][player.UserId] = nil
		end
		return { removed = false, reason = "not-admitted" }
	end

	local wasLeader = queue["leader-user-id"] == player.UserId
	for index, member in ipairs(queue.members) do
		if member.UserId == player.UserId then
			table.remove(queue.members, index)
			break
		end
	end
	queue["member-set"][player.UserId] = nil
	queueData["player-queue-by-user-id"][player.UserId] = nil
	queue["exit-since"][player.UserId] = nil
	queue["blocked-until-exit"][player.UserId] = if blockUntilExit then true else nil

	local result = {
		removed = true,
		queueId = queue.id,
		player = player,
		leader = wasLeader,
		-- "left while the countdown was running" is a different story from
		-- "stepped off an idle pad"; the subscription layer logs both.
		state = queue.state,
		closePlayer = if wasLeader then player else nil,
	}
	if queue.state == "teleporting" then
		Core.Refresh(queue)
		return result
	end
	if wasLeader then
		queue["leader-user-id"] = nil
		queue.difficulty = nil
		queue["max-players"] = Core.Config().maxPlayers
		queue["countdown-ends-at"] = nil
		queue["launch-members"] = {}
		if #queue.members == 0 then
			queue.state = "idle"
			queue["session-key"] = ""
		else
			queue["leader-user-id"] = queue.members[1].UserId
			queue.state = "configuring"
			Core.NextSession(queue)
			local effect = Core.OpenEffect(queue)
			result.openPlayer = effect.openPlayer
			result.openQueueId = effect.openQueueId
		end
	elseif #queue.members == 0 then
		queue["leader-user-id"] = nil
		queue.difficulty = nil
		queue["max-players"] = Core.Config().maxPlayers
		queue.state = "idle"
		queue["countdown-ends-at"] = nil
		queue["session-key"] = ""
	elseif queue.state == "configuring" or queue.state == "failed" then
		local effect = Core.OpenEffect(queue)
		result.openPlayer = effect.openPlayer
		result.openQueueId = effect.openQueueId
	end

	Core.Refresh(queue)
	Log.Info("LobbyQueue", `{player.Name} removed from queue {queue.id} ({#queue.members}/{queue["max-players"]})`)
	return result
end

function Membership.ForgetPlayer(player: Player)
	local result = Membership.Remove(player, false)
	for _, queue in ipairs(queueData.queues) do
		queue["exit-since"][player.UserId] = nil
		queue["blocked-until-exit"][player.UserId] = nil
	end
	return result
end

function Membership.Reconcile(queueId: number, occupants: { [number]: Player }, now: number): { any }
	local queue = Core.GetQueue(queueId)
	if queue == nil then
		Log.Once("LobbyQueue", `reconcile-missing-{queueId}`, `occupancy scan targeted missing queue {queueId}`)
		return {}
	end
	for userId in pairs(queue["blocked-until-exit"]) do
		if occupants[userId] == nil then
			queue["blocked-until-exit"][userId] = nil
		end
	end

	local effects = {}
	for _, player in ipairs(table.clone(queue.members)) do
		if occupants[player.UserId] then
			queue["exit-since"][player.UserId] = nil
		else
			local missingSince = queue["exit-since"][player.UserId]
			if missingSince == nil then
				queue["exit-since"][player.UserId] = now
			elseif now - missingSince >= Core.Config().exitGraceSeconds then
				table.insert(effects, Membership.Remove(player, false))
			end
		end
	end

	local occupantPlayers = {}
	for _, player in pairs(occupants) do
		table.insert(occupantPlayers, player)
	end
	table.sort(occupantPlayers, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, player in ipairs(occupantPlayers) do
		if not queue["member-set"][player.UserId] then
			table.insert(effects, Membership.Admit(queueId, player))
		end
	end
	return effects
end

return Membership
