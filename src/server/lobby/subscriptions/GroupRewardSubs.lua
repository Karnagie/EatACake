--[[
	GroupRewardSubs — the one-time "like the game + join the community" reward
	(R4, features/group-reward.md).

	There is NO like/favorite API on Roblox — none, for anyone — so "did they
	like it?" is unanswerable and the reward is deliberately built around that:
	the player is asked to like the game and WAIT, and the boost lands
	`SocialData.claimDelaySeconds` later provided the one thing that IS verifiable,
	community membership, holds at the END of the wait. A player who was already a
	member takes the identical path — same message, same wait — because a claim
	that resolves instantly for members and slowly for everyone else teaches the
	fast group to skip the like.

	ClaimGroupReward (no args) ->
	  1. guards (configured / not claimed / not pending / cooldown / handler+ready)
	  2. LIVE membership check (SocialService.IsInGroup — YIELDS on a web request)
	  3. push `pending` carrying `member`, so the CLIENT knows whether to raise the
	     community join prompt (GroupService:PromptJoinAsync is client-only)
	  4. wait out the window
	  5. LIVE re-check — this is the one that decides. Joining during the wait
	     counts; leaving during it does not.
	  6. grant -> mark claimed -> Save -> push `granted`

	GroupRewardUpdate payload:
	  { configured, claimed, groupId, status?, member?, waitSeconds?, granted? }
	status ∈ "pending" | "granted" | "not-in-group" | "already-claimed".

	Anti-spam: in-flight guard + per-player cooldown (each claim spends TWO web
	requests, and a modified client can fire the remote as fast as it likes).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
-- Resolved from the subscriptions registry in Start (RewardGrantSubs lives in
-- the COMMON partition; a static script.Parent require breaks once this sub
-- moves to the lobby partition — see the lobby/game split).
local RewardGrantSubs

local SCOPE = "GroupRewardSubs"

local GroupRewardSubs = {}

local SocialService, PersistenceService
local uGroup

-- Wiring state: pending[userId] = in-flight guard, lastAttempt[userId] = os.time().
local pending = {}
local lastAttempt = {}

local function statePayload(userId: number, status: string?, extra: { [string]: any }?)
	local payload = {
		configured = SocialService.IsConfigured(),
		claimed = SocialService.IsRewardClaimed(userId),
		groupId = SocialService.GroupId(),
		status = status,
		-- On EVERY payload, including the join push. The client shows the red
		-- "like the game and wait {n} seconds" line the instant GET REWARD is
		-- pressed — before any reply exists — so it must already know the real
		-- number by then, or its own fallback constant becomes a second source of
		-- truth for a value this data module owns (R1).
		waitSeconds = SocialService.ClaimDelaySeconds(),
	}
	for key, value in pairs(extra or {}) do
		payload[key] = value
	end
	return payload
end

--API
-- Push the claimed/configured state on join (called by PlayerLifecycleSubs).
function GroupRewardSubs.SendState(player: Player)
	if uGroup == nil then
		Log.Warn(SCOPE, `SendState({player.Name}) before Start ran — push dropped`)
		return
	end
	uGroup:FireClient(player, statePayload(player.UserId))
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function GroupRewardSubs.PushInitialState(player: Player)
	GroupRewardSubs.SendState(player)
end

function GroupRewardSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	local socialData = data.SocialData
	SocialService = services.SocialService
	PersistenceService = services.PersistenceService
	uGroup = Net.Update("GroupRewardUpdate")

	if not (type(socialData.groupId) == "number" and socialData.groupId > 0) then
		Log.Warn(SCOPE, "SocialData.groupId is not set — group reward disabled (claims refused, client panel hidden)")
	end

	-- The claim RUNS FOR ~10 SECONDS across two web requests, so its guards have to
	-- outlive every one of them: `pending` is the in-flight lock, `lastAttempt`
	-- spaces out COMPLETED attempts. `owned.started` is flipped at the exact line
	-- that takes the lock, so the caller below can release it on EVERY exit —
	-- including a raised error — while a call that never took it releases nothing.
	local function claim(player: Player, owned: { started: boolean })
		local userId = player.UserId

		if not SocialService.IsConfigured() then
			return
		end
		if pending[userId] then
			return
		end
		-- Cooldown is measured from the last RESOLUTION, not the last press: a
		-- claim takes the whole wait plus two web round-trips, so a cooldown timed
		-- from the press would silently refuse the immediate retry that the
		-- "Join the community first, then try again" copy explicitly invites.
		if lastAttempt[userId] and (os.time() - lastAttempt[userId]) < socialData.claimCooldownSeconds then
			return
		end
		-- Below the spam guards on purpose: this echo is client-triggered and
		-- otherwise unbounded, and the panel already knows it is claimed (the
		-- button is dead and the line reads "Already claimed") — this only
		-- re-syncs a client whose state drifted.
		if SocialService.IsRewardClaimed(userId) then
			uGroup:FireClient(player, statePayload(userId, "already-claimed"))
			return
		end
		local descriptor = SocialService.RewardDescriptor()
		if not RewardGrantSubs.HasHandler(descriptor.kind) then
			Log.Warn(SCOPE, `SocialData.reward kind '{tostring(descriptor.kind)}' has no grant handler`)
			return
		end
		-- "Deliverable to THIS player right now", checked BEFORE the wait rather
		-- than after it: `HasHandler` only answers "this place can grant that kind"
		-- (ADR-0018), and finding out at t+10s that it cannot is a player who
		-- watched a countdown for nothing.
		local isReady, reason = RewardGrantSubs.IsReady(player, descriptor)
		if not isReady then
			Log.Warn(SCOPE, `group reward not deliverable to {player.Name} — {tostring(reason)}; claim refused`)
			return
		end
		-- Past every guard: this is a REAL attempt, so it takes the in-flight lock
		-- and (on the way out) the cooldown stamp. Both belong to THIS call now.
		pending[userId] = true
		owned.started = true

		-- First LIVE check. Its only job is to decide whether the client raises the
		-- community join prompt — the check that DECIDES the reward is the second
		-- one, after the wait.
		local memberBefore = SocialService.IsInGroup(userId) -- YIELDS
		if player.Parent ~= Players then
			return
		end
		if SocialService.IsRewardClaimed(userId) then
			uGroup:FireClient(player, statePayload(userId, "already-claimed"))
			return
		end

		local waitSeconds = SocialService.ClaimDelaySeconds()
		uGroup:FireClient(player, statePayload(userId, "pending", { member = memberBefore }))

		task.wait(waitSeconds)

		if player.Parent ~= Players then
			return
		end
		-- Re-checks after the yields: the player may have claimed via a concurrent
		-- request, or their session may have ended (teleport into a match).
		if SocialService.IsRewardClaimed(userId) then
			uGroup:FireClient(player, statePayload(userId, "already-claimed"))
			return
		end

		local inGroup = SocialService.IsInGroup(userId) -- YIELDS
		if player.Parent ~= Players then
			return
		end
		if not inGroup then
			uGroup:FireClient(player, statePayload(userId, "not-in-group", { member = false }))
			return
		end

		if not PersistenceService.IsLoaded(userId) then
			-- R8: never return silently from a failure path. The session ended
			-- while we were on a web request (left, or the match teleport took
			-- them); the one-time flag is untouched, so the claim survives.
			Log.Info(SCOPE, `group reward for {userId} resolved with no loaded profile — claim NOT consumed`)
			return
		end
		-- Mid-teleport-release: the profile is being handed to the game place and
		-- every write from here on is thrown away (PersistenceService.Save refuses
		-- outright), so granting now would mark the ONE-TIME claim consumed and
		-- deliver nothing. The claim survives; they can press it again after the
		-- handoff. Same rule the money path uses (ShopSubs, ADR-0014).
		if data.PlayerProfileData.releaseNonces[userId] ~= nil then
			Log.Warn(SCOPE, `group reward for {player.Name} landed mid-teleport-release — claim NOT consumed, retry after the handoff`)
			uGroup:FireClient(player, statePayload(userId))
			return
		end

		local granted = RewardGrantSubs.Grant(player, descriptor, "group")
		if granted == nil then
			-- Grant declined (mistuned reward): do NOT consume the one-time
			-- flag for nothing.
			Log.Warn(SCOPE, "group reward grant declined — claim NOT consumed (check SocialData.reward)")
			uGroup:FireClient(player, statePayload(userId))
			return
		end
		SocialService.MarkRewardClaimed(userId)
		PersistenceService.Save(userId)
		uGroup:FireClient(player, statePayload(userId, "granted", { member = true, granted = granted }))
		Log.Info(SCOPE, `group reward granted to {player.Name}`)
	end

	Net.Remote("ClaimGroupReward").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		-- pcall'd, and the guards released in ONE place: the body spans two web
		-- requests and a 10-second wait, and anything raised in there would
		-- otherwise leave `pending[userId]` set for the rest of the session — a
		-- player who could never claim again, with nothing in the console.
		local owned = { started = false }
		local ok, err = pcall(claim, player, owned)
		-- ⚠ Only the call that TOOK the lock releases it. A press refused because
		-- another claim is already running must not clear that claim's lock.
		-- The cooldown is stamped at RESOLUTION and only for a real attempt:
		-- stamping a refused press would let a spamming client push its own
		-- cooldown forward forever while punishing the honest double-tap.
		if owned.started then
			pending[userId] = nil
			lastAttempt[userId] = os.time()
		end
		if not ok then
			Log.Warn(SCOPE, `group reward claim for {player.Name} FAILED — {err}; claim NOT consumed, they can retry`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player.UserId] = nil
		lastAttempt[player.UserId] = nil
	end)

	-- Config validation (after all Starts — grant kinds must be registered).
	task.defer(function()
		-- Through Log, not a raw `warn` (R8): the `[Server/GroupRewardSubs]` prefix
		-- is the contract every console grep is built on, and these are exactly the
		-- lines an operator filters for. The pre-2026-08-05 version of this block
		-- bypassed it.
		local reward = socialData.reward
		if type(reward) ~= "table" or not RewardGrantSubs.HasHandler(reward.kind) then
			Log.Warn(SCOPE, "SocialData.reward kind is missing/unregistered — claims would be refused")
		elseif reward.kind == "boost" and type(reward.boostId) ~= "string" then
			Log.Warn(SCOPE, "SocialData.reward has no boostId — the boost grant would decline")
		elseif reward.kind == "gems" and math.floor(tonumber(reward.amount) or 0) <= 0 then
			Log.Warn(SCOPE, "SocialData.reward gems amount <= 0 — grants would decline")
		end
		-- The wait is the whole mechanic; a zero one turns the reward into a plain
		-- membership check and quietly drops the "like the game" half.
		if SocialService.ClaimDelaySeconds() <= 0 then
			Log.Warn(SCOPE, "SocialData.claimDelaySeconds is 0 — the reward grants instantly and no longer asks for a like")
		end
	end)
end

return GroupRewardSubs
