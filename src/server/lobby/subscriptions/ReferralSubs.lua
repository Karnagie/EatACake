--[[
	ReferralSubs — friend referrals: 500 gems to the INVITER, once per invited
	account (features/referrals.md, R4).

	Two halves that never run for the same player at the same time:

	  ATTRIBUTION (the invitee's join). Roblox fills
	  `Player:GetJoinData().ReferredByPlayerId` for every kind of invite. The first
	  time an account joins carrying one, it is stamped permanently into that
	  account's `social.referredBy` and a payment is sent to the inviter. That stamp
	  is the load-bearing anti-abuse gate: an account can be re-invited any number
	  of times and only ever pays out once, forever, across servers. It says
	  nothing about MANY accounts, so `SocialData.referral.minInviteeAccountAgeDays`
	  adds a floor under the throwaway-account farm.

	  PAYMENT (the inviter's session). The inviter is usually NOT on this server —
	  Roblox drops the friend into whichever server has room — and is often not
	  online at all, so the payment is a ProfileStore MESSAGE
	  (`PersistenceService.SendMessage`, see its header) rather than a direct
	  write. It lands in their active session, or waits — intact — until their next
	  load. The handler grants the gems, counts the referral, saves, and only then
	  calls `processed()`. ⚠ Because this module is lobby-only, the handler only
	  exists in the LOBBY: a message that arrives while the inviter is in a match
	  simply stays queued until they come back. Nothing is lost, but it is not
	  instant for them.

	ReferralUpdate payload: { rewarded, rewardGems } — the panel's "N friends
	joined" number and the advertised per-friend figure. Pushed on join and after
	every payment.

	⚠ LOBBY partition. The invite prompt itself is client-side and lives in the
	lobby HUD, the public place is the lobby, and a reserved game server is not
	reachable by an invite link — so a `ReferredByPlayerId` can only ever arrive
	here. It must NOT move to common: the game place's join data is teleport data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

-- Resolved from the subscriptions registry in Start (COMMON partition), like
-- every other cross-sub reference in this codebase — a static sibling require
-- would break the lobby/game split.
local RewardGrantSubs

local SCOPE = "ReferralSubs"
local MESSAGE_TYPE = "referral"

local ReferralSubs = {}

local SocialService, PersistenceService, profileData
local uReferral

local function statePayload(userId: number)
	return {
		rewarded = SocialService.ReferralsRewarded(userId),
		rewardGems = SocialService.ReferralDisplayGems(),
	}
end

local function pushState(player: Player)
	if uReferral == nil then
		Log.Warn(SCOPE, `pushState({player.Name}) before Start ran — push dropped`)
		return
	end
	uReferral:FireClient(player, statePayload(player.UserId))
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function ReferralSubs.PushInitialState(player: Player)
	pushState(player)
end

--API
-- Runs BEFORE anything is replicated (PlayerLifecycleSubs' OnProfileLoaded hook).
-- Attribution has to happen here rather than on PlayerAdded: the read is trivial,
-- but the STAMP is a profile mutation, and doing it before the push gate opens is
-- what guarantees the client's first ReferralUpdate already reflects it.
-- The payment itself yields on a DataStore write, so it is spawned — the join
-- must never wait on it.
function ReferralSubs.OnProfileLoaded(player: Player)
	if SocialService == nil or PersistenceService == nil then
		-- A player who joined in the window between PlayerLifecycleSubs.Start (which
		-- arms PlayerAdded) and this module's own Start. Their invite goes unpaid;
		-- say so rather than throwing inside the join path (R8).
		Log.Warn(SCOPE, `OnProfileLoaded({player.Name}) ran before Start — referral attribution skipped`)
		return
	end
	local userId = player.UserId

	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		-- GetJoinData throws for a player who left mid-load. Not an error worth a
		-- warn on every disconnect, but never silent either (R8).
		Log.Info(SCOPE, `join data unavailable for {userId} — no referral attribution`)
		return
	end

	local referrerId = math.floor(tonumber(joinData.ReferredByPlayerId) or 0)
	if referrerId <= 0 then
		return -- ordinary join, not an invite. The overwhelming majority.
	end
	if referrerId == userId then
		Log.Warn(SCOPE, `{userId} joined referred by THEMSELVES — ignored`)
		return
	end
	-- Throwaway-account gate. The per-invitee stamp below makes one account pay
	-- ONCE; it does nothing about MANY accounts, which is the whole alt-farm.
	-- `AccountAge` is free (no web call) and kills the cheapest version of that
	-- loop — create, join, collect, repeat, all inside one sitting — while
	-- costing a real friend who signed up yesterday nothing. It is a floor, not a
	-- solution: a patient farmer still gets through, so watch the payout rate.
	local minAgeDays = SocialService.ReferralMinInviteeAgeDays()
	if player.AccountAge < minAgeDays then
		Log.Info(SCOPE, `{userId} was invited by {referrerId} but its account is {player.AccountAge}d old (< {minAgeDays}d) — not attributed, not paid`)
		return
	end
	if SocialService.ReferredBy(userId) ~= 0 then
		-- Already counted for somebody, at some point, on some server. Re-inviting
		-- the same account is the obvious farm, and this is where it dies.
		Log.Info(SCOPE, `{userId} was already attributed — referral by {referrerId} ignored`)
		return
	end
	if not SocialService.MarkReferredBy(userId, referrerId) then
		Log.Warn(SCOPE, `could not attribute {userId} to {referrerId} (profile not loaded?) — no payment sent`)
		return
	end

	-- Both halves YIELD, so they run off the join path — nothing here may delay a
	-- player entering the lobby.
	task.spawn(function()
		-- COMMIT THE STAMP BEFORE QUEUEING THE MONEY. `Save` is fire-and-forget
		-- (ProfileStore spawns it), so a crash in that window would leave this
		-- account unstamped with a payment already queued — and the same friend
		-- would pay the same inviter again on their next join. `SaveAndWait` is
		-- the money-path save this codebase already uses for receipts (ADR-0014),
		-- and the ordering is the same rule: never tell an external system about a
		-- grant whose anti-duplicate mark has not landed.
		if not PersistenceService.SaveAndWait(userId) then
			Log.Warn(
				SCOPE,
				`referral stamp for {userId} did NOT commit — payment to {referrerId} withheld (it would be re-payable on their next join)`
			)
			return
		end
		local sent = PersistenceService.SendMessage(referrerId, {
			type = MESSAGE_TYPE,
			from = userId,
		})
		if sent then
			Log.Info(SCOPE, `referral payment queued: {userId} -> inviter {referrerId}`)
		else
			-- The stamp is committed, so this inviter will never be paid for this
			-- friend. Loud on purpose: it is the one lossy edge in the feature.
			Log.Warn(SCOPE, `referral payment for {userId} could NOT be queued to {referrerId} — inviter goes unpaid`)
		end
	end)
end

function ReferralSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	SocialService = services.SocialService
	PersistenceService = services.PersistenceService
	profileData = data.PlayerProfileData
	uReferral = Net.Update("ReferralUpdate")

	-- Config validation, DEFERRED (R8: a late-arriving dependency must never
	-- false-positive). Grant kinds are registered inside `RewardGrantSubs.Start`,
	-- and subscriptions Start in sorted name order — "ReferralSubs" sorts BEFORE
	-- "RewardGrantSubs" ('f' < 'w'), so a HasHandler check here would be false on
	-- every single boot and would claim inviters go unpaid while the payout works
	-- perfectly. Same pattern, and the same reason, as GroupRewardSubs.
	task.defer(function()
		local descriptor = SocialService.ReferralDescriptor()
		if RewardGrantSubs == nil then
			Log.Warn(SCOPE, "RewardGrantSubs missing — referral payments cannot be granted")
		elseif not RewardGrantSubs.HasHandler(descriptor.kind) then
			Log.Warn(SCOPE, `SocialData.referral.reward kind '{tostring(descriptor.kind)}' has no grant handler — inviters will not be paid`)
		end
	end)

	-- The inviter's side. Registered at Start so LoadProfile can attach it to
	-- every session it opens from here on (PersistenceService header).
	PersistenceService.RegisterMessageHandler(MESSAGE_TYPE, function(player: Player, message, processed)
		if message.type ~= MESSAGE_TYPE then
			return -- another feature's message; its own handler will take it
		end
		local userId = player.UserId
		if RewardGrantSubs == nil then
			Log.Warn(SCOPE, `referral payment for {userId} cannot be granted (no RewardGrantSubs) — stays queued`)
			return
		end
		if not PersistenceService.IsLoaded(userId) then
			-- The session ended between delivery and this handler running. NOT
			-- processed: it is re-delivered next load rather than paid into nothing.
			Log.Warn(SCOPE, `referral payment for {userId} arrived with no loaded profile — stays queued`)
			return
		end
		if profileData.releaseNonces[userId] ~= nil then
			-- Mid-teleport-release: every write from here is discarded. Leaving the
			-- message unprocessed is exactly right (ADR-0014's rule, and the reason
			-- the queue exists at all). ⚠ It is NOT re-delivered by the game place —
			-- this module is lobby-only, so nothing there registers a handler and
			-- the message simply waits, intact, until they are next in the lobby.
			Log.Info(SCOPE, `referral payment for {userId} arrived mid-teleport-release — stays queued for the next load`)
			return
		end
		local granted = RewardGrantSubs.Grant(player, SocialService.ReferralDescriptor(), "referral")
		if granted == nil then
			Log.Warn(SCOPE, `referral grant DECLINED for {userId} — message stays queued (check SocialData.referral.reward)`)
			return
		end
		local total = SocialService.CountReferral(userId)
		-- Consume, then persist. The order is deliberate: `processed()` only takes
		-- effect once a save commits, so saving after it is what actually retires
		-- the message. A crash in this window re-delivers it and over-pays by one —
		-- the safe direction, since the alternative loses the reward entirely.
		processed()
		PersistenceService.Save(userId)
		pushState(player)
		Log.Sum(SCOPE, `referral reward paid to {player.Name} (friend #{total or "?"}, from {tostring(message.from)})`)
	end)
end

return ReferralSubs
