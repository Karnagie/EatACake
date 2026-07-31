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
-- owned by ~46% of the cake, which means the BACK HALF of every run is now
-- played at full power — that alone took the solo-easy clear from 54.6 min to
-- 36.8. The 8% work bump buys it back to **38.9 min**, i.e. the 40-minute
-- target, without shrinking the cake or slowing the fun half.
-- Measured over 5 seeds by `tools/balance-model/pacing.py --candidate`; the
-- ratios between the three modes are untouched, so the ladder is unchanged.
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

MatchConfig.queue = {
	countdownSeconds = 30,
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
