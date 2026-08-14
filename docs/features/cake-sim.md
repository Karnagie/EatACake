# Cake simulation (granular heightfield)

## What it does
ONE shared cake per server: a 64×64 u16 heightfield (fixed-point 0.01
studs, `GridUtil` layout) inside a fixed **ROUND** maximum footprint
(`composition.footprint`, a 93.3-stud disc). Classic is 170 edible studs;
selectable rainbow is 204, still below `grid.maxHeight=340`. Difficulty
and party size do not change the selected silhouette: they add thinner layers
and smaller scoops (cake-cycle.md, ADR-0011/0020).

Each composition band may carry its own smaller `footprint`. `ResetCake` raises
each cell only through the highest band whose mask contains it, so the rainbow's
seven progressively wider colour groups materialize as terraces rather than a
full cylinder. Initial edible/band volumes are measured from those exact masks;
auto-, sliver-, remnant- and paid-layer sweeps use the active band's footprint.
Classic bands all use the maximum disc and remain byte-for-byte cylindrical. The
renderer draws only the current + next band (see `CakeRenderer` below), so the
layer count is not capped by the mesh budget. A bite CLEARS its footprint down toward the current layer's floor (a
clean scoop — `CakeOps.ApplyBite`, Req 2: one side of a layer clears completely,
the other stays full — a clean cut edge), tapering to a soft rim. The angle-of-
repose settle only SLOPES the cut edge (a small drip); it will NOT ooze into the
cleared zone near the active floor (`sim.sliverSweepStuds`), so cleared cake stays
clean — no puddles. Any thin bits on the active floor auto-sweep to it (1 Hz). ⚠ Every sweep
distance is capped at `sim.sweepBandFraction` (0.25) of the ACTIVE BAND's own
thickness — the raw values are absolute studs, so a thin band would otherwise be
swallowed by a fixed rule (measured: 8.3% → 6.8% forfeited, +3.4% food, at the
cost of +0.7 min clear time; `tools/headless-sim/pacing_scenario.lua` §C).
Digging a shaft is impossible by construction (layer gate).

## Where the bite LANDS: the forward aim search (2026-07-30)
You eat the cake directly in front of you. The old rule — sample the surface a
fixed `reach` ahead — broke the most common way people actually eat: **running
head-on into the WALL of the layer they are clearing.** Standing in the crater you
just made, the point `reach` ahead is still crater FLOOR, so
1. the client's layer-gate pre-check read it as "already eaten to the floor here"
   and **skipped the bite entirely**, popping "Eat the top layer first!", and
2. any bite that did fire centred on a floor cell, where `ApplyBite`'s
   `h > floorUnits` test fails — only the falloff RIM reached the wall, shaving a
   sliver.

Mowing ACROSS the top surface centres the scoop on full cake and clears its whole
footprint to the floor, which is why the two felt nothing alike — and it got worse
with depth, because `reach` scales with the shrinking scoop. Fix
(`CakeSubsClient.computeBitePoint`, tuned in `CakeConfig.aim`): step forward in
`stepStuds` increments out to `max(nominalReach, scoopedRadius + probeStuds)` and
bite the first point standing above the active floor.
- The fast path is **unchanged**: when there is cake at the nominal point it
  returns immediately, so surface mowing behaves exactly as before.
- The probe is deliberately SHORT — pressed against a wall the face is ~2-3 studs
  out. A long probe would let the front crater detach from the beneath crater and
  leave an un-eaten ring around the eater.
- When nothing ahead is above the floor it returns the nominal point, so the
  genuine "this layer is finished here" cue still fires.
- Client-only: the server just validates reach (`antiCheat.maxBiteReachStuds` 18 +
  biteRadius), and its own clamp is authoritative either way.

