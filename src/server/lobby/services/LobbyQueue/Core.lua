--[[
	LobbyQueue.Core -- internal queue setup, shared state transitions, and world
	label projection for LobbyQueueService. Logic only; state stays in
	LobbyQueueData. This helper is not bootstrap-registered as a separate service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Core = {}
local queueData

function Core.Init(data)
	queueData = data
end

function Core.Config()
	return queueData and queueData["queue-config"]
end

--API
-- Countdown length for a party of `memberCount`, per MatchConfig.queue. A solo
-- player is only waiting on themselves; 2+ needs time for everyone to settle.
function Core.CountdownSeconds(memberCount: number): number
	local config = Core.Config()
	return if memberCount <= 1 then config.countdownSecondsSolo else config.countdownSeconds
end

function Core.GetQueue(queueId: number)
	return queueData and queueData["queue-by-id"][queueId]
end

function Core.LeaderPlayer(queue)
	if queue["leader-user-id"] == nil then
		return nil
	end
	for _, player in ipairs(queue.members) do
		if player.UserId == queue["leader-user-id"] then
			return player
		end
	end
	return nil
end

function Core.NextSession(queue)
	queueData["next-session-serial"] += 1
	queue["session-key"] = `{queue.id}:{queueData["next-session-serial"]}`
end

local function setLabelText(queue, label: Instance?, kind: string, value: string)
	if label == nil then
		return
	end
	local ok, err = pcall(function()
		(label :: any).Text = value
	end)
	if not ok then
		Log.Once("LobbyQueue", `queue-label-write-{queue.id}-{kind}`, `queue {queue.id} {kind}.Text update failed -- {err}`)
	end
end

function Core.Refresh(queue, now: number?)
	local config = Core.Config()
	if config == nil then
		Log.Once("LobbyQueue", "refresh-no-config", "queue visual refresh skipped: queue config missing")
		return
	end
	setLabelText(queue, queue["player-count-label"], "PlayerCount", `{#queue.members}/{queue["max-players"]}`)
	local status = config.statuses.idle
	if queue.state == "configuring" then
		status = config.statuses.configuring
	elseif queue.state == "failed" then
		status = config.statuses.failed
	elseif queue.state == "teleporting" then
		status = config.statuses.teleporting
	elseif queue.state == "countdown" then
		local difficulty = queueData["match-config"].difficulties[queue.difficulty]
		local modeLabel = difficulty and difficulty.worldLabel or tostring(queue.difficulty)
		if difficulty == nil then
			Log.Once("LobbyQueue", `queue-difficulty-{queue.id}`, `queue {queue.id} has unknown difficulty '{tostring(queue.difficulty)}'`)
		end
		local seconds = math.max(0, math.ceil((queue["countdown-ends-at"] or 0) - (now or os.clock())))
		status = `{modeLabel} - {seconds}s`
	end
	setLabelText(queue, queue["waiting-status-label"], "WaitingStatus", status)
end

local function clearMembers(queue)
	for _, player in ipairs(queue.members) do
		if queueData["player-queue-by-user-id"][player.UserId] == queue.id then
			queueData["player-queue-by-user-id"][player.UserId] = nil
		end
	end
	queue.members = {}
	queue["member-set"] = {}
end

function Core.SetIdle(queue, clearTransient: boolean)
	clearMembers(queue)
	queue["leader-user-id"] = nil
	queue.difficulty = nil
	queue["max-players"] = Core.Config().maxPlayers
	queue.state = "idle"
	queue["countdown-ends-at"] = nil
	queue["session-key"] = ""
	queue["launch-members"] = {}
	if clearTransient then
		queue["exit-since"] = {}
		queue["blocked-until-exit"] = {}
	end
	Core.Refresh(queue)
end

function Core.OpenEffect(queue)
	local leader = Core.LeaderPlayer(queue)
	return if leader then { openPlayer = leader, openQueueId = queue.id } else {}
end

function Core.BusyResult(queue, player: Player, reason: string)
	Log.Once(
		"LobbyQueue",
		`admission-rejected-{queue.id}-{player.UserId}-{reason}`,
		`{player.Name} not admitted to queue {queue.id}: {reason}`
	)
	return { admitted = false, reason = reason }
end

local function resolveTextLabel(parent: Instance, childName: string, path: string): Instance?
	local child = parent:FindFirstChild(childName)
	if child == nil then
		Log.Warn("LobbyQueue", `{path}.{childName} missing -- authored queue label cannot update`)
		return nil
	end
	if not (child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox")) then
		Log.Warn("LobbyQueue", `{path}.{childName} must be a text GUI object, got {child.ClassName}`)
		return nil
	end
	return child
end

local function validConfig(): boolean
	local config = Core.Config()
	if config == nil then
		Log.Warn("LobbyQueue", "MatchConfig.queue missing -- queues cannot be set up")
		return false
	end
	if type(config.maxPlayers) ~= "number" or config.maxPlayers < 1 or config.maxPlayers % 1 ~= 0 then
		Log.Warn("LobbyQueue", "MatchConfig.queue.maxPlayers must be a positive integer")
		return false
	end
	if type(config.countdownSeconds) ~= "number" or config.countdownSeconds <= 0 then
		Log.Warn("LobbyQueue", "MatchConfig.queue.countdownSeconds must be positive")
		return false
	end
	if type(config.countdownSecondsSolo) ~= "number" or config.countdownSecondsSolo <= 0 then
		Log.Warn("LobbyQueue", "MatchConfig.queue.countdownSecondsSolo must be positive")
		return false
	end
	if type(config.exitGraceSeconds) ~= "number" or config.exitGraceSeconds < 0 then
		Log.Warn("LobbyQueue", "MatchConfig.queue.exitGraceSeconds must be non-negative")
		return false
	end
	return true
end

function Core.SetupQueues(map: Instance): { any }
	queueData.queues = {}
	queueData["queue-by-id"] = {}
	queueData["player-queue-by-user-id"] = {}
	queueData["bound-map"] = map
	if not validConfig() then
		return queueData.queues
	end
	if typeof(map) ~= "Instance" then
		Log.Warn("LobbyQueue", "SetupQueues received no LobbyMap instance")
		return queueData.queues
	end

	local config = Core.Config()
	local environment = map:FindFirstChild(config.environmentName)
	if environment == nil then
		Log.Warn("LobbyQueue", `{map:GetFullName()}.{config.environmentName} missing -- no queue pads can bind`)
		return queueData.queues
	end
	local touchers = environment:FindFirstChild(config.touchersFolderName)
	if touchers == nil then
		Log.Warn("LobbyQueue", `{environment:GetFullName()}.{config.touchersFolderName} missing -- no queue pads can bind`)
		return queueData.queues
	end

	local authored = {}
	for childIndex, child in ipairs(touchers:GetChildren()) do
		if child:IsA("Model") then
			table.insert(authored, { model = child, x = child:GetPivot().Position.X, childIndex = childIndex })
		end
	end
	table.sort(authored, function(a, b)
		return if a.x == b.x then a.childIndex < b.childIndex else a.x < b.x
	end)
	if #authored == 0 then
		Log.Warn("LobbyQueue", `{touchers:GetFullName()} has no direct Model children -- no queues created`)
		return queueData.queues
	end

	for queueId, item in ipairs(authored) do
		local model = item.model
		local toucher = model:FindFirstChild(config.toucherName)
		if toucher == nil or not toucher:IsA("BasePart") then
			Log.Warn("LobbyQueue", `queue {queueId} at X={item.x}: direct {config.toucherName} BasePart missing -- skipped`)
			continue
		end
		local visual = model:FindFirstChild(config.visualName)
		local countLabel
		local statusLabel
		if visual == nil then
			Log.Warn("LobbyQueue", `queue {queueId}: direct {config.visualName} missing -- queue works without labels`)
		else
			local count = visual:FindFirstChild(config.playerCountName)
			if count then
				countLabel = resolveTextLabel(count, config.textName, `queue {queueId}.{config.visualName}.{config.playerCountName}`)
			else
				Log.Warn("LobbyQueue", `queue {queueId}: {config.visualName}.{config.playerCountName} missing`)
			end
			local status = visual:FindFirstChild(config.waitingStatusName)
			if status == nil then
				local legacy = visual:FindFirstChild(config.legacyStatusName)
				if legacy then
					legacy.Name = config.waitingStatusName
					status = legacy
					Log.Info("LobbyQueue", `queue {queueId}: normalized legacy {config.legacyStatusName}`)
				else
					Log.Warn("LobbyQueue", `queue {queueId}: {config.visualName}.{config.waitingStatusName} missing`)
				end
			end
			if status then
				statusLabel = resolveTextLabel(status, config.textName, `queue {queueId}.{config.visualName}.{config.waitingStatusName}`)
			end
		end

		local queue = {
			id = queueId, model = model, toucher = toucher, visual = visual,
			["player-count-label"] = countLabel, ["waiting-status-label"] = statusLabel,
			members = {}, ["member-set"] = {}, ["leader-user-id"] = nil,
			difficulty = nil, ["max-players"] = config.maxPlayers, state = "idle",
			["countdown-ends-at"] = nil, ["session-key"] = "", ["launch-token"] = 0,
			["launch-members"] = {}, ["exit-since"] = {}, ["blocked-until-exit"] = {},
		}
		table.insert(queueData.queues, queue)
		queueData["queue-by-id"][queueId] = queue
		Core.Refresh(queue)
	end
	if #queueData.queues == 0 then
		Log.Warn("LobbyQueue", "all authored queue models were invalid -- no touchers bound")
	else
		Log.Sum("LobbyQueue", `set up {#queueData.queues} independent queue(s), ordered by pivot X`)
	end
	return queueData.queues
end

return Core
