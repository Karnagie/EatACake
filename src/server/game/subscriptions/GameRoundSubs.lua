--[[
	GameRoundSubs -- reserved-round event and cross-domain orchestration (R4).

	GameRoundService owns the fixed roster. This wires profile-gated arrivals,
	participant authority, cake start, and bounded terminal lobby returns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local Return = require(script.Parent:WaitForChild("GameRound"):WaitForChild("Return"))

local SCOPE = "GameRound"

local GameRoundSubs = {}

local roundState -- RoundStateData
local roundService -- GameRoundService
local persistenceService -- PersistenceService
local CakeCycleSubs
local TeleportSubs
local returnFinishedRound

local function rejectArrival(player: Player, reason: string, playerMessage: string?)
	Log.Warn(SCOPE, `{player.Name} rejected from this server's match: {reason}`)
	if player.Parent == Players then
		player:Kick(playerMessage or "This match reservation does not include you. Please return to the lobby.")
	end
end
local function failStart(reason: string)
	Log.Warn(SCOPE, reason)
	if roundService.MarkFinished("loss") then
		Log.Sum(SCOPE, `round '{roundState["round-id"]}' failed closed; returning participants to the lobby`)
		task.spawn(returnFinishedRound, "loss")
	end
end
local function beginMatchIfReady(trigger: string)
	if CakeCycleSubs == nil or type(CakeCycleSubs.BeginMatch) ~= "function" then
		failStart("CakeCycleSubs.BeginMatch missing -- established round cannot start")
		return
	end
	local now = os.clock()
	local deadline = roundState["arrival-deadline"] or math.huge
	local timedOut = now >= deadline
	local participants = roundService.Participants()
	if #participants == 0 then
		return
	end
	-- All present profiles gate start. At the deadline, remove the still-unloaded
	-- members so the loaded subset can start against the fixed expected count.
	local allLoaded = true
	for _, player in ipairs(participants) do
		if not persistenceService.IsLoaded(player.UserId) then
			allLoaded = false
			if timedOut then
				roundService.RemoveParticipant(player)
				rejectArrival(
					player,
					"profile was not loaded before the arrival window expired",
					"Your data did not load before this match started. Please rejoin from the lobby."
				)
			end
		end
	end
	if not allLoaded and not timedOut then
		return
	end
	participants = roundService.Participants()
	if #participants == 0 then
		return
	end
	local claimed, claimTimedOut = roundService.ClaimStart(now)
	if not claimed then
		return
	end
	local ok, beganOrError = pcall(
		CakeCycleSubs.BeginMatch,
		roundState["difficulty"],
		roundState["expected-count"]
	)
	local began = ok and beganOrError == true
	roundService.CompleteStart(began)
	if began then
		Log.Sum(
			SCOPE,
			`starting round '{roundState["round-id"]}' ({#participants}/{roundState["expected-count"]} present, trigger={trigger}{if claimTimedOut then ", arrival-window-expired" else ""})`
		)
	elseif not began then
		failStart(if ok then "CakeCycleSubs.BeginMatch declined the round" else `CakeCycleSubs.BeginMatch FAILED: {beganOrError}`)
	end
end
local function establishMatch(player: Player, candidate)
	roundService.Establish(player, candidate)
	Log.Sum(
		SCOPE,
		`established round '{candidate.roundId}' -- difficulty={candidate.difficulty}, expected={candidate.expectedCount}{if candidate.directJoin then " (direct easy-solo fallback)" else ""}`
	)
	beginMatchIfReady("first-arrival")
end
local function handleArrival(player: Player)
	if roundService.IsParticipant(player) then
		return
	end
	local candidate, validationError = roundService.CandidateFor(player)
	if candidate == nil then
		rejectArrival(player, validationError or "invalid arrival metadata")
		return
	end
	if not roundState["established"] then
		establishMatch(player, candidate)
		return
	end
	if roundState["finished"] then
		if not roundService.Matches(candidate) then
			rejectArrival(player, "arrival metadata does not match the finished round")
			return
		end
		local returnDeadline = roundState["return-deadline"]
		if returnDeadline ~= nil and os.clock() >= returnDeadline then
			rejectArrival(
				player,
				"the finished round's lobby-return window already expired",
				"This match has ended. Please rejoin from the lobby."
			)
			return
		end
		roundService.AddParticipant(player)
		Log.Info(SCOPE, `{player.Name} arrived after round completion -- admitted only for the bounded lobby return`)
		return
	end
	if not roundService.Matches(candidate) then
		rejectArrival(player, "arrival metadata does not match the established round")
		return
	end
	roundService.AddParticipant(player)
	Log.Info(
		SCOPE,
		`{player.Name} joined round '{roundState["round-id"]}' ({#roundService.Participants()}/{roundState["expected-count"]})`
	)
	beginMatchIfReady("roster-arrival")
end
--API
function GameRoundSubs.Participants(): { Player }
	if roundService == nil then
		Log.Once(SCOPE, "participants-before-start", "Participants called before Start -- returning none")
		return {}
	end
	return roundService.Participants()
end
--API
function GameRoundSubs.ParticipantCount(): number
	return #GameRoundSubs.Participants()
end
--API
function GameRoundSubs.ExpectedCount(): number
	return if roundState then roundState["expected-count"] else 0
end
--API
function GameRoundSubs.Difficulty(): string?
	return if roundState then roundState["difficulty"] else nil
end
--API
function GameRoundSubs.IsActive(): boolean
	return roundState ~= nil and roundState["round-active"] == true
end
--API
function GameRoundSubs.IsParticipant(player: Player): boolean
	return GameRoundSubs.IsActive()
		and roundService ~= nil
		and roundState["established"]
		and roundService.IsParticipant(player)
end
--API
function GameRoundSubs.IsStarted(): boolean
	return roundState ~= nil and roundState["match-started"] == true and roundState["finished"] ~= true
end
--API
-- A completed round still owns a valid authoritative cake snapshot, while a
-- roster-waiting or fail-before-build round does not.
function GameRoundSubs.HasCakeSnapshot(): boolean
	return roundState ~= nil and roundState["match-started"] == true
end
returnFinishedRound = function(result: string)
	Return.Run(result, roundState, roundService, persistenceService, TeleportSubs)
end
--API
function GameRoundSubs.Finish(result: string): boolean
	if result ~= "win" and result ~= "loss" then
		Log.Warn(SCOPE, `Finish received invalid result '{tostring(result)}' -- ignored`)
		return false
	end
	if roundService == nil or not roundState["match-started"] then
		Log.Warn(SCOPE, `Finish('{result}') before a match started -- ignored`)
		return false
	end
	if not roundService.MarkFinished(result) then
		return false
	end
	local delaySeconds = math.max(0, roundState["match-config"].round.resultDelaySeconds)
	Log.Sum(SCOPE, `round '{roundState["round-id"]}' finished: {result}; returning to lobby in {delaySeconds}s`)
	task.spawn(returnFinishedRound, result)
	return true
end

function GameRoundSubs.Start(data, services, subscriptions)
	roundState = data.RoundStateData
	roundService = services.GameRoundService
	persistenceService = services.PersistenceService
	CakeCycleSubs = subscriptions and subscriptions.CakeCycleSubs
	TeleportSubs = subscriptions and subscriptions.TeleportSubs
	if roundState == nil then
		Log.Warn(SCOPE, "RoundStateData missing -- round/fallback mode cannot be resolved")
		return
	end
	local placeConfig = roundState["place-config"]
	if placeConfig == nil or placeConfig.current() ~= "game" then
		roundState["round-active"] = false
		Log.Info(SCOPE, `game place partition inactive at PlaceId {game.PlaceId} -- reserved-round ownership skipped`)
		return
	end
	roundState["round-active"] = true
	if roundService == nil
		or persistenceService == nil
		or type(persistenceService.IsLoaded) ~= "function"
	then
		Log.Warn(SCOPE, "GameRoundService/PersistenceService.IsLoaded missing -- arrivals cannot start safely")
		return
	end
	if CakeCycleSubs == nil then
		Log.Warn(SCOPE, "CakeCycleSubs missing -- matches cannot reset their cake")
	end
	if TeleportSubs == nil then
		Log.Warn(SCOPE, "TeleportSubs missing -- finished matches cannot return to the lobby")
	end

	Players.PlayerAdded:Connect(handleArrival)
	Players.PlayerRemoving:Connect(roundService.RemoveParticipant)
	RunService.Heartbeat:Connect(function()
		if roundState["established"]
			and not roundState["match-starting"]
			and not roundState["match-started"]
			and not roundState["finished"]
		then
			beginMatchIfReady("roster-profile-ready")
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(handleArrival, player)
	end
end

return GameRoundSubs
