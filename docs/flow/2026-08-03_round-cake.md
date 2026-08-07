# 2026-08-03: Round cake (equal-area)

Tags: cake-sim, cake-cycle, map, checkpoint, treasures, balance, render

## Task
> "Make the cake round, but keep its area the same so the balance doesn't change."

## Context
The cake was a rounded-rectangle **loaf**, `composition.footprint =
{hx=30, hz=26, corner=10}` cells on a 64×64 grid at 1.5 studs/cell — 90×78 studs.
Clear time and income are **area**-driven (ADR-0011): a bite clears its footprint
to the active band's floor, so the pacing curve is tuned against how much cake
there is in XZ, not how tall it is. That is exactly why the user's constraint is
the right one — changing the silhouette is free only if the area holds.

## Plan
1. Find the *right* invariant. Not continuous area — the **cell count** passing
   `GridUtil.InCake`. Edible volume = cells × cell² × height and height is always
   `composition.maxTotalHeight`, so calories, belly fill and clear time all scale
   with the cell count and nothing else.
2. Express "round" without a new shape type or a second code path.
3. Solve for the radius, then **measure** the before/after with the project's own
   `tools/headless-sim/pacing_scenario.lua` rather than asserting it.
4. Sweep every consumer of `footprint` for rectangle assumptions.

## Changes

**Modified:**
- `src/shared/config/CakeConfig.lua` — `footprint = {hx=31.1, hz=31.1, corner=31.1}`
  (was `{30, 26, 10}`), with the invariant + the area math written down.
- `src/client/common/modules/CakeWrapper.lua` — the outer wall Part goes
  **Block → Cylinder** (upright rotation, `(HEIGHT, ⌀, ⌀)` sizing, re-mapped
  texture faces). Without this the cake reads square from the side.
- `src/server/game/data/MapConfigData.lua` — tray `114×102` → `117.3` square
  (restores a uniform ~12-stud lip); checkpoint-placement and candle comments
  rewritten for a shape with no straight edge.
- `src/server/game/subscriptions/CakeCycleSubs.lua` — the new-cake player lift
  test: AABB → the footprint's own rounded-rect SDF in world studs, grown 4 studs.
- `src/server/game/services/CakeFieldService.lua` — build log reports `⌀N studs`
  (it printed `{hx*2}x{hz*2} cells`, which reads as a square for a disc). R8.
- `src/server/game/services/MapService.lua` — comments only (`loafEdgeX` is now
  an extreme reached at one point, not an edge).
- `docs/features/cake-sim.md`, `docs/features/cake-cycle.md` — the above.

## Decisions

**A circle is `hx == hz == corner`, not a new shape.** `GridUtil.InCake` is the
standard rounded-rect SDF (`|q| − (h − corner)` clamped at 0, then `|q| ≤ corner`).
Setting the corner radius equal to *both* half-extents collapses the straight
edges to zero length and leaves a pure disc of radius `corner`. This was worth
more than the one-line diff suggests: **every downstream consumer inherits the
circle for free**, with no branch and no second path —
- `CakeRenderer`'s rim projection: `rectX = (hx+0.5)*cell − cornerR` → `0`, so
  `clamp(x, -0, 0)` makes the projection `dir * cornerR` — an exact circle;
- `CakeWaxShell`'s outline: its four quarter-arc centres all collapse to the
  origin and concatenate into one circle;
- `TreasureService`'s inset subtracts `margin` from all three and stays a disc;
- `CakeCollisionService`, `CakeOps`, `SurfaceHeightAt` never knew the shape.

The risk this creates is that the triple looks redundant and invites "tidying" —
so the invariant is stated at the config, in the feature doc, and again wherever
the three are read apart.

**The balance quantity is the CELL COUNT, not the area.** Matching continuous
area (R = 31.0774) lands on 3024 cells, −0.40%. Matching the *lattice* gives
R = 31.1 → **3032 cells vs the loaf's 3036, −0.13%**, which is the closest a
64-cell grid reaches — the count steps in jumps of 4-8 cells, so 3036 is simply
not reachable by any disc. Values are floats on purpose; nothing loops over them.

