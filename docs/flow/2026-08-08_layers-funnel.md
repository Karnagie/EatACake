# 2026-08-08: Layers funnel — how deep a run gets

Tags: analytics, funnel, cake-cycle, tooling

## Task
> "Add a funnel for layers - i want to see how many layers players clear"

## Context
`docs/features/analytics.md` (the catalog, the quotas, the 8 existing funnels)
and `docs/features/cake-cycle.md` (the 1 Hz layer gate, the zone gates). The
game already fired three beats when a layer was cleared — `first-layer` (flow
step 21, once per session), `match:layer` (once per round) and the
`layer_cleared` counter — and **none of them can answer "how many"**: the first
two fire on the FIRST layer only, and a counter has no per-attempt shape.
Prior flow: `2026-08-02_analytics-player-flow.md`,
`2026-08-07_cake-zones-and-mini-bosses.md`.

## Plan
One new funnel with **one step per layer of DEPTH**, so the dashboard's own bar
chart is the answer: step N = "cleared N layers on this cake". Fire it from the
single place the layer gate advances, next to the beats already there.

## Changes

**Modified:**
- `src/shared/config/AnalyticsConfig.lua` — new `layers` funnel (`CakeLayers`,
  `session = "visit"`); `maxLayerDepth = 42` + generated steps `l1`..`l42`;
  `AnalyticsConfig.LayerStep(depth)`; funnel occupancy comment 8→9 of 10
- `src/server/game/subscriptions/CakeSimulationSubs.lua` — the layer-gate beat
  block now reports depth: one funnel step per depth crossed (skipped depths
  filled, capped at 8/scan with a warn), and `layer-cleared` carries
  `depth / total edible layers / zone` instead of the default field triple. Boot
  check: cake `maxLayers` > `maxLayerDepth` warns (R8)
- `tools/headless-sim/catalog_xcheck.py` — rebuilds the GENERATED step keys, so
  the layers funnel is cross-checked like every hand-written one
- `tools/headless-sim/analytics_scenario.lua` — new section, 66 → **76 checks**
- `docs/features/analytics.md`, `docs/features/cake-cycle.md`, `docs/MAP.md`,
  `docs/registries/data-keys.md`

## Decisions

**Per-layer steps, not buckets.** The funnel step limit is 100 and the deepest
cake the config can roll is 42 layers, so full resolution is affordable and it
is what was asked for. Cost per player per cake: 28-42 critical events spread
over ~35 min (~1/min), against a 140/min solo budget.

**`session = "visit"`, not `"round"`.** A cake is the attempt. `Session.Funnel`
already opens a new attempt when a `visit` funnel's FIRST step lands, and depth 1
is that step — so a new cake starts a new attempt with no extra wiring, and the
endless-fallback build's second cake is not swallowed by the first one's
seen-set. In a reserved match (one cake per round) it is identical to `round`.

**Analytics owns `maxLayerDepth`; it does not read `CakeConfig`.** A funnel step
NUMBER is a permanent contract with 90 days of already-recorded data — step 7
must mean "7 layers" forever — and generating the list from live cake tuning
would let a balance change renumber history. Steps past the shipped cake size
read zero, which is the honest answer. The coupling is enforced in the other
direction instead: `CakeSimulationSubs` compares the two at boot and WARNS if a
cake could roll deeper than the funnel is long (R8 — otherwise Roblox accepts the
extra step numbers and drops them).

**Steps are generated, and the cross-check tool was taught to generate them
too.** Forty hand-written rows that must equal an integer sequence are forty
chances to typo one. But `catalog_xcheck.py` parses funnel steps out of the
config text, so a generated funnel would have been invisible to it — it now
rebuilds `l1..lN` from `maxLayerDepth`, or every depth call site would have read
as an unknown step (or, worse, no step at all).

**Skipped depths are filled in.** The gate normally moves one band per scan, but
a paid `eatlayer` clear or a wide scoop through thin frosting can cross several
inside one 1 Hz window. A funnel with a hole in it reads as a data error, so the
gap is filled — bounded at 8 per scan, with the clamp REPORTED rather than
silent, so a pathological jump cannot spend a minute's budget in one frame.

**`layer_cleared`'s fields changed.** It carried the default cohort/platform/place
triple, all three of which the funnel already provides for the same moment. It now
carries the CAKE's side of the story — depth, the cake's total edible layers,
the flavour zone — because the total is the denominator that tells a real cliff
apart from a cake that simply ENDED (~28 layers solo-easy vs the 42 cap on a hard
4-player cake). Cost: nothing; both vocabularies are ≤42 bounded values.

**The depth formula was measured, not reasoned.** `depth = #composition -
activeBandIndex` rests on two facts (band 1 is the inedible core; the gate starts
at `#composition`), and an off-by-one would mis-report every number the feature
exists to produce. A throwaway scenario drove the REAL `RollComposition` +
`ClearActiveBand` + `ScanStats`: 29 bands = core + 28 edible, depths 1..28 each
reported exactly once, the last one landing exactly when `IsBottomReached()` goes
true. Removed after it passed.

## Open Questions / Followups
- **Not verified in Studio** — analytics is server-only AND published-place-only,
  so the funnel cannot be observed anywhere but the live dashboard. The headless
  scenario covers the mechanics; the numbers themselves land ~24 h after a
  publish.
- The funnel's tail (steps ~29-42) is only reachable on harder/co-op cakes. Break
  down by difficulty (the funnel's third field) before reading it. If that proves
  annoying in practice, the alternative is a PERCENT-of-cake funnel — comparable
  across cake sizes, but it stops answering "how many layers".

## Related
- Feature: `docs/features/analytics.md` (`CakeLayers` section),
  `docs/features/cake-cycle.md`
- ADRs touched: ADR-0017 (analytics quotas) — no change, the slot budget it
  documents just went 8 → 9 of 10
- Prior flow: `docs/flow/2026-08-02_analytics-player-flow.md`
- Upstream: EAC-0266
