--[[
	TeleportSubs — DATA-SAFE lobby<->game teleport handoff (COMMON, ADR-0009).

	One universe = one universe-scoped "PlayerProfiles" session lock per user, so
	the SOURCE place must RELEASE the profile before the DESTINATION loads it, or
	the two servers fight over the lock (stall / steal / lost writes). We use the
	"Option A" single-writer handoff (recommended in the split design):

	  1. re-entrancy guard (one teleport per player at a time)
	  2. set the "Teleporting" attribute (client freezes input / shows a transition)
	  3. fold the leave-time bookkeeping (TimeRewardService) BEFORE the final save
	  4. PersistenceService.Save(userId)          -- explicit; Unload also saves
	  5. PersistenceService.Unload(userId, true)  -- INTENTIONAL release: the
	     intentionalRelease flag suppresses the "session-taken" kick (Phase 2)
	  6. WAIT for the release to actually commit (profiles[userId] == nil)
	  7. TeleportAsync; on failure RE-ACQUIRE the profile so the player isn't
	     stranded profile-less (release succeeded but teleport didn't).

	The destination place runs the UNCHANGED LoadProfile — the lock is already
	free, so it reads fresh, fully-saved data. NEVER Steal=true (P5): that skips
	the source's final save and drops writes.

	VERIFY ON PUBLISHED PLACES ONLY — Studio mock DataStores are per-VM and share
	no lock, so cross-place session behaviour is invisible in Studio.

	Trigger: the RequestTeleport remote (a HUD "Play"/"Return" button), or call
	TeleportSubs.Send(player) from a scene pad's ProximityPrompt subscription.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local PlaceConfig = require(Shared:WaitForChild("config"):WaitForChild("PlaceConfig"))

local SCOPE = "Teleport"
local RELEASE_TIMEOUT = 10 -- seconds to wait for the source lock to release

local TeleportSubs = {}

local services_
-- Wiring state (not game data): who is mid-handoff, so a double-tap can't
-- release twice or teleport a player already leaving.
local teleporting: { [Player]: boolean } = {}

--API
-- Release the profile safely, then teleport `player` to the OTHER place. Returns
-- false (and leaves the player put, data intact) if teleport is unavailable or
-- fails. Safe to call from a remote handler or a scene-pad subscription.
function TeleportSubs.Send(player: Player): boolean
	local targetPlaceId = PlaceConfig.otherPlaceId()
	if targetPlaceId == nil or targetPlaceId == 0 then
		Log.Once(SCOPE, "no-target", `teleport requested but PlaceConfig is unset/unknown here (PlaceId {game.PlaceId}) — set PlaceConfig.lobbyPlaceId/gamePlaceId after publishing`)
		return false
	end
	if teleporting[player] then
		return false -- already handing off
	end
	local userId = player.UserId
	teleporting[player] = true
	player:SetAttribute("Teleporting", true)

	if services_.PersistenceService.IsLoaded(userId) then
		-- Fold leave-time bookkeeping BEFORE the final save (mirrors PlayerRemoving;
		-- EndSession is idempotent, so the later PlayerRemoving one is a no-op).
		services_.TimeRewardService.EndSession(userId)
		services_.PersistenceService.Save(userId)
		services_.PersistenceService.Unload(userId, true) -- intentional: no kick

		local deadline = os.clock() + RELEASE_TIMEOUT
		while services_.PersistenceService.IsLoaded(userId) do
			if player.Parent ~= Players then
				teleporting[player] = nil
				return false -- left during the release
			end
			if os.clock() > deadline then
				-- Release never confirmed — do NOT teleport into a lock race.
				-- Re-anchor the playtime session; the player stays put, data intact.
				Log.Warn(SCOPE, `release not confirmed for {player.Name} in {RELEASE_TIMEOUT}s — teleport aborted`)
				services_.TimeRewardService.BeginSession(userId)
				player:SetAttribute("Teleporting", nil)
				teleporting[player] = nil
				return false
			end
			task.wait(0.1)
		end
	end

	if player.Parent ~= Players then
		teleporting[player] = nil
		return false
	end

	local options = Instance.new("TeleportOptions")
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(targetPlaceId, { player }, options)
	end)
	if not ok then
		-- Released but not teleported: re-acquire the lock so the player isn't
		-- stranded profile-less (their data is unchanged — it round-tripped the
		-- DataStore on the release-save, and we reload the same bytes).
		Log.Warn(SCOPE, `TeleportAsync to place {targetPlaceId} FAILED for {player.Name}: {err} — reloading profile`)
		local profile = services_.PersistenceService.LoadProfile(player)
		if profile then
			services_.TimeRewardService.BeginSession(userId)
		end
		player:SetAttribute("Teleporting", nil)
		teleporting[player] = nil
		return false
	end
	-- Success: the player is leaving. teleporting[player] is cleared on
	-- PlayerRemoving; PlayerRemoving's Unload/EndSession are safe no-ops (already
	-- released / idempotent).
	Log.Info(SCOPE, `{player.Name} handed off to place {targetPlaceId}`)
	return true
end

function TeleportSubs.Start(data, services, subscriptions)
	services_ = services

	local here = PlaceConfig.current()
	if here == "unknown" then
		Log.Warn(SCOPE, `PlaceConfig is unset/unknown here (PlaceId {game.PlaceId}) — lobby<->game teleport DISABLED. Set PlaceConfig.lobbyPlaceId/gamePlaceId after publishing both places to one universe.`)
	else
		Log.Info(SCOPE, `this place is '{here}'; RequestTeleport sends players to the opposite place`)
	end

	Net.Remote("RequestTeleport").OnServerEvent:Connect(function(player)
		-- Server-authoritative: the destination is always the opposite place
		-- (no client-chosen target to validate). Rate-limited by the handoff
		-- guard (teleporting[player]).
		TeleportSubs.Send(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
	end)
end

return TeleportSubs