**Measured, not asserted.** `pacing_scenario.lua`, A/B by patching only the
footprint line of the generated `sim.luau` (deterministic — verified identical
across 3 seeds):

| | loaf | round | Δ |
|---|---|---|---|
| fresh — session | 91.6 min | 92.0 min | +0.4% |
| fresh — food | 4 628 766 | 4 616 809 | −0.3% |
| fresh — waste | 14.1% | 14.2% | +0.1 pp |
| maxed — session | 27.8 min | 27.4 min | −1.4% |
| maxed — food | 5 252 872 | 5 178 910 | −1.4% |
| maxed — waste | 2.6% | 3.8% | +1.2 pp |

The residual beyond the −0.13% cell delta is **shape**, not area: a disc is
staircased *everywhere*, where the loaf had two long clean straight edges, so
`sim.remnantSweep` finds slightly more isolated rim cells to forfeit. It shows up
on the maxed run because a big scoop clears interiors fast and spends
proportionally more of its time on the rim. Everything stays far inside ADR-0011's
tolerance (the failure that ADR fixed was ~25% waste).

**The wrapper had to become a cylinder.** It is the cake's visible SIDE. A Block
around the loaf poked ~6 studs at 4 corners — an accepted trade. Around a disc a
Block pokes `R(√2−1)` ≈ **19 studs** and the silhouette reads square, which
defeats the request. Roblox cylinders are axis-along-local-X with the caps on ±X,
hence the upright rotation and the `(HEIGHT, ⌀, ⌀)` size; after rotating, the top
cap is `NormalId.Right` and the curve is textured by Front/Back/Top/Bottom, each
covering one 90° quadrant — the same four-strip tiling the Block had on its four
flat sides, so the texture wrap is unchanged.

**Fixed a regression the shape change would have caused.** `CakeCycleSubs` lifted
players out of materializing cake using an **AABB** (`hx*cell+4` by `hz*cell+4`).
A box around a disc over-reaches by √2 at the diagonals: the wrong region (inside
the box, outside the cake) grows from 1597 studs² under the loaf to 3425 studs².
A player standing on a tray corner — which is exactly where the landmark candles
are — would be teleported to cake-top height with no cake under them, a ~170-stud
fall on every new cake. Replaced with the footprint's own SDF in world studs,
grown by a body width. Deliberately *not* routed through the cell grid: the grown
shape reaches past the 96-stud field along the axes and an `InBounds` check would
clip precisely the margin the test exists to provide. The bug predates this task
(the box already over-reached the loaf) but the disc more than doubles it, so it
is in scope.

