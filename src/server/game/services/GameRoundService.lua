--[[
	GameRoundService -- pure reserved-round roster/join/state logic (R2).

	It validates server-authenticated Player:GetJoinData(), establishes exactly
	one fixed roster, tracks present participants, claims/commits the arrival-window start,
	and guards the terminal result. Event wiring and cross-subscription calls stay
	in GameRoundSubs. All mutable state lives in RoundStateData.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "GameRound"

local GameRoundService = {}

local roundState -- RoundStateData
local cakeConfig -- CakeConfigData.cake

function GameRoundService.Init(data)
	roundState = data.RoundStateData
	cakeConfig = data.CakeConfigData and data.CakeConfigData.cake
	if roundState == nil then
		Log.Warn(SCOPE, "RoundStateData missing -- round validation disabled")
	end
	if cakeConfig == nil or type(cakeConfig.variants) ~= "table" then
		Log.Warn(SCOPE, "CakeConfigData.cake.variants missing -- all round arrivals will be rejected")
	end
end

local function directJoin(joinData): boolean
	local sourceGameId = joinData.SourceGameId
	local sourcePlaceId = joinData.SourcePlaceId
	local noGameSource = sourceGameId == nil or sourceGameId == 0 or sourceGameId == ""
	local noPlaceSource = sourcePlaceId == nil or sourcePlaceId == 0
	return noGameSource and noPlaceSource and joinData.TeleportData == nil
end

local function validateExpectedRoster(rawRoster, player: Player): ({ number }?, string?)
	if type(rawRoster) ~= "table" then
		return nil, "expectedUserIds is not an array"
	end
	local matchConfig = roundState["match-config"]
	local maximum = matchConfig.queue.maxPlayers
	local keyCount = 0
	local maxIndex = 0
	local seen = {}
	local containsPlayer = false
	for key, userId in pairs(rawRoster) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return nil, "expectedUserIds has a non-array key"
		end
		if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
			return nil, "expectedUserIds contains an invalid user id"
		end
		if seen[userId] then
			return nil, "expectedUserIds contains a duplicate user id"
		end
		seen[userId] = true
		containsPlayer = containsPlayer or userId == player.UserId
		keyCount += 1
		maxIndex = math.max(maxIndex, key)
	end
	if keyCount < 1 or keyCount > maximum then
		return nil, `expectedUserIds must contain 1..{maximum} users`
	end
	if maxIndex ~= keyCount then
		return nil, "expectedUserIds must be contiguous"
	end
	if not containsPlayer then
		return nil, "expectedUserIds does not contain the arriving player"
	end

	local roster = {}
	for index = 1, keyCount do
		local userId = rawRoster[index]
		if userId == nil then
			return nil, "expectedUserIds must be contiguous"
		end
		table.insert(roster, userId)
	end
	return roster, nil
end

local function validateCakeId(rawCakeId): (string?, string?)
	if cakeConfig == nil or type(cakeConfig.variants) ~= "table" then
		return nil, "CakeConfigData.cake.variants is unavailable"
	end
	if type(rawCakeId) ~= "string" or rawCakeId == "" or cakeConfig.variants[rawCakeId] == nil then
		return nil, "cakeId is not a configured cake variant"
	end
	return rawCakeId, nil
end

local function directJoinCakeId(): (string?, string?)
	local defaultId = cakeConfig and cakeConfig.defaultVariantId
	local studioId = if RunService:IsStudio() and cakeConfig then cakeConfig.studioVariantId else nil
	if type(studioId) == "string" and studioId ~= "" then
		local validated, studioError = validateCakeId(studioId)
		if validated ~= nil then
			Log.Once(
				SCOPE,
				"studio-variant-override",
				`Studio direct join override active -- using '{validated}' (CakeConfig.studioVariantId)`
			)
			return validated, nil
		end
		Log.Once(
			SCOPE,
			"invalid-studio-variant-override",
			`CakeConfig.studioVariantId '{studioId}' is invalid ({tostring(studioError)}) -- production default used`
		)
	elseif studioId ~= nil then
		Log.Once(
			SCOPE,
			"malformed-studio-variant-override",
			"CakeConfig.studioVariantId must be a non-empty string or nil -- production default used"
		)
	end
	return validateCakeId(defaultId)
end

local function validateLobbyJoin(joinData, player: Player): (any?, string?)
	local matchConfig = roundState["match-config"]
	local placeConfig = roundState["place-config"]
	if joinData.SourceGameId ~= game.GameId then
		return nil, "SourceGameId is not this universe"
	end
	if joinData.SourcePlaceId ~= placeConfig.lobbyPlaceId then
		return nil, "SourcePlaceId is not the configured lobby"
	end

	local teleportData = joinData.TeleportData
	if type(teleportData) ~= "table" then
		return nil, "TeleportData is missing"
	end
	if teleportData.version ~= matchConfig.protocolVersion then
		return nil, "protocol version does not match"
	end
	if type(teleportData.roundId) ~= "string" or #teleportData.roundId == 0 then
		return nil, "roundId is empty"
	end
	if type(teleportData.difficulty) ~= "string"
		or matchConfig.difficulties[teleportData.difficulty] == nil
	then
		return nil, "difficulty is unknown"
	end
	local cakeId, cakeError = validateCakeId(teleportData.cakeId)
	if cakeId == nil then
		return nil, cakeError
	end

	local roster, rosterError = validateExpectedRoster(teleportData.expectedUserIds, player)
	if roster == nil then
		return nil, rosterError
	end
	if type(teleportData.expectedCount) ~= "number"
		or teleportData.expectedCount % 1 ~= 0
		or teleportData.expectedCount ~= #roster
	then
		return nil, "expectedCount does not match expectedUserIds"
	end
	return {
		roundId = teleportData.roundId,
		difficulty = teleportData.difficulty,
		cakeId = cakeId,
		expectedUserIds = roster,
		expectedCount = #roster,
		directJoin = false,
	}, nil
end

--API
function GameRoundService.CandidateFor(player: Player): (any?, string?)
	if roundState == nil then
		return nil, "RoundStateData is unavailable"
	end
	local ok, joinData = pcall(player.GetJoinData, player)
	if not ok or type(joinData) ~= "table" then
		return nil, `GetJoinData failed: {if ok then "non-table result" else tostring(joinData)}`
	end
	if directJoin(joinData) then
		local matchConfig = roundState["match-config"]
		local difficulty = matchConfig.round.directJoinDifficulty
		if matchConfig.difficulties[difficulty] == nil then
			return nil, `direct-join difficulty '{tostring(difficulty)}' is not configured`
		end
		local cakeId, cakeError = directJoinCakeId()
		if cakeId == nil then
			return nil, `direct-join cake is not configured: {cakeError}`
		end
		return {
			roundId = `direct-{HttpService:GenerateGUID(false)}`,
			difficulty = difficulty,
			cakeId = cakeId,
			expectedUserIds = { player.UserId },
			expectedCount = 1,
			directJoin = true,
		}, nil
	end
	return validateLobbyJoin(joinData, player)
end

--API
function GameRoundService.Matches(candidate): boolean
	if not roundState["established"]
		or candidate.roundId ~= roundState["round-id"]
		or candidate.difficulty ~= roundState["difficulty"]
		or candidate.cakeId ~= roundState["cake-id"]
		or candidate.expectedCount ~= roundState["expected-count"]
	then
		return false
	end
	for index = 1, candidate.expectedCount do
		if candidate.expectedUserIds[index] ~= roundState["expected-user-ids"][index] then
			return false
		end
	end
	return true
end

--API
function GameRoundService.Establish(player: Player, candidate)
	local expectedSet = {}
	for _, userId in ipairs(candidate.expectedUserIds) do
		expectedSet[userId] = true
	end
	roundState["established"] = true
	roundState["direct-join"] = candidate.directJoin
	roundState["round-id"] = candidate.roundId
	roundState["difficulty"] = candidate.difficulty
	roundState["cake-id"] = candidate.cakeId
	roundState["expected-user-ids"] = candidate.expectedUserIds
	roundState["expected-user-set"] = expectedSet
	roundState["expected-count"] = candidate.expectedCount
	roundState["participants"][player.UserId] = player
	roundState["arrival-deadline"] = os.clock() + roundState["match-config"].round.arrivalWindowSeconds
end

--API
function GameRoundService.AddParticipant(player: Player)
	if roundState["expected-user-set"][player.UserId] then
		roundState["participants"][player.UserId] = player
	end
end

--API
function GameRoundService.RemoveParticipant(player: Player)
	if roundState["participants"][player.UserId] == player then
		roundState["participants"][player.UserId] = nil
	end
end

--API
function GameRoundService.Participants(): { Player }
	local current = {}
	for _, userId in ipairs(roundState["expected-user-ids"]) do
		local player = roundState["participants"][userId]
		if player and player.Parent == Players then
			table.insert(current, player)
		end
	end
	return current
end

--API
function GameRoundService.IsParticipant(player: Player): boolean
	return roundState["expected-user-set"][player.UserId] == true
		and roundState["participants"][player.UserId] == player
		and player.Parent == Players
end

--API
function GameRoundService.ClaimStart(now: number): (boolean, boolean)
	if not roundState["established"]
		or roundState["match-starting"]
		or roundState["match-started"]
		or roundState["finished"]
	then
		return false, false
	end
	local count = #GameRoundService.Participants()
	if count == 0 then
		return false, false
	end
	local timedOut = now >= (roundState["arrival-deadline"] or math.huge)
	if count < roundState["expected-count"] and not timedOut then
		return false, false
	end
	roundState["match-starting"] = true
	return true, timedOut
end

--API
-- The cake is not live while BeginMatch is constructing it. Committing only
-- after that call succeeds keeps Heartbeat and player input behind one gate.
function GameRoundService.CompleteStart(succeeded: boolean): boolean
	if not roundState["match-starting"] then
		return false
	end
	roundState["match-starting"] = false
	if succeeded then
		roundState["match-started"] = true
	end
	return succeeded
end

--API
function GameRoundService.MarkFinished(result: string): boolean
	if not roundState["established"] or roundState["finished"] then
		return false
	end
	roundState["finished"] = true
	roundState["result"] = result
	return true
end

return GameRoundService
