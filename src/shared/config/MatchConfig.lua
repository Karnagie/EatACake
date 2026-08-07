--[[
	MatchConfig -- shared lobby queue + reserved game-round contract.

	The lobby and game places load this exact module, so difficulty ids, party
	limits, teleport metadata, authored-instance names, and result timings cannot
	drift between places. TeleportData selects transient round tuning only; player
	profiles remain authoritative through ProfileStore (ADR-0009).
]]

local MatchConfig = {}

MatchConfig.protocolVersion = 1

-- Difficulty tuning (2026-07-30 rebalance, docs/features/cake-cycle.md, ADR-0013).
--   workMultiplier     — how much EATING WORK the cake is worth. Buys extra
--                        LAYERS first, then smaller scoops; it never makes the
--                        cake taller (CakeConfig.composition).
--   caloriesMultiplier — payout premium. Deliberately steeper than the work, so
--                        a strong player farms on HARD rather than on easy.
--   bossHp/bossDuration— the fight at the end, unchanged in spirit.
-- ⚠ `cakeHeightMultiplier` is GONE: cake height no longer varies (a bite clears
-- to the band floor, so height never changed clear time — the old multipliers
-- moved solo clear time by ~2%).
--
-- ⚠ 2026-07-30: every workMultiplier went UP by x1.08 (easy 1 -> 1.08). The
-- upgrade tree is RUN-scoped and its costs were cut ~20x so the whole tree is
-- owned by ~half the cake, which means the BACK HALF of every run is now
-- played at full power — that alone took the solo-easy clear from 54.6 min to
-- 36.8. The 8% work bump buys it back toward the 40-minute target, without
-- shrinking the cake or slowing the fun half. The ratios between the three modes
-- are untouched, so the ladder is unchanged.
-- ⚠ 2026-08-05 (ADR-0019): the clear time this 1.08 was calibrated against
-- (38.9 min) is gone — the belly rebalance re-measures at **35.3 min**, because
-- halving the tier-1 prices puts the eating stats in the player's hands minutes
-- earlier. `workMultiplier` was deliberately NOT raised to claw those 3.4 minutes
-- back: it would have re-shifted the freshly solved belly-interval curve and
-- compressed the easy/medium spacing. Re-measure with
-- `tools/balance-model/pacing.py` (and `--intervals`) before touching it.
MatchConfig.difficultyOrder = { "easy", "medium", "hard" }
MatchConfig.difficulties = {
	easy = {
		labelKey = "match-difficulty-easy",
		worldLabel = "Easy",
		workMultiplier = 1.08,
		caloriesMultiplier = 1,
		bossHpMultiplier = 0.75,
		bossDurationMultiplier = 1.5,
	},
	medium = {
		labelKey = "match-difficulty-medium",
		worldLabel = "Medium",
		workMultiplier = 1.27,
		caloriesMultiplier = 1.25,
		bossHpMultiplier = 1,
		bossDurationMultiplier = 1.2,
	},
	hard = {
		labelKey = "match-difficulty-hard",
		worldLabel = "Hard",
		workMultiplier = 1.49,
		caloriesMultiplier = 1.55,
		bossHpMultiplier = 1.25,
		bossDurationMultiplier = 1,
	},
}

MatchConfig.playerCounts = { 1, 2, 3, 4 }

-- What the selector opens ON. The panel used to open with NOTHING selected, so
-- the fastest possible route into a match was three taps; solo-easy is what the
-- overwhelming majority of first sessions pick anyway, and it is the mode every
-- pacing number in `features/upgrades.md` is measured against.
-- ⚠ A preselection is still a SELECTION: the panel reports both picks the moment
-- it applies them, or the `difficulty-pick` / `party-pick` steps of the player
-- flow would go dark for everyone who simply presses START
-- (`features/analytics.md`). Whether the player CHOSE or merely accepted is
-- still visible — the kit counts the `Difficulty_*` / `Players_*` taps
-- themselves, and those only exist when a finger lands on one.
-- Values that are not in `difficultyOrder` / `playerCounts` are ignored (the
-- panel falls back to no preselection), so retiring a mode cannot wedge START.
MatchConfig.defaults = {
	difficulty = "easy",
	playerCount = 1,
}

MatchConfig.queue = {
	-- Launch countdown, picked by PARTY SIZE when START is pressed
	-- (`Core.CountdownSeconds`). A solo player is only ever waiting on
	-- themselves, so a long timer is pure dead time before the run; a party needs
	-- long enough for everyone to be on the pad and settled.
	-- ⚠ Chosen ONCE, at the moment the countdown starts. Someone joining a solo
	-- queue at t=4s rides the remaining 1s rather than resetting it to 15 — the
	-- countdown never jumps backwards on people already waiting.
	countdownSeconds = 15, -- 2+ players
	countdownSecondsSolo = 5,
	scanIntervalSeconds = 0.2,
	requestCooldownSeconds = 0.2,
	exitGraceSeconds = 0.75,
	launchResetSeconds = 12,
	maxPlayers = 4,
	mapName = "LobbyMap",
	mapContainerName = "LobbyMapContainer",
	environmentName = "LobbyEnvironment",
	spawnName = "LobbySpawn",
	touchersFolderName = "Touchers",
	toucherName = "GroupToucher",
	visualName = "GroupToucherVisual",
	playerCountName = "PlayerCount",
	waitingStatusName = "WaitingStatus",
	legacyStatusName = "ChestStatus",
	textName = "Txt",
	statuses = {
		idle = "Waiting Players...",
		configuring = "Choose Game Mode",
		teleporting = "Teleporting...",
		failed = "Try Again",
	},
}

MatchConfig.round = {
	arrivalWindowSeconds = 10,
	resultDelaySeconds = 5,
	returnRetrySeconds = 10,
	returnRetryWindowSeconds = 180,
	directJoinDifficulty = "easy",
}

MatchConfig.teleport = {
	releaseTimeoutSeconds = 30,
	releaseVerificationIntervalSeconds = 1,
	retryAttemptLimit = 5,
	retryDelaySeconds = 1,
	floodRetryDelaySeconds = 15,
}

MatchConfig.client = {
	shopOpenDebounceSeconds = 0.8,
	forestName = "Forest",
	chocolateModelName = "Chocolate",
	chocolatePartName = "Meshes/chocolate",
}

return MatchConfig
