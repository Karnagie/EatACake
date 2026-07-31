# 2026-07-26: Cake pacing rebalance (40-min Easy), rebirth removed, upgrades reachable

Tags: cake-sim, cake-cycle, upgrades, body-gym, economy, config, game-round, rebirth, app-root

## Task
User (as game designer): balance the cakes so **Easy is a ~40-minute solo
clear**; derive the numbers for the other difficulties and party sizes;
**account for all upgrades**; **remove the Rebirth system for now**; eating must
feel satisfying and never grindy — "the first layers should be eaten much faster
so players immediately feel a strong sense of progress". Aim at 30+ min sessions
and 20%+ retention.

## Context
`features/cake-sim.md`, `cake-cycle.md`, `upgrades.md`, `body-gym.md`. Prior
balance pass: `2026-07-19_easy-mode-balance.md` (whose model predates the
clean-cut bite of `2026-07-20_clean-eat-textured-wall.md`, which is why its
conclusions no longer held).

## What the measurement showed
A simulator (scratchpad, not committed) ports the real `CakeOps.ApplyBite`, the
auto/sliver/remnant sweeps, the layer gate, the belly + gym + purchase loop, and
a player who mows the loaf in lanes. Against the SHIPPED config it found:

| | shipped | why |
|---|---|---|
| Easy solo clear | **~18 min** (and ~47 min on another roll) | pacing was RNG, not design |
| `cakeHeightMultiplier` effect | **~2%** | a bite clears to the band FLOOR, so clear time is area-driven — thickness and height barely matter |
| cake forfeited uneaten | **~25%** | the remnant sweep collapsed any cell nicked >1 stud below its band TOP |
| `biteDepth` (5 tiers, 56k) | **~10%** total | swallowed by the same sweep |
| gym trips | every ~35 s | belly far too small for the bite volumes |

So the levers the previous balance used were the wrong ones, and two of the
sweeps were quietly eating the design space.

## Changes

**The pacing curve (ADR-0011).** Pacing moved onto the BAND: every layer is
rolled with a `scoop` (bite-radius multiplier, 2.23 at the icing → 0.558 at the
core) and a `density` (calories + belly fill per stud³, set so one bite is worth
the same FOOD at any depth). Thickness follows the ramp and is renormalised so
every cake is exactly 330 studs. Difficulty/party size buy more layers first,
then smaller scoops — never a taller cake.

**Modified:**
- `src/shared/config/CakeConfig.lua` — new `composition` model (baseLayers 28,
  maxLayers 42, maxTotalHeight 330, scoop/density/thickness ramp, `coopWork`,
  `layerExponent`, `coopCalories`); `grid.maxHeight` 270→340; `sim
  .minBiteRadiusStuds`; `autoSweepFraction` 0.12→0.10; remnant sweep rule
  `eatenEpsilonStuds` → **`nearFloorStuds`** (measured from the floor, not the
  band top); layer `hardness` spread narrowed to 0.85–1.25 and `calories`
  rescaled (the band carries the ramp now); NEW `biomeOrder`; boss retuned to a
  real finale (`bossTapsPerPlayer` 40→120, `bossDuration` 30→45).
- `src/shared/config/UpgradeConfig.lua` — all nine stats retuned
  (`capacity` 7800→84000 food units, `biteRadius` 2.7→3.4, `runSpeed` 16→20,
  costs ~8× to pace ~21/44 tiers per Easy match); **`rebirth` block deleted**.
- `src/shared/config/MatchConfig.lua` — `cakeHeightMultiplier` → `workMultiplier`
  (1 / 1.18 / 1.38) + NEW `caloriesMultiplier` (1 / 1.25 / 1.55); boss
  multipliers rebalanced so the timer always leaves ~1.5× the time a base eater
  needs.
- `src/shared/CakeOps.lua` — `ApplyBite` always processes the cell under the
  bite point (a sub-cell scoop could miss every cell centre and remove nothing).
- `src/server/game/services/CakeCycleService.lua` — `RollComposition` rewritten
  to the designed curve; NEW `CakeWork`; `CakeCaloriesMult` now includes the
  cake's `payoutScale` (difficulty premium × per-head co-op payout, fixed at
  roll time so it can't drift as players leave).
- `src/server/game/services/CakeFieldService.lua` — NEW `ScoopedRadius`;
  `ApplyBite` applies it and returns the surface BAND; remnant sweep uses the
  near-floor rule.
- `src/server/game/subscriptions/CakeSubs.lua` — a bite's `removed × density` is
  the FOOD credited to belly + calories.
