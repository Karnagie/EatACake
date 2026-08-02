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
local analytics -- optional; features/analytics.md

function Protocol.Init(data, service, analyticsSubs)
	queueData = data
	queueService = service
	analytics = analyticsSubs
end

-- Every queue beat funnels through here so the instrumentation lives in one
-- readable block instead of being sprinkled through the protocol branches.
-- Telemetry is ALWAYS optional and never on a gameplay path (R8).
local function beat(player: Player?, flowStep: string?, funnelStep: string?, eventKey: string?, a: any?, b: any?)
	if analytics == nil or player == nil then
		return
	end
	local ok, err = pcall(function()
		if flowStep then
			analytics.Flow(player, flowStep)
		end
		if funnelStep then
			analytics.Funnel(player, "queue", funnelStep)
		end
		if eventKey then
			analytics.Event(player, eventKey, 1, { a, b, "lobby" }, { tier = "normal" })
		end
	end)
	if not ok then
		Log.Once("LobbyQueueSubs", "queue-analytics", `queue analytics beat FAILED (telemetry only, queue unaffected): {err}`)
	end
end
Protocol.Beat = beat

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
	-- Stepping onto a pad IS "approached the game's starting area, and acted
	-- on it" — the first irreversible commitment in the initial player flow.
	if effect.admitted and effect.player then
		-- `enter` is the matchmaking funnel's first step, so Session opens a
		-- new ATTEMPT here automatically — a player who steps on three pads is
		-- three attempts, not one attempt with three step-1s.
		beat(
			effect.player,
			"pad-enter",
			"enter",
			"pad-enter",
			`pad-{tostring(effect.queueId)}`,
			if effect.leader then "leader" else "member"
		)
	end
	if effect.removed and effect.player then
		beat(effect.player, nil, nil, "pad-exit", `pad-{tostring(effect.queueId)}`, tostring(effect.state))
		if effect.state == "countdown" then
			-- Walked away from a match that was already counting down.
			beat(effect.player, nil, nil, "queue-abandon", "countdown", nil)
		end
	end
	if effect.closePlayer then
		Protocol.FireUpdate(effect.closePlayer, "close", nil)
	end
	if effect.openPlayer and effect.openQueueId then
		local payload = queueService.GetOpenPayload(effect.openQueueId)
		if payload then
			Protocol.FireUpdate(effect.openPlayer, "open", payload)
			-- The selector is on their screen. Anything that does not follow
			-- this is a player who saw the menu and did not use it.
			beat(effect.openPlayer, "selector-open", "selector", nil, nil, nil)
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

local function invalidRequest(player: Player, message: string, reason: string?)
	Log.Once("LobbyQueueSubs", `invalid-request-{player.UserId}`, `rejected malformed LobbyQueueRequest from {player.Name}`)
	Protocol.FireUpdate(player, "error", { message = message })
	-- Every refusal the player SEES is counted by its reason. A spike in any
	-- one row is a UI that is asking for something it cannot accept.
	beat(player, nil, nil, "queue-error", reason or "invalid", nil)
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
	beat(player, nil, nil, "queue-error", reason, nil)
end

function Protocol.OnQueueRequest(player: Player, action: any, sessionKey: any, difficulty: any, maxPlayers: any)
	local withinBudget, requestNow = consumeBudget(player)
	if not withinBudget then
		return
	end
	if type(action) ~= "string" then
		invalidRequest(player, "Invalid queue request.", "bad-action")
		return
	end
	if type(sessionKey) ~= "string" or #sessionKey == 0 then
		invalidRequest(player, "Invalid queue selection.", "bad-session")
		return
	end

	if action == "leave" then
		if difficulty ~= nil or maxPlayers ~= nil then
			invalidRequest(player, "Invalid leave request.", "bad-leave")
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
		invalidRequest(player, "Unknown queue action.", "bad-action")
		return
	end
	if type(difficulty) ~= "string" or queueData["match-config"].difficulties[difficulty] == nil then
		invalidRequest(player, "Choose a valid difficulty.", "bad-difficulty")
		return
	end
	if type(maxPlayers) ~= "number"
		or maxPlayers ~= maxPlayers
		or maxPlayers == math.huge
		or maxPlayers == -math.huge
		or maxPlayers % 1 ~= 0
		or not allowedPlayerCount(maxPlayers)
	then
		invalidRequest(player, "Choose a valid player count.", "bad-player-count")
		return
	end

	local result = queueService.Configure(player, sessionKey, difficulty, maxPlayers, requestNow)
	if result.ok then
		Protocol.EmitEffect(result)
		-- ACCEPTED. The countdown is now running with these settings, which is
		-- the last thing the player controls before the teleport.
		beat(player, "countdown", "countdown", "queue-configure", difficulty, tostring(maxPlayers))
		if analytics ~= nil then
			pcall(analytics.SetMatch, player, nil, difficulty)
		end
	elseif result.reason == "not-admitted" then
		Protocol.FireUpdate(player, "error", { message = "You are not in a queue." })
		beat(player, nil, nil, "queue-error", "not-admitted", nil)
	elseif result.reason == "leader-only" then
		Protocol.FireUpdate(player, "error", { message = "Only the queue leader can configure this match." })
		beat(player, nil, nil, "queue-error", "leader-only", nil)
	elseif result.reason == "stale-session" then
		sessionFailure(player, result.reason)
	elseif result.reason == "below-current" then
		Protocol.FireUpdate(player, "error", { message = "Maximum players cannot be below the current player count." })
		beat(player, nil, nil, "queue-error", "below-current", nil)
	elseif result.reason == "already-starting" then
		Protocol.FireUpdate(player, "busy", { message = "This queue is already starting." })
		beat(player, nil, nil, "queue-error", "already-starting", nil)
	else
		Protocol.FireUpdate(player, "error", { message = "Invalid queue configuration." })
		beat(player, nil, nil, "queue-error", tostring(result.reason), nil)
	end
end

return Protocol
