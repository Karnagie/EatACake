# 2026-08-11: Cake-First Match Carousel

Tags: lobby-matchmaking, cake-select, ui-kit, horizontal-scroll, tonal-review

## Task
Redesign **Choose a Match** again so cakes, rather than difficulty, own the visual hierarchy. Cake cards must scroll horizontally and the screen must remain intuitive, attractive, and easy to use.

## Context
The first redesign made difficulty a 560x304 primary browser while cake selection was a 328x168 secondary rail of 58px rows. That hierarchy was the opposite of the product intent even though the controls and CTA were larger than the original screen. See [the prior matchmaking redesign](2026-08-11_matchmaking-ui-redesign.md) and [cake selection UI](2026-08-11_cake-selection-ui.md).

## Plan
Keep the proven 1000x600 wide shell and 904x432 safe content region, but invert the composition:

- A full-width **Choose a Cake** hero gallery comes first and consumes 236/432px of the content height.
- Fixed 336x158 landscape cake cards use the real cake art, name, unlock explanation, lock/soon badge, and selected check; three cards produce a 1040px canvas inside a 904px viewport, so the third card visibly peeks and establishes horizontal movement.
- A 30px bottom candy scrollbar plus native swipe/wheel behavior makes the gallery directly manipulable; cards never shrink as the catalogue grows.
- Difficulty and party size become one compact 82px setup strip. Difficulty uses three 176x58 icon/title/reward buttons; party uses four 70x58 icon/count buttons. Both remain large enough to press at the measured runtime scale.
- Readiness copy stays quiet and the large sticky START remains the terminal action.

Exact vertical budget: cake heading 32 + gap 8 + carousel 196 + gap 8 + setup 82 + gap 4 + status 22 + gap 4 + START 76 = 432.

Exact horizontal setup budget: difficulty 560 + gap 16 + party 328 = 904; difficulty 3x176 + 2x16 = 560; party 4x70 + 3x16 = 328.

## Changes

**Created:**
- `src/shared/UIKit/Components/MatchDifficultyChoice.lua` — compact, semantic
  difficulty button with icon, title, passive reward cue and per-mode analytics.

**Modified:**
- `src/shared/UIKit/Components/MatchmakingPanel.lua` — replaced the
  difficulty-first master/detail composition with the full-width cake carousel,
  compact setup strip and sticky CTA while preserving the two-argument start
  contract and synchronous session defaults.
- `src/shared/UIKit/Components/ScrollPane.lua` — generalized the existing custom
  pane to a scalar X/Y axis, including deterministic canvas size, track/thumb
  math, reset, mouse and touch correlation; pointer-only track/thumb controls no
  longer advertise controller focus.
- `src/shared/UIKit/Interaction.lua` — changed shared button activation from the
  mouse-only click event to Roblox's mouse/touch/gamepad `Activated` contract.
- `src/shared/UIKit/Components/CakeCard.lua` — added opt-in external disable,
  selected check and hover scale so the same card contract can serve the
  landscape matchmaking cut without changing the portrait chooser.
- `src/shared/UIKit/Components/MatchPartyChoice.lua` — recut the party control
  to the compact 70x58 setup geometry.
- `src/shared/UIKit/Theme.lua` — added horizontal scrollbar, landscape cake and
  compact difficulty styles; replaced matchmaking geometry and reduced
  secondary selection emphasis.
- `src/shared/UIKit/init.lua` — exported `MatchDifficultyChoice`.
- `src/client/common/modules/AppRoot.lua` — uses the existing localized
  `title-cakes` copy for the new primary heading and guards every matchmaking
  close path while launch is busy.
- `docs/MAP.md` and feature docs for matchmaking, cake selection, AppRoot,
  UIKit and analytics — updated routing, behavior, geometry, controller
  activation and shared pane contracts.

**Deleted:**
- None. `MatchModeCard` and `CakeChoice` remain exported for compatibility, but
  matchmaking no longer uses them.

## Decisions
- Cake choice remains account-persisted presentation state and does not participate in readiness or the queue payload.
- Easy and one player remain the per-session defaults, preserving the one-tap START path.
- The shared ScrollPane gained a backwards-compatible X-axis mode instead of a
  second scrolling implementation; all pre-existing Y callers keep their
  default behavior.
- Matchmaking reuses `CakeCard` with a landscape style and opt-in selected badge;
  the standalone portrait chooser remains compatible.
- No arrow buttons were added. A visible 60% peek of the third card, native
  horizontal scrolling and the persistent 30px draggable track communicate the
  carousel without taking focus from cake art.
- A session reset ensures the persisted selected card is fully visible rather
  than blindly returning to X=0; this matters once unlocked choices extend past
  the first 2.6 cards.
- The shared matchmaking closer, not only the panel X, rejects close requests
  while START is busy; an outside-scrim tap can no longer hide a countdown whose
  server-side leave would be rejected.
- Every focusable control on the screen activates under controller A/cross.
  Pointer-only scrollbar chrome and the full-screen tap-outside scrim are
  excluded from gamepad selection rather than creating dead focus stops.
- Secondary selections keep a blue face with only a gold perimeter. Filling the
  whole difficulty/party button gold made those setup controls compete with the
  selected cake and START.

## Verification

- All changed Luau modules compiled; lobby, game and combined Rojo builds passed.
- Production-fit Studio preview measured 303x143 cake cards, 159x52 difficulty
  controls, 63x52 party controls and a 686x69 START button. The 939px rendered
  canvas exceeded its 816px window and reached the exact 122.8px X maximum;
  track/thumb travel matched the scroll range.
- Default, selected/locked/coming-soon, Hard/4, busy, maximum-scroll and
  session-reset states were rendered. Busy disabled every pressable; a new
  session painted Easy/1 and X=0 without exposing stale state.
- A synthetic five-card catalogue with the last card persisted selected opened
  at X=max 758.520; the card was fully visible with 0.147px clearance and the
  thumb ended within 0.00003px of the track edge.
- Tonal hierarchy improved from score 59.8 to 64.1, with CRITICAL findings
  reduced from 6 to 0. The heavy/extreme squint pass preserves cake art and the
  emerald CTA while merging the compact setup strip into the secondary plane.
- Final integrated adversarial review passed with no remaining CRITICAL/WARN
  findings after closing off-screen selection, busy-scrim and controller-focus
  paths. Controller activation matches Roblox's `GuiButton.Activated` contract;
  all changed modules compile.
- Studio's edit-mode fallback passed and cleaned every preview clone/global.
  Play Solo itself hung in the bridge before entering Play, so the R8 healthy
  boot console contract was not observable; Studio finished in Edit with an
  empty console, not a runtime failure signal.

## Open Questions / Followups
- Rainbow cake selection is still presentation-only until rainbow cake gameplay content exists.
- Re-run a real Play Solo/R8 boot when the Studio bridge can enter Play mode;
  this session verified the exact rendered tree and states in Edit fallback.

## Related
- Feature: `docs/features/lobby-matchmaking.md`
- Feature: `docs/features/cake-select.md`
- Prior flow: `docs/flow/2026-08-11_matchmaking-ui-redesign.md`
- Prior flow: `docs/flow/2026-08-11_cake-selection-ui.md`