## Bite size: the per-band SCOOP
The eater's `biteRadius` stat is multiplied by the ACTIVE band's `scoop`
(cake-cycle.md) and floored at `sim.minBiteRadiusStuds` — `CakeFieldService
.ScoopedRadius` on the server, mirrored EXACTLY by `LocalCakeField.ScoopedRadius`
on the client (prediction AND the placement of the bite point in front of the
eater, which scales with it so the front + beneath craters always overlap).
⚠ Change the rule on one side only and prediction pops. `CakeOps.ApplyBite` also
always processes the cell UNDER the bite point, so a sub-cell scoop still bites.
The band's `density` turns the removed volume into FOOD (`CakeSubs`): belly fill
and calories are `removed × density`, never raw studs³.

## State & config
- `CakeStateData` — field buffer, composition, queues, phase (ALL runtime state)
  + the LAYER GATE: `activeBandIndex` (current top edible band) and
  `activeFloorUnits` (its bottom — the bite clamp) + `payoutScale` (this cake's
  calorie multiplier), `findPayoutScale`, and `cakeId`.
- `Shared/config/CakeConfig` — grid, sim budgets, net rates, layers (§5),
  composition rolls, cycle timings, `layerGate`. Server accesses it via
  `CakeConfigData` (which also owns anti-cheat caps).

## Layer gate (eat top-down, one layer at a time)
`CakeConfig.layerGate.enabled` — bites can't dig below the CURRENT top edible
band's bottom (`state.activeFloorUnits`) until that band is consumed. `ApplyBite`
clamps to `activeFloorUnits` instead of the core `floorUnits`; `ScanStats`
advances the active band down as each layer is leveled/auto-swept (one band
lower in the same scan when a band is swept, so the fresh floor never reads as
"locked"). `activeBandIndex` rides `Snapshot` meta + `CakeCycleUpdate` so the
client's `LocalCakeField.PredictBite` clamps to the SAME floor (no phantom
crater below a locked layer). Aiming at a spot already eaten to the active
floor pops `announce-layer-locked` ("Eat the top layer first!") on the client
(debounced `layerGate.cueInterval`, cue only for HELD input) and skips the bite;
the server clamp is authoritative regardless. `enabled=false` = old free-dig.
Auto-Eat no-ops silently at the active floor (no cue — passive eating isn't
nagged). Classic starts with flowing frosting, so a stationary auto-eater keeps
earning as its crater refills. Rainbow deliberately uses solid soft terraces;
the eater must remain over that active terrace rather than relying on flow.

## Server pipeline (CakeSimulationSubs Heartbeat, one connection)
| Job | Rate | Call |
|---|---|---|
| settle automaton | 20 Hz | `CakeFieldService.SettleStep` (≤ 1500 cells/tick) |
| delta flush | 12 Hz | `CollectDelta` → `CakeDeltaUpdate` — up to 3 packets/flush, each ≤ 150 cells + 40 repair (UnreliableRemoteEvent drops fires over ~900 B!) |
| collision | 5 Hz | `CakeCollisionService.UpdateHeights` (16×16 invisible parts, 256) |
| treasures | 2 Hz | `TreasureService.Tick` |
| progress scan | 1 Hz | `ScanStats` (progress %, auto-sweep + sliver sweep + thin-remnant sweep §7.6, bottom check) |

`CakeFieldService.ClearActiveBand()` is the one-shot version of the auto-sweep:
it collapses every in-cake cell above the TOP band's bottom onto it and
returns the removed volume + the band + its layer def, so the caller can price it
as FOOD exactly like a bite. Sold by the checkpoint's LayerEater
(`features/checkpoint.md`). ⚠ It resolves that band from the FIELD (the same
maxH rule `ScanStats` uses), not from `activeBandIndex` — that index only
refreshes at 1 Hz, so two purchases inside one tick would both target it and the
second would clear an already-flat band. ⚠ It deliberately does NOT advance the layer gate —
the 1 Hz `ScanStats` does, and that single path is also what moves the checkpoint
plate, announces the cleared layer and fires the retention beat.

