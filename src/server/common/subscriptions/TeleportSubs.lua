--[[
	TeleportSubs -- data-safe lobby <-> game ProfileStore handoff (COMMON).

	One universe has one profile session lock per user. Before a player moves,
	the source intentionally unloads the profile and waits for the ending save's
	committed-release signal. Only then does it call TeleportAsync. A failed
	teleport re-acquires the released profile so nobody is stranded without an
	active session.

	SendGroup performs that contract for a whole party and invokes exactly one
	TeleportAsync call. Lobby -> game may reserve an isolated round server; game
	-> lobby targets the public start place. TeleportData is transient match
	metadata only and is never authoritative profile/reward state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))
local PlaceConfig = require(Shared:WaitForChild("config"):WaitForChild("PlaceConfig"))
local Release = require(script.Parent:WaitForChild("Teleport"):WaitForChild("Release"))
local Recovery = require(script.Parent:WaitForChild("Teleport"):WaitForChild("Recovery"))
local Resync = require(script.Parent:WaitForChild("Teleport"):WaitForChild("Resync"))

local SCOPE = "Teleport"

local TeleportSubs = {}

local services_
local teleportData_
local subscriptions_

export type GroupOptions = {
	targetPlaceId: number,
	reserveServer: boolean?,
	teleportData: any?,
}

local function handoffs(): { [Player]: boolean }
	return teleportData_["teleporting"]
end

local function clearHandoff(player: Player)
	player:SetAttribute("Teleporting", nil)
	teleportData_.Clear(player)
	if services_ and services_.PersistenceService and services_.PersistenceService.ClearReleaseState then
		services_.PersistenceService.ClearReleaseState(player.UserId)
	end
end

--API
function TeleportSubs.RecoverPlayer(player: Player)
	if teleportData_ == nil or services_ == nil or teleportData_["enabled"] ~= true then
		Log.Warn(SCOPE, `RecoverPlayer({player.Name}) called while teleport handoffs are disabled`)
		return false
	end
	if not handoffs()[player] then
		return false
	end
	return Recovery.Start(
		player,
		teleportData_,
		services_.PersistenceService,
		function(recoveredPlayer)
			Resync.Push(recoveredPlayer, subscriptions_)
		end
	)
end

local function normalizeGroup(players: { Player }): { Player }
	local unique = {}
	local group = {}
	for _, player in ipairs(players) do
		if typeof(player) == "Instance" and player:IsA("Player") and not unique[player] then
			unique[player] = true
			table.insert(group, player)
		end
	end
	return group
end

local function recoverPresentGroup(group: { Player })
	for _, player in ipairs(group) do
		if player.Parent == Players then
			Recovery.Start(
				player,
				teleportData_,
				services_.PersistenceService,
				function(recoveredPlayer)
					Resync.Push(recoveredPlayer, subscriptions_)
				end
			)
		else
			teleportData_.Clear(player)
			if services_.PersistenceService.ClearReleaseState then
				services_.PersistenceService.ClearReleaseState(player.UserId)
			end
		end
	end
end

