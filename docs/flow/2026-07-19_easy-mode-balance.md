# 2026-07-19: Easy-mode balance (eating-dominant loop, bigger cake, tamed endgame)

Tags: cake-sim, cake-cycle, upgrades, body-gym, config, map, economy

## Task
User: eating levels up too fast; overall reduce final sizes; make the cake
bigger/longer. "1 bite and you're full, can't eat anymore." More time is spent
running back and forth than eating — even at the start you fill the belly in ~1
second and run off to deflate. **Eating should be the main activity, not running.**
Target an EASY mode for 1–4 players: one player clears it in ~40 min; 4 players
in ~15–20 min (not ~10).

## Context
The core loop (`features/cake-sim.md`, `body-gym.md`, `upgrades.md`): bite the
shared heightfield cake → volume fills the belly (`stomach.fill`, capped at the
`capacity` stat) → at full you CAN'T eat → teleport to the checkpoint gym (F) →
drain the belly (banking calories) → buy hex-tree upgrades → repeat; clear the
cake → boss → new cake. Prior flow: `2026-07-19_layer-gate.md`,
`2026-07-19_gym-fat-drain-rework.md`, `2026-07-16_eat-the-cake-v1.md`.

Root cause found by modelling the real bite/volume math (`CakeOps.ApplyBite`,
crater ≈ depth·πR²/2 / hardness):
- Base bite ≈ 32 studs³ on frosting, capacity 150 → **belly full in ~4.6 bites
  ≈ 1.2 s** → constant gym trips ("накликаешь за секунду").
- After ONE eating upgrade a single bite (175 studs³) **exceeds** capacity 150 →
  literally "1 bite = full".
- Bite volume grows as depth·radius² while capacity grew only linearly, so the
  two diverge hard; max eating tier = **11,773 studs³/bite** (whole cake ≈ 23
  bites) → endgame trivialised the cake ("финальные размеры" far too large).

## Plan
Ground the numbers in a loop+economy simulation (`scratchpad/model3.js`) rather
than guessing. Targets: solo clears one cake in ~40 min, eating ≈ 90%+ of
playtime, belly holds MANY bites at every tier (never 1-bite-full), eating power
grows only modestly (~4×, not ~2000×), 4 players ~18 min. Then size the cake and
pace the upgrade costs to hit those, keeping the loop's rhythm (long eating
stretch → quick gym → repeat).

## Changes

**Modified:**
- `src/shared/config/UpgradeConfig.lua` — retuned tier VALUES + COSTS of all 9
  upgrades (tier COUNT and remote contract unchanged → no profile migration).
  `capacity` base **150 → 2600** (belly now holds ~50–160 BITES); eating stats
  flattened (`biteDepth` max **26 → 1.8**, `biteRadius` **12 → 4.2**, `eatSpeed`
  **41 → 5.2**) so total eating power grows ~4× over the tree; `gymEff` max
  **4.32 → 2.35**; `burnSpeed`/`burnPerTap`/`instantBurn` VALUES unchanged (gym
  stays a quick beat), only costs rescaled to the new economy.
- `src/shared/config/CakeConfig.lua` — `grid.maxHeight` **70 → 90**;
  `composition.footprint` **28/19/8 → 30/26/10** (84×57 → 90×78 studs, +46%
  area); `totalHeight` **{52,68} → {50,60}**; NEW `composition.perPlayerScale`
  (0.15) — co-op cake-height lever.
- `src/server/services/CakeCycleService.lua` — `RollComposition` now uses the
  previously-IGNORED `playerCount`: rolled `totalHeight` ×
  `(1 + perPlayerScale·(players−1))`, clamped to `maxHeight`.
- `src/server/data/MapConfigData.lua` — `platform.width` **72 → 88** (cake tray;
  the bigger loaf would otherwise overhang it), candles moved **x±46/z±32 →
  x±48/z±42** (z±32 was now INSIDE the ±39 footprint → would clip through the
  mesh, the exact bug their own comment warns about).
- `src/server/services/MapService.lua` — the `CakeSpawn` pad's Y now RIDES the
  cake top via `SetCheckpointHeight` (was hard-anchored to `maxHeight`). Adversarial
  review WARN: raising `maxHeight` 70→90 turned the intended small crust-crack drop
  into a ~40-stud free-fall for the common solo cake (~54 tall). Verified live:
  spawn Y = cake-top + `spawnHeightAboveCake` (8).
