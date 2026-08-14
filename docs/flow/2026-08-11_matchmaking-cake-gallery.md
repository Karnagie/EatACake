# 2026-08-11: Matchmaking Cake Gallery

Tags: lobby-matchmaking, cake-select, ui-kit, vertical-scroll, tonal-hierarchy, squint-test

## Task
Replace the cluttered right-side cake records with an aligned, child-first
visual selector that does not read as a data table.

## Context
The one-column 512x156 rail repeats an image, title, and sentence across wide
horizontal slabs. Under heavy Squint the gold/grey slabs survive while the cake
art disappears; the selected cake art ranked #15 in the preceding report. The
layout therefore asks a young player to read rows instead of recognise cakes.
See [the surface cleanup](2026-08-11_matchmaking-surface-simplification.md).

## Plan — Phase B design brief

- **Archetype:** the existing match configurator remains a two-zone hybrid, but
  cakes use the collection/teleport **gallery** archetype, not the read-and-act
  list archetype. Roblox's official guidance favours visual interfaces for
  younger players and grids for item collections; Pet Simulator 99, Adopt Me,
  and Brookhaven likewise put object thumbnails in repeated tiles and reserve
  compact glyphs for locked state.
- **Orientation:** vertical scrolling remains the catalogue axis, but each row
  contains two portrait/near-square art tiles. Direct card dragging, wheel
  scrolling, and the clipped next row remain the movement affordances; there is
  no scrollbar.
- **Zones:** saturated header; left setup rail; 40px empty separator; centred
  cake heading; two-column cake viewport; one contextual cake notice below it.
- **States:** selected = gold perimeter + deep candy-purple card mass; unlocked = normal navy card;
  locked = grey card + faded art + padlock; coming-soon = same grey language +
  clock; busy = existing overlay/inert inputs; empty catalogue = cake zone
  omitted. No selected check disk and no permanent metadata sentence per tile.
- **Props/callbacks:** unchanged. Cake selection remains external persisted
  state; the panel adds only ephemeral locked-cake feedback and still invokes
  `onStart(difficulty, maxPlayers)` with exactly two arguments.

Research references: [Roblox visual guidance](https://create.roblox.com/docs/production/game-design/design-for-roblox),
[Roblox grid/table layouts](https://create.roblox.com/docs/ui/grid-table-layouts),
[Pet Simulator 99](https://www.biggames.io/post/pet-simulator-99-update-61),
[Adopt Me](https://www.playadopt.me/news/farm-pets-backpack-improvements).

## Phase C — exact zone arithmetic

The 904x432 content box stays fixed.

- Horizontal: setup `344` + empty gutter `40` + gallery `520` = `904`.
- Left vertical: `28 + 8 + 168 + 16 + 28 + 8 + 60 + 8 + 24 + 8 + 68 + 8 = 432`.
  Difficulty remains `3*52 + 2*6 = 168`; Party becomes
  `4*74 + 3*16 = 344`.
- Right vertical: heading `28` + gap `8` + viewport `360` + gap `8` +
  contextual notice `28` = `432`.
- Gallery row: `2*254 + 12 = 520`. Card `254x248`; row stride `260`.
  Current three cakes make two rows: `2*248 + 12 = 508 > 360`, showing one
  full row plus `100px` of the next. The maximum initial catalogue scroll is
  `148px`; odd final rows are centred at x=`133`.

Tap and reset math use the same row/column geometry. The 12px gaps and empty
space around a centred odd row are not tappable. Reopening scrolls to the
minimum Y that fully reveals the selected row.

## Phase D — element inventory

- Reuse `MatchmakingPanel`, `ScrollPane`, `CakeCard`, `OutlinedText`, and all
  existing interaction/state language.
- Re-cut only matchmaking Theme geometry: `MatchCakeCard`,
  `MatchDifficultyChoice`, `MatchPartyChoice`, `MatchmakingStartButton`, and
  `MatchmakingLayout`.
- No new component is justified: this is an existing collection card changing
  orientation, and `CakeCard` already owns every required state and semantic
  button contract.

## Changes

**Created:**
- This design/verification record.

**Modified:**
- `UIKit/Components/MatchmakingPanel.lua`: deterministic two-column card
  placement, matching 2D gap-safe tap dispatch, minimum selected-row reveal,
  centred heading, and one ephemeral id-backed contextual lock notice whose
  localized copy follows live entitlement/locale props.
- `UIKit/Components/CakeCard.lua`: optional locked-card controller focus and
  non-pointer activation hook; pointer behavior and standalone chooser defaults
  are unchanged.
- `UIKit/Components/ScrollPane.lua`: backward-compatible tap dispatch now also
  supplies normalized press origin; the gallery requires origin/release to hit
  the same tile. Property observation moved to declarative `React.Change`.
- `UIKit/InputBridge.lua` + `client/common/subscriptions/UiInputSubsClient.lua`:
  subscription-owned global move/release continuation (R4), shared by mounted
  panes instead of one `UserInputService` pair per component.
- `UIKit/Theme.lua`: 344/40/520 split; 254x248 art-first tile; compact left
  controls and CTA re-cut to the narrower setup rail. Tonal iteration gives
  the selected cake a deep purple value field, keeps selected setup controls
  blue inside a single gold perimeter, and separates the bright emerald START
  into the second-read value band.
- `features/lobby-matchmaking.md`, `features/cake-select.md`, `features/ui-kit.md`
  and `MAP.md`: live gallery contract and routing.
- `upstream/QUEUE.md`: EAC-0284 captures the child-facing art-first selector;
  EAC-0285 captures the subscription-owned global input bridge.

**Deleted:**
- None.

## Verification

- `luau-compile`: 68 UIKit modules plus `UiInputSubsClient` pass (69 files).
- `rojo build`: `default.project.json`, `lobby.project.json`, and
  `game.project.json` pass.
- Fresh current lobby build mounted in Studio Edit: 1502x962 viewport,
  1350x810 panel, exact 344/40/520 split, 254x248 gallery cards, current
  purple-selected / blue-setup / emerald-START gradients, and the declarative
  input bridge all passed. The final 830x531 evidence capture is
  `matchmaking-cake-gallery/candidate-final-evidence.png`; the faint device
  simulator text lies outside the panel. Studio exited before a real Play/R8
  run, so physical mouse/touch injection and boot-console verification remain
  unavailable; deterministic drag math, reset, focus, busy, and state probes
  passed in the fresh Edit harness.
- Tonal compare against the rejected row layout: `33.4 -> 68.8` (`+35.4`,
  **IMPROVED**), CRITICAL `2 -> 0`. The selected cake owns 83% of extracted
  hotspot mass and START the remaining 17%; no setup/copy hotspot survives.
  The analyzer still reports `crowded-top` from local outlined-text edges in the
  cake heading and first party tile, but both are `GONE` under heavy Squint and
  contribute no hotspot mass. Heavy colour/grey preserve the chosen cake and
  START while setup merges; extreme blur leaves only panel, cake, and CTA
  masses. No horizontal metadata slab or scrollbar survives.
- Adversarial review: no CRITICAL/WARN after controller feedback, live-localized
  notices, press-origin correlation, legacy-layout fallback, and R4 input-owner
  fixes. `InputBridge` dispatch failures are `Log.Once` keyed by listener/kind.

## Related

- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_matchmaking-surface-simplification.md`