--API
-- Preflights, committed-releases, then teleports the whole group together.
-- Returns false only when the handoff was refused/failed synchronously. An
-- asynchronous per-player failure is recovered by TeleportInitFailed.
function TeleportSubs.SendGroup(players: { Player }, options: GroupOptions): boolean
	if teleportData_ == nil or services_ == nil or teleportData_["enabled"] ~= true then
		Log.Warn(SCOPE, "SendGroup called before TeleportSubs.Start -- handoff refused")
		return false
	end
	if type(options) ~= "table" or type(options.targetPlaceId) ~= "number" then
		Log.Warn(SCOPE, "SendGroup received invalid options/targetPlaceId -- handoff refused")
		return false
	end
	if type(players) ~= "table" then
		Log.Warn(SCOPE, "SendGroup received a non-table player list -- handoff refused")
		return false
	end

	local targetPlaceId = options.targetPlaceId
	local currentPlace = PlaceConfig.current()
	if currentPlace == "unknown" then
		Log.Warn(SCOPE, `SendGroup refused from unknown PlaceId {game.PlaceId} -- PlaceConfig routing is disabled here`)
		return false
	end
	local configuredTarget = targetPlaceId ~= 0
		and (targetPlaceId == PlaceConfig.lobbyPlaceId or targetPlaceId == PlaceConfig.gamePlaceId)
	if not configuredTarget or targetPlaceId == game.PlaceId then
		Log.Warn(SCOPE, `SendGroup refused unconfigured/same-place target {targetPlaceId} from PlaceId {game.PlaceId}`)
		return false
	end

	local group = normalizeGroup(players)
	if #group == 0 then
		Log.Warn(SCOPE, "SendGroup received no valid players -- handoff refused")
		return false
	end
	if #group > 50 then
		Log.Warn(SCOPE, `SendGroup received {#group} players (TeleportAsync limit is 50) -- handoff refused`)
		return false
	end

	local active = handoffs()
	for _, player in ipairs(group) do
		if player.Parent ~= Players then
			Log.Warn(SCOPE, `{player.Name}: left before group handoff preflight -- group refused`)
			return false
		end
		if active[player] then
			Log.Once(SCOPE, `teleport-reentry-{player.UserId}`, `{player.Name}: handoff already in progress -- duplicate request ignored`)
			return false
		end
		if not services_.PersistenceService.IsLoaded(player.UserId) then
			Log.Once(SCOPE, `teleport-preload-{player.UserId}`, `{player.Name}: handoff requested before profile load -- group refused (retry once loaded)`)
			return false
		end
	end

	for _, player in ipairs(group) do
		active[player] = true
		teleportData_["handoff-targets"][player] = targetPlaceId
		teleportData_["retry-attempts"][player] = 0
		teleportData_["next-release-check-at"][player] = 0
		player:SetAttribute("Teleporting", true)
	end
	for _, player in ipairs(group) do
		-- Unload includes the final save. PersistenceService associates it with a
		-- unique nonce; the loop below read-backs that nonce and the cleared lock.
		services_.PersistenceService.Unload(player.UserId, true)
	end

	local timeoutSeconds = teleportData_["release-timeout-seconds"]
	local releaseResult = Release.Wait(group, teleportData_, services_.PersistenceService)
	if releaseResult == "timeout" then
		Log.Warn(SCOPE, `group release not confirmed in {timeoutSeconds}s -- cancelling handoff to avoid stale destination reads`)
		for _, player in ipairs(group) do
			if player.Parent == Players then
				if services_.PersistenceService.IsReleased(player.UserId) then
					Recovery.Start(
						player,
						teleportData_,
						services_.PersistenceService,
						function(recoveredPlayer)
							Resync.Push(recoveredPlayer, subscriptions_)
						end
					)
				else
					clearHandoff(player)
					player:Kick("Couldn't move you between places (your save is retrying). Please rejoin.")
				end
			else
				teleportData_.Clear(player)
				services_.PersistenceService.ClearReleaseState(player.UserId)
			end
		end
		return false
	elseif releaseResult == "departed" then
		Log.Warn(SCOPE, "a player left during the release wait -- group handoff cancelled; recovering remaining players")
		recoverPresentGroup(group)
		return false
	end

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ShouldReserveServer = options.reserveServer == true
	if options.teleportData ~= nil then
		teleportOptions:SetTeleportData(options.teleportData)
	end
	local ok, result
	local attemptLimit = teleportData_["retry-attempt-limit"]
	for attempt = 1, attemptLimit do
		ok, result = pcall(TeleportService.TeleportAsync, TeleportService, targetPlaceId, group, teleportOptions)
		if ok then
			break
		end
		Log.Warn(SCOPE, `TeleportAsync to place {targetPlaceId} FAILED synchronously (attempt {attempt}/{attemptLimit}): {result}`)
		if attempt < attemptLimit then
			task.wait(teleportData_["retry-delay-seconds"])
		end
	end
	if not ok then
		Log.Warn(SCOPE, `TeleportAsync to place {targetPlaceId} exhausted synchronous retries for group of {#group}`)
		recoverPresentGroup(group)
		return false
	end

	-- Keep the guard/attribute set until PlayerRemoving confirms departure, or
	-- TeleportInitFailed recovers that individual player.
	Log.Info(SCOPE, `group of {#group} handed off to place {targetPlaceId} (reserved={options.reserveServer == true})`)
	return true
end

--API
-- Compatibility wrapper for the legacy RequestTeleport remote. Lobby -> game
-- is intentionally forbidden because game arrivals require reserved-round
-- metadata; only a game player may use this wrapper to return to the lobby.
function TeleportSubs.Send(player: Player): boolean
	if PlaceConfig.current() ~= "game" then
		Log.Once(SCOPE, "legacy-send-not-game", `RequestTeleport refused outside the game place (PlaceId {game.PlaceId}); lobby launches must use a queue`)
		return false
	end
	return TeleportSubs.SendGroup({ player }, {
		targetPlaceId = PlaceConfig.lobbyPlaceId,
		reserveServer = false,
	})
end

function TeleportSubs.Start(data, services, subscriptions)
	services_ = services
	teleportData_ = data.TeleportData
	subscriptions_ = subscriptions
	if teleportData_ == nil then
		Log.Warn(SCOPE, "TeleportData missing -- teleport handoffs disabled")
		return
	end
	teleportData_["enabled"] = false
	if services_.PersistenceService == nil then
		Log.Warn(SCOPE, "PersistenceService missing -- teleport handoffs disabled")
		return
	end
	if type(services_.PersistenceService.VerifyReleased) ~= "function"
		or type(services_.PersistenceService.ClearReleaseState) ~= "function"
	then
		Log.Warn(SCOPE, "PersistenceService release-verification API missing -- teleport handoffs disabled")
		return
	end

	local here = PlaceConfig.current()
	local target = PlaceConfig.otherPlaceId()
	if here == "unknown" or target == nil then
		Log.Warn(SCOPE, `PlaceConfig unknown/unconfigured here (PlaceId {game.PlaceId}) -- lobby/game teleport DISABLED`)
		return
	end
	Log.Info(SCOPE, `this place is '{here}'; opposite target is {target}`)
	teleportData_["enabled"] = true

	Net.Remote("RequestTeleport").OnServerEvent:Connect(function(player)
		TeleportSubs.Send(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		teleportData_.Clear(player)
		services_.PersistenceService.ClearReleaseState(player.UserId)
	end)
end

return TeleportSubs
