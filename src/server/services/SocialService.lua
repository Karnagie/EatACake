--[[
	SocialService
	Logic for the one-time group-join reward over the profile's `social`
	section (R2). Config (groupId, reward) comes from SocialData.

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

return SocialService
