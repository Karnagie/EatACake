--[[
	UpgradeConfig — the calorie-bought upgrades (GDD §10), organised as a
	HEXAGON TREE of discrete TIERS (see features/upgrades.md, UpgradeTreeConfig
	for the honeycomb layout). Nine stats across three categories: eating
	(biteRadius/biteDepth/eatSpeed), body (capacity/runSpeed), gym (gymEff +
	the fat-burn stats burnSpeed/burnPerTap/instantBurn).

	Each upgrade is a short chain of TIERS. `levels[id]` in the profile is the
	number of tiers OWNED (0 = none, #tiers = maxed). A tier is one chunky
	purchase:
	  value(tier) = def.tiers[tier].value    (tier 0 -> def.base)
	  cost(tier)  = def.tiers[tier].cost      (calories for tier-1 -> tier)
	Effects are consumed by StatsService only — nothing else interprets these
	tables. The tier COUNT (5, +4 for instantBurn) and the remote contract are
	unchanged, so no profile migration is needed when only values/costs move.

	⚠ REBALANCE 2026-07-30 — COSTS CUT ~20x (docs/flow/2026-07-30_*.md, ADR-0013).
	The tree is RUN-scoped now (see UpgradeConfig.run below), and the design
	target changed with it: a player must be able to own EVERY tier by the time
	they have eaten HALF the cake.
	⚠ `instantBurn` is priced at ~0.35x the others' scale on purpose: at a flat
	scale its 4 tiers were 48% of the entire tree, so one gym-convenience stat
	crowded out everything that touches the cake.
	The cake's own pacing knobs (scoop / density / layer count) live in
	CakeConfig.composition; work per difficulty is MatchConfig. These are the
	PLAYER side of the same curve.

	⚠ REBALANCE 2026-08-05 — THE BELLY IS THE PROGRESSION AXIS (user request;
	docs/flow/2026-08-05_*.md, ADR-0019). Two things changed, both measured with
	`tools/balance-model/pacing.py --intervals`:

	1. `capacity` no longer tracks eating power — it OUTRUNS it. The belly is
	   what sends you to the gym, so how OFTEN it fills is the pacing the player
	   actually feels, and until now that curve ran BACKWARDS: 227 s per belly at
	   tier 0 falling to 63 s at tier 5, because capacity grew 4x while eating
	   power grew ~20x. Every purchase made the interruption MORE frequent. The
	   new curve stretches 10 s -> 30 s -> 90 s -> 120 s -> 150 s -> 180 s
	   (measured first-belly-after-purchase, solo easy, 5 seeds), so the first
	   two capacity tiers are the most legible upgrades in the game.
	2. Tier-1 costs are ~0.55x (the per-tier ratio went 3.1 -> 3.4 to hold the
	   tree total, 772,250 -> 755,260, so tree-completion timing is preserved).
	   This is what makes the opening loop work: ONE 10-second belly of frosting
	   banks ~612 calories, and `biteRadius` I costs 450 — so the first upgrade
	   is affordable ~7.4 s into the very first belly, which is exactly what the
	   onboarding flow now waits for (features/tutorial.md).
	3. `burnSpeed` base 0.06 -> 0.20. Burn time is a FRACTION of the belly, so it
	   is a constant ~1/burnSpeed seconds no matter how small the belly is: at
	   0.06 a hands-free burn took 16.7 s against a 10 s belly, which inverts the
	   loop. 0.20 = 5 s, and the tiers still cut it to well under a second.

	Measured, solo easy, 5 seeds (`--intervals` for the curve, plain run for
	these; the model excludes boss/travel/reveal so clear time is a FLOOR):
	  * clear **35.3 min** = eat 29.6 + gym 5.7 over 22 trips (84% of the session
	    spent eating). Was 38.7 = eat 33.4 + gym 5.3 over 20 trips — so the gym got
	    slightly LONGER (more trips, each much shorter) and the entire 3.4-minute
	    win is EAT time: halving the tier-1 prices puts the eating stats in the
	    player's hands minutes earlier, and they clear cake faster for the rest of
	    the run;
	  * every tier owned at **48% of the cake** (5/5 seeds), target <= 50%;
	  * 22 belly->gym trips per cake, i.e. 22 purchase moments.
	⚠ The 2026-07-30 note that "VALUES ARE UNCHANGED / power grows ~2.4x" is dead:
	a later hand-tune (commit 1c21a15) moved biteRadius base 3.4 -> 2.4 and
	biteDepth 3.6 -> 2.6 and pushed their top tiers up, so total eating power now
	grows ~20x end to end. Re-measure, never extrapolate.

	⚠ REBIRTH REMOVED (2026-07-26, by request). There is no `UpgradeConfig
	.rebirth` block any more, and the calorie multiplier no longer has a rebirth
	term (StatsService). The profile still carries `progress.rebirths` (always 0)
	so no migration was needed. What resets the tiers now is the RUN reset below.

	Upgrades group into 3 CATEGORIES (root honeycomb nodes that drill into a
	sub-tree): eating / body / gym.
]]

local UpgradeConfig = {}

-- ── RUN-SCOPED progression (ADR-0013, by request 2026-07-30) ─────────────
-- The tree is no longer permanent meta. Every profile load — entering the lobby
-- AND arriving in a match — wipes the owned tiers and the spendable calorie
-- balance, so a run starts as a base eater and buys the WHOLE tree back inside
-- one cake (the costs below are calibrated for exactly that).
-- What survives is META: gems, squishies, daily rewards, shop purchases +
-- gamepasses, timed boosts, and every `progress.lifetime*` stat.
-- ⚠ `progress.lifetimeCalories` is NOT this balance — it is the permanent
-- leaderboard stat and must never be reset (EconomyService.ResetCalories).
UpgradeConfig.run = {
	resetOnLoad = true,
	-- Belly volume + unbanked calories are run state too: carrying a full
	-- stomach out of a finished match into the lobby made no sense, and a
	-- carried-over `stored` would bank against the NEXT run's gymEff.
	resetBelly = true,
}

UpgradeConfig.order =
	{ "capacity", "biteRadius", "biteDepth", "eatSpeed", "gymEff", "burnSpeed", "burnPerTap", "instantBurn", "runSpeed" }

-- Root honeycomb nodes: each opens a sub-tree grouping its stats' tier-chains.
UpgradeConfig.categories = {
	eating = { id = "eating", nameKey = "cat-eating", icon = "eating" },
	body = { id = "body", nameKey = "cat-body", icon = "body" },
	gym = { id = "gym", nameKey = "cat-gym", icon = "gym" },
}
UpgradeConfig.categoryOrder = { "eating", "body", "gym" }

UpgradeConfig.upgrades = {
	capacity = {
		id = "capacity",
		nameKey = "upgrade-capacity",
		descKey = "upgrade-capacity-desc",
		category = "body",
		icon = "capacity",
		-- Belly size in FOOD units (eaten volume × the band's density, so it means
		-- the same thing at every depth — see CakeConfig.composition).
		-- ⚠ THIS IS THE PACING STAT. The belly is what interrupts eating, so
		-- `capacity / food-per-second` — the seconds of eating per belly — is the
		-- rhythm the player feels, and it must GROW, visibly, as tiers are bought.
		-- Measured (`pacing.py --intervals`, solo easy, 5 seeds, seconds of eating
		-- for the first belly filled at each tier):
		--   base 10.0 s | I 30.6 s | II 89.1 s | III 122.3 s | IV 148.5 s | V 183.8 s
		-- The jumps are deliberately biggest at the bottom (3x, then 3x): the first
		-- two purchases are the ones that have to TEACH the player that upgrades
		-- change how the game plays. Growing 147x looks extreme next to the old 4x,
		-- but eating power itself grows ~20x across the tree — the old curve lost
		-- that race, which is why the belly used to fill FASTER the stronger you got.
		-- ⚠ Re-measure with the model after ANY change to biteRadius/biteDepth/
		-- eatSpeed values or CakeConfig.composition; these six numbers are outputs
		-- of that curve, not free parameters.
		base = 4400,
		tiers = {
			{ value = 13000, cost = 400 },
			{ value = 58000, cost = 1350 },
			{ value = 120000, cost = 4600 },
			{ value = 235000, cost = 15500 },
			{ value = 645000, cost = 53000 },
		},
	},
	runSpeed = {
		id = "runSpeed",
		nameKey = "upgrade-run-speed",
		descKey = "upgrade-run-speed-desc",
		category = "body",
		icon = "runSpeed",
		-- WalkSpeed (Roblox default 16). This matters MORE than it looks: on the
		-- wide top layers a wide scoop clears cake faster than you can walk over
		-- it, so speed — not chewing — is what finishes those layers.
		base = 20,
		tiers = {
			{ value = 23, cost = 300 },
			{ value = 26, cost = 1000 },
			{ value = 29, cost = 3400 },
			{ value = 32, cost = 11500 },
			{ value = 35, cost = 39000 },
		},
	},
	biteRadius = {
		id = "biteRadius",
		nameKey = "upgrade-bite-radius",
		descKey = "upgrade-bite-radius-desc",
		category = "eating",
		icon = "biteRadius",
		-- Bite SCOOP radius in studs, BEFORE the band's `scoop` multiplier (the
		-- cake's own pacing curve — icing ×2.23, deepest band ×0.558). So a base
		-- eater scoops ~7.6 studs of icing and ~1.9 studs of the dense core.
		-- Because a bite clears to the layer floor, clear time scales with the
		-- bite AREA: this is the single strongest eating stat (each tier is ~15%
		-- more area) and it is priced accordingly.
		-- ⚠ `tiers[1].cost` (450) is LOAD-BEARING for onboarding: the tutorial's
		-- "go burn it off" step fires the moment the player can afford THIS tier
		-- (features/tutorial.md), and the only calories they have at that point are
		-- the unbanked ones in their belly. A full base belly of frosting is worth
		-- ~612 calories, so 450 fires at ~74% of the first belly with a x1.36
		-- margin. Raising it past ~600 would make the step unreachable and strand
		-- a first-time player full and unable to eat.
		base = 2.4,
		tiers = {
			{ value = 2.65, cost = 450 },
			{ value = 2.9, cost = 1550 },
			{ value = 3.2, cost = 5250 },
			{ value = 4.5, cost = 17800 },
			{ value = 5.8, cost = 60500 },
		},
	},
	biteDepth = {
		id = "biteDepth",
		nameKey = "upgrade-bite-depth",
		descKey = "upgrade-bite-depth-desc",
		category = "eating",
		icon = "biteDepth",
		-- Bite STRENGTH in studs, read against sim.biteClearRefDepth (3.6): a bite
		-- clears each cell toward the layer floor by falloff × (biteDepth /
		-- refDepth) / hardness. At the base value the centre of the scoop clears
		-- a soft layer in one bite; upgrading WIDENS the fully-cleared core (and
		-- lets you chew the dense deep layers in one bite instead of three).
		base = 2.6,
		tiers = {
			{ value = 3.1, cost = 440 },
			{ value = 3.6, cost = 1500 },
			{ value = 4.1, cost = 5100 },
			{ value = 5.6, cost = 17300 },
			{ value = 6.2, cost = 58800 },
		},
	},
	eatSpeed = {
		id = "eatSpeed",
		nameKey = "upgrade-eat-speed",
		descKey = "upgrade-eat-speed-desc",
		category = "eating",
		icon = "eatSpeed",
		-- Bites per second (base 4). Gentle ramp to 5.6 — a comfortable rapid
		-- nibble, not a blender. Also drives the eat-gesture speed and the
		-- anti-cheat token bucket, so it is deliberately the flattest curve.
		base = 4,
		tiers = {
			{ value = 4.4, cost = 390 },
			{ value = 4.75, cost = 1300 },
			{ value = 5.05, cost = 4400 },
			{ value = 5.3, cost = 15000 },
			{ value = 5.6, cost = 51000 },
		},
	},
	gymEff = {
		id = "gymEff",
		nameKey = "upgrade-gym-eff",
		descKey = "upgrade-gym-eff-desc",
		category = "gym",
		icon = "gymEff",
		-- Calories banked per stored calorie (base 1). The pure income stat: it
		-- buys nothing on the cake, so it is the natural second purchase once the
		-- eating stats have paid for themselves.
		base = 1,
		tiers = {
			{ value = 1.2, cost = 550 },
			{ value = 1.45, cost = 1850 },
			{ value = 1.7, cost = 6300 },
			{ value = 2.0, cost = 21400 },
			{ value = 2.35, cost = 72800 },
		},
	},
	burnSpeed = {
		id = "burnSpeed",
		nameKey = "upgrade-burn-speed",
		descKey = "upgrade-burn-speed-desc",
		category = "gym",
		icon = "burnSpeed",
		-- PASSIVE fat drain while at the machine: fraction of the belly per
		-- second. Fraction-based, so the burn takes ~1/value SECONDS whatever the
		-- belly holds — it does NOT get quicker when the belly gets smaller.
		-- ⚠ That is why base moved 0.06 -> 0.20 with the 2026-08-05 belly curve:
		-- 0.06 is a 16.7 s hands-free burn, and against a 10 s opening belly the
		-- burn was LONGER than the eating it interrupted. 0.20 = 5 s hands-free,
		-- and tapping (burnPerTap, 10 taps) still clears it far faster.
		base = 0.20,
		tiers = {
			{ value = 0.28, cost = 280 },
			{ value = 0.40, cost = 950 },
			{ value = 0.58, cost = 3200 },
			{ value = 0.85, cost = 10900 },
			{ value = 1.25, cost = 37000 },
		},
	},
	burnPerTap = {
		id = "burnPerTap",
		nameKey = "upgrade-burn-per-tap",
		descKey = "upgrade-burn-per-tap-desc",
		category = "gym",
		icon = "burnPerTap",
		-- Fat burned per on-screen TAP, as a fraction of the belly. Base 0.10 =
		-- 10 taps clears a full belly (the user's spec) — fraction-based, so it
		-- still clears the bigger belly in ~10 taps. VALUES unchanged; only costs.
		base = 0.10,
		tiers = {
			{ value = 0.14, cost = 250 },
			{ value = 0.20, cost = 850 },
			{ value = 0.30, cost = 2900 },
			{ value = 0.45, cost = 9800 },
			{ value = 0.70, cost = 33300 },
		},
	},
	instantBurn = {
		id = "instantBurn",
		nameKey = "upgrade-instant-burn",
		descKey = "upgrade-instant-burn-desc",
		category = "gym",
		icon = "instantBurn",
		-- Fraction of the belly removed the INSTANT you press the prompt. Base 0
		-- (none). Four EXPENSIVE tiers; the final tier (1.0) clears the whole
		-- belly on press — no tapping needed (the user's spec). VALUES unchanged;
		-- costs scaled to the retuned economy (a big-ticket end-game QoL sink).
		base = 0,
		tiers = {
			{ value = 0.20, cost = 3300 },
			{ value = 0.45, cost = 11200 },
			{ value = 0.70, cost = 38100 },
			{ value = 1.00, cost = 129500 },
		},
	},
}

return UpgradeConfig
