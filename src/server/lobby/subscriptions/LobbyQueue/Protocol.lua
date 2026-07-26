--[[
	LobbyQueue.Protocol -- internal queue remote validation and update projection.
	It creates no subscriptions; LobbyQueueSubs connects OnServerEvent (R4).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Protocol = {}
local queueData
local queueService

function Protocol.Init(data, service)
	queueData = data
	queueService = service
end

function Protocol.FireUpdate(player: Player, kind: string, payload: any?)
	if queueData == nil or queueData["update-remote"] == nil then
		Log.Once("LobbyQueueSubs", "update-remote-missing", `LobbyQueueUpdate '{kind}' dropped: remote unresolved`)
		return
	end
	if player.Parent ~= Players then
		Log.Once("LobbyQueueSubs", `update-dropped-{player.UserId}-{kind}`, `LobbyQueueUpdate '{kind}' dropped for {player.Name}: player left`)
		return
	end
	local ok, err = pcall(function()
		if payload == nil then
			queueData["update-remote"]:FireClient(player, kind)
		else
			queueData["update-remote"]:FireClient(player, kind, payload)
		end
	end)
	if not ok then
		Log.Warn("LobbyQueueSubs", `LobbyQueueUpdate '{kind}' failed for {player.Name}: {err}`)
	end
end

function Protocol.EmitEffect(effect)
	if effect == nil then
		return
	end
	if effect.closePlayer then
		Protocol.FireUpdate(effect.closePlayer, "close", nil)
	end
	if effect.openPlayer and effect.openQueueId then
		local payload = queueService.GetOpenPayload(effect.openQueueId)
		if payload then
			Protocol.FireUpdate(effect.openPlayer, "open", payload)
		else
			Log.Warn("LobbyQueueSubs", `selector open dropped for {effect.openPlayer.Name}: queue {effect.openQueueId} has no session payload`)
		end
	end
end

function Protocol.EmitEffects(effects)
	for _, effect in ipairs(effects) do
		Protocol.EmitEffect(effect)
	end
end

local function allowedPlayerCount(maxPlayers: number): boolean
	if maxPlayers > queueData["queue-config"].maxPlayers then
		return false
	end
	for _, allowed in ipairs(queueData["match-config"].playerCounts) do
		if allowed == maxPlayers then
			return true
		end
	end
	return false
end

local function invalidRequest(player: Player, message: string)
	Log.Once("LobbyQueueSubs", `invalid-request-{player.UserId}`, `rejected malformed LobbyQueueRequest from {player.Name}`)
	Protocol.FireUpdate(player, "error", { message = message })
end

local function consumeBudget(player: Player): (boolean, number)
	local now = os.clock()
	local lastAt = queueData["request-last-at-by-user-id"][player.UserId]
	if lastAt and now - lastAt < queueData["queue-config"].requestCooldownSeconds then
		Log.Once("LobbyQueueSubs", `request-throttled-{player.UserId}`, `LobbyQueueRequest spam throttled for {player.Name}`)
		return false, now
	end
	queueData["request-last-at-by-user-id"][player.UserId] = now
	return true, now
end

local function sessionFailure(player: Player, reason: string)
	if reason == "not-admitted" then
		Protocol.FireUpdate(player, "error", { message = "You are not in a queue." })
	elseif reason == "leader-only" then
		Protocol.FireUpdate(player, "error", { message = "Only the queue leader can use this selection." })
	else
		Protocol.FireUpdate(player, "error", { message = "This queue selection expired. Step off and re-enter." })
	end
end

function Protocol.OnQueueRequest(player: Player, action: any, sessionKey: any, difficulty: any, maxPlayers: any)
	local withinBudget, requestNow = consumeBudget(player)
	if not withinBudget then
		return
	end
	if type(action) ~= "string" then
		invalidRequest(player, "Invalid queue request.")
		return
	end
	if type(sessionKey) ~= "string" or #sessionKey == 0 then
		invalidRequest(player, "Invalid queue selection.")
		return
	end

	if action == "leave" then
		if difficulty ~= nil or maxPlayers ~= nil then
			invalidRequest(player, "Invalid leave request.")
			return
		end
		local valid, reason, queue = queueService.ValidateLeaderSession(player, sessionKey)
		if not valid then
			sessionFailure(player, reason)
			return
		end
		if queue.state == "teleporting" then
			Protocol.FireUpdate(player, "busy", { message = "This queue is teleporting." })
			return
		end
		Protocol.EmitEffect(queueService.Remove(player, true))
		return
	end

	if action ~= "configure" then
		invalidRequest(player, "Unknown queue action.")
		return
	end
	if type(difficulty) ~= "string" or queueData["match-config"].difficulties[difficulty] == nil then
		invalidRequest(player, "Choose a valid difficulty.")
		return
	end
	if type(maxPlayers) ~= "number"
		or maxPlayers ~= maxPlayers
		or maxPlayers == math.huge
		or maxPlayers == -math.huge
		or maxPlayers % 1 ~= 0
		or not allowedPlayerCount(maxPlayers)
	then
		invalidRequest(player, "Choose a valid player count.")
		return
	end

	local result = queueService.Configure(player, sessionKey, difficulty, maxPlayers, requestNow)
	if result.ok then
		Protocol.EmitEffect(result)
	elseif result.reason == "not-admitted" then
		Protocol.FireUpdate(player, "error", { message = "You are not in a queue." })
	elseif result.reason == "leader-only" then
		Protocol.FireUpdate(player, "error", { message = "Only the queue leader can configure this match." })
	elseif result.reason == "stale-session" then
		sessionFailure(player, result.reason)
	elseif result.reason == "below-current" then
		Protocol.FireUpdate(player, "error", { message = "Maximum players cannot be below the current player count." })
	elseif result.reason == "already-starting" then
		Protocol.FireUpdate(player, "busy", { message = "This queue is already starting." })
	else
		Protocol.FireUpdate(player, "error", { message = "Invalid queue configuration." })
	end
end

return Protocol
