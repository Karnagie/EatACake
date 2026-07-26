--[[
	LobbyQueue.Launch -- internal reserved-server launch orchestration. It owns no
	event subscription; LobbyQueueSubs schedules it from the reconciliation loop.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Launch = {}
local queueData
local queueService
local teleportSubs
local Protocol

function Launch.Init(data, service, teleport, protocol)
	queueData = data
	queueService = service
	teleportSubs = teleport
	Protocol = protocol
end

local function fail(launch, message: string)
	Log.Warn("LobbyQueueSubs", `queue {launch.queueId} launch failed: {message}`)
	Protocol.EmitEffect(queueService.FailLaunch(launch.queueId, launch.launchToken))
end

function Launch.Perform(launch)
	local placeConfig = queueData["place-config"]
	local matchConfig = queueData["match-config"]
	local targetPlaceId = placeConfig and placeConfig.gamePlaceId
	if type(targetPlaceId) ~= "number" or targetPlaceId <= 0 then
		fail(launch, "PlaceConfig.gamePlaceId is unset")
		return
	end
	if teleportSubs == nil or type(teleportSubs.SendGroup) ~= "function" then
		fail(launch, "TeleportSubs.SendGroup is unavailable")
		return
	end

	local expectedUserIds = {}
	for _, player in ipairs(launch.players) do
		table.insert(expectedUserIds, player.UserId)
	end
	local options = {
		targetPlaceId = targetPlaceId,
		reserveServer = true,
		teleportData = {
			version = matchConfig.protocolVersion,
			roundId = HttpService:GenerateGUID(false),
			difficulty = launch.difficulty,
			expectedUserIds = expectedUserIds,
			expectedCount = #launch.players,
			sourcePlaceId = game.PlaceId,
		},
	}
	local ok, sentOrError = pcall(teleportSubs.SendGroup, launch.players, options)
	if not ok then
		fail(launch, tostring(sentOrError))
		return
	end
	if sentOrError ~= true then
		fail(launch, "TeleportSubs rejected or could not send the group")
		return
	end

	Log.Info("LobbyQueueSubs", `queue {launch.queueId} handed {#launch.players} player(s) to round {options.teleportData.roundId}`)
	task.delay(queueData["queue-config"].launchResetSeconds, function()
		if not queueService.CompleteLaunch(launch.queueId, launch.launchToken) then
			Log.Info("LobbyQueueSubs", `queue {launch.queueId} launch reset skipped: token is stale`)
		end
	end)
end

return Launch
