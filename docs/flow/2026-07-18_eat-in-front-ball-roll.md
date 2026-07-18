# 2026-07-18: Eat-in-front, hand-piece eat gesture, full-belly ball roll

Tags: cake-sim, body-gym, juice, config

## Task
"Улучши поедание торта": eating grows the body; a full belly can't eat and
turns the body into a BALL you ROLL (visual only — jump still works); you eat
the cake IN FRONT of you (not where you click); each click rips a piece of the
correct LAYER into your hand and you eat it; the eat animation's speed tracks
the eat-rate stat.

## Context
Cake bite loop already existed: `CakeSubsClient` aimed bites with a pointer
raycast (§7.6 "eat anywhere you tap") → `EatAt` → `CakeSubs` (anti-cheat,
`ApplyBite`, `StomachService.Ingest`) → `StomachUpdate` + `BodySubs.RefreshBody`
(WalkSpeed penalty + replicated `StomachFill` attribute). `BodyMorphController`
already inflated every character locally from that attribute; at full the old
rule was "fill stops, glutton ×2 keeps rewarding overeating". Read
`features/cake-sim.md`, `features/body-gym.md`, prior flow
`2026-07-18_wax-shell.md` / `_layer-meshes-crust-feel.md` for the render/feel
context.

## Plan
Reuse the existing pipelines, add the feel on top:
- **Eat in front**: replace the pointer-raycast bite target with the surface
  directly ahead along HRP LookVector (turn to aim).
- **Eat gesture**: new LOCAL `EatGestureController` — pooled piece flies cake→
  hand→mouth, arm lifts via Motor6D override, flight time from the eat-rate
  stat. Local-only, matching the existing local-prediction bite juice.
- **Grow → ball → roll**: bump the morph, add a new `BallRollController` that
  (like BodyMorphController) reads `StomachFill` on every client and past
  `enterFill` cross-fades the rig into a spinning cake ball rolled by real
  distance. Visual only — never touch WalkSpeed/jump.
- **Can't eat when full**: `StomachService.IsFull` + a pre-carve drop in
  `CakeSubs`; the client mirrors it (`isFull`) to stop firing + a soft cue.

## Changes

**Created:**
- `src/client/modules/EatGestureController.lua` — pooled flying eat pieces +
  chew-arm Motor6D override; `Play(fromPos, layer, eatRate)` / `Step(dt)`.
- `src/client/modules/BallRollController.lua` — per-character rig→ball cross-
  fade + physics-correct rolling; `Step(dt)`.
- `docs/flow/2026-07-18_eat-in-front-ball-roll.md` (this file).

**Modified:**
- `src/shared/config/BodyConfig.lua` — morph tuned bigger/rounder; NEW `ball`
  and `eatGesture` tuning sections; header/comments updated (full = blocked).
- `src/server/services/StomachService.lua` — NEW `IsFull`; glutton redefined as
  the bite that reaches capacity (`fill + volume ≥ capacity`).
- `src/server/subscriptions/CakeSubs.lua` — EatAt drops the bite when `IsFull`
  BEFORE carving (no phantom crater); reuses the `capacity` local for Ingest.
- `src/client/subscriptions/CakeSubsClient.lua` — forward-eating bite target
  (removed pointer raycast + touch-aim tracking + `InputChanged`); `isFull`
  gate with soft cue; drives `EatGestureController.Play`/`.Step`.
- `src/client/subscriptions/BodySubsClient.lua` — drives `BallRollController.Step`.
- `docs/MAP.md`, `docs/features/cake-sim.md`, `docs/features/body-gym.md`,
  `docs/upstream/QUEUE.md`.

## Decisions
- **Eat gesture is LOCAL only** (like the existing bite particles/chunks/
  prediction). Other players see the shared BALL morph but not each other's
  chew — per-bite gesture replication would fight the local-prediction model
  for no real gain. Config `BodyConfig.eatGesture`.
- **Ball is a cosmetic proxy, movement is untouched** (R6 "visual on client").
  Rig hidden per-client via `LocalTransparencyModifier` (so every viewer sees
  the ball; nametag Billboards ride the Head part and survive). Rolling is
  physics-true (revolutions = distance / πd, axis = up × moveDir) so it never
  visibly slips; a short down-ray grounds it and it follows the body up on a
  jump. WalkSpeed/jump stay server-authoritative (the fullness penalty already
  slows you — "you roll slowly").
