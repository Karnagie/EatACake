--[[
	Profile section: tutorial — the one-time onboarding flag (features/tutorial.md).

	`done` = this ACCOUNT has finished the guided steps (eat -> belly full ->
	walk to the checkpoint -> open the upgrades computer). It is deliberately
	NOT run-scoped: RunResetSubs wipes upgrades/calories/belly on every profile
	load (ADR-0013), so parking this flag in any of those sections would replay
	the whole tutorial on every single match.

	The story SLIDES are not gated by it — they play on every entry to the game
	place by design; only steps 2-4 are one-time.
]]

return {
	key = "tutorial",
	version = 1,
	defaults = {
		done = false,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		section.done = section.done == true
		return section
	end,
}
