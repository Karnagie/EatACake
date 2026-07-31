# ADR-0011 — Cake pacing lives on the BAND (scoop + density), not on height

Date: 2026-07-26
Status: Accepted
Supersedes the population/difficulty levers of ADR-0003 (`perPlayerScale`,
`cakeHeightMultiplier`).

## Context

Target: a solo player clears **Easy in ~40 minutes**, the first layers fall away
fast, and higher difficulties / bigger parties scale sensibly.

The shipped tuning could not express any of that, and a simulation that ports
the real `CakeOps.ApplyBite`, the three `ScanStats` sweeps and a mowing player
showed why:

- **Easy solo actually took ~18 min**, and the same config took **~47 min** on a
  different composition roll — a 2.6× swing driven purely by RNG.
- **`cakeHeightMultiplier` moved solo clear time by ~2%.** A bite clears its
  footprint *toward the active band's floor*, so a layer costs the same number
  of bites whether it is 5 or 25 studs thick. Height (the only difficulty and
  co-op lever we had) is therefore almost a no-op on time, and the whole
  difficulty ladder was cosmetic.
- **~25% of every cake was forfeited uneaten.** The remnant sweep collapsed any
  cell bitten more than 1 stud below its *band top*; on chunky bands one nick
  deleted the rest of the cell for free. That also flattened the bite stats:
  `biteDepth`'s five tiers were worth ~10% end to end.
- Belly filled every ~35 s, so the loop was a stream of gym trips.

## Decision

Pacing is a property of the **band**, expressed as two rolled numbers per layer
(`CakeCycleService.RollComposition`, tuned in `CakeConfig.composition`):

- **`scoop`** — multiplies the eater's `biteRadius` on that band. Ramps
  geometrically from **2.23** at the icing to **0.558** at the core, so a base
  eater takes a ~7.6-stud spoonful of frosting and a ~1.9-stud chip of the dense
  bottom. Since a bite clears to the floor, clear time scales with bite AREA —
  this is the pacing curve, and it reads on screen without a tutorial.
- **`density`** — how rich/filling that band is per stud³ (calories AND belly
  fill). Set to `refBandWeight / (thickness × scoop²)`, i.e. exactly the value
  that keeps the FOOD in one bite constant as the scoop shrinks. That is what
  holds the belly→gym rhythm at ~90 s and the calorie income flat from the first
  layer to the last, on every difficulty and party size.

Layer thickness follows the same ramp (deeper = chunkier) and is renormalised so
**every** cake is exactly `maxTotalHeight` (330 studs at the time of this ADR;
**170 since 2026-07-26** — see the note at the end) tall. A harder or more
crowded cake is not a taller tower: it has **more, thinner layers and smaller
scoops** — more "layer cleared!" moments inside the same silhouette.

Work (`MatchConfig.difficulties[x].workMultiplier × (1 + coopWork·(n−1))`) buys
extra layers first (`layerExponent`), and whatever the `maxLayers` cap cannot
absorb becomes smaller scoops. Calorie payout scales separately
(`caloriesMultiplier` × per-head `coopCalories`) so co-op and hard mode pay for
themselves.

Two supporting fixes make the curve possible at all:
- the remnant sweep's rim rule is measured from the **active floor**
  (`nearFloorStuds`) instead of the band top, so it cleans the rim instead of
  deleting the layer;
- `ApplyBite` always processes the cell under the bite point, and the effective
  radius is floored (`minBiteRadiusStuds`), so the smallest scoops still bite.

## Consequences

- Sim-measured: **Easy solo 40 min**, medium 41, hard 44; 4-player 23–25 min.
  First layer ~28 s, last ~150 s. Gym every ~83–110 s everywhere. A player
  finishes an Easy match owning ~21 of 44 upgrade tiers.
- `cakeHeightMultiplier` and `composition.perPlayerScale` are **gone**. Anything
  that wants a "bigger" cake changes `workMultiplier` / `coopWork`.
- The composition bands now carry `scoop` and `density`, and they ride the
  snapshot meta — the client mirrors the scoop in `LocalCakeField.ScoopedRadius`
  for bite prediction and for placing the bite point in front of the eater.
  **A change to the scoop rule must be made on BOTH sides or prediction pops.**
- Calories/belly are computed from `removed × density`, not raw volume. Belly
  numbers are "food units" now (capacity base 84 000), not studs³.
- The cake is always 333 studs tall, so the room walls were raised to 380.
- Risk: the curve is calibrated against a model, not a playtest. The model ports
  the real bite math and sweeps, and its predictions held across seeds and
  player-skill variations (±4 min), but the FEEL of a 7.6-stud icing scoop vs a
  1.9-stud core chip is the thing to check first in Studio.

## Alternatives rejected

- **Depth-capped bites** (bite removes a bounded depth, so thickness drives
  time). Modelled and rejected: it turns the surface into a bowl landscape and
  the eater digs a pit they cannot walk out of — it would undo the deliberate
  "one flat walkable surface, straight-line eating" work of the collision
  rework. Clearing to the floor is what keeps the floor flat.
- **Scaling work by the loaf FOOTPRINT.** Capped by the 64-cell grid; growing
  the grid inflates the per-slab vertex budget and the three 1 Hz full-field
  scans on exactly the weak devices ADR-0008 protects.
- **Scaling work by hardness/toughness alone.** Beyond ~2× the bite stops
  clearing anything to the floor and eating becomes shaving a fraction off every
  cell — visible progress dies. Hardness stays a narrow per-layer identity knob.

---

## Note — 2026-07-26: `maxTotalHeight` 330 → 170

This ADR's invariance claim was later MEASURED rather than reasoned about, with
`tools/headless-sim/pacing_scenario.lua` (mows a whole cake through the real
`CakeOps.ApplyBite` + layer gate). At 330 / 170 / 110 studs: bites +0.5% / +0.0%,
food +0.0% / +0.0%. The claim holds exactly — clear time is area-driven and the
per-band `density = refBandWeight / (thickness x scoop^2)` absorbs the thickness
change — so height was reduced purely for the SILHOUETTE (at 330 on a 90x78
footprint the loaf read as a striped tower, not a cake).

⚠ The boundary the measurement also found: below ~130 studs the deepest band's
density approaches `maxDensity` (11.7 of 12 at 110) and the thinnest band hits
`minLayerThickness`. Clamp either and the invariance breaks — the curve is only
free between roughly 130 and 330.