## Remotes / updates
- `EatAt` (client→server, Vector3): bite intent — the surface point directly
  IN FRONT of the eater (see input below). The server applies TWO bites per
  accepted `EatAt`: the sent point AND one directly BENEATH the player (their own
  XZ, server-chosen so no anti-cheat), so the spot they stand on clears and the
  eaten area is contiguous (user req). The BENEATH bite is GEOMETRY ONLY — its
  volume is NOT paid as calories, so one accepted `EatAt` (one rate-limited token)
  still credits exactly ONE bite (no double-income from aiming the front bite at a
  separate spot). Anti-cheat: token bucket from
  eat-rate stat, reach check, type/NaN check. Volume/layer/calories are
  computed SERVER-side — the client can spoof nothing but position. Server
  also drops the bite when the belly is full (`StomachService.IsFull`, before
  carving) — see `features/body-gym.md`. The bite is CLAMPED to the layer-gate
  active floor (see Layer gate above), so it can't cut past the top layer.
- `CakeSnapshotUpdate`: full buffer + meta `{cakeIndex, cakeId, footprint,
  composition, waxEnabled, crustEnabled, rareKind, biome, phase, progress,
  activeBandIndex}` on join
  (via lifecycle push) and on every new cake. (`footprint` = `{hx, hz, corner}`
  in cells — the rounded-rect SDF; all three EQUAL == the round cake that ships.
  The client reads `meta.footprint`, never a radius.
  `activeBandIndex` seeds the layer gate — see Layer gate above.)
- `CakeDeltaUpdate` (Unreliable): `(cakeIndex, buffer[u16 idx, u16 h]*n)`.
  Losses self-heal via the rotating repair cursor (full sweep ≈ 9 s).

## Client
- `LocalCakeField` — mirror + LOCAL BITE PREDICTION with the same shared
  `CakeOps` math; deltas plain-overwrite (reconcile). Non-predicted delta
  energy drives the slump loop SFX.
