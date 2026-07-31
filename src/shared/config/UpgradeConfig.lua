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
	they have eaten HALF the cake. The whole tree costs **772,250** calories,
	down from 16,019,500.

	Measured with `tools/balance-model/pacing.py` (ports ApplyBite, the layer
	gate, both forfeiting sweeps, per-band density and a player who BUYS TIERS
	MID-RUN — which is the thing the old numbers were never checked against).
	Solo easy, 5 seeds:
	  * clear time **38.9 min** (target ~40; the shipped tuning measured 54.6 min
	    of eat+gym, and a real playtest reported 1 h 01 m);
	  * every tier owned at **46% of the cake** (5/5 seeds), around the 27-minute
	    mark — so the back half is played at full power, which is what pulls the
	    clear time down without shrinking the cake;
	  * a full belly is ~18 trips per cake, so the gym stays a quick beat.
	VALUES ARE UNCHANGED. The power curve (~2.4x total eating power) was never
	the problem — the PRICE of reaching it was: at the old costs a run ended
	owning 21 of 44 tiers, and since nothing carries over any more that would
	mean never seeing most of the tree at all.
	⚠ `instantBurn` is priced at ~0.35x the others' scale on purpose: at a flat
	scale its 4 tiers were 48% of the entire tree, so one gym-convenience stat
	crowded out everything that touches the cake.
	The cake's own pacing knobs (scoop / density / layer count) live in
	CakeConfig.composition; work per difficulty is MatchConfig. These are the
	PLAYER side of the same curve.

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
		-- the same thing at every depth — see CakeConfig.composition). Base 84000
		-- ≈ 90 s of eating before the belly tops out, which is the loop's rhythm:
		-- a long eating stretch, then one quick treadmill beat + a purchase.
		-- Grows 4x across the tree so the stretch lengthens as you get stronger.
		base = 84000,
		tiers = {
			{ value = 110000, cost = 750 },
			{ value = 145000, cost = 2500 },
			{ value = 190000, cost = 7000 },
			{ value = 255000, cost = 19000 },
			{ value = 335000, cost = 45000 },
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
			{ value = 23, cost = 550 },
			{ value = 26, cost = 1900 },
			{ value = 29, cost = 6000 },
			{ value = 32, cost = 15000 },
			{ value = 35, cost = 37000 },
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
		base = 3.4,
		tiers = {
			{ value = 3.65, cost = 850 },
			{ value = 3.9, cost = 2800 },
			{ value = 4.2, cost = 8750 },
			{ value = 4.5, cost = 22500 },
			{ value = 4.8, cost = 54000 },
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
		base = 3.6,
		tiers = {
			{ value = 4.1, cost = 800 },
			{ value = 4.6, cost = 2650 },
			{ value = 5.1, cost = 8000 },
			{ value = 5.6, cost = 20500 },
			{ value = 6.2, cost = 50500 },
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
			{ value = 4.4, cost = 700 },
			{ value = 4.75, cost = 2450 },
			{ value = 5.05, cost = 7700 },
			{ value = 5.3, cost = 19500 },
			{ value = 5.6, cost = 47500 },
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
			{ value = 1.2, cost = 1000 },
			{ value = 1.45, cost = 3350 },
			{ value = 1.7, cost = 10000 },
			{ value = 2.0, cost = 26000 },
			{ value = 2.35, cost = 61500 },
		},
	},
	burnSpeed = {
		id = "burnSpeed",
		nameKey = "upgrade-burn-speed",
		descKey = "upgrade-burn-speed-desc",
		category = "gym",
		icon = "burnSpeed",
		-- PASSIVE fat drain while at the machine: fraction of the belly per
		-- second (base 0.06 -> ~16 s to fully burn hands-free; tapping speeds it).
		-- Fraction-based, so it clears any belly size — VALUES unchanged by the
		-- easy-mode retune (the gym is deliberately a quick beat); only costs moved.
		base = 0.06,
		tiers = {
			{ value = 0.10, cost = 500 },
			{ value = 0.16, cost = 1700 },
			{ value = 0.25, cost = 5000 },
			{ value = 0.40, cost = 13000 },
			{ value = 0.65, cost = 31500 },
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
			{ value = 0.14, cost = 450 },
			{ value = 0.20, cost = 1550 },
			{ value = 0.30, cost = 4550 },
			{ value = 0.45, cost = 12000 },
			{ value = 0.70, cost = 28750 },
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
			{ value = 0.20, cost = 6000 },
			{ value = 0.45, cost = 17500 },
			{ value = 0.70, cost = 46500 },
			{ value = 1.00, cost = 117500 },
		},
	},
}

return UpgradeConfig