- `src/client/modules/CakeWaxShell.lua` — wax-web creation Y `maxHeight*0.5 →
  *0.75`. Review NIT: FixedSize meshes cull from creation bounds; the shell is
  built once and rides solo(~52)→4p(~89) cake tops, so centering the creation Y
  on that range keeps overshoot within the proven-safe band (0.5 sat ~42 studs
  under a 4-player top).

**Created:**
- `docs/flow/2026-07-19_easy-mode-balance.md` (this doc); scratchpad sim
  `model3.js` (not committed — analysis artifact).

## Decisions
- **"Clear one shared cake" = the unit of "пройти".** It's the natural 1–4 player
  co-op activity (one shared loaf, more mouths → faster) and the only reading
  where the 40 min / 15–20 min targets and the "not 10 min" complaint line up
  (a fixed cake drained 4× faster by 4 players = the old ~10 min). Endless
  respawn + rebirth continue on top; the 40 min is one cake.
- **Fix "1 bite = full" by decoupling belly size from bite growth, not by
  shrinking bites to nothing.** Big capacity (base 2600) + flattened bite growth
  means the belly holds ≥48 bites on the *softest* layer even at max eating power
  (sanity table in the sim). A full belly is now ~50 s of eating → the loop is
  eat-dominant (~94% eating / ~5% walk-back in the model), gym is a quick tap
  beat. This directly fixes "running dominates".
- **"Reduce final sizes" = flatten the eating upgrade curve.** biteDepth was the
  culprit (depth·R² compounding); capping it at 1.8 (from 26) keeps every bite a
  nibble and, with the layer gate, you always eat top-down. Eating power grows
  ~4× total (base 50 → 199 studs³/s) instead of ~2000×.
- **Co-op scaling via cake HEIGHT, not footprint.** The 64-cell grid caps
  footprint half-extents at ~31 (footprint is already 30/26); growing `grid.size`
  would inflate the per-layer render vertex budget (weak-laptop risk). Height is
  the only free population lever and literally makes the loaf "longer to eat".
  `perPlayerScale` 0.15 → 4-player loaf ×1.45, sublinear so 4p ≈ 18 min while
  solo ≈ 40 (model). One tunable knob.
- **Absolute calorie scale is a free parameter; pacing depends on the
  income/cost RATIO.** Costs were set to ramp the ~5-tier tree across the whole
  ~40-min cake (max reached ~78% through in the model). Rare/rebirth blocks left
  UNTOUCHED (separate meta) — see Followups re: the calorie surplus.
- **No profile migration.** Only tier values/costs moved; `levels[id]` still
  means tier count, `UpgradesSection` stays v2, Stats/UpgradeService clamp reads.

## Open Questions / Followups
- **Numbers are simulation-grounded, not playtested.** Model assumptions (avg
  layer hardness 1.3, sustained tap rate 8/s, ~3 s walk-back, continuous eating,
  greedy purchase) will differ live. Verify solo pace + rhythm in Studio and
  tune from the config (the whole design is in `CakeConfig`/`UpgradeConfig`; the
  fastest knobs are `capacity.base`, `perPlayerScale`, and the cost tables).
- **Calorie surplus → rebirth.** With the big belly the solo cake banks far more
  than the upgrade tree costs (~360k surplus after maxing). Rebirth
  (`UpgradeConfig.rebirth.baseCost` 25000) is untouched, so the surplus funds
  early rebirths quickly. Left as-is (rebirth is opt-in and resets upgrades); if
  rebirth should stay a bigger milestone in the new economy, bump `baseCost`.
- **Weak-laptop render budget.** +46% footprint cells → +46% verts per layer
  mesh; the degradation ladder (slabs → palette → keycaps) covers a budget
  failure, but confirm on the low-RAM secondary laptop.
- **Body morph max (2.8× torso) left alone** — "final sizes" was read as upgrade
  magnitudes, not body size. Easy one-line tune (`BodyConfig.morph`) if the fat
  body should be less extreme.

## Related
- Features: `docs/features/cake-sim.md`, `cake-cycle.md`, `upgrades.md`, `body-gym.md`
- Prior flow: `2026-07-19_layer-gate.md`, `2026-07-19_gym-fat-drain-rework.md`,
  `2026-07-16_eat-the-cake-v1.md`
