--[[
	GroupRewardSubs — one-time "join the group" reward domain (R4).

	ClaimGroupReward: verify LIVE membership (SocialService.IsInGroup —
	YIELDS on a web request), grant via RewardGrantSubs, mark claimed,
	persist, push the outcome. There is NO like/favorite verification
	(Roblox exposes none) — membership alone gates the reward.

	GroupRewardUpdate payload:
	  { configured, claimed, groupId, status?, granted? }
	status ∈ "granted" | "not-in-group" | "already-claimed".

	Anti-spam: in-flight guard + per-player cooldown (the membership check is
	a web request a modified client could hammer).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "GroupRewardSubs"

local GroupRewardSubs = {}

local SocialService, PersistenceService
local uGroup

-- Wiring state: pending[userId] = in-flight guard, lastAttempt[userId] = os.time().
local pending = {}
local lastAttempt = {}

local function statePayload(userId: number, status: string?, granted)
	return {
		configured = SocialService.IsConfigured(),
		claimed = SocialService.IsRewardClaimed(userId),
		groupId = SocialService.GroupId(),
		status = status,
		granted = granted,
	}
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

function GroupRewardSubs.Start(data, services)
	local socialData = data.SocialData
	SocialService = services.SocialService
	PersistenceService = services.PersistenceService
	uGroup = Net.Update("GroupRewardUpdate")

	if not (type(socialData.groupId) == "number" and socialData.groupId > 0) then
		Log.Warn(SCOPE, "SocialData.groupId is not set — group reward disabled (claims refused, client row hidden)")
	end

	Net.Remote("ClaimGroupReward").OnServerEvent:Connect(function(player)
		local userId = player.UserId

		if not SocialService.IsConfigured() then
			return
		end
		if SocialService.IsRewardClaimed(userId) then
			uGroup:FireClient(player, statePayload(userId, "already-claimed"))
			return
		end
		if pending[userId] then
			return
		end
		local now = os.time()
		if lastAttempt[userId] and (now - lastAttempt[userId]) < socialData.claimCooldownSeconds then
			return
		end
		local descriptor = SocialService.RewardDescriptor()
		if not RewardGrantSubs.HasHandler(descriptor.kind) then
			Log.Warn(SCOPE, `SocialData.reward kind '{tostring(descriptor.kind)}' has no grant handler`)
			return
		end
		lastAttempt[userId] = now
		pending[userId] = true

		local inGroup = SocialService.IsInGroup(userId) -- YIELDS

		-- Re-checks after the yield: the player may have left, or claimed
		-- via a concurrent request.
		if player.Parent ~= Players then
			pending[userId] = nil
			return
		end
		if SocialService.IsRewardClaimed(userId) then
			pending[userId] = nil
			uGroup:FireClient(player, statePayload(userId, "already-claimed"))
			return
		end
		if not inGroup then
			pending[userId] = nil
			uGroup:FireClient(player, statePayload(userId, "not-in-group"))
			return
		end

		if not PersistenceService.IsLoaded(userId) then
			pending[userId] = nil
			return -- session ended while we yielded on the web request
		end

		local granted = RewardGrantSubs.Grant(player, descriptor, "group")
		if granted == nil then
			-- Grant declined (mistuned reward): do NOT consume the one-time
			-- flag for nothing.
			Log.Warn(SCOPE, "group reward grant declined — claim NOT consumed (check SocialData.reward)")
			pending[userId] = nil
			uGroup:FireClient(player, statePayload(userId))
			return
		end
		SocialService.MarkRewardClaimed(userId)
		PersistenceService.Save(userId)
		pending[userId] = nil
		uGroup:FireClient(player, statePayload(userId, "granted", granted))
		Log.Info(SCOPE, `group reward granted to {player.Name}`)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pending[player.UserId] = nil
		lastAttempt[player.UserId] = nil
	end)

	-- Config validation (after all Starts — grant kinds must be registered).
	task.defer(function()
		local reward = socialData.reward
		if type(reward) ~= "table" or not RewardGrantSubs.HasHandler(reward.kind) then
			warn("[GroupRewardSubs] SocialData.reward kind is missing/unregistered — claims would be refused")
		elseif reward.kind == "gold" and math.floor(tonumber(reward.amount) or 0) <= 0 then
			warn("[GroupRewardSubs] SocialData.reward gold amount <= 0 — grants would decline")
		end
	end)
end

return GroupRewardSubs
