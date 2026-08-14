-- ROUND CAKE HANDOFF scenario: leader selection -> TeleportData -> validated
-- destination candidate/state, including direct-join and mismatch guards.

local CakeConfig = __REGISTRY["Shared.config.CakeConfig"]
local CakeSelectConfig = __REGISTRY["Shared.config.CakeSelectConfig"]
local MatchConfig = __REGISTRY["Shared.config.MatchConfig"]
local PlaceConfig = __REGISTRY["Shared.config.PlaceConfig"]
local RoundStateData = __REGISTRY["__RoundStateData"]
local GameRoundService = __REGISTRY["__GameRoundService"]
local Launch = __REGISTRY["__LobbyQueueLaunch"]

local failures, checks = 0, 0
local function check(label: string, ok: boolean, detail: string?)
	checks += 1
	if ok then
		print(`  ok    {label}{detail and (" — " .. detail) or ""}`)
	else
		failures += 1
		print(`  FAIL  {label}{detail and (" — " .. detail) or ""}`)
	end
end

local leader = __newPlayer(101, "Leader")
local member = __newPlayer(202, "Member")
local captured = nil
local completed = false
local failed = false
local queueService = {
	FailLaunch = function()
		failed = true
		return nil
	end,
	CompleteLaunch = function()
		completed = true
		return true
	end,
}
local teleportSubs = {
	SendGroup = function(players, options)
		captured = { players = players, options = options }
		return true
	end,
}
local protocol = { EmitEffect = function() end }
local profiles = {
	Get = function(userId)
		if userId == leader.UserId then
			return { cakes = { selected = "cake-rainbow" } }
		end
		return nil
	end,
}
local queueData = {
	["place-config"] = PlaceConfig,
	["match-config"] = MatchConfig,
	["queue-config"] = { launchResetSeconds = 1 },
}

print("\n[1] lobby launch snapshots the leader's playable selection")
game.PlaceId = PlaceConfig.lobbyPlaceId
game.GameId = 987654
Launch.Init(queueData, queueService, teleportSubs, protocol, nil, profiles)
Launch.Perform({
	queueId = 1,
	launchToken = 9,
	leaderUserId = leader.UserId,
	players = { leader, member },
	difficulty = "easy",
})
local teleportData = captured and captured.options.teleportData
check("launch succeeded", captured ~= nil and not failed and completed)
check("protocol is version 2", teleportData ~= nil and teleportData.version == 2)
check("leader rainbow selection enters TeleportData", teleportData ~= nil and teleportData.cakeId == "cake-rainbow")
check("roster remains a contiguous numeric array",
	teleportData ~= nil and teleportData.expectedUserIds[1] == 101
		and teleportData.expectedUserIds[2] == 202 and teleportData.expectedCount == 2)

print("\n[2] non-playable catalogue entries fall back before teleport")
profiles.Get = function()
	return { cakes = { selected = "cake-coming-soon" } }
end
captured, completed, failed = nil, false, false
Launch.Perform({
	queueId = 2,
	launchToken = 10,
	leaderUserId = leader.UserId,
	players = { leader },
	difficulty = "easy",
})
check("coming-soon cannot launch", captured ~= nil
	and captured.options.teleportData.cakeId == CakeSelectConfig.defaultId)

print("\n[3] destination validates and establishes the cake variant")
RoundStateData.Init()
GameRoundService.Init({
	RoundStateData = RoundStateData,
	CakeConfigData = { cake = CakeConfig },
})
game.PlaceId = PlaceConfig.gamePlaceId
leader._joinData = {
	SourceGameId = game.GameId,
	SourcePlaceId = PlaceConfig.lobbyPlaceId,
	TeleportData = teleportData,
}
local candidate, candidateError = GameRoundService.CandidateFor(leader)
check("valid rainbow arrival accepted", candidate ~= nil and candidateError == nil,
	tostring(candidateError))
check("candidate carries rainbow", candidate ~= nil and candidate.cakeId == "cake-rainbow")
if candidate ~= nil then
	GameRoundService.Establish(leader, candidate)
end
check("round state stores cake-id", RoundStateData["cake-id"] == "cake-rainbow")
check("matching later arrival is accepted", candidate ~= nil and GameRoundService.Matches(candidate))
if candidate ~= nil then
	local mismatch = table.clone(candidate)
	mismatch.cakeId = "cake-classic"
	check("later arrival with a different cake is rejected", not GameRoundService.Matches(mismatch))
end

print("\n[4] missing/unknown ids reject; direct join defaults classic")
local badData = table.clone(teleportData)
badData.cakeId = nil
member._joinData = {
	SourceGameId = game.GameId,
	SourcePlaceId = PlaceConfig.lobbyPlaceId,
	TeleportData = badData,
}
local missing, missingError = GameRoundService.CandidateFor(member)
check("missing cakeId rejected", missing == nil and type(missingError) == "string")
badData.cakeId = "cake-coming-soon"
local unknown, unknownError = GameRoundService.CandidateFor(member)
check("non-playable cakeId rejected", unknown == nil and type(unknownError) == "string")

local direct = __newPlayer(303, "Direct")
direct._joinData = {}
local directCandidate, directError = GameRoundService.CandidateFor(direct)
check("direct join accepted", directCandidate ~= nil and directError == nil)
check("direct join defaults to classic",
	directCandidate ~= nil and directCandidate.cakeId == CakeConfig.defaultVariantId)

print("\n[5] Studio direct join uses the configured rainbow override")
local RunService = game:GetService("RunService")
local originalIsStudio = RunService.IsStudio
RunService.IsStudio = function() return true end
local studioDirect = __newPlayer(404, "StudioDirect")
studioDirect._joinData = {}
local studioCandidate, studioError = GameRoundService.CandidateFor(studioDirect)
check("Studio direct join accepted", studioCandidate ~= nil and studioError == nil)
check("Studio direct join starts rainbow",
	studioCandidate ~= nil and studioCandidate.cakeId == CakeConfig.studioVariantId)

local studioLobby = __newPlayer(505, "StudioLobby")
local studioLobbyData = table.clone(teleportData)
studioLobbyData.roundId = "studio-explicit-classic"
studioLobbyData.cakeId = "cake-classic"
studioLobbyData.expectedUserIds = { studioLobby.UserId }
studioLobbyData.expectedCount = 1
studioLobby._joinData = {
	SourceGameId = game.GameId,
	SourcePlaceId = PlaceConfig.lobbyPlaceId,
	TeleportData = studioLobbyData,
}
local explicitCandidate, explicitError = GameRoundService.CandidateFor(studioLobby)
check("explicit Studio lobby cake remains authoritative",
	explicitCandidate ~= nil and explicitError == nil and explicitCandidate.cakeId == "cake-classic")

local configuredStudioId = CakeConfig.studioVariantId
CakeConfig.studioVariantId = "cake-coming-soon"
local invalidOverride = __newPlayer(606, "InvalidOverride")
invalidOverride._joinData = {}
local fallbackCandidate, fallbackError = GameRoundService.CandidateFor(invalidOverride)
check("invalid Studio override falls back to production default",
	fallbackCandidate ~= nil and fallbackError == nil
		and fallbackCandidate.cakeId == CakeConfig.defaultVariantId)
CakeConfig.studioVariantId = configuredStudioId
RunService.IsStudio = originalIsStudio

flushLog()
print(`\n{checks - failures}/{checks} round cake handoff checks passed`)
if failures > 0 then
	error(`{failures} round cake handoff check(s) failed`)
end
