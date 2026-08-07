# ADR-0019 — The belly-fill INTERVAL is the progression curve

Date: 2026-08-05
Status: accepted
Supersedes in part: ADR-0011 (the "~90 s belly→gym rhythm" constant), ADR-0013
(the cost table it published)

## Context

A player reported that progression in EatACake is not noticeable, and asked for
the belly to fill roughly every 10 s at the start, every 30 s after the first
upgrade and every 1 min 30 s after the next.

Measuring the shipped config (`tools/balance-model/pacing.py --intervals`, solo
easy, 5 seeds) showed the complaint was structurally correct, and worse than
"not noticeable" — **the curve ran backwards**:

| capacity tier | value | seconds of eating per belly |
|---|---|---|
| base | 84,000 | **227** |
| I | 110,000 | 178 |
| II | 145,000 | 188 |
| III | 190,000 | 165 |
| IV | 255,000 | 164 |
| V | 335,000 | **102** |

Two independent facts produced that:

1. **`capacity` grew 4× across the tree; eating power grows ~20×.** The doc and
   the config both said ~2.4×, which was true until a later hand-tune (commit
   `1c21a15`) moved `biteRadius` base 3.4 → 2.4 and `biteDepth` 3.6 → 2.6 while
   pushing their TOP tiers up. Nobody re-measured. Capacity lost the race, so
   every upgrade the player bought made the interruption *more* frequent.
2. **The first belly took 3.8 minutes and then paid for eleven tiers at once.**
   With one banking event worth ~11,700 calories against a 5,600-calorie row of
   tier-1 prices, the entire early tree arrived in a single lump — the opposite
   of a felt ramp.

## Decision

**`capacity` is the game's pacing stat and is tuned as an interval curve, not as
a belly size.** The design input is *seconds of eating per belly at each tier*;
the food-unit values are outputs, solved against the model:

| tier | value | measured s/belly | target |
|---|---|---|---|
| base | 4,400 | 10.0 | 10 |
| I | 13,000 | 30.6 | 30 |
| II | 58,000 | 89.1 | 90 |
| III | 120,000 | 122.3 | 120 |
| IV | 235,000 | 148.5 | 150 |
| V | 645,000 | 183.8 | 180 |

Two changes fall out of it and are part of the same decision:

- **Tier-1 costs ~0.55×, per-tier ratio 3.1 → 3.4.** A 10-second belly banks ~612
  calories, so a 850-calorie first tier would leave the opening loop paying for
  nothing. Steepening the ratio holds the tree total (772,250 → 755,260) and with
  it the "whole tree owned by ≤50% of the cake" target from ADR-0013.
- **`burnSpeed` base 0.06 → 0.20.** Burn time is a FRACTION of the belly, so it is
  a constant ~1/value seconds *at any belly size* — it does not shrink when the
  belly does. At 0.06 the hands-free burn took 16.7 s against a 10 s belly, i.e.
  longer than the eating it interrupted.

## Consequences

- Measured, solo easy, 5 seeds: clear **35.3 min** (eat 29.6 + gym 5.7), **22**
  belly→gym trips, tree complete at **48% of the cake** (5/5 seeds), ~6%
  forfeited. Before: 38.7 min (eat 33.4 + gym 5.3, 20 trips).
  ⚠ Total gym time went slightly UP (+0.4 min: two more trips, each much
  shorter). The entire 3.4-minute win is **EAT** time, and it is bought by the
  halved tier-1 prices, not by `burnSpeed` — the eating stats now reach the
  player minutes earlier, so they clear cake faster for the rest of the run.
  `burnSpeed` 0.20 pays for the extra trips rather than shortening the session.
- **The first two purchases are now the most legible upgrades in the game** (3×
  then 3× on the interruption interval), which is exactly what the request asked
  for. It also makes the onboarding flow work: one 10-second belly pays for
  `biteRadius` I, which is what the tutorial's step 3 now waits for
  (`features/tutorial.md`).
- **`capacity` base is no longer a whole-session number.** It is sized for the
  first ~10 seconds of a run, so the headless-sim's "fresh eater clears a whole
  cake" endpoint stopped being a meaningful session estimate (478 min) and now
  says so in its own output. `tools/balance-model/pacing.py` — which buys tiers
  mid-run — is the only measure of a real run.
- **New coupling to protect.** `capacity` base × the frosting band's calories must
  stay comfortably above `biteRadius` tier-1's cost, or a first-time player is
  stranded full with no guidance. `pacing_scenario.lua` section D asserts a ≥×1.2
  margin (currently ×1.36) so a re-price fails in a tool rather than in a
  playtest.
- The x2 capacity gamepass/boost still stacks multiplicatively, and now doubles a
  *rhythm* rather than a number nobody could feel.
- Number of gym trips per cake barely moves (20 → 22), so per-drain
  `PersistenceService.Save` pressure is unchanged; purchases are now spread over
  many small trips instead of arriving in one 11-tier lump, which lowers the
  worst-case burst.

## Alternatives rejected

- **Leave capacity alone and slow eating power down instead.** That fixes the
  ratio by making the upgrades weaker, i.e. by removing the thing the player is
  buying. The complaint was that progression is invisible, not that it is fast.
- **Scale all costs by one factor.** A flat 0.55× would have finished the tree at
  ~30% of the cake, breaking ADR-0013's target. The ratio had to move with it.
- **Keep `burnSpeed` at 0.06 and rely on tapping** (10 taps clears any belly, and
  `tapsPerSecondCap` is 14). Tapping is what an engaged player does; the passive
  rate is what everyone else experiences, and it must not be the longest part of
  a 10-second loop.
- **Change `MatchConfig.workMultiplier` to restore the 38.7-min clear.** It would
  have shifted every difficulty's balance to claw back time the player earned by
  reaching their eating stats sooner, and re-shifted the interval curve that had
  just been solved.
