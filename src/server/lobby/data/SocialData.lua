--[[
	SocialData
	Config for the two social rewards (R1):

	  1. the one-time "like the game + join the community" boost
	     (features/group-reward.md)
	  2. the friend REFERRAL payout (features/referrals.md)

	groupId = 0 means NOT CONFIGURED: the claim is refused and the client row/panel
	is hidden — set the game's Roblox community id per project.
	Membership is verified LIVE on the server (GroupService:GetGroupsAsync, see
	SocialService). There is NO like/favorite verification — Roblox exposes none —
	which is why the reward is a TIMED WAIT: the player is told to like the game
	and the boost lands `claimDelaySeconds` later provided they are a member.
]]

local SocialData = {}

-- The Roblox community players join to earn the reward. SET PER GAME.
-- https://www.roblox.com/communities/307557979/HBs-Interactive
SocialData.groupId = 307557979

-- One-time reward descriptor (ADR-0002 grammar). A 15-minute x2-calories boost
-- (`TreasureConfig.boosts["boost-15m"]`, features/boosts.md) — the same thing the
-- shop sells for 500 gems, which is what makes joining worth a tap.
-- ⚠ `boostId` must name a real def; RewardGrantSubs' boost handler refuses an
-- unknown id and the claim is then deliberately NOT consumed.
SocialData.reward = { kind = "boost", boostId = "boost-15m" }

-- How long the claim takes to land. The player is told "like the game and wait
-- 10 seconds", and membership is re-checked at the END of that window — so the
-- prompt they were just shown has time to complete and a player who joins during
-- the wait still gets paid.
SocialData.claimDelaySeconds = 10

-- Min seconds between one player's completed claim ATTEMPTS (each spends two
-- GetGroupsAsync web requests — this throttles a modified client). Measured from
-- when an attempt RESOLVES, not from the press, and concurrent claims are
-- already impossible via the in-flight lock — so this only has to be long enough
-- to stop a retry loop, NOT longer than `claimDelaySeconds`. Keeping it short is
-- deliberate: the "join the community first, then try again" copy invites an
-- immediate retry, and a long cooldown would silently refuse exactly that press.
SocialData.claimCooldownSeconds = 5

-- ── Referrals (features/referrals.md) ────────────────────────────────────
-- Paid to the INVITER, once per invited account, when that account first joins
-- through a Roblox invite. `rawAmount` keeps it at exactly the advertised number:
-- the gems multiplier (pets, the x2-gems pass) is for gems the player EARNS in
-- the cake, and an advertised "500 per friend" that silently pays 1000 makes the
-- panel wrong for half the playerbase.
SocialData.referral = {
	reward = { kind = "gems", amount = 500, rawAmount = true },
	-- ⚠ THE ABUSE SURFACE. The per-invitee stamp guarantees one account pays once;
	-- it says nothing about MANY accounts, and 500 gems is one cleared cake's
	-- worth of income, so a farmer minting throwaway accounts mints real value.
	-- An account-age floor is the cheapest real cost to add (no web call, no
	-- false positives worth caring about): 1 day kills the create-join-collect
	-- loop that runs inside a single sitting, while a friend who signed up
	-- yesterday still counts. Raise it if the payout rate looks wrong; 0 disables
	-- the gate entirely. Roblox's own referral guidance recommends exactly this
	-- class of mitigation plus monitoring.
	minInviteeAccountAgeDays = 1,
	-- What the invite panel advertises. Kept beside the descriptor rather than
	-- derived from it so the copy cannot drift if the reward ever changes kind.
	displayGems = 500,
}

return SocialData