**The tray needed to grow.** The default tray was `114×102`, a uniform 12-stud lip
around a 90×78 loaf. Against a 93.3-stud disc that lip becomes 10.4 studs in X but
only **4.4 in Z** — which reproduces the exact bug the 2026-07-26 map pass fixed
("a 5-stud lip read as a bare slab; the cake appeared to meet the floor with
nothing under it"). `117.3` square restores the uniform ~12.

## Adversarial review (mandatory, CLAUDE.md) — what it caught
It independently recomputed the cell count (3032, agreeing), and cleared the
cylinder mapping, the lift-test SDF equivalence, every `footprint` reader under
`hx==hz==corner` with float values, the grid fit (in-cake cells span 1..62, hosted
verts 0..64 of VSIZE 65), the treasure rejection sampler's termination, and the
exploit/persistence surface. It found one real defect and a set of stale
contracts, all fixed here:

- **The rim wax streamer (WARN).** `CakeWaxShell.cellAt` clamps into the grid but
  never tests `InCake`, and out-of-cake cells hold height 0 — so a boundary vertex
  sampling one is written at the cake base, stretching two fan triangles ~170 studs
  down the side. The reviewer produced a concrete reachable case in the first
  octant, and noted it is DETERMINISTIC (fixed RNG seed + fixed footprint), so it
  would look identical on every client and every cake. Latent on the loaf (only the
  4 corner arcs); the disc makes the entire rim an arc. Fixed with an in-cake
  fallback for both `vc` and `tc` samples. Verified from two side angles in Studio
  — the top-down check I had done could not have shown it.
- **The Python balance oracle still modelled the loaf** (`tools/balance-model/pacing.py`),
  and its sync check prints a banner but runs anyway. Updated. (Its remaining
  `upgrades.biteRadius/biteDepth` mismatches are PRE-EXISTING drift, unrelated.)
- **Stale contracts, now fixed:** `GridUtil.InCake`'s own header still said
  "rounded RECTANGLE (loaf cake)" — the one place every consumer reads the three
  values apart, and so exactly where the invariant had to be stated;
  `CakeConfig.render.wrapper` still described the Block wall; `MapConfigData`'s
  `edgeGap`/`plateWidth` comments still cited a straight edge.
- **`liftMarginStuds`** moved out of `CakeCycleSubs` into `CakeConfig` (R1/R2 — it
  is a tuning number). ⚠ My first attempt read `comp.liftMarginStuds` where no
  `comp` local existed; `luau-compile` cannot catch a global read, so it took the
  scope check to find it. Worth remembering: the syntax gate is not a name checker.
- **The default generator's fallback plate** was still a square Block under a round
  cake — now a `CylinderMesh` too, ⌀117.3.
- **The wax outline** collapsed to a 24-gon whose 4 seam points were duplicated,
  making 4 zero-normal no-op clip planes ("correct by luck"). Deduped, and the arc
  resolution raised to 8 steps/quarter so the inset sag drops ~0.39 → ~0.22 studs.
- **`docs/flow/INDEX.md`**: my appended row was preceded by a blank line (the file
  has MIXED line endings, so the "does it end in a newline" check appended a second
  one), which terminates a GFM table. Fixed at the byte level.

Not fixed, by decision: the cake's collision columns now overlap the checkpoint
plate's inner edge by ~0.675 studs where they used to clear it by the same amount
(anchored, non-colliding-with-plate; it removes the gap at z=0 rather than adding
one), and `CheckpointHideMarginStuds` is ~0.65 studs short of the true rim — a
pre-existing off-by-a-rim-radius whose stated reasoning, not whose value, is wrong.

## Follow-ups from playtesting (same day, user-reported)

**1. The wall texture was rotated 90°** — the cream layers ran as vertical columns.
Cause was the shape primitive, not the image: a native `Enum.PartType.Cylinder`
Part has its axis on LOCAL X, so standing it upright takes a `CFrame.Angles(0,0,
pi/2)` that rotates the face UV frames with it. Fixed by rendering the wall as a
Block Part carrying a **`CylinderMesh`** — that mesh runs along the part's own Y, so
the part stays axis-aligned, `Size` is the honest `(⌀, height, ⌀)`, and every
Texture maps exactly as it did on the original Block wall. Picked by building all
three candidates (native cylinder / CylinderMesh / 24-segment Block ring) side by
side in Studio and looking, rather than reasoning about UV frames.

**2. The texture was stretched in Y — and `tileStuds` did nothing.** My first
attempt here was WRONG and the user caught it. I reasoned that the `CylinderMesh`
bends the flat face onto a quarter arc, compressing U by `pi/4`, and "fixed" it by
dividing the U tile by `pi/4` — then verified by reading back the properties I had
just set and reporting "ratio 1.000". That measured my own arithmetic, not the
render.

The real behaviour: **a part carrying a mesh maps its Decals/Textures through the
MESH's UVs and ignores `StudsPerTile` completely.** Proven by setting the live wall
to 55, then 20, then 5 — pixel-identical every time. The image is stretched ONCE
over the whole cylinder, which is also why it would re-stretch each time the wall
shrinks a layer.

So the wall is now a **ring of 32 flat Block segments** (+ a meshed disc for the top
cap, where a single mapped photo is correct). Flat block faces tile for real —
verified against a plain-Block control in the same shot — and each segment carries
`OffsetStudsU` = its cumulative width so the tiling phase runs continuously around
the ring rather than restarting at each seam. Cost is 33 anchored, non-colliding,
non-query parts and mild facet shading (32 segments put the sag at 0.23 studs on a
47.4 radius). Confirmed on the live wall: 55 → ~9 bands, 110 → ~5. `tileStuds` is a
real knob again.

**Lesson, recorded because it cost a round trip:** verify a rendering property by
CHANGING IT AND LOOKING. Reading back the value you just assigned proves only that
the assignment happened.

**3. "Sometimes I spawn in the cake" — a JOIN RACE, not the round cake.**
Reproduced immediately: HRP at Y=141 with the cake surface at 174.8, i.e. 34 studs
inside and stuck. `CakeSpawn` drops the character the instant the player joins, but
the cake only becomes collidable when this client finishes its first
`columnsRebuild` — and `editableRebuild` YIELDS before it (lazy mesh-pool build).
So on a slow load you fall through and the columns come up around you. **A forced
mid-session respawn landed perfectly on top (177.99 vs surface 174.9)** — that A/B
is what identifies it as a load race rather than spawn geometry, and it is
shape-independent (the pad is at the cake centre under either footprint), so it
predates this change. Fixed client-side because only the client knows when its own
columns went up: `rescueBuriedLocal` runs right after `OnSnapshot`. Verified by
burying a character 30 studs and running the rescue's exact decision — detected
(30.04 ≥ 6) and recovered to standing on the surface.

## Open Questions / Followups
- **⚠ OPEN — the authored plate is too small in Z.** `MapConfigData.platform` is
  DEFAULT-GENERATOR ONLY (ADR-0007); the live scene clones a Studio-authored
  `ReplicatedStorage.Assets.Environment`, so the config edit does not move
  anything. Measured live: `CakePlate` is **100 × 88** (±50 × ±44), so the
  46.65-stud cake clears it by 3.35 studs in X and **overhangs by 2.65 in Z** —
  the cake visibly hangs off its own plate on two sides. Needs a human/Studio-MCP
  re-model: make it ROUND, ⌀ ≥ 117 (46.65 + a ~12-stud lip). Not done here —
  authored art is not edited from a code task.
- **The checkpoint plate's gap to the cake now varies.** It is `edgeGap` (0.5) at
  z = 0 and opens to ~2.3 studs at the plate's z-ends (±13), because a disc curves
  away from a straight plate edge. Crossing happens at the centre (the F teleport
  lands mid-plate, the walk-back runs along z ≈ 0), so the normal path is
  unchanged — but the two cake-side plate corners are a hop, not a step. Left as
  is rather than shrinking `plateWidth`, which would churn the treadmill/station
  layout. Revisit if playtesters catch a foot there.
- **Studio-VERIFIED 2026-08-03** (place `EatACake-Game`, Rojo live, playtest):
  `luau-compile` clean over 214 files; wrapper builds as
  `Shape=Cylinder Size=(166.18, 94.80, 94.80)` with its local X axis at world
  `(0, 1.00, 0)` — upright — and all 5 textures on the right faces; the curved
  side tiles the cake photo correctly (no blank quadrants, which was the risk in
  leaving the Block); top-down the surface, wax rim and outline are a clean
  circle; **0 errors** in the client log (1 warning, the pre-existing
  ShopPanel `free`-section one). The predicted checkpoint gap was confirmed to
  the centimetre: 0.50 studs at z=0, 0.96 at ±6.5, 2.35 at ±13.

## Related
- Feature: `docs/features/cake-sim.md`, `docs/features/cake-cycle.md`
- ADRs touched: ADR-0011 (pacing curve — the area invariant), ADR-0007 (authored
  scene beats the default generator), ADR-0003/0008 (cake sim)
- Tool: `tools/headless-sim/pacing_scenario.lua`