- `CakeRenderer` — renders the CURRENT + NEXT edible band as TWO height-clamped
  slab MeshParts (`assignWindowBands`/`windowFor`), NOT every layer: the layer gate
  forbids digging below the active floor, so the band below is a flat floor seen
  through craters and everything under IT is never exposed — hidden by the
  `CakeWrapper` wall (below). The window slides DOWN as each layer finishes
  (`rewindow`, polling `LocalCakeField.ActiveBandIndex()` in `editableStep`). Each
  slab carries its own Material/Transparency/Reflectance (Glass jelly, Sand sponge…;
  the LOWER windowed band is forced OPAQUE so a translucent one can't reveal the
  hollow) + an OPTIONAL image texture (`layer.texture`, `Content.fromUri`, TILED
  `render.layerTextureTiles`× so it reads sharp). The pool is built LAZILY (2 slabs) by cloning ONE
  temporary dynamic scratch mesh via `CreateEditableMeshAsync
  {FixedSize=true}` then destroying it — a DYNAMIC EditableMesh reserves
  worst-case budget (60k verts, ~8 fit a desktop client) while FixedSize
  clones cost actual complexity (~2.4k verts each, footprint-hosted verts
  only); source vertex/normal ids stay valid on clones (probe-verified).
  A slab WITHOUT `layer.texture` renders the layer BODY color as a FLAT
  `part.Color` (wax-enabled variants add the pale `CakeWaxShell`, so the darker
  body shows through its cracks); a slab WITH a texture
  maps that image over the top surface (planar XZ UVs, TILED `render.layerTextureTiles`×
  so it's sharp) — affordable now that only 2 slabs render (a static texture reference, no paint).
  A per-CELL `EditableImage` was dropped as a mobile perf trap: since the crust moved to
  the wax shell it only ever held a uniform bodyColor fill, yet cost a 384²
  paint + GPU upload per band per rebuild (the new-cake frame spike) and a
  `DrawRectangle` per eaten cell per bite — for zero visual gain
  (`2026-07-19_cake-rebuild-mobile-spike.md`). Only the palette FALLBACK below
  keeps a texture (real per-cell height variation). Underfoot SQUISH
  (§7.2) dents the slab; a hard landing stomps deeper (`CrackAt`). Eaten-
  through slabs TUCK `render.hideSink` studs under the local surface (drape-
  under-cover — dropping to 0 hung curtains through side cuts; alpha does NOT
  render, see gotchas). Each slab carries its band's footprint-specific vertex
  layout and independent target/display/ooze state: its rim averages only cells
  inside that mask and projects onto that mask's analytic outline. Sharing the
  maximum-footprint state across terraces creates tall diagonal spikes and
  cross-colour shoulder bleed. Equal-footprint classic bands keep the shared
  fast path. Degradation ladder on budget failure: two slabs → ONE slab for an
  equal-footprint cake → visible keycap
  part grid (Create* return NIL, no throw — every creation is nil-checked
  + warned, R8). BITE FEEL = drops > `render.snapDropStuds` snap; refills
  ooze at the LAYER's `oozeSpeed`; jelly wobble; variants may opt into underfoot
  squish multiplied by that layer's `squishMult` (rainbow = 2.6 for the heavy
  soft-cake dent; classic preserves its shipped uniform non-rigid dent). The
  EditableMesh and visible-column fallback share that exact resolver: rigid
  `squishMult=0` layers never dent in either implementation.
  Invisible 32×32 collision columns always exist. COLLISION FEEL (Task 4):
  a bite DROPS a column instantly (fall into the hole) but a RISE (cake
  oozing/refilling back) is rate-limited to `render.collision.riseRate`
  studs/s so refilling cake never punts the player up — they stay partly BURIED
  and jump to get back on the surface. New cake / snapshot snaps columns
  (columnsRebuild, run BEFORE the yielding mesh rebuild since 2026-08-07) so you
  never fall through fresh cake; `CakeRenderer.SnapCollisionNow()` is the same snap
  on demand (used for a fresh character). `CakeRenderer.ColumnTopAt(wx, wz)` reports
  the walkable top at any XZ (nil off the column grid / for a non-collidable stub) —
  the BURIAL TRUTH, and the only one valid off the footprint. PERF (Task 2):
  `updateCollisionNearPlayer` refreshes ONLY the columns within
  `render.collision.updateRadiusStuds` of the local player each frame, centred on
  the character's RAW position (it was the surface point, which is nil off the
  footprint and so blinded the scan exactly at the rim) — eating +
  the settle ooze change cells across the WHOLE cake, and resizing every affected
  CanCollide column re-indexed the physics broadphase (frame → 60+ ms while
  eating). The player only collides with nearby columns, so distant ones keep
  their last size until approached. The VISUAL mesh still updates everywhere
  (cheap Lua, no physics). ⚠ Engine gotchas
  (Precise vs Automatic LODs, raw-origin vertex mapping, creation-time
  bounds, two-pass + neighbor-ring normals, 3×3-neighborhood skirt faces,
  NO vertex/texture alpha on MeshParts) — flow docs
  (`2026-07-16_eat-the-cake-v1.md` Cake 2.0 + `2026-07-18_layer-meshes…` +
  `2026-07-18_wax-shell.md`).
