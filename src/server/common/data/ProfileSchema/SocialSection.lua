--[[
	Profile section: social — the one-time group/like reward flag plus referral
	attribution (features/group-reward.md, features/referrals.md).

	  groupRewardClaimed  the "join the community + like the game" boost, once ever
	  referredBy          userId of the player whose invite brought this account in
	                      (0 = nobody / never attributed). Set at most ONCE, the
	                      first time a join carries a ReferredByPlayerId — it is
	                      what stops one friend paying an inviter twice, so it is
	                      permanent even though the reward it gated is long spent.
	  referralsRewarded   how many friends THIS player has been paid for; the
	                      number the invite panel shows.

	⚠ `referredBy` / `referralsRewarded` were ADDED to a v1 section with no version
	bump: new fields with defaults are filled by the load pipeline's reconcile
	step, so a returning save reads them as 0 (P2). Renaming or restructuring
	either one WOULD need v2 + a migration.
]]

return {
	key = "social",
	version = 1,
	defaults = {
		groupRewardClaimed = false,
		referredBy = 0,
		referralsRewarded = 0,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		section.groupRewardClaimed = section.groupRewardClaimed == true
		-- Floored and clamped at 0: these come back through DataStore JSON, and a
		-- negative or fractional count would flow straight into a player-facing
		-- number and into the "have I already paid for this friend?" test.
		section.referredBy = math.max(math.floor(tonumber(section.referredBy) or 0), 0)
		section.referralsRewarded = math.max(math.floor(tonumber(section.referralsRewarded) or 0), 0)
		return section
	end,
}
