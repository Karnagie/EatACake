# 2026-07-22: Per-layer wax, wax-hole reveal, thin-remnant sweep, treadmill run

Tags: cake-sim, body-gym, checkpoint, config, rendering, gameplay

## Task
Four user requests:
1. The wax colour on each layer should depend on that layer — slightly brighter
   than the layer itself (not a generic vivid glaze).
2. Eating leaves too many small hard-to-eat pieces that ruin the look — they
   should be easy to eat OR disappear automatically.
3. The wax barely disappears when eating; it should VANISH wherever a hole is
   eaten through the cake (regression — the wax on the layer below looked
   "connected"). This did not happen before.
4. Fat removal should be animated: the user added a treadmill model. Activating
   the "Remove Fat" prompt should put the player ON the treadmill and start them
   running; once all the fat is gone, teleport them back next to the treadmill.

## Context
- The 2026-07-20 "coat every layer" change made `CakeWaxShell` ride the surface
  DOWN to the active-band floor and re-coat craters — which is exactly the
  "wax barely disappears / layers connected" regression the user now reports (3).
- The clean-cut bite + the settle `clearedCeil` guard leave thin WALLS/SPIKES
  standing between craters that can't relax without refilling a crater
  (conservation) — the "small pieces" (2).
- The treadmill the user added is the authored `Model` INSIDE the invisible
  `GymMachine` collider Part (all parts anchored, no welds).

## Changes (all in existing files)
- **(1) Wax colour** — `CakeConfig.render.wax`: `satBoost 1.4→1.05`,
  `valBoost(×1.12) → valBrighten(0.22, headroom-proportional)`;
  `CakeWaxShell.glazeColor` = the layer's own top colour, hue/saturation kept,
  value lifted toward white by `valBrighten·(1-v)` (always brightens, no clamp
  flattening). Studio-verified: frosting wax reads as a soft brighter pink.
- **(3) Wax hole reveal** — `CakeWaxShell`: hide reference changed from
  `ActiveFloorStuds()-0.3` back to `lastMaxH - wax.hideDepth` (a crater
  `hideDepth` below the outermost remaining layer hides that piece); new module
  `lastMaxH` (fed each frame, 1-frame lag) + `lastCakeIndex` (reset `lastMaxH` on
  a new cake so a fresh, shorter cake doesn't flash all-hidden for a lag frame).
  Reverts the ride-to-active-floor "coat every layer" rule. Studio-verified: a
  crater shows the frosting body / next layer, wax gone.
- **(2) Thin-remnant sweep** — `CakeConfig.sim.remnantSweep {enabled,
  wallDropStuds=4, minClearedNeighbors=3}`; `CakeFieldService.ScanStats` two-phase
  (collect/apply) sweep collapses ISOLATED active-band remnants to the active
  floor: a cell with `>=minClearedNeighbors` in-cake neighbours a crater below it
  (a spike), or exactly 2 OPPOSITE (a 1-cell wall). Out-of-cake neighbours count
  as SUPPORT, so the loaf perimeter + clean cut edges + convex corners survive.
  Forfeits the volume (like auto-sweep). Studio-verified: a bite cluster merges
  into one clean hole, no leftover-piece field.
- **(4) Treadmill run** — server-only:
  - `MapConfigData.checkpoint.treadmill*` (`treadmillStandHeight=6.2` verified,
    `FaceYaw=0`, `DismountBack=5`, `DismountHeight=3.5`).
  - `BodyConfig.gym.treadmill {enabled, runAnimationId}`.
  - `MapService.GetGymMountCFrame()` / `GetGymDismountCFrame()`.
  - `BodySubs`: `gymMount` wiring table, `playRunAnim` (server-side Animator
    LoadAnimation → replicates to everyone; the character's own `Animate.run`,
    else the config fallback), `mountTreadmill` (teleport + anchor HRP + run
    anim), `unmountTreadmill` (stop anim + restore anchor + step off). The
    GymPrompt handler mounts on a real session; the drain loop splits into a
    MOUNTED branch (no walk-away stop, re-assert the mount CFrame, unmount on
    complete) and the legacy STANDING branch; `burnAll` unmounts; a per-tick
    SAFETY NET unmounts any player mounted-without-session (covers rebirth's
    external `EndSession`) and fires `{event="stopped"}`; `CharacterRemoving` +
    `PlayerRemoving` clear the mount. Studio-verified: mount pose (feet on belt,
    facing along the belt), run animation plays, prompt shows, treadmill + upgrade
    station ride the plate.

## Decisions
- **`BasePart:PivotTo()` moves descendant parts** (unlike `.CFrame =`). First
  attempt added a `rigidMoveTo` that ALSO moved descendants by a delta → the
  treadmill DOUBLE-moved (visual at ~2× plate height). Reverted to plain
  `PivotTo`; the authored treadmill/station child visuals ride the plate for free.
- **Run animation is played SERVER-side** so it replicates to all clients without
  the network-ownership ambiguity of playing it on the anchored (server-owned)
  character from the client. Prefer the rig's own `Animate.run`; config id is the
  fallback.
- **Committed run** — the player is ANCHORED on the belt, so the old "walk away to
  stop" rule is superseded for a run (it ends when the belly empties; taps still
  speed it up; passive `burnSpeed` guarantees completion). The walk-away stop
  stays for the standing fallback. A per-tick safety net + `CharacterRemoving`
  make "stuck anchored" impossible (adversarial-reviewer CRITICAL).
- **Remnant sweep FORFEITS volume** (documented gotcha). A tall 1-cell wall is a
  non-trivial forfeit; tunable via `wallDropStuds` / `enabled`.

## Verification (Studio, live)
Studio's Rojo plugin was disconnected (stale source); synced my 7 edited files
into the Edit DataModel by serving the repo over local HTTP and `HttpService:
GetAsync` → set `.Source`, then playtested. Boot clean (0 errors); treadmill
rides the plate (belt bottom on plate top), mount pose + run anim + prompt good;
wax reads brighter-pink; a dug crater shows the wax GONE + cake body; 0 runtime
errors across eating + sweep + treadmill.

## Open Questions / Followups
- Treadmill mount offsets are tunable (`treadmillStandHeight`/`FaceYaw` etc.) —
  verified against the current authored treadmill; re-tune if the model changes.
- `runAnimationId` fallback is the R15 default run; the rig's own `Animate.run`
  is preferred at runtime.
- A mounted player can still fire `ReturnToCheckpoint` (F/button) — the re-assert
  snaps them back (1-tick jitter, harmless); could gate the button while mounted.
- Wax brightness + remnant-sweep aggressiveness are feel values — tune in play.

## Related
- Features: `docs/features/cake-sim.md`, `docs/features/body-gym.md`,
  `docs/features/checkpoint.md`
- Prior flow: `2026-07-20_two-layer-wax-cleaner-cut.md` (the wax rule this
  reverts), `2026-07-20_collision-rework.md`
