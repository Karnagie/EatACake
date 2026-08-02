# 2026-08-01: Onboarding tutorial

Tags: tutorial, onboarding, ui-kit, app-root, persistence, checkpoint, body-gym, analytics, theme

## Task
Verbatim: show four slides (`139890329511008`, `88501692577908`,
`135307023473908`, `99839198517910`) in a 2x2 grid with a Skip button when the
GAME (not lobby) starts; then a popup teaching that you eat the cake (mobile =
the on-screen button, PC = left mouse); at >=90% stomach a guiding beam toward
the path plus a tween on the Teleport-to-Checkpoint button; after the path, an
arrow toward the upgrades PC. That ends the tutorial — later playthroughs show
only the slides. Beam template: `ReplicatedStorage.Assets.GuidanceTemplates.HintBeam`.

## Context
No tutorial/onboarding feature existed (the only `onboarding` in `src/` was
`AnalyticsSubs`' retention funnel). Recon workflow (7 parallel readers +
synthesis) mapped every subsystem it had to hook into; the resulting integration
contract drove the build. Studio was open on the GAME place (`136881957250247`).

## Plan
Two independent halves: the slides play EVERY entry (they are the premise, not a
lesson); steps 2-5 run once per account behind a persisted flag. Client owns the
whole step machine — the server owns exactly one boolean, because a round trip
per step buys nothing on a flow whose job is to feel immediate.

Design ran the `roblox-ui-kit` method: archetype reasoned from genre (no
window-archetypes row for a story intro), zone arithmetic with closing
check-sums, new elements DERIVED from kit relatives, then the visual iteration
loop with the tonal-hierarchy + squint gates.

## Changes

**Created:**
- `src/shared/config/TutorialConfig.lua` — slides, 0.90 threshold, world names, beam overrides
- `src/shared/UIKit/Components/TutorialSlides.lua` — the 2x2 comic board
- `src/shared/UIKit/Components/TutorialHint.lua` — the instruction card
- `src/shared/UIKit/Components/InputGlyph.lua` — vectored mouse / EAT-button miniature
- `src/shared/UIKit/Components/HintArrow.lua` — world-tracking objective marker (ADR-0016)
- `src/shared/remotes/TutorialComplete.model.json`, `src/shared/remoteUpdates/TutorialUpdate.model.json`
- `src/server/common/data/ProfileSchema/TutorialSection.lua` — `{ done }`
- `src/server/game/subscriptions/TutorialSubs.lua`
- `src/client/common/subscriptions/TutorialSubsClient.lua` — the step machine + beam
- `docs/features/tutorial.md`, `docs/decisions/0016-world-tracking-hud-marker.md`

**Modified:**
- `Theme.lua` — `TutorialSlides`/`TutorialPanel`/`TutorialHint`/`TutorialGlyph`/`TutorialArrow` sections, two button styles, `Feel.Pulse`, freezes
- `Icons.lua` — the 4 slide ids (order is load-bearing)
- `UIKit/init.lua` — 4 component registrations
- `Components/Button.lua` — optional `pulse` prop (a SECOND UIScale on the root; Roblox applies one UIScale per GuiObject, so it cannot share `Content` with the press one)
- `AppRoot.lua` — `tutorial` state, `AppRoot.Get`, 3 overlays, pulse wiring, 2 viewport scales, HUD suppressed under the comic
- `LocaleData.lua` — `tutorial-*` keys
- `AnalyticsSubs.lua` — `tutorialDone` funnel beat (step 7)

## Decisions
- **The slides are NOT an `openPanel`.** Routing them through it would fire the
  audio whoosh, arm the scrim's shop-closing branch, and — fatally — hide the
  touch EAT button, since `eatButtonVisible` requires `openPanel == nil`.
