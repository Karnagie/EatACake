--[[
	SocialSubsClient — the two social offers' client half (R4, LOBBY partition):

	  INVITE FRIENDS (features/referrals.md)
	    `SocialService:PromptGameInvite` is CLIENT-ONLY, so the button lives here.
	    Nothing is claimed and no remote is fired: the gems are paid server-side
	    when an invited account actually joins, which can be minutes or days later
	    and on another server entirely. `ReferralUpdate` carries the count back.

	  COMMUNITY REWARD (features/group-reward.md)
	    `ClaimGroupReward` starts a server-owned wait. Two things must happen on
	    the client, and only here:
	      - the red "like the game and wait N seconds" line appears on the PRESS,
	        not a round-trip later — there is no like API to verify against, so
	        that instruction IS the mechanic;
	      - `GroupService:PromptJoinAsync` (client-only too) raises the community
	        join dialog when the server's `pending` push says the player is not a
	        member yet. They have the whole wait to accept it — the check that
	        decides the reward is the one at the END of the window.

	This module owns `AppRoot.group` (the shop's Free row reads the same field —
	ShopSubsClient routes that row here rather than claiming, so there is exactly
	ONE claim path), plus the two client-owned status lines.
]]

local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local SCOPE = "SocialClient"

-- Last-resort fallback for the red wait line. `SocialData.claimDelaySeconds` is
-- the single source (R1) and it rides EVERY GroupRewardUpdate — including the
-- join push, which lands long before the panel can be opened — so this is only
-- reached if the server never spoke at all, in which case the claim is not going
-- to resolve either. Never tune the wait here.
local FALLBACK_WAIT_SECONDS = 10

local SocialSubsClient = {}

function SocialSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	if AppRoot == nil then
		Log.Warn(SCOPE, "AppRoot missing -- invite / community reward UI wiring skipped")
		return
	end

	local rClaimGroup = Net.Remote("ClaimGroupReward")
	local uGroup = Net.Update("GroupRewardUpdate")
	local uReferral = Net.Update("ReferralUpdate")
	local localPlayer = Players.LocalPlayer

	-- Last wait length the server told us about. Not read from AppRoot state: the
	-- press handler needs it synchronously and AppRoot.Get would hand back the
	-- whole payload for one number.
	local waitSeconds = FALLBACK_WAIT_SECONDS
	-- Guards the CLIENT half of a claim (the prompt + the local status), so a
	-- double-tap cannot raise two community dialogs. The server has its own
	-- in-flight guard; this one exists so the UI never disagrees with it.
	local claimInFlight = false
	local claimGeneration = 0
	local promptOpen = false

	-- The invite panel's status line is TRANSIENT: it borrows the slot that
	-- otherwise shows "N friends joined so far", which is the number the player
	-- actually came to see. Every transient message therefore hands the slot back.
	local inviteStatusGeneration = 0
	local INVITE_STATUS_SECONDS = 6
	local function setInviteStatus(statusKey: string, statusKind: string)
		inviteStatusGeneration += 1
		local generation = inviteStatusGeneration
		AppRoot.Set({ inviteStatus = { statusKey = statusKey, statusKind = statusKind } })
		task.delay(INVITE_STATUS_SECONDS, function()
			if inviteStatusGeneration == generation then
				AppRoot.Set({ inviteStatus = false })
			end
		end)
	end

	local function setGroupStatus(statusKey: string, statusKind: string, params: { [string]: any }?, pending: boolean?)
		AppRoot.Set({
			groupClaim = {
				pending = pending == true,
				statusKey = statusKey,
				statusKind = statusKind,
				statusParams = params,
			},
		})
	end

	AppRoot.SetCallbacks({
		onInviteFriends = function()
			-- CanSendGameInviteAsync yields and can throw (it is a web capability
			-- check). A failure must degrade to a message, never to a dead button
			-- with nothing in the console (R8).
			task.spawn(function()
				local ok, canInvite = pcall(function()
					return RobloxSocialService:CanSendGameInviteAsync(localPlayer)
				end)
				if not ok then
					Log.Warn(SCOPE, `CanSendGameInviteAsync FAILED -- {canInvite}`)
				end
				if not ok or canInvite ~= true then
					setInviteStatus("invite-unavailable", "error")
					if SoundPool then
						SoundPool.Play("uiError")
					end
					return
				end
				local promptOk, err = pcall(function()
					RobloxSocialService:PromptGameInvite(localPlayer)
				end)
				if not promptOk then
					Log.Warn(SCOPE, `PromptGameInvite FAILED -- {err}`)
					setInviteStatus("invite-unavailable", "error")
				end
			end)
		end,

		onClaimGroupReward = function()
			if claimInFlight then
				return
			end
			claimInFlight = true
			claimGeneration += 1
			-- The instruction lands on the PRESS. Red, and identical whether or not
			-- the player is already a member: a claim that resolves instantly for
			-- members would teach exactly the group we are asking to like the game
			-- that they can skip that half.
			setGroupStatus("group-wait", "error", { n = waitSeconds }, true)
			rClaimGroup:FireServer()

			-- Every server-side refusal on this path is deliberately SILENT (the
			-- cooldown, the in-flight guard, an unconfigured community, a
			-- kind with no handler — all `return` without a push, because a modified
			-- client must not be able to farm replies). A silent refusal would
			-- otherwise leave the button dead and the red line frozen for the rest of
			-- the session, so the CLIENT gives up on its own.
			local generation = claimGeneration
			task.delay(waitSeconds + 15, function()
				if claimGeneration ~= generation or not claimInFlight then
					return
				end
				claimInFlight = false
				Log.Warn(SCOPE, "community reward claim got no answer -- releasing the button (try again)")
				AppRoot.Set({ groupClaim = false })
			end)
		end,
	})

	uGroup.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		AppRoot.Set({
			group = {
				configured = payload.configured == true,
				claimed = payload.claimed == true,
				groupId = payload.groupId,
				status = payload.status,
			},
		})

		-- Captured from EVERY payload (the join push carries it too), so the red
		-- wait line is already correct on the very first press.
		if type(payload.waitSeconds) == "number" then
			waitSeconds = math.max(math.floor(payload.waitSeconds), 0)
		end

		local status = payload.status
		if status == "pending" then
			setGroupStatus("group-wait", "error", { n = waitSeconds }, true)
			-- Not a member yet -> raise the community join dialog. Client-only API,
			-- yields until the player answers, and it is wrapped because it throws
			-- on an unjoinable/invalid community rather than returning a status.
			if payload.member ~= true and type(payload.groupId) == "number" and payload.groupId > 0 and not promptOpen then
				promptOpen = true
				task.spawn(function()
					local ok, result = pcall(function()
						return GroupService:PromptJoinAsync(payload.groupId)
					end)
					promptOpen = false
					if not ok then
						Log.Warn(SCOPE, `PromptJoinAsync({payload.groupId}) FAILED -- {result}`)
						return
					end
					Log.Info(SCOPE, `community join prompt closed with '{tostring(result)}'`)
				end)
			end
			return
		end

		claimInFlight = false
		if status == "granted" then
			AppRoot.Set({ groupClaim = { pending = false, statusKey = "group-granted", statusKind = "ok" } })
			if SoundPool then
				SoundPool.Play("purchaseOk")
			end
		elseif status == "not-in-group" then
			AppRoot.Set({ groupClaim = { pending = false, statusKey = "group-not-in-group", statusKind = "error" } })
			if SoundPool then
				SoundPool.Play("uiError")
			end
		elseif status == "already-claimed" then
			AppRoot.Set({ groupClaim = { pending = false, statusKey = "group-claimed", statusKind = "ok" } })
		elseif status ~= nil then
			-- A payload with a status this build does not know, or the bare
			-- resync the server sends when a grant declined: clear the local line
			-- so the panel falls back to the claimed/unclaimed default instead of
			-- freezing on "wait 10 seconds" forever.
			Log.Once(SCOPE, `group-status-{status}`, `unknown GroupRewardUpdate status '{tostring(status)}' -- local claim state cleared`)
			AppRoot.Set({ groupClaim = false })
		elseif payload.claimed ~= true then
			-- The status-less resync after a declined grant. Same reasoning.
			AppRoot.Set({ groupClaim = false })
		end
	end)

	uReferral.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		-- A fresh count is the thing the panel exists to show, so it takes the
		-- status slot back from any transient message still sitting in it.
		inviteStatusGeneration += 1
		AppRoot.Set({
			inviteStatus = false,
			referral = {
				rewarded = if type(payload.rewarded) == "number" then payload.rewarded else 0,
				rewardGems = if type(payload.rewardGems) == "number" then payload.rewardGems else 0,
			},
		})
	end)

	-- The native invite dialog closing tells us how many friends were picked. It
	-- is not the reward (that lands when they JOIN) — it is the only honest
	-- acknowledgement the button can give, and without it the press does nothing
	-- visible once the dialog is gone. Connect is pcall'd: the event is a
	-- platform surface, and a missing one must not take the whole sub down.
	local connectOk, connectErr = pcall(function()
		RobloxSocialService.GameInvitePromptClosed:Connect(function(player, recipientIds)
			if player ~= localPlayer then
				return
			end
			if type(recipientIds) == "table" and #recipientIds > 0 then
				setInviteStatus("invite-sent", "ok")
			end
		end)
	end)
	if not connectOk then
		Log.Warn(SCOPE, `GameInvitePromptClosed unavailable -- invite confirmations will not show ({connectErr})`)
	end
end

return SocialSubsClient
