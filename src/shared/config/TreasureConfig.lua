--[[
	TreasureConfig — finds BURIED in the cake (GDD §6.1).

	Since 2026-07-26 a find is not a pop-up bauble: it is a real, chunky
	AUTHORED MODEL (place-authored library, see `model.folderName`) sitting
	inside the loaf at a rolled depth. It is scaled to ~1.5-2× the player, so
	freeing one is a genuine DIG — you eat the cake off it until nothing covers
	it any more, then it pops out and flies to you on its own.

	Every find pays GEMS, and only gems (user req): eggs and boosts no longer
	drop. Gems are what the shop sells boosts for (500 each), so a dug-up find is
	a step towards the boost the player CHOSE instead of a random one handed to
	them — and one currency keeps the dig legible while 40 finds cascade out of a
	cleared layer.
	⚠ The payout table, the weights and `spawn` below are ONE balance set: a solo
	cake's 40 finds are worth ~496 gems, i.e. exactly one boost per cleared cake.
	(The flat-weight expectation is ~347; `spawn.depthRarityBias` skews the deep
	bands towards the rare tiers and carries the rest — which is the point:
	because rarity now scales only the SIZE of the gem payout, depth pays in gems
	directly.) Change any one of them and the "one cake = one boost" rule breaks.

	Reward kind is therefore always `gems` (granted through RewardGrantSubs,
	ADR-0002). `weight` — relative roll weight. `rarity` drives FX loudness /
	colour / size and the size of the payout.
	`model` — OPTIONAL exact child name inside the authored Items library; when
	nil (or missing from the library) the find is assigned a library model
	round-robin, so dropping new models in needs NO config edit.

	⚠ Round-robin is a FALLBACK, not a design. Unpinned, a common berry can get
	the strawberry while a legendary gets whatever is next in the rotation, and
	the reward reads as random rather than earned. Four finds are pinned below;
	`bolt`, `whisk`, `lost-phone` and `trapped-pet` still round-robin because the
	library holds 5 treasure models for 9 finds. More props are now a VARIETY win
	rather than a correctness fix — rarity is carried by `rarityScale` (size),
	`rarityFx[].glowPulse` (pulse) and `sceneryModels` (scenery can never be
	treasure), none of which need new art.

	⚠ Adding art needs a HUMAN in the Toolbox dock. The scripted route
	(`InsertService:LoadAsset`) reaches a strictly smaller set than the Toolbox:
	16 of 16 candidates found via the public toolbox-service search failed with
	"User is not authorized to access Asset", across both old and new asset-id
	formats. Worth ONE attempt, then drag it in by hand. Whatever the route, free
	models can carry scripts — strip `BaseScript`/`RemoteEvent`/`RemoteFunction`
	BEFORE parenting into `Workspace.Items`, because `prepareTemplate` only
	strips the clone, never the authored original.
]]

local TreasureConfig = {}

TreasureConfig.finds = {
	{ id = "berry", model = "strawberry", nameKey = "find-berry", weight = 40, rarity = "common", reward = { kind = "gems", amount = 2 }, color = Color3.fromRGB(200, 40, 80) },
	{ id = "candy-gem", model = "candy", nameKey = "find-candy-gem", weight = 20, rarity = "common", reward = { kind = "gems", amount = 5 }, color = Color3.fromRGB(90, 200, 255) },
	{ id = "charm", model = "Meshes/Peppermint", nameKey = "find-charm", weight = 12, rarity = "uncommon", reward = { kind = "gems", amount = 8 }, color = Color3.fromRGB(255, 215, 120) },
	{ id = "bolt", nameKey = "find-bolt", weight = 6, rarity = "uncommon", reward = { kind = "gems", amount = 10 }, color = Color3.fromRGB(140, 140, 150) },
	{ id = "whisk", nameKey = "find-whisk", weight = 6, rarity = "uncommon", reward = { kind = "gems", amount = 10 }, color = Color3.fromRGB(200, 200, 210) },
	{ id = "lost-phone", nameKey = "find-lost-phone", weight = 3, rarity = "rare", reward = { kind = "gems", amount = 25 }, color = Color3.fromRGB(40, 40, 45) }, -- Drain the Lake easter egg
	{ id = "golden-slice", model = "donut 1", nameKey = "find-golden-slice", weight = 5, rarity = "rare", reward = { kind = "gems", amount = 20 }, color = Color3.fromRGB(255, 200, 30) },
	{ id = "capsule", model = "Yoyle Berry", nameKey = "find-capsule", weight = 4, rarity = "epic", reward = { kind = "gems", amount = 35 }, color = Color3.fromRGB(255, 120, 200) },
	{ id = "trapped-pet", nameKey = "find-trapped-pet", weight = 2, rarity = "legendary", reward = { kind = "gems", amount = 70 }, color = Color3.fromRGB(120, 255, 180) },
}

