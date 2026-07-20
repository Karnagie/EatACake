--[[
	BodyConfig — stomach, body morph and gym tuning (GDD §8).

	The loop: bites add VOLUME to the stomach (fill) and CALORIES to the
	unbanked pool (stored). The gym DRAINS the belly (fill -> 0) while you
	stand at the machine — passively (burnSpeed) and per TAP (burnPerTap) —
	banking stored -> calories (currency) * gymEff as it drains. While the
	belly is FULL: eating is BLOCKED (StomachService.IsFull -> CakeSubs drops
	the bite), WalkSpeed drops, the body is SCALED UP big & fat (morph), and it
	TUMBLES forward as you move — the gym is the only release valve.

	The calorie gain on the bite that TIPS you into full is still x2
	("glutton mode") — the last mouthful is the reward.
]]

local BodyConfig = {}

BodyConfig.stomach = {
	gluttonCaloriesMult = 2, -- x2 on the bite that reaches capacity
	fullSpeedPenalty = 0.4, -- -40% WalkSpeed at full (scales linearly with fill)
}

-- Body morph: only the TORSO grows (bigger + fatter) as the belly fills —
-- arms/legs/head keep their natural size. No proxy meshes, no added parts, just
-- the avatar's own torso parts scaled. We scale each torso part's OriginalSize
-- (the Humanoid auto-scaler enforces Size = OriginalSize × BodyScale, so
-- growing only the torso's OriginalSize grows only the torso, and it holds).
-- The factors below are the TORSO scale at a full belly (relative to natural);
-- width/depth grow more than height so the belly reads fat. Driven from
-- `stomach` fill01, LERPED SERVER-SIDE in BodySubs (⚠ runtime part-size changes
-- only take when set on the SERVER — the client's are reverted by replication;
-- see body-gym gotcha). Cartoonish/non-sexualized (GDD §8).
BodyConfig.morph = {
	widthScale = { 1.0, 2.8 }, -- torso width × this at full (fat & wide)
	depthScale = { 1.0, 2.8 }, -- torso depth × this at full
	heightScale = { 1.0, 1.3 }, -- torso height × this (a bit taller too, but far less than width)
	lerpSpeed = 4, -- 1/s exponential approach (server lerp — you SEE it grow)
	rateHz = 15, -- server morph-lerp tick rate
	minStep = 0.02, -- snap to target within this (reach full / return to natural); no writes at rest
}

-- Rolling TUMBLE (client visual, BallRollController), applied by EVERY client
-- for EVERY character from the replicated "StomachFill" attribute (zero network
-- cost). Once the body is round/full enough (past tumbleFill) the whole scaled
-- body TUMBLES forward as you MOVE (settles upright when you stop), by rotating
-- the ROOT joint's static offset — Motor6D.C0, or on AnimationConstraint
-- avatars the Root constraint's Attachment0 (the one channel the Animator never
-- overwrites). VISUAL ONLY: the HumanoidRootPart (physics/collision/camera)
-- stays upright, so WalkSpeed and jump are untouched.
BodyConfig.tumble = {
	tumbleFill = 0.85, -- fullness where the tumble ramps in
	rollRadius = 3.0, -- studs travelled per radian of tumble (smaller = faster spin)
	spinMaxDegPerSec = 900, -- cap on the visual tumble rate
	moveSpeedThreshold = 1.5, -- studs/s below which you count as STOPPED (settle upright)
	unwindLerp = 7, -- 1/s ease the tumble back upright when stopped or de-rounded
}

-- Eat GESTURE (client visual, EatGestureController, LOCAL character only —
-- consistent with the local-prediction bite juice): every bite rips a chunky
-- piece of the eaten LAYER out of the cake in front of you and flies it through
-- your hand to your mouth, shrinking it away. Flight time SHORTENS with the
-- eat-rate stat, so faster eating visibly chews faster.
BodyConfig.eatGesture = {
	poolSize = 6, -- concurrent flying pieces (recycled)
	pieceSize = 2.0, -- studs (chunky, clearly visible in-hand piece)
	baseDuration = 0.6, -- seconds of flight at eatRate = 1
	minDuration = 0.24, -- clamp so even fast eating stays clearly readable
	maxDuration = 0.7,
	handFraction = 0.5, -- fraction of the flight spent cake -> hand (rest hand -> mouth)
	arcHeight = 2.6, -- studs the piece bulges above the straight path
	tumbleDegPerSec = 520, -- piece spin while flying (cosmetic)
	tint = 0.14, -- lighten the layer top colour toward white (appetising glaze)
}

-- Fat-burn session (GDD §8, reworked). Press the gym prompt to START burning;
-- the belly then DRAINS from its start fill toward empty — PASSIVELY at the
-- `burnSpeed` stat (fraction of the belly per second) and by `burnPerTap` per
-- on-screen TAP (both are UPGRADES, tuned in UpgradeConfig). Burn progress runs
-- 0..1 and maps fill start->0; calories bank proportionally (× gymEff) as it
-- drains, so currency ticks up live. STEPPING AWAY from the machine stops it and
-- keeps the partially-burned belly. The `instantBurn` upgrade removes a slice
-- the instant you press (final tier = the whole belly at once). No fixed timer,
-- no mash bonus — the burn ends when the belly is empty or you leave.
BodyConfig.gym = {
	stepHz = 8, -- server drain tick + progress/stomach push rate
	tapsPerSecondCap = 14, -- anti-cheat: taps counted server-side, capped per second (§13)
	minStartFill = 1, -- below this the belly is "empty" — pressing the prompt does nothing
	-- Auto-gym (gamepass/VIP): background FULL burns when NOT in a session.
	autoBurnInterval = 6, -- seconds between automatic burns
	minStoredToBurn = 1, -- don't spam zero burns
}

return BodyConfig
