--[[
	SocialData
	Config for the one-time "join the group" reward (R1).

	groupId = 0 means NOT CONFIGURED: the claim is refused and the client row
	shows as unavailable — set the game's Roblox group id per project.
	Membership is verified LIVE on the server (GroupService:GetGroupsAsync,
	see SocialService) — there is NO like/favorite verification (Roblox
	exposes none), membership alone gates the reward.
]]

local SocialData = {}

-- The Roblox group players join to earn the reward. SET PER GAME.
SocialData.groupId = 0

-- One-time reward descriptor (ADR-0002 grammar).
SocialData.reward = { kind = "gems", amount = 50 }

-- Min seconds between one player's membership checks (GetGroupsAsync is a
-- web request — this throttles a modified client; legit claims are farther
-- apart than this anyway).
SocialData.claimCooldownSeconds = 5

return SocialData