- `CakeWaxShell` — an optional wax coating as ONE MeshPart of organic
  VORONOI pieces (`render.wax`). Each piece owns its boundary verts (on the
  exact Voronoi edge so neighbours MEET, no gap) + a raised centre (`dome`);
  it RIDES the surface (re-reads `LocalCakeField.ReadHeightStuds` per frame) and
  HIDES where a HOLE is eaten through the cake — a crater `wax.hideDepth` below
  the OUTERMOST REMAINING layer (`lastMaxH`, 1-frame lag) — so the hole shows the
  cake body / wall, not a wax skin (Req: "wax disappears where you ate a hole";
  reverted the old ride-to-active-floor "coat every layer"). An even, hole-less
  drop keeps the coating and rides down; when a whole layer clears the surface
  drops to the next layer and the wax re-coats it, retinted. A piece also hides when its
  AREA straddles a crater (min surface over its fan-TRIANGLE centres `c.tc` <
  hideBelow), so the wax RECEDES cleanly from an eaten hole instead of hanging a
  flat SHELF / drooping flap over the edge (user req: no wax pieces at the eaten
  rim). Cracks underfoot. Clipped to the loaf
  rounded-rect outline (`edgeInset`) for a clean edge. SMOOTH at rest; under
  the foot each piece carries a `dent` 0..1 (ramps `fracture.riseRate`, heals
  `fracture.healRate`) that DENTS it down, TILTS it and SPREADS it toward its
  centroid — cracks open ONLY underfoot and the cake body shows in the gaps.
  Built once via the same FixedSize-clone pattern, kicked off a `task.spawn`
  so the yielding async build never stalls the render step; a `building` guard
  blocks re-entry (the "run-immediately-breaks-it" bug). Colour = the current
  OUTERMOST REMAINING layer's OWN colour, only SLIGHTLY brighter (`wax.satBoost`
  ~1 keeps the hue, `wax.valBrighten` lifts the value) — so each layer's wax
  reads as THAT layer (`maxH` band, not the foot — one colour per mesh). Idle pieces are dirty-
  skipped (no per-frame re-write when nothing moves). Setup(mirror) +
  Step(dt, footPos) from CakeSubsClient. `meta.waxEnabled=false` parks it fully
  transparent; the next wax-enabled snapshot restores it.
- `CakeWrapper` — the outer wall below the two rendered slabs. It collapses the
  bottom-up composition into one pooled, non-colliding segmented ring per flavour
  group. Every ring uses that group's own `band.footprint`; a narrower upper
  group therefore gets a smaller diameter. At each footprint expansion it clones
  a pooled horizontal cap from the existing cap template: the next ring covers
  the centre and leaves the wider lower disc visible as the terrace shoulder.
  Classic footprints are equal, so it creates no shoulders and renders exactly
  the existing cylinder. Rainbow groups use empty `sideTexture` intentionally,
  producing flat vivid colour rather than a generic cake-photo fallback.
  The current wall top still follows `composition[activeIndex-1].bottom`; rings
  and terrace caps park off-screen rather than being destroyed. The per-layer top
  cap is sized to the band directly under the active crater. Block faces remain
  necessary because a meshed cylinder ignores `Texture.StudsPerTile`; cumulative
  `OffsetStudsU` keeps the tiled phase continuous around each ring.
- `CakeFeelSubsClient` — per-layer FEEL under the feet (`CakeConfig.feel`):
  `jumpMult` on the client Humanoid (WalkSpeed stays SERVER-authoritative
  in BodySubs), `bounce` landing restitution (trampoline sponge), the
  landing squish stomp (`CrackAt`) incl. the ONE fresh-cake first-crack
  ceremony when `crustEnabled`; crust-free rainbow keeps the body dent/landing
  feel but skips the break ceremony (owns ALL Landed handling — CakeSubsClient
  has no landing logic).
  **FLAT WHILE EATING (Task 4):** while `LocalEatState.Get()` (actively eating,
  published by CakeSubsClient = hold/tap or Auto-Eat), the landing bounce is
  suppressed (`feel.noBounceWhileEating`) and the jumpMult is capped to
  `feel.jumpMultCapWhileEating` (≈1) so running-while-eating goes in a straight
  line; the per-layer bounce/jump (toned down in `CakeConfig.layers`) only
  applies when NOT eating.
- `EatGestureController` — the LOCAL "player eats a piece" animation: each
  accepted bite rips a chunky piece of the eaten LAYER out of the cake in front
  and flies it (two-arc: cake→hand→mouth) up to the mouth, shrinking it away
  (eaten). Flight time is derived from the eat-rate stat (faster eating chews
  faster). RIG-AGNOSTIC on purpose — it only reads Head/RightHand positions and
  moves its OWN pooled parts, never poses joints (this avatar's rig uses
  AnimationConstraints and the Animator overwrites joint Transforms every frame
  — see `features/body-gym.md` gotcha; the flying piece IS the animation). Pool
  built once at Init (Instance.new only there, ChunkDebris pattern). LOCAL only
  — like the rest of the bite juice; the body morph + tumble are what other
  players see.
