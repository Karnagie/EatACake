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
local analytics -- optional; features/analytics.md

function Launch.Init(data, service, teleport, protocol, analyticsSubs)
	queueData = data
	queueService = service
	teleportSubs = teleport
	Protocol = protocol
	analytics = analyticsSubs
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

	-- Hand the analytics session ids across with the roster. Without this the
	-- initial-player-flow funnel breaks in half at exactly the teleport: the
	-- lobby half would end at "teleport started" and the game half would open
	-- at "arrived" under a brand-new session id, with nothing joining them.
	-- GameRoundService validates only the fields it knows, so this extra key
	-- is inert to admission (features/game-round.md).
	if analytics ~= nil then
		local okPayload, payload = pcall(analytics.HandoffPayload, launch.players)
		if okPayload and type(payload) == "table" and #payload > 0 then
			options.teleportData.analytics = payload
		elseif not okPayload then
			Log.Once("LobbyQueueSubs", "handoff-analytics", `analytics handoff payload FAILED (funnel will split at the teleport): {payload}`)
		end
		for _, player in ipairs(launch.players) do
			pcall(function()
				analytics.Flow(player, "launch")
				analytics.Funnel(player, "queue", "launch")
				analytics.SetMatch(player, options.teleportData.roundId, launch.difficulty)
				analytics.Event(player, "queue-launch", 1, {
					launch.difficulty,
					tostring(#launch.players),
					"lobby",
				}, { tier = "critical" })
			end)
		end
	end

	local ok, sentOrError = pcall(teleportSubs.SendGroup, launch.players, options)
	if not ok then
		fail(launch, tostring(sentOrError))
		return
	end
	if sentOrError ~= true then
		fail(launch, "TeleportSubs rejected or could not send the group")
		return
	end

	if analytics ~= nil then
		for _, player in ipairs(launch.players) do
			pcall(analytics.Funnel, player, "queue", "sent")
		end
	end
	Log.Info("LobbyQueueSubs", `queue {launch.queueId} handed {#launch.players} player(s) to round {options.teleportData.roundId}`)
	task.delay(queueData["queue-config"].launchResetSeconds, function()
		if not queueService.CompleteLaunch(launch.queueId, launch.launchToken) then
			Log.Info("LobbyQueueSubs", `queue {launch.queueId} launch reset skipped: token is stale`)
		end
	end)
end

return Launch
