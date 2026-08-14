--[[
	LobbyQueue.Launch -- internal reserved-server launch orchestration. It owns no
	event subscription; LobbyQueueSubs schedules it from the reconciliation loop.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local config = Shared:WaitForChild("config")
local CakeConfig = require(config:WaitForChild("CakeConfig"))
local CakeSelectConfig = require(config:WaitForChild("CakeSelectConfig"))

local Launch = {}
local queueData
local queueService
local teleportSubs
local Protocol
local analytics -- optional; features/analytics.md
local playerProfileData

function Launch.Init(data, service, teleport, protocol, analyticsSubs, profiles)
	queueData = data
	queueService = service
	teleportSubs = teleport
	Protocol = protocol
	analytics = analyticsSubs
	playerProfileData = profiles
	if playerProfileData == nil or type(playerProfileData.Get) ~= "function" then
		Log.Warn(
			"LobbyQueueSubs",
			`PlayerProfileData.Get missing -- launches will fall back to CakeSelectConfig.defaultId '{tostring(CakeSelectConfig.defaultId)}'`
		)
	end
end

local function fail(launch, message: string)
	Log.Warn("LobbyQueueSubs", `queue {launch.queueId} launch failed: {message}`)
	Protocol.EmitEffect(queueService.FailLaunch(launch.queueId, launch.launchToken))
end

local function fallbackCakeId(launch, reason: string): string?
	local defaultId = CakeSelectConfig.defaultId
	local catalogue = CakeSelectConfig.cakes
	if type(defaultId) ~= "string"
		or defaultId == ""
		or type(catalogue) ~= "table"
		or catalogue[defaultId] == nil
		or type(CakeConfig.variants) ~= "table"
		or CakeConfig.variants[defaultId] == nil
	then
		Log.Warn(
			"LobbyQueueSubs",
			`queue {launch.queueId} cannot fall back after {reason}: default cake '{tostring(defaultId)}' is not a playable CakeConfig variant`
		)
		return nil
	end
	Log.Warn(
		"LobbyQueueSubs",
		`queue {launch.queueId} {reason} -- falling back to cake '{defaultId}'`
	)
	return defaultId
end

local function resolveCakeId(launch): string?
	local leaderUserId = launch.leaderUserId
	if type(leaderUserId) ~= "number" or leaderUserId <= 0 or leaderUserId % 1 ~= 0 then
		return fallbackCakeId(launch, `has invalid leaderUserId '{tostring(leaderUserId)}'`)
	end
	if playerProfileData == nil or type(playerProfileData.Get) ~= "function" then
		return fallbackCakeId(launch, `cannot read leader {leaderUserId}'s profile`)
	end

	local profile = playerProfileData.Get(leaderUserId)
	if type(profile) ~= "table" then
		return fallbackCakeId(launch, `leader {leaderUserId}'s profile is not loaded`)
	end
	local cakes = profile.cakes
	local selected = if type(cakes) == "table" then cakes.selected else nil
	if type(selected) ~= "string"
		or selected == ""
		or type(CakeSelectConfig.cakes) ~= "table"
		or CakeSelectConfig.cakes[selected] == nil
		or type(CakeConfig.variants) ~= "table"
		or CakeConfig.variants[selected] == nil
	then
		return fallbackCakeId(
			launch,
			`leader {leaderUserId} has invalid profile.cakes.selected '{tostring(selected)}'`
		)
	end
	return selected
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
	local cakeId = resolveCakeId(launch)
	if cakeId == nil then
		fail(launch, "no valid cake id is available")
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
			cakeId = cakeId,
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
