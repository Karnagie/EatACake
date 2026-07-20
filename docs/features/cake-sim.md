# Cake simulation (granular heightfield)

## What it does
ONE shared cake per server: a 64×64 u16 heightfield (fixed-point 0.01
studs, `GridUtil` layout), FIXED rounded-rect "loaf" footprint
(`composition.footprint`, 90×78 studs, ~360k studs³ solo — Drain-the-Lake
scale; HEIGHT scales up per player, see cake-cycle.md `perPlayerScale`),
layered composition. Bites rip out craters INSTANTLY; the torn
cells are held for `sim.settleDelayAfterBite`, then the angle-of-repose
automaton slowly oozes the walls back (GDD §4). Digging a shaft is
impossible by construction.

## State & config
- `CakeStateData` — field buffer, composition, queues, phase (ALL runtime state)
  + the LAYER GATE: `activeBandIndex` (current top edible band) and
  `activeFloorUnits` (its bottom — the bite clamp).
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
nagged); the top band is always frosting (flows, so craters refill), so a
stationary auto-eater keeps earning rather than stalling.

## Server pipeline (CakeSubs Heartbeat, one connection)
| Job | Rate | Call |
|---|---|---|
| settle automaton | 20 Hz | `CakeFieldService.SettleStep` (≤ 1500 cells/tick) |
| delta flush | 12 Hz | `CollectDelta` → `CakeDeltaUpdate` — up to 3 packets/flush, each ≤ 150 cells + 40 repair (UnreliableRemoteEvent drops fires over ~900 B!) |
| collision | 5 Hz | `CakeCollisionService.UpdateHeights` (16×16 invisible parts, 256) |
| treasures | 2 Hz | `TreasureService.Tick` |
| progress scan | 1 Hz | `ScanStats` (progress %, auto-sweep §7.6, bottom check) |

## Remotes / updates
- `EatAt` (client→server, Vector3): bite intent — the surface point directly
  IN FRONT of the eater (see input below). Anti-cheat: token bucket from
  eat-rate stat, reach check, type/NaN check. Volume/layer/calories are
  computed SERVER-side — the client can spoof nothing but position. Server
  also drops the bite when the belly is full (`StomachService.IsFull`, before
  carving) — see `features/body-gym.md`. The bite is CLAMPED to the layer-gate
  active floor (see Layer gate above), so it can't cut past the top layer.
- `CakeSnapshotUpdate`: full buffer + meta `{cakeIndex, footprint,
  composition, rareKind, biome, phase, progress, activeBandIndex}` on join
  (via lifecycle push) and on every new cake. (`footprint` = the rounded-rect
  loaf `{hx, hz, corner}`; the client reads `meta.footprint`, never a radius.
  `activeBandIndex` seeds the layer gate — see Layer gate above.)
- `CakeDeltaUpdate` (Unreliable): `(cakeIndex, buffer[u16 idx, u16 h]*n)`.
  Losses self-heal via the rotating repair cursor (full sweep ≈ 9 s).

## Client
- `LocalCakeField` — mirror + LOCAL BITE PREDICTION with the same shared
  `CakeOps` math; deltas plain-overwrite (reconcile). Non-predicted delta
  energy drives the slump loop SFX.
- `CakeRenderer` — ONE MeshPart PER SIM LAYER (height-clamped slabs): each
  layer carries its own Material/Transparency/Reflectance (Glass jelly,
  Sand sponge…). The pool is built LAZILY per composition by cloning ONE
  temporary dynamic scratch mesh via `CreateEditableMeshAsync
  {FixedSize=true}` then destroying it — a DYNAMIC EditableMesh reserves
  worst-case budget (60k verts, ~8 fit a desktop client) while FixedSize
  clones cost actual complexity (~2.4k verts each, footprint-hosted verts
  only); source vertex/normal ids stay valid on clones (probe-verified).
  Each layer slab renders the layer BODY color as a FLAT `part.Color` — NO
  per-band texture (the pale crust look is the always-visible `CakeWaxShell` on
  top, so the darker body shows through the wax cracks). A per-band
  `EditableImage` was dropped as a mobile perf trap: since the crust moved to
  the wax shell it only ever held a uniform bodyColor fill, yet cost a 384²
  paint + GPU upload per band per rebuild (the new-cake frame spike) and a
  `DrawRectangle` per eaten cell per bite — for zero visual gain
  (`2026-07-19_cake-rebuild-mobile-spike.md`). Only the palette FALLBACK below
  keeps a texture (real per-cell height variation). Underfoot SQUISH
  (§7.2) dents the slab; a hard landing stomps deeper (`CrackAt`). Eaten-
  through slabs TUCK `render.hideSink` studs under the local surface (drape-
  under-cover — dropping to 0 hung curtains through side cuts; alpha does NOT
  render, see gotchas). The loaf outline is
  smoothed: ring/staircase-boundary verts project onto the analytic
  rounded rect (no corner pleats). Degradation ladder on budget failure:
  per-layer slabs → ONE slab + height-palette texture → visible keycap
  part grid (Create* return NIL, no throw — every creation is nil-checked
  + warned, R8). BITE FEEL = drops > `render.snapDropStuds` snap; refills
  ooze at the LAYER's `oozeSpeed`; jelly wobble; underfoot squish §7.2.
  Invisible 32×32 collision columns always exist. ⚠ Engine gotchas
  (Precise vs Automatic LODs, raw-origin vertex mapping, creation-time
  bounds, two-pass + neighbor-ring normals, 3×3-neighborhood skirt faces,
  NO vertex/texture alpha on MeshParts) — flow docs
  (`2026-07-16_eat-the-cake-v1.md` Cake 2.0 + `2026-07-18_layer-meshes…` +
  `2026-07-18_wax-shell.md`).
