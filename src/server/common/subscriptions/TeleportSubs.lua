--[[
	TeleportSubs — DATA-SAFE lobby<->game teleport handoff (COMMON, ADR-0009).

	One universe = one universe-scoped "PlayerProfiles" session lock per user, so
	the SOURCE place must RELEASE the profile (and the release must actually
	COMMIT) before the DESTINATION loads it, or the two servers fight over the
	lock (stall / steal / lost writes). "Option A" single-writer handoff:

	  1. re-entrancy guard (one teleport per player at a time)
	  2. set the "Teleporting" attribute (client freezes input / shows a transition)
	  3. fold the leave-time bookkeeping (TimeRewardService) before the release
	  4. PersistenceService.Unload(userId, true)  -- INTENTIONAL release: the
	     intentionalRelease flag suppresses the "session-taken" kick (Phase 2)
	  5. WAIT for PersistenceService.IsReleased(userId) -- the ending save's
	     OnAfterSave, i.e. the on-disk lock is actually CLEARED. NOT IsLoaded:
	     ProfileStore fires OnSessionEnd (which clears profiles[]) BEFORE the
	     release write commits, so IsLoaded flips too early (ProfileStore.luau:725
	     vs 924). Waiting on IsLoaded would teleport into a lock race.
	  6. TeleportAsync; on failure — SYNC (pcall) or ASYNC (TeleportInitFailed) —
	     RE-ACQUIRE the profile (the lock is free) so the player isn't stranded.

	The destination runs the UNCHANGED LoadProfile — the lock is free, so it reads
	fresh, fully-saved data. NEVER Steal=true (P5): that skips the source's final
	save and drops writes.

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
local RELEASE_TIMEOUT = 12 -- seconds to wait for the source lock to actually commit-release

local TeleportSubs = {}

local services_
-- Wiring state (not game data): who is mid-handoff, so a double-tap can't
-- release twice or teleport a player already leaving.
local teleporting: { [Player]: boolean } = {}

-- Re-acquire the profile for a player whose teleport FAILED after we already
-- released it. The lock is free (the release committed before we ever called
-- TeleportAsync), so LoadProfile re-locks cleanly and the player isn't left
-- profile-less. Their data is unchanged (saved then reloaded), so no re-push.
local function recoverStranded(player: Player)
	local userId = player.UserId
	if player.Parent == Players and not services_.PersistenceService.IsLoaded(userId) then
		local profile = services_.PersistenceService.LoadProfile(player)
		if profile then
			services_.TimeRewardService.BeginSession(userId)
			Log.Info(SCOPE, `re-acquired profile for {player.Name} after a failed teleport`)
		end
	end
	player:SetAttribute("Teleporting", nil)
	teleporting[player] = nil
end

--API
-- Release the profile safely, then teleport `player` to the OTHER place. Returns
-- false (and leaves the player put/recovered, data intact) if teleport is
-- unavailable or fails. Safe from a remote handler or a scene-pad subscription.
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

	if not services_.PersistenceService.IsLoaded(userId) then
		-- No loaded profile to release (still joining, or already gone). Teleporting
		-- now could race the in-flight LoadProfile for the lock — abort; the player
		-- can retry once loaded. (Never teleport without a confirmed source release.)
		Log.Once(SCOPE, `teleport-preload-{userId}`, `{player.Name}: RequestTeleport before profile load — ignored (retry once loaded)`)
		player:SetAttribute("Teleporting", nil)
		teleporting[player] = nil
		return false
	end
	do
		-- Fold leave-time bookkeeping BEFORE the release (mirrors PlayerRemoving;
		-- EndSession is idempotent, so the later PlayerRemoving one is a no-op).
		services_.TimeRewardService.EndSession(userId)
		-- Release: EndSession's final save + lock-clear. Unload(intentional) wires
		-- the committed-release signal (OnAfterSave -> IsReleased) and suppresses
		-- the kick. EndSession is fire-and-forget (it retries until it succeeds).
		services_.PersistenceService.Unload(userId, true)

		-- WAIT for the release to actually COMMIT (lock cleared) — not merely for
		-- OnSessionEnd. The destination must read fully-saved data.
		local deadline = os.clock() + RELEASE_TIMEOUT
		while not services_.PersistenceService.IsReleased(userId) do
			if player.Parent ~= Players then
				teleporting[player] = nil
				return false -- left during the release; the release save still completes
			end
			if os.clock() > deadline then
				-- The release save is retrying (DataStore trouble) and WILL eventually
				-- commit, but we can't confirm the lock is clear — teleporting now would
				-- risk a stale destination read. Safest: kick (the data IS being saved
				-- by the retrying release); the player rejoins fresh. Rare.
				Log.Warn(SCOPE, `release not confirmed for {player.Name} in {RELEASE_TIMEOUT}s — kicking to avoid a stale cross-place read (the release save keeps retrying)`)
				player:SetAttribute("Teleporting", nil)
				teleporting[player] = nil
				player:Kick("Couldn't move you between places (your save is retrying). Please rejoin.")
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
		-- SYNCHRONOUS failure (bad args / immediate throttle). ASYNC failures are
		-- caught by TeleportInitFailed (see Start). Either way -> recover the lock.
		Log.Warn(SCOPE, `TeleportAsync to place {targetPlaceId} FAILED (sync) for {player.Name}: {err}`)
		recoverStranded(player)
		return false
	end
	-- Success so far — but the teleport can still fail ASYNC (TeleportInitFailed).
	-- Keep teleporting[player]/Teleporting set; cleared on PlayerRemoving (actual
	-- departure) or by the TeleportInitFailed handler (recover).
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
		-- Server-authoritative: the destination is always the opposite place (no
		-- client-chosen target). Rate-limited by the handoff guard.
		TeleportSubs.Send(player)
	end)

	-- ASYNC teleport failure: TeleportAsync returned ok but the move failed later
	-- (place unavailable, reserved-server flood, moderation). The profile is
	-- already released -> recover so the player isn't stranded profile-less.
	TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
		if teleporting[player] then
			Log.Warn(SCOPE, `TeleportInitFailed for {player.Name}: {teleportResult} — {errorMessage} — recovering`)
			recoverStranded(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		teleporting[player] = nil
	end)
end

return TeleportSubs
