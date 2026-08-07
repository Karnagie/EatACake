# Cake cycle (phases, boss, rare cakes, biomes)

## What it does
State machine per cake (GDD §9): `spawning → eating → boss → reward →
spawning`. `CakeSimulationSubs` drives `CakeCycleService.Step(dt)`; returned
events are orchestrated by `CakeCycleSubs` (R3/R4). In a reserved match the
first fresh cake is finite: reward is terminal and `GameRoundSubs` returns the
roster instead of spawning another cake.
In an active game-place round, cake construction/snapshots/simulation are
deferred until the profile-ready roster start commits. The combined/unknown
development build is not active round mode and retains the endless fallback.

## Phases
- **eating** — bottom reached (`progress ≥ 0.995`, 1 Hz scan) → `BeginBoss`.
- **boss** — Cake Guardian: HP = `bossTapsPerPlayer (120) × players ×
  bossHpMultiplier` (fixed launch count in a reserved match; current population
  in endless fallback); every `EatAt` = 1 damage. Sized as a ~20-30 s frantic
  finale, with the timer always leaving ~1.5× the time a base eater needs.
  ⚠ **Keep that margin when tuning**: `HP / (players × eatRate)` must stay well
  under the timer or the match is unwinnable by construction (easy solo 90 taps
  / 67.5 s; hard solo 150 / 45 s; hard 4p 600 / 45 s).
  Defeat before the timer is a win; timer expiry is a
  loss (no reward). Boss VISUAL is
  client-side only (`BossView`), HP travels in `CakeCycleUpdate` (4 Hz).

### The prize is shown DURING the fight (2026-07-30)
The finale used to be a blind tap race — you could not see what you were fighting
for until it was already yours. `CakeCycleSubs.BeginBoss` (which
`CakeSimulationSubs` now calls instead of the service directly) PRE-ROLLS one
squishy per loaded participant into `CakeStateData.pendingPetRolls`, and the win
path grants **exactly that id**, so the card on screen is the prize you get.
- `PetService.Roll` was split into pure **`Preview`** (decides, mutates nothing)
  and **`Grant(petId)`** (commits); `Roll = Preview + Grant`, so every other
  caller is unchanged (`features/pets.md`).
- The rainbow-cake Epic floor is applied at PREVIEW time — applying it only at
  grant time could disagree with what was advertised.
- It is **per player**, so `fireCycle` shallow-clones the payload per recipient
  and attaches `pendingPet = { petId, rarity }`; a broadcast is still used when no
  prizes exist.
- Cleared on win, on timeout (forfeited), and on every new cake — so the card's
  lifetime is exactly the fight's.
- A player who arrives mid-fight (or whose profile loaded late) has no preview and
  falls back to a fresh roll on the win; that is logged, not silent.
