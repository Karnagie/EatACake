# 2026-07-20: Collision rework — straight-line eating, buried + jump

Tags: cake-sim, body-gym, config, collision, mobile

## Task
User: "gameplay feels uncomfortable. When the player runs while eating, the
character constantly bounces, sometimes falls through objects, and has other
collision issues. Rework the collision behavior. While eating, they should move
more or less in a straight line. If the cake piles up around them, the character
should remain partially buried and should have to jump to get back onto the
surface." (Task 4 of a 4-part mobile/asset overhaul.)

## Context
Two CanCollide grids overlapped: the fine CLIENT columns (32×32, snap to server
truth every changed cell — `CakeRenderer`) and the coarse SERVER safety slabs
(16×16, AVERAGE height, 5 Hz — `CakeCollisionService`). Near a fresh crater the
coarse average poked ABOVE the fine columns → the player floated waist-deep /
juddered as the two disagreed ("falls through"). Refilling cake snapped the fine
columns UP instantly → punted the player ("constant bounce"). Per-layer
`bounce` restitution (sponge 0.55, jelly 0.3) + `jumpMult` (sponge 1.9×) launched
the player on bouncy layers.

## Plan
1. One walkable surface: server slabs at MIN of their block so they can't poke
   above the fine columns (keep them as a join fall-catch).
2. Rate-limit the column RISE (drops stay instant): refilling cake lifts you only
   gently → you stay buried, jump to climb out.
3. Flat while eating: suppress the landing bounce + cap the jump while actively
   eating; tone down the per-layer feel for normal walking.

## Changes

**Created:**
- `src/client/modules/LocalEatState.lua` — one client-local boolean (is the local
  player actively eating), Set/Get; shared between CakeSubsClient (setter) and
  CakeFeelSubsClient (reader).

**Modified:**
- `src/server/services/CakeCollisionService.lua` — slabs sit at the MIN height of
  their in-cake block (was average). min-of-4×4 ≤ every fine 2×2 client column,
  so the coarse slab never blocks a descent into a crater; still catches a
  falling player on join. Header rewritten.
- `src/client/modules/CakeRenderer.lua` — collision columns: a bite DROPS a
  column straight to truth (fall into the hole), a RISE is rate-limited.
  `updateCollisionColumns` snaps down / marks `colActive[ci]` for a gradual rise;
  new `stepCollisionRise(dt)` (forward-declared, called each frame in
  `editableStep`) raises active columns at `render.collision.riseRate` studs/s.
  `columnsRebuild` still snaps all + clears colActive (new cake never rate-limits
  → no fall-through).
- `src/client/subscriptions/CakeSubsClient.lua` — each Heartbeat publishes
  `LocalEatState.Set(eating or AutoEat)`.
- `src/client/subscriptions/CakeFeelSubsClient.lua` — `applyJump` caps the mult to
  `feel.jumpMultCapWhileEating` while eating; the landing bounce is suppressed
  while eating (`feel.noBounceWhileEating`); the surface poll re-applies the jump
  on a layer change OR an eating-state flip (new `appliedEating`); reset on
  respawn.
- `src/shared/config/CakeConfig.lua` — `render.collision.riseRate = 6`;
  `feel.noBounceWhileEating`, `feel.jumpMultCapWhileEating = 1`, `feel.bounceMaxUp`
  85→60; toned layer bounce/jump (sponge 1.9/0.55→1.4/0.3, jelly
  1.25/0.3→1.12/0.16, cotton 1.1→1.05).
- Docs: `features/cake-sim.md` (collision gotcha + feel), `features/body-gym.md`.

## Decisions
- **MIN slabs, not collision groups.** Removing server-slab-vs-player collision
  via a collision group risked a join fall-through (client columns may not be
  built when the character spawns and falls). MIN-height keeps the slabs as a
  safe fall-catch while guaranteeing they sit at/under the fine columns
  (min-of-4×4 ≤ any fine column in the block), so they can't block a descent.
  Residual: a ≤200 ms stale window during active eating (5 Hz slab vs per-frame
  columns) where the slab can be slightly high — acceptable, far better than the
  average.
- **Rate-limit RISE only.** Drops must be instant (fall into the hole you bit);
  only refills are capped, which is what produces "buried, jump to climb out". A
  full snapshot/new cake SNAPS (never rate-limit a legit full rebuild).
- **BOTH grids rate-limited (adversarial review finding #1).** The client
  rate-limit alone was defeated on fast/wide refills (cotton/crumb/jelly, ooze >
  6 studs/s): the fine columns are held low, but the coarse server slab still
  snapped to ~truth at 5 Hz and poked above → punt. Fix: the server slab
  (`CakeCollisionService`) now rate-limits its RISE too (same `riseRate`), snaps
  on drops (join fall-catch) and on a jump > `slabSnapStuds` (new cake).
- **Rise writes throttled to `collision.riseHz` (review finding #2).** Each
  rising column resizes a CanCollide part (physics broadphase); 60 Hz churn is a
  mobile cost. Coalesced to ~15 Hz steps (still gradual).
- **Flat gate = ACTIVE hold/tap only, NOT Auto-Eat (review finding #4).** An
  Auto-Eat pass owner keeps the toned per-layer feel while just running; goes flat
  only when actively holding EAT. (The rate-limited rise fix applies to everyone
  regardless, so the pervasive column-snap punt is gone for Auto-Eat too.)
- Kept `LocalEatState` in `client/modules/` (review finding #5): matches the
  project's existing runtime-state holder `LocalCakeField` (also a module).

## Verification (Studio, live)
- Clean boot, no errors. Config synced (riseRate 6, feel gates, toned values).
- Character stands PERFECTLY stably on the cake (Y range 0 over 1.5 s) — no
  fall-through, feet on the collision surface; a fresh JOIN lands on the cake
  (min-slab catches the drop), not the floor.
- Eating carves craters → columns DROP (snap, up to 5 studs) = fall into the
  hole. Rise path wired (`colActive` + `stepCollisionRise`); no rise ever
  exceeded the per-frame rate cap in any sample.
- Bounce-suppression / jump-cap are code-wired (LocalEatState → applyJump/onLanded)
  but need a sponge/jelly SURFACE to observe at runtime (the layer gate keeps the
  surface on frosting; the test profile's high bite-depth carves through flowing
  layers) — left for the user's on-device feel-test.

## Open Questions / Followups
- **Feel tuning is on-device**: `render.collision.riseRate` (6), `riseHz` (15),
  the toned `layers[*].bounce/jumpMult`, `feel.jumpMultCapWhileEating` are dials.
- **Burial is transient (review finding #3)**: the rate-limited rise still lifts a
  standing player to the surface over ~1-2 s (it just doesn't punt them). The
  "must jump out" feel is mainly delivered by the SOLID un-eaten walls you jump
  over. If the user wants stronger burial (stay sunk until you jump), cap the
  column at the player's foot height instead of merely slowing the rise —
  deferred pending their feel-test.
- Confirm the throttled rise + server-slab rate-limit don't add to the mobile eat
  spike (Task 2 profiling covers this file).

## Related
- Feature: `docs/features/cake-sim.md`, `docs/features/body-gym.md`
- Prior flow: `2026-07-18_layer-meshes-crust-feel.md` (feel), `2026-07-19_easy-mode-balance.md`
- Upstream: `docs/upstream/QUEUE.md` (2026-07-20 comfortable heightfield collision)
