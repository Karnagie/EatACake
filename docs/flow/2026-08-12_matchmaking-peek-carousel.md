# 2026-08-12: Matchmaking Peek Carousel

Tags: lobby-matchmaking, cake-select, ui-kit, horizontal-scroll, tonal-hierarchy, squint-test, accessibility

## Task

Make the cake choices substantially taller and larger, turn them into a
horizontal rail whose opening shows one full cake plus half of Rainbow, centre
Rainbow when it can be selected, remove the post-START text row, and regroup
Party Size as a large count on the left plus a large group glyph on the right.

## Context

The prior grouping pass left enough vertical space for larger cake art, but the
420x268 vertical gallery still compressed three 132x236 cards into one row. It
showed every current item at once, so scrolling was technically available only
for future rows and the player received no direct-manipulation cue. Party
controls were still short 101x72 tiles with a stacked icon/count composition.
The shared status slot also reappeared above START as soon as launch state
changed, visually undoing the new group spacing.

## Plan

- Preserve the 904x432 content box, 452/32/420 split, Easy/1 one-tap default,
  persistent cake owner, two-argument queue request, and gesture/session guards.
- Recut the cake area as a deterministic X carousel:
  `8 + 3*264 + 2*16 + 8 = 840 = 2*420`.
- Open Classic at offset zero, exposing Rainbow by exactly
  `420 - (8 + 264 + 16) = 132 = 264/2` pixels.
- Centre the semantic selected cake with
  `cardX + cardWidth/2 - windowWidth/2`, clamped to the rail.
- Remove the default status row; retain cake requirements on their cards and put
  launch/error copy inside START.
- Grow Party Size to 101x84 and budget count, shadow, strokes, and glyph entirely
  inside the raised Face.

## Changes

**Modified:**

- `MatchmakingPanel`: deterministic horizontal canvas/placement/hit helpers,
  X-axis `ScrollPane`, semantic selection centring, session+cake reset key, and
  opt-out rendering for the shared `Status` row. The legacy Y gallery and
  explicit custom status layouts remain supported.
- `Theme.MatchmakingLayout`: 420x300 cake pane, 264x292 cards, exact 840px
  canvas recipe, 101x84 Party row, 48px Difficulty-to-Party gap, and
  `ShowStatus = false`.
- `Theme.MatchCakeCard`: larger free-standing cake art and dedicated title /
  wrapped-requirement zones.
- `Theme.MatchPartyChoice` / `MatchPartyChoice`: count-left/icon-right
  geometry and contract notes.
- Feature/UI-kit/map contracts, this flow record, and upstream candidates
  EAC-0290 (outlined-text containment) and EAC-0291 (legacy style-token
  fallback).

**Created:** this flow record. **Deleted:** no production files.

## Verification

- Live production-size Studio render at a 1003.33x482 viewport:
  panel 723x433.8; cake window 303.66x216.90; canvas 607.32x216.90 (exactly
  2x); card 190.87x211.12. At X=0 Classic is fully visible and Rainbow exposes
  95.44px, exactly half the rendered card.
- With Rainbow available, tapping its visible half through the real input
  surface selected it and moved the rail to X=151.83. The complete card was
  visible and its centre missed the window centre by only 0.17px of rounding.
  A direct pointer drag also moved the rail, with no leaked selection.
- Party controls render 73.02x60.73; the large count is on the left and the
  30.37px square group glyph is on the right. The conservative count envelopes
  (main stroke and offset-shadow stroke) remain inside the Face.
- The default content has no direct `Status` child. A busy render places
  `STARTING...` on both START text layers, disables the button, and does not
  create text above it.
- Production lobby boot remains healthy: server 11 data / 13 services / 21
  subscriptions; client 7 data / 19 initialized modules / 21 subscriptions;
  ProfileSchema 12 sections; persistence ready; ClientReady and 12/12 initial
  domains pushed. The only warning is the pre-existing missing cloud row for
  `match-status-ready`, which falls back to English.
- Tonal/Squint like-for-like gate against the prior grouping layout:
  score 59.6→57.8, CRITICAL 0→0, WARN 10→8, verdict **FLAT**. The old
  blur-invisible cake-rail finding and stray hotspot both clear. In heavy colour
  and grey blur START remains the primary mass, the enlarged cake remains the
  secondary mass, and setup recedes.
- Full source parse passes: 233/233 Luau files. Rojo builds pass for `default`,
  `lobby`, and `game` projects.
- Adversarial review found one legacy-layout render edge: custom layouts created
  before `StartPulseHeadroom` would multiply/divide by nil. The panel now uses
  a neutral factor of 1 when that optional visual token is absent; full parse
  and all three builds pass again after the fix. Focused re-review reports no
  remaining actionable findings.

## Decisions

- The half-card is deliberate affordance, not accidental clipping. Its exact
  arithmetic is documented beside the Theme tokens so later sizing changes
  cannot silently erase the cue.
- A selectable persisted cake should be fully inspectable. Centre the selected
  semantic item after the authoritative view-model update; do not maintain a
  second local cake selection.
- START owns transient launch/error feedback because it is the operation being
  affected. A separate line would rebuild the visual group the task removes.
- Party Size stays one large hit target per count. The icon is decorative and
  never becomes a nested button or a second controller target.

## Related

- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-12_matchmaking-grouping-polish.md`