- **Full = can't eat, gym is the release valve.** Blocking bites made the old
  "glutton = overeat for ×2" dead, so glutton was moved to the bite that TOPS
  YOU OFF (the last-mouthful reward). Server blocks authoritatively; the client
  gates itself so it never predicts a crater the server refused.
- **`isFull` self-probe (adversarial-review CRITICAL fix).** A hard client
  block soft-locks a full player who then buys a **capacity upgrade/gamepass**:
  those paths only call `BodySubs.RefreshBody` (no `StomachUpdate`), so the
  client's `isFull` never clears and it never fires again → stuck. Fix: while
  full the client still fires a THROTTLED (0.6 s) forward `EatAt` probe (no
  prediction); the moment the server accepts (cap raised → not full) its
  `StomachUpdate` clears `isFull`. One client-side change covers every
  capacity source (upgrade, gamepass, rebirth) — no server/cross-sub edits.
- **Arm via Motor6D.Transform in RenderStepped** (no uploaded animation asset):
  the write lands after the default Animate track for the frame; we stop
  writing once the chew decays so idle/walk anims resume. Degrades on any rig
  (R6/R15/missing joints) — the piece arc alone reads as "eating".
- New client-visual tuning lives in `BodyConfig` beside `morph` (R1) — the
  established home for body-morph client tuning; server never reads it.

## Verification (Studio, live)
- Clean boot, all modules Init/Start ok, **0 client errors** across the run.
- **Ball morph** end-to-end: forcing `StomachFill=1` hid the rig
  (`LocalTransparencyModifier=1`) and showed an opaque `Shape=Ball` proxy;
  re-engaged automatically when the belly refilled to full.
- **Full-block**: with a genuinely full belly (fill 150 = capacity 150) a valid
  forward `EatAt` at the surface carved NOTHING (verified twice).
- **Forward-eat**: after a gym burn emptied the belly, a forward `EatAt` dropped
  the surface 1.92 studs directly ahead and filled `StomachFill 0 → 1`.
- **Gym loop** still empties the belly and un-fulls the player.
- Fixed a Rojo double-sync that created duplicate `EatGestureController`/
  `BallRollController` ModuleScripts (benign — bootstrap dedupes by name — but
  removed the extras so the place is tidy; a re-sync stays consistent).

## Iteration 2 — user feedback (same day)
Feedback: (1) no eat animation; (2) don't become a bare sphere — the body
should grow round but KEEP its head + arms ("шарик с головой и ручками");
(3) cake tore off too far. Fixes, all Studio-verified with `screen_capture`:
- **Rig discovery (root cause of #1 + a rewrite driver):** the test avatar uses
  **AnimationConstraints, not Motor6Ds**, and the Animator overwrites any joint
  `.Transform` at every RenderStep priority. The old eat-gesture posed the arm
  via `Motor6D.RightShoulder` → the module never found it → silent no-op = "no
  animation". Also this avatar can't be runtime-scaled (Humanoid BodyScale
  NumberValues ignored, `ApplyDescription` fails). Both documented in
  `features/body-gym.md` gotchas.
- **#1:** removed the joint arm-posing; the eat gesture is now purely the
  rig-agnostic flying piece (bigger 2-stud piece, min 0.24 s flight). Verified:
  real pooled pieces fly (≤2 concurrent, a piece on-screen ~85% of eating).
- **#2:** dropped the sphere/rig-hide. `BallRollController` now grows a pink
  BELLY BALL welded over the torso (torso parts fade) with head+legs poking out
  and two cosmetic mitten "ручки" welded to the ball sides. Tumble (user chose
  "катится кувырком") rotates the ROOT joint's STATIC offset (Motor6D.C0 /
  AnimationConstraint Attachment0 — the channel the Animator can't clobber) by
  distance travelled; unwinds + restores on de-round. Verified: round body with
  head/mittens/legs; tumble rolls forward (legs go up-and-over).
- **#3:** forward reach `6 + r·0.5` → `3 + r·0.25` (≈ half).

Adversarial review of the rewrite → fixed: a full body standing STILL froze at
its last tumble tilt (often head-down) — now it settles UPRIGHT when stopped
(tumble only accumulates while actually moving; eases to 0 otherwise); R8 log
when no root joint is found (ball still shows, tumble disabled); tear-down +
rebuild if the rig's parts are replaced in place; removed the now-dead arm
config keys (`armRaise`/`armLerp`/`chewHold`) + stale comment. Verified:
settle-upright confirmed (root offset → 0° after stopping); 0 errors.

