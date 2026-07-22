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

	⚠ EASY-MODE REBALANCE (2026-07-19, docs/flow/2026-07-19_easy-mode-balance.md):
	values + costs were retuned from the ground up so a solo player clears ONE
	cake in ~40 min with EATING as ~94% of the playtime (was: belly filled in ~1
	bite, so the loop was mostly running to the gym). The big levers:
	  * capacity base 150 -> 2600 (belly now holds 50-160 BITES, not ~4) so a
	    full belly is ~50 s of eating, not ~1 s;
	  * eating stats (biteRadius/biteDepth/eatSpeed) grow only ~4x total over the
	    whole tree (were ~2000x) — "reduce final sizes"; endgame no longer eats
	    the whole cake in a handful of bites;
	  * costs pace the ~5-tier ramp across the full ~40-min cake.
	Grounded by a loop+economy simulation, not guesswork — tune from here in
	Studio. Rare/rebirth blocks below are UNTOUCHED (separate meta).

	Upgrades group into 3 CATEGORIES (root honeycomb nodes that drill into a
	sub-tree): eating / body / gym.
]]

local UpgradeConfig = {}

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
		-- Stomach volume in studs^3 of eaten cake. SAME-PACE ×3 for the 3× cake
		-- (base 2600→7800): bites are ×3 bigger (biteDepth ×3), so ×3 capacity
		-- holds the SAME NUMBER of bites (~50-160) and the eating stretch stays
		-- ~50 s. Grows ~4.4x across the tree so the belly keeps pace as bites get
		-- bigger. Costs unchanged (income/sec is flat).
		base = 7800,
		tiers = {
			{ value = 11400, cost = 1050 },
			{ value = 15600, cost = 3150 },
			{ value = 21000, cost = 8400 },
			{ value = 27000, cost = 21000 },
			{ value = 34500, cost = 49000 },
		},
	},
	runSpeed = {
		id = "runSpeed",
		nameKey = "upgrade-run-speed",
		descKey = "upgrade-run-speed-desc",
		category = "body",
		icon = "runSpeed",
		-- WalkSpeed (base 16). Modest ramp; the bigger loaf means more ground to
		-- cover to fresh cake, and faster travel = MORE eating, less walking.
		base = 16,
		tiers = {
			{ value = 22, cost = 900 },
			{ value = 27, cost = 2700 },
			{ value = 32, cost = 7000 },
			{ value = 37, cost = 17000 },
			{ value = 42, cost = 40000 },
		},
	},
	biteRadius = {
		id = "biteRadius",
		nameKey = "upgrade-bite-radius",
		descKey = "upgrade-bite-radius-desc",
		category = "eating",
		icon = "biteRadius",
		-- Bite SCOOP radius in studs (base 1.7). Smaller than before (was 3) because
		-- the Req 2 clean bite clears its footprint to the layer FLOOR (not a shallow
		-- dent), so a smaller scoop keeps roughly the same volume/bite and pacing
		-- while each bite reads CLEAN (one side of the layer clears, the other stays
		-- full). Grows the scoop (and forward reach) with upgrades. ⚠ STARTING value
		-- — verify clear-time by feel in Studio (this + biteDepth, the clean-bite
		-- "strength", set the pace together).
		base = 1.7,
		tiers = {
			{ value = 1.85, cost = 910 },
			{ value = 2.0, cost = 2750 },
			{ value = 2.15, cost = 7350 },
			{ value = 2.25, cost = 18000 },
			{ value = 2.4, cost = 42000 },
		},
	},
	biteDepth = {
		id = "biteDepth",
		nameKey = "upgrade-bite-depth",
		descKey = "upgrade-bite-depth-desc",
		category = "eating",
		icon = "biteDepth",
		-- Crater depth in studs at the center. SAME-PACE ×3 for the 3× TALLER
		-- cake (base 1.2→3.6, max 1.8→5.4): bite volume ∝ depth·radius², so ×3
		-- depth = ×3 removed volume, exactly offsetting the ×3 edible volume so a
		-- cake still clears in ~the same time (income stays flat via calories ÷3
		-- in CakeConfig). Still a nibble vs the chunky ~12-16-stud layers, and the
		-- layer gate clamps each bite to the current layer's floor. Costs unchanged.
		base = 3.6,
		tiers = {
			{ value = 4.05, cost = 1200 },
			{ value = 4.5, cost = 3500 },
			{ value = 4.86, cost = 9450 },
			{ value = 5.16, cost = 24000 },
			{ value = 5.4, cost = 56000 },
		},
	},
	eatSpeed = {
		id = "eatSpeed",
		nameKey = "upgrade-eat-speed",
		descKey = "upgrade-eat-speed-desc",
		category = "eating",
		icon = "eatSpeed",
		-- Bites per second (base 4). Gentle ramp to 5.2 (was 41 — a machine-gun
		-- that trivialised the cake). A comfortable rapid nibble, not a blender.
		base = 4,
		tiers = {
			{ value = 4.3, cost = 1100 },
			{ value = 4.6, cost = 3350 },
			{ value = 4.85, cost = 8750 },
			{ value = 5.0, cost = 22000 },
			{ value = 5.2, cost = 52500 },
		},
	},
	gymEff = {
		id = "gymEff",
		nameKey = "upgrade-gym-eff",
		descKey = "upgrade-gym-eff-desc",
		category = "gym",
		icon = "gymEff",
		-- Calories banked per stored calorie (base 1). Max 2.35 (was 4.32) —
		-- trimmed so the (now much bigger) belly's payout doesn't over-inflate
		-- the economy; the main income growth comes from eating more, not x4.32.
		base = 1,
		tiers = {
			{ value = 1.2, cost = 1400 },
			{ value = 1.45, cost = 4200 },
			{ value = 1.7, cost = 11000 },
			{ value = 2.0, cost = 28000 },
			{ value = 2.35, cost = 66500 },
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
			{ value = 0.10, cost = 770 },
			{ value = 0.16, cost = 2300 },
			{ value = 0.25, cost = 5950 },
			{ value = 0.40, cost = 14500 },
			{ value = 0.65, cost = 35000 },
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
			{ value = 0.14, cost = 700 },
			{ value = 0.20, cost = 2100 },
			{ value = 0.30, cost = 5450 },
			{ value = 0.45, cost = 13500 },
			{ value = 0.70, cost = 31500 },
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
			{ value = 0.15, cost = 50000 },
			{ value = 0.35, cost = 160000 },
			{ value = 0.60, cost = 450000 },
			{ value = 1.00, cost = 1400000 },
		},
	},
}

-- Rebirth ("Food Coma", GDD §9): resets calories + these upgrade levels,
-- grants a permanent +25% calories multiplier per rebirth level.
UpgradeConfig.rebirth = {
	resets = {
		"capacity",
		"biteRadius",
		"biteDepth",
		"eatSpeed",
		"gymEff",
		"burnSpeed",
		"burnPerTap",
		"instantBurn",
		"runSpeed",
	},
	multPerLevel = 0.25,
	-- Cost of rebirth N (0-based): base * growth^N calories.
	baseCost = 25000,
	growth = 2.2,
	biomes = { "factory", "donut", "candy" }, -- biome index = rebirth level + 1 (capped)
}

return UpgradeConfig
