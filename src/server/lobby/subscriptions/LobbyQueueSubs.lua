--[[
	LobbyQueueSubs -- queue event/network/loop orchestration (R4).

	Owns every GroupToucher.Touched connection, the throttled Heartbeat overlap
	scan, PlayerRemoving cleanup, and LobbyQueueRequest connection. Internal
	helpers perform protocol, occupancy, and launch logic without subscribing.

	LobbyQueueRequest(action, sessionKey, difficulty?, maxPlayers?)
	LobbyQueueUpdate(kind, payload?):
	  open {sessionKey,currentPlayers,maxPlayers} | close | error {message} | busy {message}
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local Helpers = script.Parent:WaitForChild("LobbyQueue")
local Protocol = require(Helpers:WaitForChild("Protocol"))
local Occupancy = require(Helpers:WaitForChild("Occupancy"))
local Launch = require(Helpers:WaitForChild("Launch"))

local LobbyQueueSubs = {}
local lobbyQueueData
local lobbyQueueService

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

--API
function LobbyQueueSubs.Bind(map: Instance): boolean
	if lobbyQueueData == nil or lobbyQueueService == nil then
		Log.Warn("LobbyQueueSubs", "Bind skipped: Start dependencies unavailable")
		return false
	end
	if typeof(map) ~= "Instance" then
		Log.Warn("LobbyQueueSubs", "Bind skipped: LobbyMapService returned no map instance")
		return false
	end
	for _, owner in ipairs(lobbyQueueService.GetSelectorOwners()) do
		Protocol.FireUpdate(owner, "close", nil)
	end
	disconnectAll(lobbyQueueData["queue-connections"])
	local queues = lobbyQueueService.SetupQueues(map)
	if #queues == 0 then
		Log.Warn("LobbyQueueSubs", "Bind completed with zero valid authored queue pads")
		return false
	end

	for _, queue in ipairs(queues) do
		local queueId = queue.id
		local connection = queue.toucher.Touched:Connect(function(hit)
			local player = Occupancy.PlayerFromPart(hit)
			if player then
				local ok, resultOrError = pcall(lobbyQueueService.Admit, queueId, player)
				if ok then
					Protocol.EmitEffect(resultOrError)
				else
					Log.Warn("LobbyQueueSubs", `queue {queueId} .Touched admission failed: {resultOrError}`)
				end
			end
		end)
		table.insert(lobbyQueueData["queue-connections"], connection)
	end

	lobbyQueueData["last-scan-at"] = os.clock()
	Log.Sum("LobbyQueueSubs", `bound {#lobbyQueueData["queue-connections"]} GroupToucher connection(s)`)
	local ok, err = pcall(Occupancy.Scan, lobbyQueueData["last-scan-at"])
	if not ok then
		Log.Warn("LobbyQueueSubs", `initial queue occupancy scan failed: {err}`)
	end
	return true
end

--API
-- PlayerLifecycleSubs calls this only after ClientReady and profile load. A
-- leader may already have entered a toucher before LobbySubsClient connected;
-- replay the active selector session so that one-shot early FireClient is not
-- lost.
function LobbyQueueSubs.PushInitialState(player: Player)
	if lobbyQueueData == nil or lobbyQueueService == nil then
		Log.Warn("LobbyQueueSubs", `PushInitialState({player.Name}) skipped: Start dependencies unavailable`)
		return
	end
	local queue = lobbyQueueService.GetQueueForPlayer(player)
	if queue == nil
		or queue["leader-user-id"] ~= player.UserId
		or (queue.state ~= "configuring" and queue.state ~= "failed")
	then
		return
	end
	local payload = lobbyQueueService.GetOpenPayload(queue.id)
	if payload == nil then
		Log.Warn("LobbyQueueSubs", `selector replay dropped for {player.Name}: queue {queue.id} has no active session payload`)
		return
	end
	Protocol.FireUpdate(player, "open", payload)
end

function LobbyQueueSubs.Start(data, services, subscriptions)
	lobbyQueueData = data.LobbyQueueData
	lobbyQueueService = services.LobbyQueueService
	local teleportSubs = subscriptions and subscriptions.TeleportSubs
	if lobbyQueueData == nil then
		Log.Warn("LobbyQueueSubs", "Start skipped: LobbyQueueData missing")
		return
	end
	if lobbyQueueService == nil then
		Log.Warn("LobbyQueueSubs", "Start skipped: LobbyQueueService missing")
		return
	end
	if teleportSubs == nil or type(teleportSubs.SendGroup) ~= "function" then
		Log.Warn("LobbyQueueSubs", "TeleportSubs.SendGroup missing -- launch failures will reopen the leader")
	end

	local config = lobbyQueueData["queue-config"]
	if type(config.scanIntervalSeconds) ~= "number" or config.scanIntervalSeconds <= 0 then
		Log.Warn("LobbyQueueSubs", "Start skipped: queue.scanIntervalSeconds must be positive")
		return
	end
	if type(config.launchResetSeconds) ~= "number" or config.launchResetSeconds < 0 then
		Log.Warn("LobbyQueueSubs", "Start skipped: queue.launchResetSeconds must be non-negative")
		return
	end
	if type(config.requestCooldownSeconds) ~= "number" or config.requestCooldownSeconds <= 0 then
		Log.Warn("LobbyQueueSubs", "Start skipped: queue.requestCooldownSeconds must be positive")
		return
	end

	disconnectAll(lobbyQueueData["queue-connections"])
	disconnectAll(lobbyQueueData.connections)
	lobbyQueueData["request-remote"] = Net.Remote("LobbyQueueRequest")
	lobbyQueueData["update-remote"] = Net.Update("LobbyQueueUpdate")
	lobbyQueueData["last-scan-at"] = os.clock()
	Protocol.Init(lobbyQueueData, lobbyQueueService)
	Launch.Init(lobbyQueueData, lobbyQueueService, teleportSubs, Protocol)
	Occupancy.Init(lobbyQueueData, lobbyQueueService, Protocol, Launch)

	table.insert(lobbyQueueData.connections, lobbyQueueData["request-remote"].OnServerEvent:Connect(Protocol.OnQueueRequest))
	table.insert(lobbyQueueData.connections, Players.PlayerRemoving:Connect(function(player)
		lobbyQueueData["request-last-at-by-user-id"][player.UserId] = nil
		Protocol.EmitEffect(lobbyQueueService.ForgetPlayer(player))
	end))
	table.insert(lobbyQueueData.connections, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lobbyQueueData["last-scan-at"] < config.scanIntervalSeconds then
			return
		end
		lobbyQueueData["last-scan-at"] = now
		local ok, err = pcall(Occupancy.Scan, now)
		if not ok then
			Log.Warn("LobbyQueueSubs", `queue reconciliation loop failed: {err}`)
		end
	end))
	Log.Info("LobbyQueueSubs", "request, removal, and GetPartsInPart reconciliation subscriptions started")
end

return LobbyQueueSubs