## Iteration 3 — user feedback (same day)
Feedback: don't replace the body with a ball mesh / add parts — "let the body
just scale." So the belly-ball + mittens were REMOVED and replaced with real
body scaling:
- **Key discovery:** Humanoid BodyScale NumberValues DO scale this avatar — but
  ONLY when set on the **SERVER** (client writes are reverted by replication;
  probe: client=4 → no change, server=3 → armspan 2.1→5.9). Direct part `.Size`
  is fought by the auto-scaler. That's why the old client-side
  `BodyMorphController` never scaled this avatar.
- **Removed:** the belly-ball/mittens/torso-fade from `BallRollController` (now
  tumble-only) and `BodyMorphController` entirely (client scaling is dead here;
  its per-bite squash went with it).
- **Added:** a SERVER-side morph lerp in `BodySubs` (15 Hz, from
  `StomachService.Fullness`, `BodyConfig.morph`) — the REAL body scales bigger &
  fatter (width/depth ≫ height, head unscaled). Verified: `BodyWidthScale` 1→2.8,
  armspan 2.1→5.4; body walks 27 studs on flat ground; tumble rolls to 178° then
  settles upright; 0 errors. Config `ball`→`tumble`.
- The scaled body is chunky/blocky (the R15 torso is the real mesh, not a
  sphere) — that's the trade for "no proxy meshes."

Adversarial review of the refactor → fixed: the `minStep` guard stopped the
lerp ~0.06 SHORT of target (body never reached full scale, never returned to
1.0 after the gym — stuck ~6% wide) → now SNAPS to target within minStep
(verified: 2.8 at full, exactly 1.0 when emptied); the R8 warn latch was a
single global bool (false-positived normal R15 players in the spawn window +
suppressed others) → `Log.GraceOnce` per-player; `rateHz` moved to config;
fixed `juice.md` still listing the deleted `BodyMorphController`/squash.

## Iteration 4 — user feedback (same day)
Feedback: "тело растёт правильно, но руки и ноги тоже растут — должен расти
только торс." So the morph now scales ONLY the torso, not the whole body:
- Humanoid BodyScale scales everything; the auto-scaler enforces `part.Size =
  OriginalSize × BodyScale` and reverts direct `.Size` writes. Fix: grow only
  the TORSO parts' `OriginalSize` (BodyScale left at 1) → only the torso scales,
  and it HOLDS. Server-side (client writes revert), snap-to-target on the final
  approach. Capture the true natural OriginalSize ONCE per part.
- BUG caught in verify: a weak-key cache silently dropped the natural-size
  capture → each tick re-read the already-scaled value → compounded (torso →
  112 studs). Fixed with a strong table + prune-on-destroy.
- Verified: torso grows 1.85→5.17 (2.8×) and holds, arms unchanged (armspan
  2.1), returns to exactly 1.847 after the gym; 0 errors.
- Caveat surfaced: the big torso can engulf the third-person camera at close
  zoom (would apply to any large body). Cap size / reduce depth if it bites.

## Open Questions / Followups
- Morph proportions (`widthScale`/`depthScale`/`heightScale` = torso scale at
  full) + `tumbleFill`/`rollRadius` are first-pass — tune for how fat it reads.
- Camera can clip inside the huge torso at close zoom — cap the max torso scale
  or reduce `depthScale` (front-to-back) if it's a problem in play.
- The scaled body's HRP collision scales too: fine on flat ground, but a full
  body can catch on the cake's craters (jump to unstick). Consider not scaling
  the HRP, or a smaller max scale, if it's annoying in play.
- Tumble pivots about the hip (Root attachment), so at ~180° the head dips
  through the surface. Fine for a fast roll; raise the pivot if it bothers.
- Eat gesture could later be replicated (all players see everyone chew) — needs
  a lightweight networked "bite happened" signal.
- The full-belly "nope" cue is still the rbxasset placeholder; tune SFX later.

## Related
- Features: `docs/features/cake-sim.md`, `docs/features/body-gym.md`
- Prior flow: `docs/flow/2026-07-18_wax-shell.md`,
  `docs/flow/2026-07-18_layer-meshes-crust-feel.md`
- Upstream: two recipe rows (procedural use-item gesture; rig→rolling-proxy)
