--[[
	BodyConfig — stomach, body morph and gym tuning (GDD §8).

	The loop: bites add VOLUME to the stomach (fill) and CALORIES to the
	unbanked pool (stored). The gym converts stored -> banked calories
	(currency) * gymEff * mash bonus, and empties the belly. While the belly
	is FULL: fill stops growing, WalkSpeed drops, but calorie gain is x2
	("glutton mode") — overeating is a choice, not a punishment.
]]

local BodyConfig = {}

BodyConfig.stomach = {
	gluttonCaloriesMult = 2, -- x2 while fill >= capacity
	fullSpeedPenalty = 0.4, -- -40% WalkSpeed at full (scales linearly with fill)
}

-- Body morph: applied by every client locally from the replicated
-- "StomachFill" player attribute (0..1) — smooth lerp, zero network cost.
-- Cartoonish and non-sexualized (moderation requirement, GDD §8).
BodyConfig.morph = {
	widthScale = { 1.0, 2.2 },
	depthScale = { 1.0, 2.2 },
	heightScale = { 1.0, 0.92 },
	lerpSpeed = 6, -- 1/s exponential approach
}

BodyConfig.gym = {
	duration = 4, -- seconds of mash window
	tapsPerSecondCap = 12, -- server-side anti-cheat cap (GDD §13)
	-- Mash bonus: x1.0 at 0 accurate taps -> maxBonus at perfectTaps.
	maxBonus = 1.5,
	perfectTaps = 24, -- taps needed for the full bonus within the window
	cooldown = 1, -- seconds between gym sessions (anti-spam)
	-- Auto-gym (upgrade/gamepass): burns without the minigame, no bonus.
	autoBurnInterval = 6, -- seconds between automatic burns
	minStoredToBurn = 1, -- don't spam zero burns
}

return BodyConfig
