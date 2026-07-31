--[[
	AudioConfig — the single source for EVERY sound the game plays (ADR-0004
	shared config; feature doc: docs/features/audio.md).

	The samples themselves are PLACE-AUTHORED, not code (same contract as the
	scene assets in ADR-0007): Sound instances live under
	`ReplicatedStorage.SFX` (any nesting) and `SoundService.BackgroundMusic`,
	so the samples and their base Volume/PlaybackSpeed can be auditioned and
	retuned in Studio without touching Lua. This file owns only the MAPPING:

	    semantic key -> { asset = "<Sound instance name>", ... shaping }

	Shaping fields (all optional):
	  volume  : MULTIPLIER on the instance's authored Volume (1 = as authored)
	  pitch   : MULTIPLIER on the instance's authored PlaybackSpeed
	  cut     : stop after N seconds — long library samples become crisp cues
	            (a 2.2 s "Food Valley" splat is a 0.3 s bite). nil = play out.
	  throttle: minimum seconds between plays of THIS key (drops the extras) —
	            for cues driven by high-frequency events (currency ticks).

	⚠ `asset` names are the contract with the authored folder. A name that is
	not there logs ONCE (R8) and the cue is skipped — the game never goes
	silently mute without saying so. Both places (lobby AND game) need the
	folders; they are place content, not Rojo-synced.
]]

local AudioConfig = {}

-- Authored containers (resolved by name, never created by code).
AudioConfig.sfxFolder = "SFX" -- under ReplicatedStorage
AudioConfig.musicFolder = "BackgroundMusic" -- under SoundService

-- SoundGroups created at runtime. The settings toggles drive their Volume,
-- which is the ONE place music/sfx are muted (see SettingsSubsClient).
AudioConfig.groups = {
	sfx = "GameSfx",
	music = "GameMusic",
}

-- Pooled 2D voices (GDD §14 hard cap): created ONCE at Init, round-robin,
-- zero Instance.new in hot paths. Bites at max eat-rate + walk crunch + UI
-- all share these, so the pool must outlast the longest `cut`.
AudioConfig.poolSize = 20
AudioConfig.pitchJitter = 0.1 -- ±10% per play, so repeats never phase-lock
-- Combo raises bite pitch: pitch * (1 + comboPitchPerStep * (combo - 1)).
AudioConfig.comboPitchPerStep = 0.04

-- Granular slump LOOP (§7.4, the signature avalanche sound): one dedicated
-- looping voice whose volume follows avalanche energy in studs³.
AudioConfig.slump = {
	key = "slumpLoop",
	volumeDiv = 60,
	maxVolume = 0.6,
	decayPerSecond = 0.8,
}

-- SETTINGS GATE (both SoundPool and MusicService): audio stays MUTED until the
-- player's saved toggles arrive, so someone who turned sound off never hears the
-- first seconds of a session. If a SettingsUpdate never lands, the gate opens on
-- the defaults after this grace and R8-warns — a broken settings path must
-- degrade to "sound plays", never to permanent silence.
AudioConfig.settingsGraceSeconds = 8

AudioConfig.music = {
	volume = 1, -- multiplier on each authored track Volume
	fadeSeconds = 2.5, -- fade in/out across a track change
	gapSeconds = 4, -- silence between tracks
	shuffle = true, -- shuffled playlist, never the same track twice running
	-- Re-probe the authored folder this often while it is still empty, so a
	-- library that replicates late heals without a rejoin (SoundPool does the
	-- same on a lookup miss).
	rescanSeconds = 5,
}

