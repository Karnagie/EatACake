--[[
	Return -- bounded, profile-safe finished-round return orchestration.

	Ready participants leave in one public-lobby batch. Late arrivals whose
	profiles are still loading wait for a later retry instead of blocking the
	already-ready group.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "GameRound"

local Return = {}

local function failClosed(RoundState, RoundService, reason: string)
	RoundState["return-loop-active"] = false
	RoundState["return-deadline"] = os.clock()
	Log.Warn(SCOPE, reason)
	for _, player in ipairs(RoundService.Participants()) do
		if player.Parent == Players and player:GetAttribute("Teleporting") ~= true then
			Log.Warn(SCOPE, `disconnecting {player.Name} because the finished round cannot return safely`)
			player:Kick()
		end
	end
end

--API
function Return.Run(Result: string, RoundState, RoundService, PersistenceService, TeleportSubs)
	local config = RoundState["match-config"]
	local place_config = RoundState["place-config"]
	task.wait(math.max(0, config.round.resultDelaySeconds))
	if TeleportSubs == nil or type(TeleportSubs.SendGroup) ~= "function" then
		failClosed(RoundState, RoundService, "TeleportSubs.SendGroup missing -- finished participants cannot return to the lobby")
		return
	end
	if PersistenceService == nil or type(PersistenceService.IsLoaded) ~= "function" then
		failClosed(RoundState, RoundService, "PersistenceService.IsLoaded missing -- finished participants cannot return safely")
		return
	end
	if type(place_config.lobbyPlaceId) ~= "number" or place_config.lobbyPlaceId <= 0 then
		failClosed(RoundState, RoundService, "PlaceConfig.lobbyPlaceId unset -- finished participants cannot return")
		return
	end

	RoundState["return-loop-active"] = true
	RoundState["return-deadline"] = os.clock() + config.round.returnRetryWindowSeconds
	while true do
		local participants = RoundService.Participants()
		if #participants > 0 then
			local ready = {}
			for _, player in ipairs(participants) do
				if player:GetAttribute("Teleporting") ~= true
					and PersistenceService.IsLoaded(player.UserId)
				then
					table.insert(ready, player)
				elseif player:GetAttribute("Teleporting") ~= true then
					Log.Once(
						SCOPE,
						`return-profile-wait-{player.UserId}`,
						`waiting for {player.Name}'s profile before adding them to a lobby-return batch`
					)
				end
			end
			if #ready > 0 then
				local ok, sent_or_error = pcall(TeleportSubs.SendGroup, ready, {
					targetPlaceId = place_config.lobbyPlaceId,
					reserveServer = false,
					teleportData = {
						version = config.protocolVersion,
						kind = "match-result",
						result = Result,
						roundId = RoundState["round-id"],
					},
				})
				if not ok then
					Log.Warn(SCOPE, `lobby return call FAILED for {#ready} player(s): {sent_or_error}`)
				elseif sent_or_error == false then
					Log.Warn(SCOPE, `lobby return declined for {#ready} player(s); retrying`)
				end
			end
		end
		local remaining = RoundState["return-deadline"] - os.clock()
		if remaining <= 0 then
			break
		end
		-- Wake at the deadline for one final send attempt, even if the ordinary
		-- retry interval would overshoot a just-in-time authenticated arrival.
		task.wait(math.min(config.round.returnRetrySeconds, remaining))
	end
	RoundState["return-loop-active"] = false
	if #RoundService.Participants() == 0 then
		Log.Info(SCOPE, `round '{RoundState["round-id"]}' lobby-return window closed with no participants remaining`)
	else
		Log.Warn(SCOPE, `round '{RoundState["round-id"]}' exhausted its lobby-return retry window`)
	end
end

return Return
