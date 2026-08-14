--[[
	LobbyQueue.Lifecycle -- internal leader-session validation, configuration,
	countdown launch snapshots, and launch completion/failure transitions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local Core = require(script.Parent.Core)
local Membership = require(script.Parent.Membership)

local Lifecycle = {}
local queueData

function Lifecycle.Init(data)
	queueData = data
end

local function allowedPlayerCount(maxPlayers: number): boolean
	for _, allowed in ipairs(queueData["match-config"].playerCounts) do
		if allowed == maxPlayers then
			return maxPlayers <= Core.Config().maxPlayers
		end
	end
	return false
end

function Lifecycle.ValidateLeaderSession(player: Player, sessionKey: any)
	local queue = Membership.GetQueueForPlayer(player)
	if queue == nil then
		return false, "not-admitted", nil
	end
	if queue["leader-user-id"] ~= player.UserId then
		return false, "leader-only", queue
	end
	if type(sessionKey) ~= "string" or sessionKey == "" or sessionKey ~= queue["session-key"] then
		return false, "stale-session", queue
	end
	return true, nil, queue
end

function Lifecycle.Configure(player: Player, sessionKey: any, difficulty: string, maxPlayers: number, now: number)
	local valid, reason, queue = Lifecycle.ValidateLeaderSession(player, sessionKey)
	if not valid then
		return { ok = false, reason = reason }
	end
	if queue.state ~= "configuring" and queue.state ~= "failed" then
		return { ok = false, reason = "already-starting" }
	end
	if queueData["match-config"].difficulties[difficulty] == nil or not allowedPlayerCount(maxPlayers) then
		return { ok = false, reason = "invalid-config" }
	end
	if maxPlayers < #queue.members then
		return { ok = false, reason = "below-current" }
	end

	queue.difficulty = difficulty
	queue["max-players"] = maxPlayers
	queue.state = "countdown"
	-- Solo starts get a short countdown, parties a long one (MatchConfig.queue).
	local countdownSeconds = Core.CountdownSeconds(#queue.members)
	queue["countdown-ends-at"] = now + countdownSeconds
	queue["session-key"] = ""
	queue["launch-members"] = {}
	Core.Refresh(queue, now)
	Log.Info(
		"LobbyQueue",
		`queue {queue.id} configured by {player.Name}: {difficulty}, {#queue.members}/{maxPlayers}, {countdownSeconds}s`
	)
	return { ok = true, queueId = queue.id, closePlayer = player }
end

function Lifecycle.Snapshot(queueId: number): { Player }
	local queue = Core.GetQueue(queueId)
	return if queue then table.clone(queue.members) else {}
end

function Lifecycle.Advance(now: number): { any }
	local launches = {}
	for _, queue in ipairs(queueData.queues) do
		if queue.state == "countdown" then
			Core.Refresh(queue, now)
			if queue["countdown-ends-at"] and now >= queue["countdown-ends-at"] then
				local snapshot = Lifecycle.Snapshot(queue.id)
				if #snapshot == 0 then
					Log.Warn("LobbyQueue", `queue {queue.id} countdown expired empty -- resetting`)
					Core.SetIdle(queue, true)
				else
					queue.state = "teleporting"
					queue["countdown-ends-at"] = nil
					queueData["next-launch-serial"] += 1
					queue["launch-token"] = queueData["next-launch-serial"]
					queue["launch-members"] = snapshot
					Core.Refresh(queue, now)
					table.insert(launches, {
						queueId = queue.id,
						launchToken = queue["launch-token"],
						leaderUserId = queue["leader-user-id"],
						players = snapshot,
						difficulty = queue.difficulty,
					})
				end
			end
		end
	end
	return launches
end

function Lifecycle.FailLaunch(queueId: number, launchToken: number)
	local queue = Core.GetQueue(queueId)
	if queue == nil or queue.state ~= "teleporting" or queue["launch-token"] ~= launchToken then
		return { reset = false, reason = "stale-launch" }
	end
	queue.difficulty = nil
	queue["max-players"] = Core.Config().maxPlayers
	queue["countdown-ends-at"] = nil
	queue["launch-members"] = {}
	if #queue.members == 0 then
		queue["leader-user-id"] = nil
		queue.state = "idle"
		queue["session-key"] = ""
		Core.Refresh(queue)
		return { reset = true }
	end
	if queue["leader-user-id"] == nil or not queue["member-set"][queue["leader-user-id"]] then
		queue["leader-user-id"] = queue.members[1].UserId
	end
	queue.state = "failed"
	Core.NextSession(queue)
	Core.Refresh(queue)
	local result = { reset = true }
	local effect = Core.OpenEffect(queue)
	result.openPlayer = effect.openPlayer
	result.openQueueId = effect.openQueueId
	return result
end

function Lifecycle.CompleteLaunch(queueId: number, launchToken: number): boolean
	local queue = Core.GetQueue(queueId)
	if queue == nil or queue.state ~= "teleporting" or queue["launch-token"] ~= launchToken then
		return false
	end
	Core.SetIdle(queue, true)
	return true
end

function Lifecycle.Reset(queueId: number): boolean
	local queue = Core.GetQueue(queueId)
	if queue == nil then
		Log.Once("LobbyQueue", `reset-missing-{queueId}`, `reset targeted missing queue {queueId}`)
		return false
	end
	Core.SetIdle(queue, true)
	return true
end

return Lifecycle
