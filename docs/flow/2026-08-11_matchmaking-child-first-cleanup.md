# 2026-08-11: Matchmaking Child-First Cleanup

Tags: lobby-matchmaking, cake-select, ui-kit, vertical-controls, tonal-hierarchy, squint-test, accessibility

## Task
Simplify the **Choose a Match** window for children: replace the mismatched
cake-selection colour, keep the third locked cake aligned with the others, and
reduce the amount and density of text and chrome.

## Context
The prior two-column cake gallery intentionally used a deep-purple selected
Face and centred an incomplete second row. With three catalogue entries this
made the teaser cake a clipped, centred fragment and made the selected card
dominate the whole window. See
[`2026-08-11_matchmaking-cake-gallery.md`](2026-08-11_matchmaking-cake-gallery.md).

## Plan

### Phase B — design brief

- **Archetype:** a compact match configurator mixing the teleport/world-card
  gallery with setup controls. It remains a landscape modal, but the current
  catalogue is shown as one complete three-card shelf instead of hiding a
  choice below the fold.
- **Orientation:** cake and setup controls become portrait/icon-first tiles.
  Young players can recognise cake art, difficulty glyphs, and player counts
  before reading labels.
- **Zones:** shared header; left setup column; empty separator; narrow cake
  column; one shared contextual/status line; one centred footer CTA.
- **States:** selected cake = shared gold perimeter + royal-navy Face; unlocked
  cake = navy; locked = grey + faded art + padlock; coming soon = grey + clock;
  selected setup tile = gold perimeter + blue Face; busy = all controls inert;
  error/locked requirement = the one contextual line. Normal ready copy is
  absent because selected defaults plus a live START already communicate it.
- **Props/callbacks:** unchanged. Cake remains persisted account state and
  never enters readiness or `onStart`; START still calls exactly
  `(difficulty, maxPlayers)`.

### Phase C — exact zone arithmetic

The existing 904x432 content box remains fixed.

- Horizontal: setup `452` + empty gutter `32` + cake rail `420` = `904`.
- Upper configuration height: `308`.
  - Left: heading `28` + gap `12` + difficulty tiles `112` + gap `24` +
    heading `28` + gap `12` + party tiles `72` + bottom air `20` = `308`.
  - Right: heading `28` + gap `12` + cake pane `268` = `308`.
- Footer: config `308` + gap `8` + context `24` + gap `8` + START `76` +
  bottom `8` = `432`.
- Difficulty: `3*142 + 2*13 = 452`.
- Party: `4*101 + 3*16 = 452`.
- Cakes: `3*132 + 2*12 = 420`; each card is `132x214`. The canvas has 12px
  top/bottom padding. A future second row starts at y238, leaving a 30px clipped
  continuation cue inside the 268px pane.
- START: centred `760x76` in the 904px footer, so `(904-760)/2 = 72`.

### Phase D — element inventory

- Reuse `MatchmakingPanel`, `CakeCard`, `MatchDifficultyChoice`,
  `MatchPartyChoice`, `ScrollPane`, `Button`, and `OutlinedText`.
- Re-cut the existing matchmaking-only Theme styles and layout. No new
  component is justified: this is an existing configurator changing
  composition, and every required state/interaction already has an owner.
- Keep direct card dragging, origin/release hit correlation, controller locked
  feedback, session-safe defaults, busy gating, and the two-argument START
  contract.

## Changes

**Created:**
- This design and verification record.

**Modified:**
- `Theme.MatchmakingLayout`: 452/32/420 split, portrait setup controls,
  three-card rail, shared exception line, and wide footer CTA.
- `Theme.MatchCakeCard`: 132x214 portrait geometry; selected state now uses the
  kit's royal-navy card Face plus the shared gold perimeter.
- `MatchmakingPanel`: horizontal Difficulty layout, shared incomplete-row
  origin for placement/hit testing, canvas padding, shared cake/status feedback,
  and suppression of redundant ready/fallback busy copy. Authoritative queue
  progress still uses the shared line.
- `MatchDifficultyChoice`: reward cue is optional and omitted here; labels may
  be centred for the portrait tile.
- `AppRoot`: matchmaking's cake heading is the shorter existing `Cake` locale
  key; the standalone chooser keeps `Choose a Cake`. Module-current busy state
  now guards X/scrim close and shared matchmaking callbacks instead of relying
  on one-render-old closures; background HUD toggles cannot replace any modal.
- `MatchmakingPanel`: START takes a synchronous per-session launch latch before
  dispatch; setup, cake pointer/controller, close, and repeated START callbacks
  consult it until authoritative busy completes. A second session-keyed ref
  records setup taps synchronously, so rapid setup + START submits the newest
  pair even before the selection redraw commits.
- `LobbySubsClient`: the chocolate Shop trigger cannot replace a launch-busy
  matchmaking panel.
- Feature routing/contracts in `MAP.md`, `lobby-matchmaking.md`,
  `cake-select.md`, and `ui-kit.md`.

**Deleted:**
- None.

## Decisions
- The selected cake reuses the kit's royal-navy card Face plus the shared gold
  selection perimeter. Purple conveyed flavour/rarity; the first bright-blue
  iteration blended into the pale panel under heavy blur.
- Locked guidance and exceptional queue status share one line above START.
  Permanently visible ready prose is redundant with the default selections and
  enabled CTA.
- START is the non-reader's first target; the selected cake is the second read.
  This matches the fact that Easy / 1 Player / Classic Cake are already selected
  when the window opens.

## Verification

- Tonal tool self-test: 16/16 PASS. Final annotated capture: 72.9/100, zero
  CRITICAL findings; START ranks first and both START and the selected cake
  survive heavy blur.
- Fresh Studio React harness: all three cakes have equal size and Y position;
  every visible label reports `TextFits = true`; the normal status line is
  absent; the wide START remains inside its pulse headroom.
- Busy probe without an explicit queue update renders no fallback prose; close,
  setup, cakes, and START are all non-selectable, with setup controls at the
  existing 0.32 disabled fade. Server countdown/progress may use the shared line.
- Studio's MCP screenshot call hung, so the auditable capture was taken from the
  live Studio window after the same harness was mounted into `StarterGui`.
- Full-tree compile: 233/233 Luau files parse. Rojo builds pass for `default`,
  `lobby`, and `game` partitions.
- Production Play boot meets R8: server 11 data / 13 services / 21
  subscriptions, client 7 data / 19 initialized modules / 21 subscriptions,
  ProfileSchema 12 sections, Persistence DataStore OK, ClientReady, profile
  loaded, and 12/12 initial domains pushed.
- Live authored-pad panel: cards share y=138.6 and h=144.7 at x=523.3,
  620.7, 718.1; all visible text reports `TextFits=true`. Medium, Party 3, and
  the coming-soon card responded; the first two gained gold selection and the
  locked tap populated the shared `Coming Soon!` line. START configured
  `medium, 3`; Studio's expected unpublished-destination 403 recovered the
  profile and input lock correctly.
- Adversarial review found no critical issues. Its same-frame held-pointer,
  modal replacement, logical-close, and setup-tap + START findings were fixed
  with session-keyed refs plus module-current transition guards; the final
  re-review reports no remaining CRITICAL/WARN findings.

## Open Questions / Followups
- Direct drag and controller-A injection remain outside this layout pass; their
  unchanged shared `ScrollPane`/semantic-button contracts are compile- and
  source-verified.

## Related
- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_matchmaking-cake-gallery.md`