- `src/server/game/data/{CakeStateData,MapConfigData}.lua` — `payoutScale`; room
  walls 300→380 (every cake is now 333 studs tall).
- `src/client/common/modules/LocalCakeField.lua` — NEW `ScoopedRadius` mirroring
  the server; prediction uses it.
- `src/client/common/subscriptions/CakeSubsClient.lua` — the bite point in front
  now scales with the effective scoop (a fixed 3.85-stud reach would leave an
  un-eaten RING around the eater on the smallest-scoop cakes).

**Rebirth removed** (files deleted: `RebirthSubs`, `RebirthSubsClient`,
`UIKit/RebirthPanel`, `remotes/DoRebirth`, `remoteUpdates/RebirthUpdate`,
`features/rebirth.md`). `ProgressService` keeps `GetRebirths`/`BiomeFor`
(biome = `biomeOrder[1]` now); `StatsService` lost the rebirth calorie term;
`UpgradeService.ResetForRebirth` and `EconomyService.ResetCalories` are gone; the
leaderstat column became **Calories** (lifetime). The profile still carries
`progress.rebirths` (always 0) → **no schema bump, no migration**.

**Upgrades made reachable (this was load-bearing for the balance).** The hex
tree was lobby-only and the published lobby has no authored `UpgradeStation`, so
it was reachable from nowhere — while the whole 40-minute pace assumes you buy a
tier at the checkpoint after each belly run. `UpgradeService` + `UpgradeSubs`
moved lobby→**common**; the tree's config/state moved `LobbyUiData` → new common
`UpgradesUiData`; `UpgradesSubsClient` is place-agnostic and now also exposes
`onToggleUpgrades`; AppRoot's HUD menu trades the Rebirth button for **Upgrades**
(badge when any next tier is affordable, `LocalUpgradeTree.AnyAffordable`).

## Result (simulated, 3 seeds each)

| clear time | 1p | 2p | 3p | 4p |
|---|---:|---:|---:|---:|
| **Easy** | **40.0 min** | 29.8 | 25.5 | 23.3 |
| Medium | 41.2 | 31.9 | 27.2 | 23.7 |
| Hard | 43.8 | 33.3 | 28.3 | 24.9 |

Easy-solo layer clear times ramp **28 s → ~150 s** across 28 layers (one
"layer cleared!" moment every ~85 s on average). Gym every ~83 s at every depth
and party size. A maxed player re-runs Easy solo in ~21 min (upgrades feel
strong, don't trivialise). Robustness: sloppier mowing / casual tapping / slow
walk-backs move Easy solo only to 41–44 min; a player who never buys an upgrade
takes 68 min, which is the intended cost of ignoring the tree.

## Verified
Studio play (game place): server boot 15/15 services + 15/15 subscriptions
(incl. `UpgradeService`/`UpgradeSubs` in-match), client boot clean with
`UpgradesSubsClient` starting and `UpgradesUiData` loading. Cake rolled as
designed — `cake rolled — 28 layers, 330 studs, work 1.00, scoop 2.30→0.57,
payout ×1.00`, `edible=2253005 studs³`. Real `EatAt` bites through the live
server path filled the belly (~394 food/bite). Both project files build.

## Open Questions / Followups
- **Feel, not numbers, is the open risk.** Check in Studio: the 7.6-stud icing
  scoop vs the 1.9-stud core chip, and that the player visibly sinks a layer as
  it clears. A scripted bite burst left the character resting above the crater —
  most likely a teleported-character artefact, but worth eyeballing.
- ⚠ Studio's `ReplicatedStorage.Shared` did NOT pick up file changes this
  session (server/client partitions did) — sources were pushed with the
  localhost HTTP trick. Re-check before trusting a Studio run.
- Numbers are model-grounded, not playtested. The fastest knobs are
  `composition.scoopTop/scoopBottom` (global pace, time ∝ 1/scoop²),
  `baseLayers` (how many clear moments), and the `UpgradeConfig` cost column
  (how much of the tree one match buys).
- With rebirth gone the long tail is difficulty + squishies + the ~3-match
  upgrade tree. If retention needs more, that is the gap to fill next.
- The 40 min is one cake. Endless respawn still exists in the non-round
  development build.

## Related
- Decision: `docs/decisions/0011-cake-pacing-curve.md`
- Features: `features/cake-cycle.md`, `cake-sim.md`, `upgrades.md`,
  `body-gym.md`, `economy.md`, `game-round.md`
- Prior flow: `2026-07-19_easy-mode-balance.md`,
  `2026-07-20_clean-eat-textured-wall.md`, `2026-07-22_lobby-matchmaking-rounds.md`