-- Finds per cake scale with cake volume; every player can collect every
-- find is WRONG — a find is consumed by whoever touches it first (flag on
-- the find, not on the player — GDD §13).
TreasureConfig.spawn = {
	volumePerFind = 2500, -- studs^3 of cake per one find
	minFinds = 8,
	maxFinds = 40,
	-- Finds are dealt ROUND-ROBIN over the edible bands (shuffled) instead of
	-- being sprinkled at uniform heights: with ~28-42 layers and 40 finds that
	-- puts ~1 in every layer, so no layer is ever a dry stretch. The reward
	-- beat is what carries a 40-minute cake.
	perBandJitter = 0.35, -- fraction of a band the dealt depth may wander

	-- DEPTH PAYS (competitor study, 2026-07-29). Rarity used to be completely
	-- independent of depth — bands are SHUFFLED and finds dealt round-robin, so a
	-- legendary was exactly as likely in the top layer as at the bottom. That
	-- leaves no pull DOWNWARD beyond raw progress, which is the single thing
	-- *Drain the Lake* is most praised for doing well: "a bucket that earned a
	-- trickle near the surface can be worth far more at the bottom… the rhythm
	-- becomes a satisfying spiral". A cake you eat top-down should get better as
	-- it gets harder.
	--
	-- Each tier's roll weight is multiplied by `(1 + depthRarityBias * depth)^tier`
	-- (common = tier 0 … legendary = tier 4), depth 0 at the surface → 1 at the
	-- deepest edible band. So the SURFACE distribution is exactly unchanged and
	-- only the deep end skews. At 0.6 a legendary goes 2.0% → 8.8% at the bottom
	-- (4.3×) without ever being guaranteed.
	depthRarityBias = 0.6,
}