- `CakeSubsClient` — sync wiring (stale-snapshot supersede guard around the
  yielding rebuild), input = eat the cake DIRECTLY IN FRONT of you (surface
  along HRP LookVector, snapped to the field; no pointer aim — turn to aim).
  **PC** holds the mouse ANYWHERE; **TOUCH** eats ONLY via the dedicated
  bottom-right **EAT button** (`UIKit/EatButton`, wired through AppRoot
  `onEatDown`/`onEatUp`) — never a raw finger, so the movement joystick / camera
  drag can't eat (Task 3). Held and Auto-Eat paths fail closed through
  `PlayerControlService.IsLocked`; a teleport handoff clears held/
  `LocalEatState` activity before a remote or local prediction can run. Hold =
  auto-repeat at the eat-rate stat; a tap fires
  one immediate bite. The button's press primitive is finger-aware so onEatUp
  fires only on the LAST finger up (no stuck-on). Plus the client `isFull` gate
  (stops firing + soft cue when the belly
  tops out, mirrors the server block), bite FX + `EatGestureController.Play`,
  walk-crunch (footstep-cadence layer SFX + crumb puffs), and drives
  `CakeWaxShell.Step` each frame.

## Gotchas
- Chocolate never flows (`repose = huge`) — it's eaten through (hardness 3)
  with client shatter FX; the GDD's "convert to crumb" state is NOT simulated.
- Auto-sweep, the sliver sweep AND the eaten-zone cleanup sweep (`sim.remnantSweep`:
  an active-band cell TOUCHING a crater snaps to the floor when it is itself
  within `nearFloorStuds` of the floor — the soft RIM of a bite — or is an
  isolated pillar / 1-cell wall) all FORFEIT the swept volume (nobody gets
  calories) — the price of never leaving hard-to-eat crumbs.
  ⚠ The rim rule is measured from the active FLOOR. It used to be measured from
  the band TOP (`eatenEpsilonStuds`), which collapsed a chunky band's cell the
  moment it was nicked: ~25% of every cake vanished uneaten, layer clear-time
  stopped depending on the bite stats at all, and there was no room left to pace
  the cake (ADR-0011). Keep it near the floor.
- **The cake is ROUND, and `hx == hz == corner` is HOW.** `GridUtil.InCake` is
  a rounded-rect SDF; setting the corner radius equal to BOTH half-extents
  collapses the straight edges to zero and leaves a pure disc of radius
  `corner`. Every consumer inherits the circle for free — `CakeRenderer`'s rim
  projection degenerates to `dir * (R+0.5)*cell`, `CakeWaxShell`'s four corner
  arcs share one centre and concatenate into one circle, `TreasureService`'s
  inset subtracts the margin from all three and stays a disc. Keep all THREE
  equal or the cake silently reverts to a stadium/rect. The values are FLOATS
  (31.1) — nothing loops over them integer-wise; don't "tidy" them to ints.
- **Radius is chosen by CELL COUNT, not by pretty numbers.** Edible volume =
  cells × cell² × height and height is always `maxTotalHeight`, so the cell
  count IS the balance. The old loaf covered 3036 cells; R = 31.1 covers 3032
  (−0.13% — the closest a 64-cell lattice reaches; the count steps 4-8 cells at
  a time). Re-measure with `tools/headless-sim/pacing_scenario.lua` before
  changing it: the round rim also costs a little more sweep waste (see below).
