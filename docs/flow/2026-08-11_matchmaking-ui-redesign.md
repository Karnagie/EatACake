# 2026-08-11: Matchmaking UI Redesign

Tags: lobby-matchmaking, ui-kit, app-root, localization, theme, analytics, tonal-hierarchy

## Task
Rebuild “Choose a Match” around correct hierarchy, sizing and spacing: scrollable
cards, large controls and a visually dominant START action.

## Context
The 1000x600 modal had three equal 60px selector bands inside 904x432 usable
content. Cake choices shrank to fit their count, difficulty/party read as peers,
and the 360x58 START competed with them. At the measured 0.822 render scale the
rows were ~49px and START ~48px high. Prior state: `2026-08-11_cake-selection-ui.md`;
queue authority remains `2026-07-22_lobby-matchmaking-rounds.md`.

## Plan
Use a landscape master-detail configurator: fixed-size primary mode cards in a
scroll pane, a persistent setup rail for party/cake, then sticky status and one
full-width CTA. Preserve Easy/1 Player one-tap start and keep cake outside the
queue payload.

## Changes

**Created:**
- `src/shared/UIKit/Components/MatchModeCard.lua` — 526x118 icon/detail/reward mode card with semantic press analytics.
- `src/shared/UIKit/Components/MatchPartyChoice.lua` — fixed 76x84 icon-first party control.

**Modified:**
- `src/shared/UIKit/Theme.lua` — exact 560+16+328 master-detail grid, two deterministic scroll canvases, compact filled selection token, quiet status/close and 760x80 high-chroma START.
- `src/shared/UIKit/Components/MatchmakingPanel.lua` — scrollable difficulty/cake lists, setup rail and sticky CTA; queue/session behavior unchanged.
- `src/shared/UIKit/Components/{CakeChoice,Button,CloseButton,Header,PanelWithHeader,MatchChoice,ScrollPane}.lua` — compact filled selection, optional CTA icon/close style, explicit semantic analytics ids, session reset support and touch-complete thumb dragging.
- `src/shared/UIKit/init.lua` — exported the two new match components.
- `src/shared/config/MatchConfig.lua` + `src/client/common/{data/LocaleData.lua,modules/AppRoot.lua}` — per-mode icon/accent/detail copy, localized reward format, locale-ready view models and topbar-safe panel fit.
- `docs/features/{lobby-matchmaking,ui-kit,app-root}.md`, `docs/MAP.md`, `docs/registries/data-keys.md` — new UI, safe-area and locale contracts.
- `localization/{translations.csv,.baseline.json}` + `docs/features/localization.md` — synced the 12 missing match/cake cloud rows and refreshed the live key counts.

## Decisions
- Fixed rows scroll; they never auto-shrink. Current mode canvas is 378px in a
  264px window (max scroll measured 107.52px rendered); cake is 194px in 128px
  (62.25px rendered). Bottom captures expose Hard and the coming-soon cake.
- Reading order is CTA → selected mode → selected party/cake → status/chrome.
  Selected compact controls need filled mass, not a thin gold ring, to survive
  blur; status lost banner sizing; the close affordance keeps standard geometry
  but joins the blue header instead of becoming a red attention island.
- START remains one-tap live on Easy/1, pulses with clipping headroom, and sends
  exactly `(difficulty, maxPlayers)`. Cake still persists on its own remote and
  does not affect readiness, session reset or teleport data.
- Composite pressables now pass `analyticsId` explicitly. Otherwise every child
  named `HitTarget` collapses to one analytics bucket (upstream EAC-0272).
- Session selections are key-correlated and validated during render; reset is
  no longer effect-delayed, so START can never expose a stale prior-pad choice.
  Both deterministic panes reset before paint, and exact-size card CanvasGroups
  use a non-expanding hover pose so their edges are not clipped.
- The custom scrollbar thumb now starts mouse/touch drags from `InputBegan`,
  correlates one initiating touch, and suppresses the ancestor track jump when
  the grab lands inside the thumb bounds (upstream EAC-0275).
- The scrim remains full-bleed, while the panel is centred below Roblox's topbar.
  It preserves the normal 90% viewport fit where possible and uses at most 98%
  of the remaining safe height on a short phone (896x414/68px inset: panel
  565x339 at y71.5..410.5; START 45px and party controls 47.5px high).
- Tonal/squint iteration was a gate, not polish: score 52.2 → 89.7, CRITICAL
  findings 8 → 0; the only remaining warning is the shared panel’s bottom-frame
  edge hotspot. Desktop/laptop/tablet fits keep START 74px+ high at 1024x768.
- Verification: `luau-compile` (15 touched Luau files), all three Rojo builds,
  analytics catalog cross-check, live lobby boot/selector capture, edit-mode
  clone-require geometry, top/bottom scroll captures, tonal selftest/analyze/
  compare/blur. Live boot completed 11 data / 13 services / 21 subscriptions
  server-side and 7 data / 19 initialized modules / 20 subscriptions client-side.
- Localization `pull -> push -> pull` added all 12 missing match/cake rows;
  verified cloud table 325/325 live, 0 orphan, 0 pending, 0 warnings.

## Open Questions / Followups
- A later Studio bridge attempt would not transition from Edit to Play Solo.
  The final variant passed fresh clone/require geometry, scroll, default,
  Hard/4 and busy-state checks with no new console output; rerun actual pointer
  callbacks and the current R8 boot contract once the Play Solo bridge recovers.

## Related
- Feature: `docs/features/lobby-matchmaking.md`
- UI contract: `docs/features/ui-kit.md`
- ADR: `docs/decisions/0010-reserved-matchmaking-rounds.md`
- Prior flow: `docs/flow/2026-08-11_cake-selection-ui.md`
