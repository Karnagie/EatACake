# 2026-07-20: Mobile eat CPU spike — collision-column physics broadphase

Tags: cake-sim, performance, mobile, physics, collision

## Task
User (mobile): "when the player leaves the checkpoint and starts eating cake,
CPU usage spikes significantly to over 50 ms. After about 5–10 seconds,
performance more or less returns to normal. Find the cause and optimize it.
Extremely important." (Task 2 of a 4-part mobile/asset overhaul; a prior spike —
`2026-07-19_cake-rebuild-mobile-spike.md` — fixed a *different*, per-new-cake
texture cost.)

## Context
`CakeRenderer` mirrors the eaten surface with an invisible 32×32 grid of
CanCollide "column" parts (the precise walking collision). It updated columns
event-driven: on every drained changed cell (12 Hz delta batches) it resized the
affected column part.

## Investigation (Studio, live profiling — the root cause was NOT the obvious one)
Instrumented the client render step + read the `Stats` service (physics /
frame). Key measurements (desktop; multiply for mobile):
- `CakeRenderer.Step` / `CakeWaxShell.Step` Lua time: **< 1 ms** — the
  EditableMesh vertex churn was NOT the spike (refuted the first hypothesis).
- **Major confound found**: the test profile's belly was 99.96% full, so `isFull`
  blocked nearly every bite → the "eating" tests barely carved. Drained the belly
  at the gym (triggered the GymPrompt + spammed `GymTap`) to get ACTIVE carving.
- With a low belly (real carving), moving+eating: **frame 79.7 ms, physics
  (`Workspace.Heartbeat`) 60.6 ms**, 38 frames > 50 ms. Moving+NOT-eating:
  physics **2.4 ms**. → the spike is the PHYSICS step, driven by carving.
- Mechanism: eating (bites + the settle automaton oozing crater walls back)
  changes cells across the whole cake; resizing hundreds of CanCollide column
  parts per frame re-indexes the physics BROADPHASE. Settles after 5–10 s because
  the eaten area reaches the layer floor and stops changing.
- The remaining ~1 Hz frame spikes (present even while STANDING, not eating) are
  the Studio shared-process SERVER bleed (1 Hz full-field `ScanStats`) — the same
  Studio-only artifact the prior doc noted; not a real-client cost.

**Root cause:** resizing many CanCollide collision-column parts per frame during
active eating spikes the physics broadphase.

## Changes
**Modified:**
- `src/client/modules/CakeRenderer.lua` — replaced the whole-cake, event-driven
  `updateCollisionColumns(drainedCells)` + `stepCollisionRise(dt)` with ONE
  `updateCollisionNearPlayer(dt, footPos)` (called each frame in `editableStep`).
  It scans only the columns within `render.collision.updateRadiusStuds` of the
  local player's foot, recomputes each from the field, snaps drops / rate-limits
  rises, and resizes a part only when it moved > 0.02 stud. `columnsRebuild`
  still snaps ALL columns on a snapshot/new cake. The old `colActive` set now
  serves only the parts-mode fallback.
- `src/shared/config/CakeConfig.lua` — `render.collision` →
  `{ riseRate=6, slabSnapStuds=8, updateRadiusStuds=18 }` (removed `riseHz`).
- Docs: `features/cake-sim.md`.

## Results (Studio, measured)
| Metric (moving + eating, low belly) | Before | After |
|---|---|---|
| Physics step (`Workspace.Heartbeat`) | 60.6 ms | **6–10 ms** |
| Fall-through while moving+eating | — | none (min HRP Y on cake) |
| `CakeRenderer.Step` Lua | 0.5 ms | 0.5 ms (unchanged) |
| Buried player (footPos nil), columns still update | frozen (review bug) | **yes** (8 columns dropped, verified anchored 15 studs up) |
The residual Studio frame spikes are the server-1Hz bleed (present without
eating), Studio-only. On a real mobile client (separate from the server) the
eating physics — the real cost — is now ~10× lower.

## Decisions
- **Fix the physics, not the mesh.** The mesh Lua was already cheap; the cost was
  the collision-part broadphase. The mesh still updates everywhere (visual);
  only COLLISION is radius-limited (the player can't collide with distant cake).
- **Radius-limit, don't throttle.** Throttling to a lower Hz just batches the
  same total resizes (same broadphase churn); limiting to the player's radius
  cuts the total COUNT (only nearby columns ever resize).
- **Scan centre = the player's XZ over the loaf at ANY depth (`overCakePos`), NOT
  `footPos`** (adversarial review finding #1). `footPos` is nil when the player is
  >`onCakeYTolerance` (7) studs off the surface — i.e. exactly when BURIED (the
  state Task 4 creates). Since this scan is now the ONLY thing that rises the fine
  columns, gating it on `footPos` froze a buried player's columns → they could
  stay sunk below the visual cake until the next new-cake snapshot. Fix: pass
  `LocalCakeField.SurfacePoint(root.X, root.Z)` (non-nil whenever over the loaf,
  regardless of vertical) as the scan centre; `footPos` still drives only the
  cosmetic squish/wax. A buried player keeps getting the 6 studs/s rise and
  un-buries as the cake settles — the Task 4 promise — with the perf win intact.
- Distant stale columns are otherwise safe: a field DROP there → stale-HIGH → the
  scan snaps it DOWN the frame it enters the radius (before the player stands on
  it). A large stale-LOW rise only comes from a snapshot/new-cake, which
  `columnsRebuild` snaps ALL of.

## Open Questions / Followups
- Server 1 Hz `ScanStats` full-field scan hitches the SERVER (~1/s) — Studio-only
  bleed for clients, but a real server-frame cost; make it incremental if server
  frame time ever matters (noted in the prior spike doc too).
- The per-new-cake `columnsRebuild` (snaps all 1024 columns) is a one-time
  physics cost per cake — time-slice if a new-cake hitch ever shows on mobile.

## Related
- Feature: `docs/features/cake-sim.md`
- Prior: `2026-07-19_cake-rebuild-mobile-spike.md` (a different, texture spike),
  `2026-07-20_collision-rework.md` (Task 4 — the rate-limited rise this builds on)
- Upstream: `docs/upstream/QUEUE.md` (radius-limited destructible-surface collision)