- ⚠ **An ANALYTIC rim over a STAIRCASE mask needs an in-cake fallback.** The wax
  outline (and any other smoothed edge) is a continuous curve, but `InCake` is a
  cell staircase — so short stretches of the curve overhang a cell that is OUT of
  the cake, and out-of-cake cells hold height **0**. Sampling one for a rim vertex
  writes it at the cake BASE while its piece rides the surface: a ~170-stud wax
  streamer down the side (and for a triangle-centre sample, a piece that hides
  forever = a bald patch). `CakeWaxShell.cellAt` therefore takes a `fallback` (the
  piece's own centre cell) for every rim sample. This was latent on the loaf — only
  its 4 corner arcs could do it — and the ROUND cake makes the whole rim an arc,
  which is what made it reachable. Apply the same rule to any new rim sampler.
- The maximum/base footprint XZ is FIXED (`composition.footprint`) and does NOT
  scale with population. A selectable variant may give upper bands SMALLER local
  footprints, but never a larger one (the grid caps the radius just UNDER 31.5 cells: `InCake`
  uses `half = (size-1)*0.5 = 31.5` with `<=`, so AT 31.5 the outer columns become
  in-cake, the renderer can no longer place a ring cell outside them and the skirt
  seal opens at the field boundary with no warning — 31.1 leaves 0.4 of margin); only
  the cake's WORK scales with population (`composition.coopWork`, cake-cycle.md —
  `perPlayerScale` was removed by ADR-0011). Auto-sweep + boss timers keep solo pace sane.
- ⚠ `layer.squishMult` is not descriptive metadata for an opted-in variant:
  `CakeRenderer` must multiply its fracture/deformation depth by it. Gate that
  behavior with `variant.useLayerSquishMultiplier`; classic keeps the legacy 1×
  dent for every positive value, while rainbow's heavy 2.6× is the regression
  check. Applying the field globally silently retunes every classic material.
- **A disc is staircased EVERYWHERE**, where the loaf had two long clean straight
  edges — so the remnant sweep finds slightly more isolated rim cells. Measured
  cost of the loaf→disc change at equal area (`pacing_scenario.lua`, deterministic,
  measured 2026-08-03): fresh session 91.6→92.0 min, food −0.3%, waste 14.1%→14.2%;
  fully upgraded 27.8→27.4 min, food −1.4%, waste 2.6%→3.8%. All well inside
  ADR-0011 tolerance. ⚠ The ABSOLUTE minutes are no longer reproducible: that run
  used the scenario's hardcoded eater (biteRadius 3.4 / capacity 84000), which
  2026-08-05 replaced with a live `UpgradeConfig` read. The A/B DELTAS — which is
  all this bullet claims — are unaffected, since both sides used the same eater.
- Glass jelly hides TRANSPARENT things (particles/FX) seen through it on
  high graphics — opaque layers below render fine; not a ParticlePool bug.
- Server collision (16×16 slabs) is a SAFETY net only — precise walking
  collision is the client 32×32 columns; never validate bite Y against slabs.
  The slabs sit at the **MIN** height of their block (Task 4), never the average,
  so they can't poke above the fine columns and block a descent into a fresh
  crater (the average left players floating waist-deep / juddering as the two
  grids disagreed); they only catch a fall when the fine columns aren't there
  yet (join). See `CakeCollisionService` header.
- New cakes materialize around players standing in the footprint —
  CakeCycleSubs lifts them onto the fresh frosting at spawn (see the
  "spawning inside the cake" gotcha below for the collider ordering this depends on).
