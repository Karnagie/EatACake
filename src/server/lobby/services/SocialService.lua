--[[
	SocialService
	Logic over the profile's `social` section (R2): the one-time group-join
	reward AND referral attribution/counting. Config (groupId, reward, referral)
	comes from SocialData.

	Membership is checked LIVE with GroupService:GetGroupsAsync —
	Player:IsInGroup/GetRankInGroup are cached from server-join time, so a
	player who joins the group mid-session would still read as a non-member.
	GetGroupsAsync hits the web (YIELDS) and sees a fresh join.

	R3: does NOT grant. Validates + marks; GroupRewardSubs grants + notifies.
]]

local GroupService = game:GetService("GroupService")

local SocialService = {}

local profileData, socialData

function SocialService.Init(data)
	profileData = data.PlayerProfileData
	socialData = data.SocialData
end

local function section(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.social
end

--API
function SocialService.IsConfigured(): boolean
	return type(socialData.groupId) == "number" and socialData.groupId > 0
end

--API
function SocialService.GroupId(): number
	return socialData.groupId
end

--API
function SocialService.IsRewardClaimed(userId: number): boolean
	local social = section(userId)
	return social ~= nil and social.groupRewardClaimed == true
end

--API
function SocialService.MarkRewardClaimed(userId: number)
	local social = section(userId)
	if social then
		social.groupRewardClaimed = true
	end
end

--API
-- LIVE membership check (YIELDS on a web request). Web errors are treated
-- as "not a member" (fail closed — the player can simply try again).
function SocialService.IsInGroup(userId: number): boolean
	if not SocialService.IsConfigured() then
		return false
	end
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(userId)
	end)
	if not ok or type(groups) ~= "table" then
		return false
	end
	for _, group in ipairs(groups) do
		if group.Id == socialData.groupId then
			return true
		end
	end
	return false
end

--API
function SocialService.RewardDescriptor()
	return table.clone(socialData.reward)
end

--API
-- Seconds between pressing GET REWARD and the grant landing (the "like the game
-- and wait" window — there is no like API to verify against).
function SocialService.ClaimDelaySeconds(): number
	return math.max(tonumber(socialData.claimDelaySeconds) or 0, 0)
end

-- ── Referrals (features/referrals.md) ────────────────────────────────────

--API
-- The userId this account was already attributed to (0 = never attributed).
-- Non-zero is the permanent "this invitee has been counted" mark.
function SocialService.ReferredBy(userId: number): number
	local social = section(userId)
	return if social ~= nil then (tonumber(social.referredBy) or 0) else 0
end

--API
-- Attributes this account to `referrerId`, ONCE. Returns false when the profile
-- is not loaded or an attribution already exists — the caller must not pay out
-- on a false, since a second true would pay the same friend twice.
function SocialService.MarkReferredBy(userId: number, referrerId: number): boolean
	local social = section(userId)
	if social == nil then
		return false
	end
	if (tonumber(social.referredBy) or 0) ~= 0 then
		return false
	end
	social.referredBy = referrerId
	return true
end

--API
-- How many friends this player has been paid for (the invite panel's number).
function SocialService.ReferralsRewarded(userId: number): number
	local social = section(userId)
	return if social ~= nil then (tonumber(social.referralsRewarded) or 0) else 0
end

--API
-- Counts one paid referral. Returns the new total, or nil when the profile is
-- not loaded (the caller must then NOT consume the message that delivered it).
function SocialService.CountReferral(userId: number): number?
	local social = section(userId)
	if social == nil then
		return nil
	end
	social.referralsRewarded = (tonumber(social.referralsRewarded) or 0) + 1
	return social.referralsRewarded
end

--API
function SocialService.ReferralDescriptor()
	return table.clone(socialData.referral.reward)
end

--API
-- Minimum age (days) an invited account must have before it can be attributed
-- and paid for. 0 disables the gate. See SocialData for why it exists.
function SocialService.ReferralMinInviteeAgeDays(): number
	return math.max(tonumber(socialData.referral.minInviteeAccountAgeDays) or 0, 0)
end

--API
-- The gem figure the invite panel advertises (config, not derived — see
-- SocialData).
function SocialService.ReferralDisplayGems(): number
	return math.floor(tonumber(socialData.referral.displayGems) or 0)
end

return SocialService
