# Cake simulation (granular heightfield)

## What it does
ONE shared cake per server: a 64×64 u16 heightfield (fixed-point 0.01
studs, `GridUtil` layout), FIXED rounded-rect "loaf" footprint
(`composition.footprint`, 90×78 studs), ~3× TALLER as of 2026-07-20
(`totalHeight` {150,180}, `grid.maxHeight` 270) with ~10–14 chunky layers,
~1M studs³ solo — Drain-the-Lake scale; HEIGHT also scales up per player
(cake-cycle.md `perPlayerScale`). The renderer draws only the CURRENT top
layer (see `CakeRenderer` below), so the layer count is not capped by the mesh
budget. A bite CLEARS its footprint down toward the current layer's floor (a
clean scoop — `CakeOps.ApplyBite`, Req 2: one side of a layer clears completely,
the other stays full — a clean cut edge), tapering to a soft rim. The angle-of-
repose settle only SLOPES the cut edge (a small drip); it will NOT ooze into the
cleared zone near the active floor (`sim.sliverSweepStuds`), so cleared cake stays
clean — no puddles. Any thin bits on the active floor auto-sweep to it (1 Hz).
Digging a shaft is impossible by construction (layer gate).

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
| progress scan | 1 Hz | `ScanStats` (progress %, auto-sweep + sliver sweep + thin-remnant sweep §7.6, bottom check) |

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
  `part.Color` (the pale crust look is the always-visible `CakeWaxShell` on
  top, so the darker body shows through the wax cracks); a slab WITH a texture
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
  render, see gotchas). The loaf outline is
  smoothed: ring/staircase-boundary verts project onto the analytic
  rounded rect (no corner pleats). Degradation ladder on budget failure:
  per-layer slabs → ONE slab + height-palette texture → visible keycap
  part grid (Create* return NIL, no throw — every creation is nil-checked
  + warned, R8). BITE FEEL = drops > `render.snapDropStuds` snap; refills
  ooze at the LAYER's `oozeSpeed`; jelly wobble; underfoot squish §7.2.
  Invisible 32×32 collision columns always exist. COLLISION FEEL (Task 4):
  a bite DROPS a column instantly (fall into the hole) but a RISE (cake
  oozing/refilling back) is rate-limited to `render.collision.riseRate`
  studs/s so refilling cake never punts the player up — they stay partly BURIED
  and jump to get back on the surface. New cake / snapshot snaps columns
  (columnsRebuild) so you never fall through fresh cake. PERF (Task 2):
  `updateCollisionNearPlayer` refreshes ONLY the columns within
  `render.collision.updateRadiusStuds` of the local player each frame — eating +
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
- `CakeWaxShell` — the ALWAYS-VISIBLE wax coating as ONE MeshPart of organic
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
  Step(dt, footPos) from CakeSubsClient.
- `CakeWrapper` — the textured OUTER WALL that hides the cake BELOW the current +
  next rendered layers (`CakeRenderer` window). A plain anchored Part (Block,
  NOT a mesh — cheaper + the `Texture` path reliably tiles the image, which the
  MeshPart `TextureContent`-from-URI approach did NOT display), sized to the loaf,
  standing from the base up to the NEXT layer's bottom
  (`composition[activeIndex-1].bottom`) and shrinking as each layer clears. Wears a
  RANDOM cake photo (`render.wrapper.textures`, one per cake by `cakeIndex`) as
  tiling `Texture` instances on its 4 sides + top cap (a crater cleared to the
  next-layer floor shows the cap, not a void). Square corners poke ~6 studs past the rounded
  loaf at the 4 corners (the Block-vs-rounded-rect trade). CanCollide/CanQuery=false;
  reads `LocalCakeField` itself. Setup(mirror) + OnSnapshot() (pick texture) +
  Step(dt) from CakeSubsClient.
- `CakeFeelSubsClient` — per-layer FEEL under the feet (`CakeConfig.feel`):
  `jumpMult` on the client Humanoid (WalkSpeed stays SERVER-authoritative
  in BodySubs), `bounce` landing restitution (trampoline sponge), the
  landing squish stomp (`CrackAt`) incl. the ONE fresh-cake first-crack
  ceremony (owns ALL Landed handling — CakeSubsClient has no landing logic).
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
  drag can't eat (Task 3). Hold = auto-repeat at the eat-rate stat; a tap fires
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
  any active-band cell TOUCHING a crater that is either eaten-into or an isolated
  pillar / 1-cell wall snaps to the floor, so the eaten footprint is a clean cliff,
  no ragged rim) all FORFEIT the swept volume (nobody gets calories) — the price of
  never leaving hard-to-eat crumbs. Tune `clearedMarginStuds` / `eatenEpsilonStuds`
  or set `enabled=false` if it eats too eagerly.
- The footprint XZ is FIXED (`composition.footprint` loaf) — it does NOT
  scale with population (the 64-cell grid caps it); only the cake HEIGHT
  scales up per player (`composition.perPlayerScale`, cake-cycle.md). Auto-
  sweep + boss timers keep solo pace sane.
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
  CakeSubs lifts them onto the fresh frosting at spawn.

## Files
Server: `CakeStateData`, `CakeConfigData`, `services/CakeFieldService`,
`CakeCollisionService`, `subscriptions/CakeSubs`. Shared: `GridUtil`,
`CakeOps`, `config/CakeConfig`. Client: `LocalCakeField`, `CakeRenderer`,
`CakeWaxShell`, `CakeWrapper` (textured outer wall over the ungenerated bulk),
`EatGestureController`, `CakeSubsClient`, `CakeFeelSubsClient`,
`LocalEatState` (flat-while-eating flag), `UIKit/EatButton` (touch hold-to-eat).
Cycle/boss/pets: `features/cake-cycle.md`.