- ⚠ **"Spawning inside the cake" — the whole chain, fixed 2026-08-07.** A cake is
  HEIGHTS before it is a COLLIDER, and characters were being placed on it inside
  that window. Four independent things had to be true; all four are now closed:
  1. **The server net was structurally late.** `CakeCollisionService.UpdateHeights`
     is only called by the 5 Hz clock in `CakeSimulationSubs`, which sits BELOW
     that Heartbeat's `roundSimulationEnabled()` early-return — **and so does the
     accumulator**. That gate (`match-started`) is set by `CompleteStart` only
     AFTER `BeginMatch` returns, so at a reserved-match start the 256 slabs were
     provably still their 1-stud build pose for a full tick period after the lift.
     `SpawnNewCake` now calls `UpdateHeights()` synchronously between `ResetCake`
     and the lift, and zeroes the accumulator. Measured after: centre slab
     `SizeY = 172.70`, top `174.70` against a crust at ~175.
  2. **The client net needed a YIELD.** `OnSnapshot` ran `editableRebuild` (the
     lazy mesh-pool build — **measured 482 ms cold**) before `columnsRebuild`, so
     the cake was visible-but-not-solid for half a second. The order is now
     collision first, visuals second. ⚠ `editableRebuild` can DEGRADE to
     `impl = "parts"` and flip `visualColumns`, so that branch repaints — else the
     fallback renders an invisible cake you can walk on.
  3. **The lift kept velocity.** `root.CFrame = …` does not clear
     `AssemblyLinearVelocity`, and during the arrival window there is no cake at
     all, so every character is mid-fall from the pad at up to terminal speed.
     Placed at cake height still carrying it, they punched through on the next
     step — this was the "sometimes". Both lift branches now zero the assembly,
     skip `Anchored` roots (the treadmill mount owns those, `BodySubs` re-asserts
     them), and target `surfaceY + composition.liftClearanceStuds` (8) while the
     PREDICATE stays on `surfaceY` (so a player already on fresh crust is not
     re-hopped). The old `+ 3` was an R15 HRP offset = zero clearance.
  4. **The rescue had exactly one shot.** `rescueBuriedLocal` was called from ONE
     place — after a snapshot — and a reserved match broadcasts ONE snapshot per
     ~35-minute session, so any guard that tripped (no character yet, a movement
     lock held, off the footprint) spent it permanently. It is now armed three
     ways: after a rebuild, on every fresh character (including the one that
     already exists at `Start` — on a slow client `CharacterAdded` never fires for
     life #1), and by a dwell-gated watchdog polled from the existing
     `RenderStepped` loop. A movement lock now SKIPS a tick instead of forfeiting.
  **Burial is measured against the COLLISION COLUMN top
  (`CakeRenderer.ColumnTopAt`), never the field surface** — the two differ ON
  PURPOSE (`riseRate` holds the column below the field so refilling cake buries
  you and you jump out), so a field-based test would read a big depth during
  exactly that feel and teleport the player to the full refilled height. The
  column is also what covers the rim ring, where `SurfacePoint` is nil but a
  column can stand at full cake height (`colTarget` averages only IN-cake cells,
  so an edge column with one in-cake cell gets that cell's full height over
  out-of-cake XZ) — that ring used to be an unrecoverable trap.
  Studio-verified 2026-08-07 on the reserved-match path: standing player
  `columnTop − HRP = −3.29` on spawn AND after a respawn; a forced 25-stud burial
  recovered after exactly the 2 s dwell; a 3.75-stud sink (under
  `buriedRescueStuds`) correctly left alone for 4 s+, so the crater feel survives.
  Server-side lifting alone cannot fix any of this: only the client knows when its
  own columns went up.

## Files
Server: `CakeStateData`, `CakeConfigData`, `services/CakeFieldService`,
`CakeCollisionService`, `subscriptions/CakeSubs` (input/snapshot),
`CakeCycleSubs` (spawn/lifecycle), `CakeSimulationSubs` (Heartbeat/deltas).
Shared: `GridUtil`,
`CakeOps`, `config/CakeConfig`. Client: `LocalCakeField`, `CakeRenderer`,
`CakeWaxShell`, `CakeWrapper` (textured outer wall over the ungenerated bulk),
`EatGestureController`, `CakeSubsClient`, `CakeFeelSubsClient`,
`LocalEatState` (flat-while-eating flag), `UIKit/EatButton` (touch hold-to-eat).
In a reserved match, `EatAt` is accepted only after the match starts and only
from a present validated participant (`features/game-round.md`). Cycle/boss/pets:
`features/cake-cycle.md`.
