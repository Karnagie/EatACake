# 2026-08-12: Matchmaking Grouping Polish

Tags: lobby-matchmaking, cake-select, ui-kit, tonal-hierarchy, squint-test, accessibility

## Task

Make **Choose a Match** read as three distinct groups, move the rainbow unlock
instruction onto its cake card, enlarge the cake cards, unify and centre the
group headings, and keep Difficulty/Party text inside the raised button faces.

## Context

The child-first composition already separated setup from cakes horizontally,
but its left column still read as one pile: Difficulty ended only 24px before
the Party Size heading and both headings were left-aligned over centred rows.
The Cake heading also used a separate quieter blue. Difficulty labels extended
9 nominal px below their Face and party counts extended 6px below theirs, so
both appeared on the button lip/shadow. Cake cards used only 214 of the 268px
rail height, while a locked rainbow tap borrowed the footer line above START.

## Plan

- Keep the existing 904x432 content box, 452/32/420 horizontal split, sticky
  footer, persisted cake owner, two-argument queue request, and gesture/session
  guards unchanged.
- Re-budget the left 308px setup height as
  `28 + 12 + 112 + 40 + 28 + 12 + 72 + 4 = 308`.
- Grow cards to 132x236. With 12px canvas padding, row two starts at y260 and
  leaves an 8px direct-manipulation cue inside the 268px rail.
- Use one centred heading language for Difficulty, Party Size, and Cake.
- Give the earnable rainbow requirement a wrapped 42px card zone; do not repeat
  the coming-soon title/clock as a second sentence. Keep the footer for
  authoritative queue progress and errors.
- Re-cut selector label boxes against the Face bottom including OutlinedText's
  10%-down shadow, not just the nominal frame.

## Changes

**Modified:**

- `Theme.MatchmakingLayout`: card height 214→236, Difficulty→Party gap 24→40,
  centred-group positions, card-owned lock guidance, and shared heading tokens.
- `Theme.MatchCakeCard`: 132x236 Face/title/status geometry with an opt-in
  wrapped requirement block.
- `Theme.MatchDifficultyChoice`: 54px icon and an inset x9..133, y66..90
  label; its down-left shadow starts at x8.63 and ends at y92.4, inside the
  Face bounds x8..134, y8..93.
- `Theme.MatchPartyChoice`: 29px icon and a y36..57 count; count shadow ends at
  y59.1 inside the Face bottom y60.
- `MatchmakingPanel`: centred setup headings, card-owned earnable requirement,
  no duplicate teaser status, no default/partial setup guidance in the
  queue/error footer, and legacy contextual-notice/status compatibility.
- `CakeCard` / `OutlinedText`: opt-in wrapping. `OutlinedText` leaves
  `TextWrapped` unset for normal labels because explicitly assigning false in
  Studio collapses TextScaled labels toward the default TextSize.
- Feature/UI-kit contracts, this flow record, and upstream candidate EAC-0289
  for the generic TextScaled/TextWrapped engine gotcha.

**Created/Deleted:** none outside documentation.

## Verification

- Live Studio geometry at a 723x434 rendered panel: all headings report centred
  alignment and identical gradients; the inter-group gap measures 28.87px
  (40 nominal); the rainbow card measures 95.26x170.31 (132x236 nominal).
- Difficulty label + shadow ends at 215.31 vs Face bottom 215.74; party count +
  shadow ends at 329.84 vs Face bottom 330.49. Both containment checks pass.
- Rainbow renders `Finish a cake to unlock!` with `TextWrapped = true`;
  coming-soon has no redundant Status child; the ready footer Status is absent.
  A busy probe renders `Starting queue...` in the footer and makes Difficulty,
  Party, cake, and START targets all `Active=false, Selectable=false`.
- The first after capture caught an engine regression from explicitly assigning
  `TextWrapped=false`: every ordinary outlined label shrank. The primitive now
  sets the property only for opt-in wrapped blocks; the final capture restores
  header, headings, selector labels, and START at their established sizes.
- Tonal/Squint like-for-like gate: 67.6→64.0 score, CRITICAL 1→0, WARN 10→10,
  verdict **IMPROVED**. The prior flat-primary finding on START cleared; the
  final screen has zero critical findings. Heavy colour/grey blur keeps START
  as the first mass and the enlarged cake rail as the other major mass.
- Full source parse passes: 232/232 Luau files. Rojo builds pass for `default`,
  `lobby`, and `game` projects.
- Adversarial re-review passes after two edge-case fixes: the default layout now
  suppresses 0/1-selection guidance in the queue/error footer, and the
  Difficulty shadow's left edge remains inside the raised Face.
- Production lobby boot remains healthy: server 11 data / 13 services / 21
  subscriptions; client 7 data / 19 initialized modules / 21 subscriptions;
  ProfileSchema 12 sections; persistence ready; ClientReady and 12/12 initial
  domains pushed. No new runtime errors; the existing missing cloud row warning
  for `match-status-ready` still falls back to English.

## Decisions

- The unlock sentence is persistent card information because it explains how
  to earn one specific cake. Queue progress/errors are transient panel state
  and keep the footer line.
- Group headings are intended second-read anchors (L2): this task exists because
  the decisions were not distinguishable enough, so weakening those anchors
  would undo the grouping fix.
- Card height grows without changing width or the three-column rail, preserving
  all placement/hit-test math and the full current catalogue in one row.

## Related

- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_matchmaking-child-first-cleanup.md`
