# 2026-08-11: Matchmaking Surface Simplification

Tags: lobby-matchmaking, cake-select, ui-kit, tonal-hierarchy, squint-test

## Task
Restore the saturated candy-blue matchmaking header and remove redundant nested
backgrounds, especially the cake-art plates and Difficulty multiplier pills.

## Context
The vertical cake-rail layout is structurally successful, but its final tonal
cleanup over-corrected the header into a pale slate slab and retained nested
plates inside already-framed cards/buttons. See
[the vertical cake rail](2026-08-11_matchmaking-vertical-cake-rail.md).

## Plan
This remains the existing two-column configurator archetype: a compact setup
rail beside a browsable cake collection. Orientation, zones, state ownership,
callbacks, scroll behavior, and exact 904x432 arithmetic do not change.

- Restore the standard saturated `HeaderWide` color family so the window again
  matches the candy-style panel catalog.
- Keep structural interactive surfaces: the cake card Face, each Difficulty
  row, each Party tile, START, locked/soon badges, and selection treatment.
- Remove redundant surfaces inside those controls: render cake art directly in
  its 132px content zone, render the lightning + multiplier directly on the
  Difficulty row, and remove passive section wells that duplicate headings and
  spacing.
- Preserve every state: selected, unlocked, locked, coming-soon, busy,
  Easy/1 defaults, controller focus, direct cake dragging, and two-argument
  `onStart(difficulty, maxPlayers)`.

### Zone arithmetic and props

Unchanged: left 368 + gutter 24 + right 512 = 904. Right title 32 + gap 8 +
pane 392 = 432; cards remain 512x156 with 12px gaps. Left row/tile/status/START
geometry remains exactly as documented in `Theme.MatchmakingLayout`. No new
props or callbacks are introduced; cleanup is expressed through matchmaking
Theme style flags/geometry so the portrait cake chooser remains unchanged.

## Changes

**Created:**
- This flow record and like-for-like Studio/Tonal/Squint captures.

**Modified:**
- `Theme.MatchmakingHeader` now exactly clones the shared saturated
  `HeaderWide` style; the matchmaking-only pale slate override is gone.
- `MatchmakingPanel` no longer renders passive Difficulty/Party wells or the
  redundant selected-cake check badge.
- `MatchDifficultyChoice` can omit its nested reward pill and renders the
  lightning/value directly in the row for the matchmaking style.
- `CakeCard` can omit its internal art plate by style. `MatchCakeCard` does so
  and uses 120px free-standing art; the standalone portrait chooser keeps its
  original art window.
- Updated `lobby-matchmaking`, `cake-select`, and `ui-kit` contracts.

**Deleted:**
- None.

## Decisions
- Removing a nested plate is not permission to flatten the parent pressable.
  The card/button layer recipe still communicates interaction and state.
- Matchmaking-only style options protect the standalone cake chooser's portrait
  card contract.

## Open Questions / Followups
- Play Solo remained stuck in Edit, so shipped-client R8 boot output and direct
  injected drag input remain pending. The established fresh-clone Edit harness
  covered rendering, geometry, state, scroll/reset, and compatibility.

## Verification
- Full UIKit Luau compile: 67 files passed.
- Rojo builds: default, lobby, and game passed.
- Studio fresh-clone preview: vivid header matched `HeaderWide` 17/17 keys;
  default, alternate-selected, locked, coming-soon, busy, close/reopen, rail,
  and selected-reset states passed. Matchmaking had zero art plates, reward
  pills, passive wells, and selected badges; standalone `CakeSelectPanel`
  retained one `ArtRing` + `ArtFace` per portrait card.
- Like-for-like capture:
  `matchmaking-surface-cleanup/candidate-default-like-for-like.png`.
- Tonal/Squint: 0 CRITICALs. Accurate warnings fell 3→2, resolving selected
  cake and Difficulty-surface noise; the requested vivid header introduced one
  expected header-noise warning. Score moved 68.2→60.5 because the analyzer
  still treats the brand band as receding chrome. Heavy colour blur preserves
  the blue header, selected gold cake, and green START while setup recedes.
- Adversarial review: no CRITICAL/WARN findings; standalone-card compatibility,
  Theme freeze order, style-key safety, states, interactions, and docs were clean.

## Related
- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_matchmaking-vertical-cake-rail.md`
