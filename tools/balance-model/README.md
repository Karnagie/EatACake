# balance-model — how long is a run, and when is the upgrade tree maxed?

One script: `pacing.py`. It answers the two questions the game's pacing targets
are stated in, neither of which the other tools measure:

| Question | Target |
|---|---|
| How long does a solo easy cake take, end to end? | ~40 min |
| What fraction of the cake is eaten by the time every tier is owned? | ≤ 50% |
| How OFTEN does the belly send the player to the gym, per capacity tier? | 10 / 30 / 90 / 120 / 150 / 180 s (ADR-0019) |

```bash
python tools/balance-model/pacing.py             # validate + report the LIVE config
python tools/balance-model/pacing.py --intervals # seconds per belly, by capacity tier
python tools/balance-model/pacing.py --solve     # sweep cost scales
python tools/balance-model/pacing.py --grid      # sweep cost scale x work
```

Needs `numpy`. No Roblox, no Luau, no Studio.

## Why it exists next to `tools/headless-sim/`

`headless-sim` runs the **real `src/` modules** and is the authority on bite math —
prefer it. Two gaps made this necessary in July 2026:

1. It needed the standalone Luau CLI, which was not installed at the time. (It IS
   installed now — `luau` / `luau-compile` are on PATH — so the two tools can and
   should be cross-checked. Reason 2 below still stands and is the real one.)
2. It measures the upgrade curve's **endpoints** (a fresh eater, a maxed eater) as
   two separate cakes. The run people actually play is neither: calories come in,
   tiers get bought mid-run, and the eater speeds up as it goes. You cannot
   interpolate "126 min fresh / 33 min maxed" into the real number — and the
   documented "40 min solo easy" was in fact **54.6**, which is why a playtest
   came back at 1 h 01 m.

This model simulates that middle: a mowing player who banks calories at the gym
and spends them cheapest-tier-first.

## What it models

`RollComposition` (scoop ramp, thickness, per-band density), `CakeOps.ApplyBite`,
the layer gate, the sliver + remnant sweeps (both forfeiting, both capped by
`sweepBandFraction`), per-layer hardness/calories, belly → gym trips, and tier
purchases.

**Not** modelled: the settle automaton (it only reshapes the cut edge), walking
between craters, boss/reveal/spawn time, pets, gamepasses, rare cakes. So its
clear time is a floor — real sessions add a few minutes of boss and travel.

Note it assumes an OPTIMAL mower (it always centres the scoop on the tallest
remaining cell). Before the 2026-07-30 aim fix that made it optimistic, because a
real player running head-on into a layer wall was losing bites entirely
(`features/cake-sim.md`). With the aim search in, optimal mowing is roughly what
head-on play now achieves, so the model tracks reality much more closely.

## Drift guards — read this before trusting a number

It is a PORT of Lua math, so it can silently diverge. Two protections, both
automatic:

- **`check_config_sync()`** re-reads `CakeConfig.lua`, `UpgradeConfig.lua` and
  `MatchConfig.lua` and prints a loud failure for every mirrored constant that no
  longer matches (grid, footprint, the whole composition curve, sim/sweep
  distances, per-layer hardness + calories, all 44 tier values AND costs,
  difficulty work multipliers). If it complains, fix the model — do not read the
  numbers below it.
- **`validate()`** prints the endpoint runs so they can be compared against
  `headless-sim`.

⚠ Porting this found a real bug in `headless-sim/pacing_scenario.lua`: it
multiplied `CakeOps.ApplyBite`'s return — already a volume — by `cellArea` a
second time, inflating food 2.25×, hence belly→gym trips 2.25×, and understating
the forfeited fraction by the same factor (6.8% published vs ~17% actual). Fixed
there. When the Luau CLI is available, re-run both and reconcile; they should now
agree closely, and the two are only useful as a cross-check of each other.

## ⚠ Fixed 2026-08-05: `apply_bite` booked NEGATIVE food at the loaf rim

`new_h = np.maximum(floor_units, sub_h - delta)` applied the band-floor clamp to
the WHOLE bite window, not just to the cells the bite was allowed to touch. Every
out-of-cake cell in the window (height 0) was raised to the floor and the rise was
summed as *negative* removed volume — so every bite whose disc overlapped the rim
under-reported food, and the OPENING bites were catastrophic, because `argmax` on
a flat field tie-breaks to the lowest index, i.e. the rim. Nothing crashed and the
totals stayed positive, which is why it survived a rebalance and a published clear
time. Lua has no such bug: `CakeOps.ApplyBite` iterates only the cells it selected.

If you port more of the Lua bite math here, the rule this cost us: **a vectorised
form must apply its write under the same selection mask the scalar loop iterates**,
and a model that cannot produce a negative quantity should assert that it doesn't.
