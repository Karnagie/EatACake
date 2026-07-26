--[[
	MatchConfig -- shared lobby queue + reserved game-round contract.

	The lobby and game places load this exact module, so difficulty ids, party
	limits, teleport metadata, authored-instance names, and result timings cannot
	drift between places. TeleportData selects transient round tuning only; player
	profiles remain authoritative through ProfileStore (ADR-0009).
]]

local MatchConfig = {}

MatchConfig.protocolVersion = 1

MatchConfig.difficultyOrder = { "easy", "medium", "hard" }
MatchConfig.difficulties = {
	easy = {
		labelKey = "match-difficulty-easy",
		worldLabel = "Easy",
		cakeHeightMultiplier = 0.8,
		bossHpMultiplier = 0.75,
		bossDurationMultiplier = 1.5,
	},
	medium = {
		labelKey = "match-difficulty-medium",
		worldLabel = "Medium",
		cakeHeightMultiplier = 1,
		bossHpMultiplier = 1,
		bossDurationMultiplier = 1,
	},
	hard = {
		labelKey = "match-difficulty-hard",
		worldLabel = "Hard",
		cakeHeightMultiplier = 1.08,
		bossHpMultiplier = 1.5,
		bossDurationMultiplier = 0.75,
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