- **The eat popup carries no scrim and no click-catcher.** PC eating is a global
  `InputBegan` guarded by `gameProcessed`, so a full-screen `Active` surface
  swallows the very click being taught. Verified live: belly 0→495 with the
  popup up, and it auto-dismissed on that first bite.
- **The whole `Hud` LAYER hides under the comic**, not element-by-element —
  three separate leaks (TO CHECKPOINT, BellyBar, EAT) showed through the scrim
  before that. The EAT button keeps its own gate too, because `Interaction`
  releases a hold on `enabled` flipping, not on an ancestor's `Visible`.
- **The 90% threshold is latched** — gym drains resync the belly at ~8 Hz and an
  un-latched test would blink the beam off at 89% mid-walk.
- **Arrival reads `AppRoot.Get("checkpointFar")`** (new tiny API) rather than
  duplicating BodySubsClient's plate-footprint test — one definition of the fact.
- **Completion fires from ANY live step**, not just step 4 — see below.
- **Beam overrides live on the CLONE**, never the authored template.

## Findings that changed the code
- **Adversarial review (21 agents, 17 findings, 10 refuted).** The load-bearing
  one: the `UpgradeStation` prompt is a 10-stud no-line-of-sight sphere ~3.5
  studs from the loaf edge, so it lights up several studs back ONTO the cake —
  while `checkpointFar` stays true anywhere on the loaf by design. Gating
  completion on `step == "upgrades"` silently dropped it for anyone who pressed
  E on the way in, and their tutorial replayed forever. Also fixed: `HintArrow`
  parked mid-screen for a behind-camera target (mirrored projection + per-axis
  clamp — now a ray-box push-out), its edge-pin angle was computed in viewport
  FRACTIONS (~20° error on a wide viewport — now pixel space), the hint card
  overlapped the CakeBar on any window shorter than ~1000px, and the server's
  pre-load `Log.Warn` was unthrottled on a client-fired remote (now keyed
  `Log.Once`, matching CakeSubs/BodySubs).
- **The authored beam is invisible as authored.** `HintBeam` is a 3-stud WHITE
  line; this guidance run is 80+ studs across a pastel sky over a near-white
  loaf. Isolated in Studio by fattening it to 20 and stripping the texture (it
  rendered), then restoring the texture at width 20 (near-invisible) — so it is
  BOTH width and hue. `TutorialConfig.beam.width`/`.color` now override on the
  clone; nil defers to the template.
- **Tonal/squint gate**: first play capture scored 47.4 with 5 CRITICALs — the
  blue Skip button ranked #9 and dissolved at a squint, and the gold order
  badges were the screen's #1 attention magnet. Fixes: scrim 0.35→0.24, Skip →
  green and 300x76→420x120, badges gold→panel-navy at 56→44. Gate: **IMPROVED,
  49.9 → 88.2, CRITICALs 4 → 1.**

## Open Questions / Followups
- One residual `blur-invisible` CRITICAL on the Skip CTA: it is attention rank
  #1 with dL* 37 vs surround and WCAG 4.66, and survives the COLOUR squint as a
  distinct green mass, but merges with the comic board in GRAYSCALE — the board
  and the button occupy the same value band, and the art is user-supplied and
  spans the full value range, so no single button value separates from all four
  panels. Three levers (colour, tone, size) were taken and moved it +2→+4 dL*.
  Worth revisiting only with a value treatment on the board itself.
- Verified in Studio on the GAME place only; the lobby gate is code-verified
  (`GameUiData` absent → early return) but not play-verified in the lobby place.
- `roblox-ui-kit` iteration count: 4 visual loops (glyph legibility, HUD leak,
  tonal fixes, CTA size).

## Related
- Feature: `docs/features/tutorial.md`
- ADRs: ADR-0016 (new); touches ADR-0006 (animation), ADR-0007 (place assets),
  ADR-0013 (run reset — why the flag needs its own section)
- Prior flow: `docs/flow/2026-08-01_tonal-hierarchy-toolkit.md`