-- The authored MODEL library + how a buried find behaves.
TreasureConfig.model = {
	-- Place-authored container. The user drops models under `Workspace.Items`;
	-- TreasureService MOVES it to `ReplicatedStorage.Assets.Items` on boot so it
	-- becomes a replicated template library (ADR-0007) and stops cluttering the
	-- scene. Editing + saving the place keeps it there.
	folderName = "Items",
	sourceParent = "Workspace", -- where the user authors them (migrated on boot)

	-- SIZE: every find's LONGEST dimension is scaled to this, so whatever art is
	-- dropped in reads at a consistent, predictable size (measured live in Studio:
	-- the R15 rig is 5.73 studs tall, so 10.5 = 1.83× the player — the requested
	-- 1.5-2× band). Uniform scale, measured on the model's OWN (local) extents:
	--   scale = targetSizeStuds / max(localExtents)
	-- ⚠ Local, NOT the world AABB. A prop authored at an angle has a world box
	-- much bigger than itself, and scaling against that shrinks it wrongly (a
	-- rotated Part came out visibly smaller than its neighbours). The world AABB
	-- is still what SpawnForCake uses for burial depth — that one IS a world span.
	-- Height is not targeted directly: `tiltDegrees` is what gives a flat prop its
	-- vertical span, and targeting height would blow a pan up to a football field.
	targetSizeStuds = 10.5,
	sizeJitter = 0.12, -- ±fraction per spawned find (variety, still 1.5-2×)

	-- RARITY IS SIZE — but ONLY UPWARD. Colour rides the rim glow, and the glow
	-- does not exist until the crown breaks through, so size is the only rarity
	-- cue readable while a find is still being dug.
	-- ⚠ Never put a tier BELOW 1.0. Measured: scaling commons to 0.85 pushed
	-- one-layer finds from 13/40 to 15/40, i.e. it broke the "usually two or
	-- three layers" requirement to serve a cue — the wrong trade. Scaling only
	-- the rare tiers up costs nothing there and makes the best rewards the
	-- deepest digs, which is where the anticipation belongs.
	-- Size band (5.73-stud R15 rig): 1.00 -> 1.83×, 1.28 -> 2.35×. The top of
	-- that is past the requested "1.5-2×", deliberately and only for legendary
	-- (2% of rolls) + epic (4%); 86% of finds sit exactly at 1.83×.
	rarityScale = {
		common = 1.0,
		uncommon = 1.0,
		rare = 1.10,
		epic = 1.18,
		legendary = 1.28,
	},

	-- Library models that are SCENERY, not treasure. They stay resolvable BY
	-- NAME (an explicit `model =` pin still works) but are removed from the
	-- round-robin pool — otherwise a legendary can dig up as a floor tile, which
	-- reads as a bug rather than a reward. Match is on the exact child name.
	sceneryModels = { "KK Candy Floor" },
	-- Random pitch/roll per find. Half-buried objects never lie flat — and an
	-- elongated prop laid flat is only ~1 stud tall, i.e. uncovered by a single
	-- scoop. A tilt gives every SHAPE a real vertical span to dig through.
	tiltDegrees = 35,

	-- BURIAL. The find's TOP is sunk this fraction of its band's thickness below
	-- the band top, so uncovering always costs real eating. A 9-stud model in a
	-- 5-12 stud band therefore spans 1-3 bands: with the layer gate you often
	-- see its crown in one layer and only free it in the next (user req).
	burialFraction = { 0.2, 0.6 },
	edgeMarginCells = 2, -- EXTRA cells beyond the find's own footprint radius
	topClearanceStuds = 8, -- nothing buried within this of the fresh surface

	-- REVEAL / FREE thresholds, all measured against the MAX surface height over
	-- the model's own XZ footprint (it is only free when NOTHING covers it).
	preloadLeadStuds = 9, -- fade the model in this far before the first pixel shows
	fadeInSeconds = 0.45,
	revealEpsilonStuds = 0.25, -- surface at/below top + this = first crown showing
	freedEpsilonStuds = 0.6, -- a footprint cell at/below bottom + this is "cleared"
	-- FREED when this FRACTION of the find's footprint cells are cleared — not
	-- all of them. A find's footprint is its bounding box, which for a wide or
	-- tilted prop is much larger than its silhouette, so demanding 100% left
	-- items sitting fully exposed and uncollectable behind one corner cell.
	freedCoverFraction = 0.95,

	-- STRAIN — the anticipation beat. Between "crown showing" and "free" the
	-- find used to just SIT there: the sparkle rate rose, and nothing else. That
	-- is the exact moment the payoff is closest and it was the flattest part of
	-- the dig. Now the rim glow deepens and floods as the last cake comes off,
	-- so the release is something you can SEE coming.
	-- ⚠ This is a PROPERTY animation, not a pose animation, and it must stay one.
	-- The first cut wobbled the model per tick and stranded 6 finds: `GetPivot()`
	-- on a Model with no PrimaryPart returns the recomputed bounding-box centre
	-- with IDENTITY rotation, so every `PivotTo` re-derives the parts' relative
	-- offsets from a frame that has already lost the previous rotation and the
	-- transform COMPOUNDS. Animate a find's pose only via `playCollect`, which
	-- runs once and then destroys the model.
	strain = {
		startFraction = 0.45, -- clearFrac at which the escalation begins
		pulseGain = 1.2, -- extra rim-pulse depth at the moment of release
		fillGain = 0.45, -- how far the glow FILL floods in by release
	},

	-- COLLECT. Freed finds are collected automatically (user req) and dealt out
	-- one at a time so an auto-swept layer produces a satisfying CASCADE of pops
	-- instead of one confusing frame.
	cascadeSeconds = 0.22,
	pop = { heightStuds = 7, seconds = 0.42, overshoot = 1.15, spinDegrees = 520 },
	fly = { seconds = 0.5, spinDegrees = 300, arcStuds = 4 },
	sparkleRate = 7, -- particles/s on a partially exposed find
	highlightPulseHz = 2.4,
}

