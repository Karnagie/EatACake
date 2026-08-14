# ADR-0021 — Footprint-aware rainbow terraces

Date: 2026-08-12
Status: accepted
Supersedes in part: ADR-0020 (rainbow physical-size interpretation and six-colour silhouette)

## Context

The first playable rainbow used six masks from .62 to 1.00 radius and reached
1.5× physical size by growing from 170 to 255 edible studs. Live screenshots
showed three failures: the tall silhouette hid much of the spectrum, the narrow
top was too far from the fixed checkpoint, and its mesh perimeter formed large
spikes/triangles that bled through lower shoulders.

The field and wrapper already respected each band's local footprint. The slab
renderer did not: it averaged every band through the maximum mask, kept one
shared display/ooze surface and projected only the maximum rim. At an inner
boundary, valid but very different heights were therefore joined by diagonal
triangles. Moving the whole checkpoint inward was also unsafe because its four
floor-length legs would become colliders inside the wider cake below.

The 64×64 field cannot make the base wider than the classic 31.1-cell radius,
and the authored 100×88 plate cannot support a literal 1.5× diameter. Once the
cake becomes shorter, a stepped silhouette inside those bounds also cannot be
1.5× classic edible volume.

## Decision

1. The corrected rainbow is seven ordered ROYGBIV terraces, 204 edible studs
   (`heightScale=1.20`) and radii `.72/.76/.81/.87/.94/.97/1` from top to base.
   Solo/easy's 29 bands split `7/5/4/4/3/3/3`; the top-heavy counts compensate
   for deeper bands being physically thicker so every hue remains visible.
2. The newer shorter/wider direction supersedes ADR-0020's “1.5× size means
   height” choice. No false replacement physical metric is claimed. The exact
   1.5× requirements retained are find-gem payout and measured clear duration;
   `durationWorkScale=1.75` measures 52.09 vs 34.86 minutes (1.4943×).
3. Every rendered slab owns a layout and display state keyed by its footprint.
   Vertex heights sample only in-mask cells, and partial/ring vertices project
   onto that mask's analytic rim. Equal-footprint classic bands share the
   existing fast path. A one-slab budget cannot represent several rims and
   degrades to the visible column grid.
4. The supported checkpoint stays fixed beside the maximum footprint.
   MapService clones one authored plain `CheckpointLeg` as a horizontal pooled
   `CheckpointBridge` and spans it from the active terrace edge to the actual
   authored plate edge. Height and span both participate in the redundant-move
   guard. The post-scan `state.activeBandIndex`, not ScanStats' pre-sweep sample,
   owns the bridge pose.
5. Visual terraces and boss chapters are independent. Optional
   `groups.gateBoundaries` defaults to every boundary gated (classic); rainbow
   leaves indigo→violet open, retaining five distinct authored mini-bosses and a
   gateIndex independent from the seven-zone index. If one authoritative scan
   crosses several zones, every gated destination is queued FIFO and the Cake
   Guardian waits until the queue drains.

## Consequences

- `CakeRenderer`, field cleanup, finds, wrapper and checkpoint all consume the
  same per-band footprint contract.
- Inner layouts collapse unused fixed-topology faces onto the analytic rim.
  Geometry invariants prevent sloped cross-terrace edges; live rendering still
  owns the final shading/seam check.
- A checkpoint asset without a plain `CheckpointLeg` warns and loses only the
  bridge; the supported platform, spawn and teleport path continue degrading as
  documented.
- Seven locale keys replace the unpublished six-colour set: indigo and violet
  are explicit; the old purple key is retired before cloud publication.

## Alternatives rejected

- **Shorten/widen config only.** It reduces spike height but leaves the renderer
  mixing masks, so the topology defect remains.
- **Move the checkpoint platform to each radius.** Its legs pass through lower
  terraces and create hidden colliders; a bridge solves reach without that.
- **Grow the grid/base.** A ~96×96 field multiplies hot simulation/render work by
  2.25 and still needs new authored plates.
- **Keep six colours.** Purple is not a substitute for both indigo and violet;
  the requested full rainbow needs seven readable runs.
- **Add a sixth mini-boss.** Only five distinct rigs exist, and the sixth growth
  step can out-HP the Cake Guardian. Colour boundaries need not all be gates.