- `CakeWaxShell` — the ALWAYS-VISIBLE wax coating as ONE MeshPart of organic
  VORONOI pieces (`render.wax`). Each piece owns its boundary verts (on the
  exact Voronoi edge so neighbours MEET, no gap) + a raised centre (`dome`);
  it RIDES the surface (re-reads `LocalCakeField.ReadHeightStuds` per frame),
  HIDES where the cake is eaten (`hideDepth`), and is clipped to the loaf
  rounded-rect outline (`edgeInset`) for a clean edge. SMOOTH at rest; under
  the foot each piece carries a `dent` 0..1 (ramps `fracture.riseRate`, heals
  `fracture.healRate`) that DENTS it down, TILTS it and SPREADS it toward its
  centroid — cracks open ONLY underfoot and the cake body shows in the gaps.
  Built once via the same FixedSize-clone pattern, kicked off a `task.spawn`
  so the yielding async build never stalls the render step; a `building` guard
  blocks re-entry (the "run-immediately-breaks-it" bug). Colour = a BRIGHT
  vivid glaze (HSV sat/val boost) of the current OUTERMOST REMAINING layer
  (`maxH` band, not the foot — one colour per mesh). Idle pieces are dirty-
  skipped (no per-frame re-write when nothing moves). Setup(mirror) +
  Step(dt, footPos) from CakeSubsClient.
- `CakeFeelSubsClient` — per-layer FEEL under the feet (`CakeConfig.feel`):
  `jumpMult` on the client Humanoid (WalkSpeed stays SERVER-authoritative
  in BodySubs), `bounce` landing restitution (trampoline sponge), the
  landing squish stomp (`CrackAt`) incl. the ONE fresh-cake first-crack
  ceremony (owns ALL Landed handling — CakeSubsClient has no landing logic).
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
  yielding rebuild), tap/HOLD input = eat the cake DIRECTLY IN FRONT of you
  (surface along HRP LookVector, snapped to the field; no pointer aim — turn
  to aim), the client `isFull` gate (stops firing + soft cue when the belly
  tops out, mirrors the server block), bite FX + `EatGestureController.Play`,
  walk-crunch (footstep-cadence layer SFX + crumb puffs), and drives
  `CakeWaxShell.Step` each frame.

## Gotchas
- Chocolate never flows (`repose = huge`) — it's eaten through (hardness 3)
  with client shatter FX; the GDD's "convert to crumb" state is NOT simulated.
- Auto-sweep forfeits the swept volume (nobody gets calories for it).
- The footprint XZ is FIXED (`composition.footprint` loaf) — it does NOT
  scale with population (the 64-cell grid caps it); only the cake HEIGHT
  scales up per player (`composition.perPlayerScale`, cake-cycle.md). Auto-
  sweep + boss timers keep solo pace sane.
- Glass jelly hides TRANSPARENT things (particles/FX) seen through it on
  high graphics — opaque layers below render fine; not a ParticlePool bug.
- Server collision (16×16 slabs) is a SAFETY net only — precise walking
  collision is the client columns; never validate bite Y against slabs.
- New cakes materialize around players standing in the footprint —
  CakeSubs lifts them onto the fresh frosting at spawn.

## Files
Server: `CakeStateData`, `CakeConfigData`, `services/CakeFieldService`,
`CakeCollisionService`, `subscriptions/CakeSubs`. Shared: `GridUtil`,
`CakeOps`, `config/CakeConfig`. Client: `LocalCakeField`, `CakeRenderer`,
`CakeWaxShell`, `EatGestureController`, `CakeSubsClient`,
`CakeFeelSubsClient`. Cycle/boss/pets: `features/cake-cycle.md`.