-- FX loudness per rarity (client). `shake` = CameraShake trauma, `burst` =
-- ParticlePool particle count, `sound` = AudioConfig key on collect.
-- `glowPulse` = rim-glow pulse DEPTH on an exposed-but-not-yet-freed find
-- (0 = steady rim). Deliberately 0 for common: with up to 40 finds in a cake, a
-- pulse on everything is wallpaper. Only the ones worth crossing the cake for
-- breathe, so the pulse itself reads as "this one matters" before the player
-- can tell what it is. Rate is `model.highlightPulseHz`.
TreasureConfig.rarityFx = {
	common = { burst = 16, shake = 0.12, sound = "treasureGet", ring = false, glowPulse = 0 },
	uncommon = { burst = 24, shake = 0.18, sound = "treasureGet", ring = false, glowPulse = 0.15 },
	rare = { burst = 34, shake = 0.28, sound = "treasureBig", ring = true, glowPulse = 0.35 },
	epic = { burst = 44, shake = 0.38, sound = "treasureBig", ring = true, glowPulse = 0.5 },
	legendary = { burst = 60, shake = 0.5, sound = "treasureBig", ring = true, glowPulse = 0.7 },
}

-- TIMED BOOSTS — the four things the gem shop sells (500 gems each, one per
-- cleared cake). Finds no longer grant them: you EARN gems by digging and then
-- CHOOSE which boost to buy, which is why all four run the same 15 minutes and
-- cost the same. `mult` applies to the named `stat` for `duration` seconds.
--
-- ⚠ `stat` is a CONTRACT with StatsService, and the only place that list exists:
--     calories | gems | biteRadius | walkSpeed | capacity
-- StatsService multiplies exactly those five by `BoostMult(userId, stat)`. A def
-- naming any other stat is a boost that silently does NOTHING — it sells, it
-- shows a timer, and no number moves. Adding a stat means teaching StatsService
-- about it AND (if the value is pushed or applied once rather than read per use)
-- adding it to BoostSubs.Apply, which is what re-applies boosted values on grant
-- and retires them on expiry.
--
-- The old `golden-slice` def (a 60 s calories boost) was DELETED here with no
-- migration, deliberately: a granted boost is stored in `progress.activeBoosts`
-- carrying its OWN stat/mult/expiresAt, and every reader takes the numbers from
-- that entry — the def is consulted only by GrantBoost, at grant time. So a
-- golden-slice still live on a returning profile keeps working and simply
-- expires; nothing can look up a def that no longer exists.
TreasureConfig.boosts = {
	["boost-15m"] = { nameKey = "boost-15m", stat = "calories", mult = 2, duration = 900 },
	["bite-15m"] = { nameKey = "boost-bite", stat = "biteRadius", mult = 1.4, duration = 900 },
	["speed-15m"] = { nameKey = "boost-speed", stat = "walkSpeed", mult = 2, duration = 900 },
	["capacity-15m"] = { nameKey = "boost-capacity", stat = "capacity", mult = 2, duration = 900 },
}

-- How often BoostSubs sweeps for a boost that was granted or has EXPIRED. An
-- expiry fires no event (a boost is just a timestamp in the profile), so this
-- poll is what retires the pushed/applied stats; a grant doesn't wait for it
-- (RewardGrantSubs re-applies immediately). 1 s is imperceptible against a
-- 900 s boost and costs one string compare per player per second.
TreasureConfig.boostTickSeconds = 1

return TreasureConfig