-- ── the map: semantic key -> authored sample ────────────────────────────
-- Keys are what call sites use; several keys deliberately share one sample at
-- different shaping (a "press" and a "toggle" are the same click, retuned).
AudioConfig.sounds = {
	-- Cake bites. These keys are referenced by CakeConfig.layers[*].sfx —
	-- one per layer material, so every layer chews differently. `cut` keeps
	-- them snappy at eat-rates up to ~10 bites/s.
	squish = { asset = "bite_soft", cut = 0.3 },
	crumble = { asset = "bite_crunch", cut = 0.3 },
	crack = { asset = "stone break 9", volume = 0.9, cut = 0.32 },
	blorp = { asset = "bite_wet", cut = 0.35 },
	pshhh = { asset = "bite_splat", cut = 0.3 },
	stretch = { asset = "bite_goo", cut = 0.4 },
	shhh = { asset = "bite_soft", pitch = 0.85, volume = 0.8, cut = 0.28 },

	-- Cake feel / cycle
	-- The EXTRA shard burst on a shatterFx layer, layered over that layer's own
	-- bite. It must be a DIFFERENT sample from `crack` (chocolate's bite key) and
	-- throttled, or the two stack into one wall of the same waveform.
	shatter = { asset = "stone hit sound", volume = 0.7, pitch = 1.15, cut = 0.25, throttle = 0.2 },

	slumpLoop = { asset = "slump_loop" },
	crustCrack = { asset = "crust_crunch", cut = 0.55 },
	-- Layered UNDER the per-bite crumbles: throttled so it keeps a slow mouth
	-- rhythm at any eat-rate instead of turning into mush at 10 bites/s.
	chew = { asset = "bite_chew", volume = 0.7, cut = 0.5, throttle = 0.55 },
	gulp = { asset = "gulp", cut = 0.6 },
	bossAppear = { asset = "muehehe" },
	bossHit = { asset = "softhit", cut = 0.3 },
	bossDefeat = { asset = "success", volume = 0.9 },
	bossLost = { asset = "lose" },
	cakeCleared = { asset = "deeppositivereward" },
	-- One layer of the cake finished — the game's core rhythm beat. Reuses an
	-- already-authored sample (no new SFX content needed), pitched up so it
	-- reads as a step, not as the end of the whole cake.
	layerCleared = { asset = "success", volume = 0.85, pitch = 1.12 },
	rareCake = { asset = "game reveal" },
	newCake = { asset = "transition", volume = 0.8 },
	land = { asset = "softhit", volume = 0.7, cut = 0.35 },
	bounce = { asset = "swoosh", volume = 1.4 },

	-- UI (driven kit-wide by the shared press primitive — Interaction)
	uiClick = { asset = "pressdown", volume = 1.2, cut = 0.16 },
	-- Throttled: sweeping a mouse across a 30-tile shop grid must tick, not buzz.
	uiHover = { asset = "hover", volume = 0.35, cut = 0.14, throttle = 0.1 },
	uiOpen = { asset = "frameopen", volume = 1.6 },
	uiClose = { asset = "close", volume = 1.6 },
	uiError = { asset = "softerror" },
	-- "You can't do that right now" (belly full, layer still locked) — the
	-- same error, quieter and lower, so a repeated nudge never nags.
	blocked = { asset = "softerror", volume = 0.55, pitch = 0.85, throttle = 0.4 },

	-- Economy / rewards
	gemGain = { asset = "medium light pickup gems", volume = 0.8, throttle = 0.5 },
	reward = { asset = "deeppositivereward" },
	rewardBig = { asset = "heavy reward reveal" },
	treasureSpawn = { asset = "mergeavailable", volume = 0.7 },
	treasureGet = { asset = "itempickup", volume = 1.2 },
	-- Rare+ find popping free of the cake — the loudest reward beat of a cake.
	treasureBig = { asset = "heavy reward reveal", volume = 1.3 },

	-- Gym / body
	gymStart = { asset = "construct1", volume = 0.9 },
	gymPayout = { asset = "sell" },
	gymWhoosh = { asset = "swoosh", volume = 1.6 },

	-- Purchases / upgrades
	purchaseStart = { asset = "purchasestart", volume = 0.7 },
	purchaseOk = { asset = "lightpurchase" },
	upgradeBuy = { asset = "brainrotupgrade1" },

	-- Squishies (pets): the reveal is rarity-tiered — a legendary must SOUND
	-- different from a common or the roll has no stakes.
	hatchCommon = { asset = "hatchcommon" },
	hatchEpic = { asset = "hatchepic" },
	hatchLegendary = { asset = "hatchlegendary" },
	petEquip = { asset = "itempickup", throttle = 0.25 },

	-- Notifications / codes
	notifyGood = { asset = "notificationgood", volume = 1.6 },
	notifyBad = { asset = "notificationbad", volume = 1.6 },

	-- Lobby matchmaking / teleport
	queueTick = { asset = "c4 beep", volume = 0.5 },
	matchStart = { asset = "transition" },
}

-- Reveal rarity -> hatch cue. Rarity ids are PetConfig's (lower-case).
AudioConfig.hatchByRarity = {
	common = "hatchCommon",
	uncommon = "hatchCommon",
	rare = "hatchEpic",
	epic = "hatchEpic",
	legendary = "hatchLegendary",
	secret = "hatchLegendary",
}

return AudioConfig
