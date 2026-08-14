# 2026-08-11: Matchmaking Vertical Cake Rail

Tags: lobby-matchmaking, cake-select, ui-kit, vertical-scroll, tonal-hierarchy, squint-test

## Task
Correct the still-jumbled **Choose a Match** screen: cakes must form a vertical, scrollbar-free rail on the right and scroll by dragging the cake cards themselves. Difficulty and Party Size must become separate, easy-to-scan sections rather than one crowded toolbar. Re-evaluate the result with Tonal Hierarchy and Squint Test.

## Context
The cake-first horizontal redesign improved the earlier difficulty-dominant screen, but its visual audit was incorrectly treated as a pass. Its final Tonal report scored 64.1 and still contained seven warnings: crowded top-level saliency, blur-invisible selected-cake art, noisy panel/header/card regions, a stray level-4 chrome hotspot holding 88% of hotspot mass, and adjacent semantic levels sharing value bands. Difficulty and Party Size also occupied one 58px baseline with the same blue/gold control language, so they read as a single seven-button toolbar. See [the horizontal cake carousel](2026-08-11_cake-first-match-carousel.md).

## Plan
Keep the proven 1000x600 shell and 904x432 safe content region, but rebuild the body as two spatially distinct columns:

- A 368px left setup column contains three stacked Difficulty rows, a separately labelled four-tile Party Size row, quiet readiness copy, and the terminal START action.
- A wider right column contains the primary **Choose a Cake** vertical rail. Fixed-height landscape cards stack on Y with a clipped next-card preview; the partial card is the scroll affordance.
- Remove scrollbar chrome entirely. Mouse/touch card-surface drags and wheel input pan the rail, and a gesture that crosses the drag threshold must not activate the card underneath it.
- Cake remains persisted presentation state. Difficulty and party retain synchronous per-session defaults, readiness behavior, busy gating, analytics identities, controller activation, and the exact two-argument `onStart(difficulty, maxPlayers)` contract.

### Visual hierarchy contract

Final annotations: START L1; selected cake CARD mass L2; literal art, close,
setup controls, available cards, headings, and status L3; locked/soon cards,
passive section surfaces, header, panel, and clipped-card cue L4. Art detail
need not survive blur; the selected card's color mass must.

Candidate 4 scored 68.2 against the rejected horizontal cut's 64.1. Both had
0 CRITICALs; warnings fell 7→3 and compare verdict was **IMPROVED +4.1**. It
resolved `crowded-top`, header noise, selected-art low separation/blur
invisibility, and the stray hotspot. Heavy blur preserves selected cake mass
and START while setup recedes; extreme blur preserves only the panel, right
cake mass, and lower-left CTA.

## Changes

**Created:**
- None.

**Modified:**
- `Theme.lua` — exact split geometry; 368x52 Difficulty and 80x60 Party
  styles; 512x156 match cake card with selected Face mass; 368x68 START.
- `MatchmakingPanel.lua` — vertical deterministic cake canvas, Y reset,
  separate setup surfaces, confirmed-tap dispatcher, and an exit-tween input
  blocker.
- `CakeCard.lua` — selected-card Face/art-stage color masses for squint survival.
- `MatchDifficultyChoice.lua` / `MatchPartyChoice.lua` — new row/tile cuts.
- `ScrollPane.lua` — optional no-track direct-manipulation capture surface.
- Matchmaking/cake/UI-kit feature docs and routing/history indexes.

**Deleted:**
- None.

## Decisions
- The user's card-drag requirement is a gesture contract, not just a new scroll direction: dragging begins on the card surface and suppresses accidental selection after crossing a deliberate threshold.
- The rail has no replacement progress indicator. A visibly clipped next card, capture-surface direct manipulation, wheel input, and persisted-selection reveal provide the movement cues without adding another competing divider.
- Difficulty and Party Size use different layouts and separate passive surfaces so proximity, alignment, and material no longer group all seven choices together.
- The 1000x600 shell and 904x432 content stay fixed: left 368 + gutter 24 +
  right 512. Right title 32 + gap 8 + 512x392 pane. Three 512x156 cards with
  12px gaps produce a 492px canvas and 56px peek. START ends at y424, leaving
  8px below.
- The transparent capture surface classifies at 8px. Confirmed unlocked taps
  cue+select once; locked/busy taps report dead once; drags report no sound,
  analytics, or selection. It handles mouse/touch/wheel and is not controller
  selectable; underlying cards remain real controller buttons.
- Persisted selection opens at the minimum Y that fully reveals it. Cake stays
  external account state; Easy/1 synchronous session defaults, busy gating,
  analytics ids, and `onStart(difficulty, maxPlayers)` are unchanged.

## Verification

- All changed Luau modules compiled; deterministic math closes exactly.
- Default, lobby, and game Rojo builds passed.
- Studio edit-mode fallback measured all nominal rectangles and confirmed no
  `Track`, default/busy/locked/soon states, five-card selected-last at max
  Y=436, and first-card reset Y=0.
- A focused close-transition mount caught the shell still visible at 50ms while
  the full-panel blocker sat at Z105 above every disabled control; reopen removed
  it and restored only eligible controls without changing the scroll offset.
- Tonal/Squint candidate 4: 68.2, 0 CRITICAL, 3 warnings, **IMPROVED +4.1**.
- Adversarial review found and fixed two edge cases: wheel movement now cancels
  a held tap before moving the canvas, and logical close immediately disables
  controller targets plus covers the still-visible shrink tween. A follow-up
  recheck also made every busy/visible interaction-state transition clear the
  gesture owner, so a press cannot begin disabled and release live.
- Play Solo remained hung in Edit, so R8 healthy boot and a direct injected
  gesture exercise remain unverified.

## Open Questions / Followups

- Re-run Play Solo/R8 and direct gesture injection when Studio can enter Play.

## Related
- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_cake-first-match-carousel.md`