- Client: `CakeSubsClient` → `AppRoot` `cake.pendingPet` →
  `LocalPetsService.BuildPrize` → kit `BossPrizeCard` (HUD top-right, wearing the
  prize's own rarity accent).
- **reward** — on a match win, every present validated participant with a loaded
  profile receives the squishy the boss HUD has been ADVERTISING (see below);
  `progress.cakesEaten += 1`.
- **spawning** — 15 s countdown → new composition roll → `ResetCake` →
  snapshot broadcast.

## Composition roll (`RollComposition`) — THE PACING CURVE (ADR-0011)
Frosting on top, core at the bottom, the rest random from `middlePool` (no
immediate repeats). The FOOTPRINT is a FIXED landmark (a ROUND ~93.3-stud cake
since 2026-08-03 — equal-area with the old 90×78 loaf, cake-sim.md) and
EVERY cake is exactly `maxTotalHeight` (**170** studs since 2026-07-26; height is a pure VISUAL knob, measured free by `tools/headless-sim/pacing_scenario.lua`) tall — difficulty and party
size never change the silhouette. Pacing lives on each BAND instead:

| per-band field | what it does |
|---|---|
| `scoop` | multiplies the eater's `biteRadius` on that band. Ramps 2.23 (icing, ~5.4-stud spoonful at base `biteRadius` 2.4) → 0.558 (core, ~1.3-stud chip). A bite clears to the band FLOOR, so clear time scales with bite AREA — **this is the difficulty ramp**, and it reads on screen. |
| `density` | how rich/filling that band is per stud³ (calories AND belly fill) = `refBandWeight / (thickness × scoop²)` — exactly the value that keeps one bite worth the same FOOD as the scoop shrinks, so the belly→gym rhythm is set by `capacity` ALONE (features/upgrades.md: ~10 s per belly at tier 0 stretching to ~180 s at tier 5) and the income stays flat at every depth. |
| thickness | follows the same ramp (deeper == chunkier), renormalised to `maxTotalHeight`. Thickness does NOT drive clear time (a bite clears to the floor). |

`work` = `MatchConfig` `workMultiplier` × `(1 + coopWork·(players−1))` (0.5; players
at spawn). It buys MORE LAYERS first (`layerExponent`), and whatever the
`maxLayers` cap cannot absorb becomes smaller scoops — so a harder/crowded cake
has more thin layers and denser cake, i.e. more "layer cleared!" moments.
Calorie payout scales separately: `caloriesMultiplier` × per-head `coopCalories`
(0.62), fixed at roll time into `state.payoutScale` so it cannot drift as players
leave. Boss HP scales with players × difficulty.

**`findPayoutScale`** is its sibling for the GEMS buried finds pay, fixed at the
same moment and applied by `CakeCycleService.ScaleFindReward` (which returns a
COPY — the caller is handed the shared config descriptor). It carries the
**per-head term ONLY**: `1 + coopFinds·(players−1)`, no difficulty premium, no
rare-cake multiplier. Why finds need a per-head term at all, and why the premium
is deliberately excluded: `features/treasures.md`.

**Measured clear time** (2026-07-30, `tools/balance-model/pacing.py`, 5 seeds —
the FIRST model that simulates a player buying tiers mid-run, which is the run
people actually play):

| solo easy | value |
|---|---|
| clear (eat + gym) | **35.3 min** = eat 29.6 + gym 5.7 (target ~40) |
| whole upgrade tree owned at | **48% of the cake** (5/5 seeds) |
| gym trips | ~22 (84% of the session is spent eating) |
| forfeited to the sweeps | ~5.5% |

⚠ The old row "easy solo **40 min**" was never measured this way: the model behind
it ran a fixed stat line, so the ramp was invisible. Re-measured, the shipped
tuning was **54.6 min** owning 21/44 tiers — and a real playtest reported
**1 h 01 m** (that plus boss, reveal, walking and time in the upgrade UI).
ADR-0013 re-priced the tree and raised work ×1.08 to land the 40-minute target.
⚠ medium/hard and the co-op matrix were scaled by the same ×1.08 but only solo
easy was measured across seeds — the party numbers are extrapolated. Party size
still multiplies work by `1 + 0.5(n−1)` and payout per head by `1 + 0.62(n−1)`.
Rare cakes:
golden 4% (x3 calories), rainbow 1% (Epic+ pet) — плюс **hourly event**: if
no rare cake happened for 3600 s the next cake is forced golden (§12.2).

## Biomes
Biomes used to be unlocked by rebirth level; **rebirth was removed 2026-07-26**,
so every cake takes `CakeConfig.biomeOrder[1]` (`ProgressService.BiomeFor`, which
keeps its signature so an unlock rule is a one-liner away). Biome = palette
recolor (`MapService.ApplyBiome`) + calories multiplier
(`MapConfigData.biomes[x].caloriesMult`).

## Update contract
`CakeCycleUpdate` (1 Hz; 4 Hz in boss): `{phase, progress, timer,
boss = {hp, maxHp}?, rareKind, biome, activeBandIndex, finds?, announce,
pendingPet?}`. `pendingPet = { petId, rarity }` is attached **per recipient**
(the boss prize is personal) — see the boss section.
(`activeBandIndex` = the layer-gate top edible band, so the client's bite
prediction/lock tracks the server between snapshots — see
`features/cake-sim.md`. Avalanche/slump energy is a client-local value in
`LocalCakeField`, never networked.)
`announce` keys: `new-cake`, `rare-cake-golden`, `rare-cake-rainbow`,
`boss-spawned`, `cake-cleared`, `layer-cleared`, `match-lost` → client `announce-*` locale keys.

**Session length — endpoints.** ⚠ The figures previously quoted here (126 min
fresh / 33 min maxed, from `tools/headless-sim/pacing_scenario.lua` §B) were
inflated by a units bug found 2026-07-30: the scenario multiplied
`CakeOps.ApplyBite`'s return — already a VOLUME — by `cellArea` a second time, so
food read 2.25× high, belly→gym TRIPS 2.25× high, and the forfeited fraction
2.25× low (6.8% shown vs ~17% actual). Fixed in that file. The Python model
measures the endpoints at **478 min at tier 0 / 18 min maxed** on the current
config. ⚠ Since the 2026-08-05 belly curve the tier-0 endpoint is not even a
hypothetical session: `capacity` base is sized for the first ~10 SECONDS of a run,
so that row is a player who eats a whole cake without ever buying a tier and its
time is dominated by hundreds of gym trips nobody makes.
Neither endpoint is the run people play — that is the 35.3-min ramped
figure above.

**`layer-cleared`** is the session's RHYTHM beat: fired by `CakeSimulationSubs`
whenever the layer gate steps DOWN a band (never on a new cake, where the index
jumps back up), so ~28-42 times per cake — one every ~1.4 min of a 40-min solo
run. The client answers with the `layerCleared` chime, a camera punch and a ring
of crumbs kicked up around the eater. Finishing a layer used to be SILENT.

## Files
`services/CakeCycleService`; `subscriptions/CakeSubs` (player input),
`CakeCycleSubs` (lifecycle/reward), `CakeSimulationSubs` (Heartbeat),
`GameRoundSubs` (finite result); client `BossView`, `CakeSubsClient`. Match
contract: `features/game-round.md`. Pets: `features/pets.md`.
