# 2026-08-07 — "sometimes i spawn in the cake"

**Tags:** cake-sim, cake-cycle, collision, map, checkpoint, config, spawn

## What was asked
> sometimes i spawn in the cake, fix it

Intermittent: the character ends up INSIDE the cake heightfield instead of on it.

## What it actually was — four independent holes, not one bug

A cake is HEIGHTS before it is a COLLIDER, and the server places characters on it
inside that window. Every hole had to be closed; each one alone still leaves a
reachable case. The `sometimes` was a race whose outcome depended on whether the
last profile load beat the character's fall.

| # | Hole | Why it fired |
|---|---|---|
| 1 | The server safety net was **structurally** late | `CakeCollisionService.UpdateHeights` has ONE caller — the 5 Hz clock in `CakeSimulationSubs`, below that Heartbeat's `roundSimulationEnabled()` early-return, **and the accumulator is below it too**. The gate (`match-started`) is set by `CompleteStart` only AFTER `BeginMatch` returns, so at a reserved-match start the 256 slabs were provably still their 1-stud build pose (top at Y=2) for a full tick period after the lift placed players at Y≈178 |
| 2 | The client net needed a **yield** | `OnSnapshot` ran the lazy `editableRebuild` before `columnsRebuild`. Measured live: **482 ms** for the cold mesh pool. For that whole time the cake was visible and not solid; `columnsRebuild` then closed 1024 solid columns around whoever had fallen |
| 3 | The lift **kept velocity** | `root.CFrame = …` does not clear `AssemblyLinearVelocity`. During the arrival window there is no cake at all, so every character is mid-fall from the pad at up to terminal speed. Placed at cake height still carrying ~150 studs/s, they punch through on the next physics step. The same codebase already does this correctly one file over (`BodySubs.mountTreadmill`). The target was also `+ 3` — an R15 HRP offset, i.e. feet flush with ZERO clearance |
| 4 | The rescue had **exactly one shot** | `rescueBuriedLocal` was called from ONE place, after a snapshot. A reserved match broadcasts ONE snapshot per ~35-minute session, so every guard (no character yet, movement lock held, off the footprint) spent the session's only chance. Its own comment said "the NEXT snapshot's rebuild will catch them" — false in the shipped mode |

## The reversal worth keeping

**Burial must be measured against the COLLIDER, not the simulated surface.** The
two differ ON PURPOSE: `render.collision.riseRate` holds a column below the field
so refilling cake buries you and you jump out. A field-based depth test therefore
reads a large depth during exactly that intended feel — and the "rescue" would
have teleported the player to the full refilled height, undoing the mechanic. New
`CakeRenderer.ColumnTopAt` is the truth source; it also covers the rim ring, where
`SurfacePoint` is nil but a column can stand at FULL cake height (`colTarget`
divides by the count of IN-cake cells, so an edge column with one in-cake cell
gets that cell's whole height over out-of-cake XZ). Both the collision scan and
the rescue used to conclude "off the cake, nothing to be buried in" there — an
unrecoverable trap ring, and the player could not even eat their way out
(`computeBitePoint` samples through the same nil).

## Changes

- `CakeCycleSubs.SpawnNewCake` — `CakeCollisionService.UpdateHeights()` + accumulator
  reset between `ResetCake` and the lift. Lift splits `surfaceY` (predicate — so a
  player already on fresh crust is not re-hopped) from `liftY = surfaceY +
  composition.liftClearanceStuds`; zeroes both assembly velocities; skips `Anchored`
  roots (the treadmill mount owns those — `BodySubs` re-asserts them at 8 Hz, which
  is why skipping is correct and not a strand).
- `CakeRenderer` — `columnsRebuild()` moved above the yielding `editableRebuild`,
  with a repaint if that degrades to `impl = "parts"`. `updateCollisionNearPlayer`
  no longer early-returns off-footprint and its write gate compares distance to
  TARGET, not the per-frame step. New `ColumnTopAt(wx, wz)` and `SnapCollisionNow()`.
- `CakeSubsClient` — rescue armed three ways (post-rebuild, every fresh character
  **including the one that already exists at `Start`**, and a dwell-gated watchdog on
  the existing `RenderStepped` loop); measures against the column; zeroes velocity;
  a movement lock SKIPS a tick instead of forfeiting.
- `MapService.SetCheckpointHeight` — the `CakeSpawn` pad move hoisted above the
  `checkpointPlate == nil` guard (it needs only `topY`); the warn names the pad.
- `CakeConfig` — new `composition.liftClearanceStuds = 8`,
  `render.collision.buriedRescuePollSeconds = 0.5`, `buriedRescueDwellSeconds = 2.0`,
  `freshCharacterSnapSeconds = 1.5`; `buriedRescueLift` 3 → 8 (it was the same R15
  HRP-offset mistake as the server's `+ 3`).

## Verified (Studio, live, reserved-match path)

The dev build takes the reserved-match path (`direct easy-solo fallback` →
`BeginMatch`), so the broken path is the one that ran.

| Check | Result |
|---|---|
| Boot | clean; no new warns; `UpdateHeights` from `SpawnNewCake` did not throw |
| Centre safety slab after cake spawn | `SizeY = 172.70`, top `174.70` — **not** the parked 1-stud plate |
| Standing player | `columnTop − HRP = −3.29` (on top of its column), 788/1024 columns collidable |
| Respawn (`Health = 0`) | `columnTop − HRP = −3.29` — identical, lands on the surface |
| Forced 25-stud burial | held through the dwell (t=0.5/1.0/1.5 s), lifted at t=2.0 s to `columnTop + 8`, settled at 178.0. Warn: `local character was 24 studs INSIDE the cake (buried for 2s) — lifted onto the surface` |
| 3.75-stud sink (< `buriedRescueStuds`) | **not** lifted for 4 s+ — the deliberate crater feel survives |

## Notes / traps hit

- **The Studio command bar's `require` returns a FRESH module instance.** Reading
  `CakeStateData` that way showed `cakeIndex=0, collisionParts=0` while the console
  proved a cake was built, and `CakeRenderer.Impl()` returned nil. Measure through
  the DataModel (`workspace.CakeCollision`, `workspace.CakeColumns`), not through a
  re-required module.
- Adversarial review caught a CRITICAL that testing would not have: moving
  `columnsRebuild` above `editableRebuild` broke the parts-fallback repaint, because
  `editableRebuild` flips `visualColumns` on its way to degrading — the fallback
  would have rendered an invisible cake you can walk on.
- Review also claimed the `Anchored` guard strands treadmill players; **refuted** —
  `BodySubs.lua:511-515` explicitly re-asserts the mount CFrame "so a (rare) plate
  step-down carries them along".

## Upstream (U1)
`EAC-0258` … `EAC-0265` — 3×P1 (collider-before-teleport ordering; zero the assembly
on any repositioning CFrame write; count how often a "safety net" is actually armed),
plus the collider-vs-simulation depth measurement, the framerate-dependent write
gate, cheap-correctness-before-expensive-cosmetics, the region-gated early return
that blinds maintenance at the boundary, and the shared setter gated on an
unrelated asset.
