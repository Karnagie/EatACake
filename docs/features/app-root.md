# AppRoot (composed UI root: HUD + panels + overlays)

## What it does
The ONE React tree rendered through `UiRoot.Render` (single-root contract,
`docs/features/ui-kit.md`). Game HUD: calories + gems StatPills, CakeBar,
BellyBar, checkpoint/eat controls, the boss prize card and game overlays. Lobby
meta HUD: 5-button GRID — Pets, Shop, DailyRewards, Codes, Settings — bare icon
+ label-BELOW buttons, NO background (`HudMenuButton`; the only badge left is
Daily-claimable; NO Upgrades — see below). The menu is a
`UIGridLayout` (`Theme.AppHud.MenuColumns`, default 2). CakeBar (top
center, phase-aware — **hidden during normal eating**, shown only for
boss/spawn/reward), BellyBar (bottom center, glutton state), ComboBadge,
AnnounceBanner, TO CHECKPOINT button (bottom-center, shown only when away from
the checkpoint — see `features/checkpoint.md`), EAT button (`EatButton`, bottom-
right thumb zone, **TOUCH devices only** — hold to eat / tap for one bite; shown
in eating/boss phases, hidden while a panel or the gym overlay is up; see
`features/cake-sim.md` input). Panels toggled by ONE `openPanel` (zIndex 50):
Pets (PetsInspectPanel), Upgrades (hex-tree overlay), Shop, DailyRewards, Codes,
Settings, Matchmaking. Overlays: GymOverlay (40), PetRevealOverlay (90).
`GameUiData` / `LobbyUiData` partition markers gate place-specific presentation:
the lobby hides cake/belly/checkpoint/eat/game overlays, shows its meta menu,
and can show the matchmaking selector or chocolate-triggered Shop. The game
hides lobby/meta UI because those handlers are lobby-only.
⚠ **There is no Upgrades button in the HUD at all** (removed 2026-07-30). The
hex-tree overlay is still rendered here and still opened through
`onToggleUpgrades`, but the only thing that calls it is the checkpoint's
`UpgradeStation` ProximityPrompt (`features/upgrades.md`). Don't re-add a button
without checking that prompt — it has been live in the game place all along.

## Two layers: `Hud` (inset) and everything else (full-bleed)
The root ScreenGui is **full-bleed** since 2026-07-30 (`UiRoot`:
`IgnoreGuiInset = true` / `ScreenInsets = DeviceSafeInsets`) so panels, overlays
and their dim SCRIMS cover the whole screen — they used to stop below Roblox's
~36 px topbar, leaving a bright strip over a "modal" tree.
So the HUD gets its own child frame, `Hud`, positioned at
`(0, GuiService:GetGuiInset().Y)` and shortened by the same amount — which
reproduces the coordinate space the root gui used to provide **exactly**, so the
inset fix moved no HUD element. Every HUD child (pills, menu, CakeBar, BellyBar,
checkpoint, EAT, combo, announce, boss prize) is built into `hudChildren` and
lives in that layer; panels/overlays are direct children of `App`.
- The inset is tracked in state (`GuiService:GetPropertyChangedSignal("TopbarInset")`
  plus the viewport refit) — it is not a constant and the topbar can hide.
- ⚠ Anything that mixes pointer coordinates with `AbsolutePosition` must not
  assume an inset root. `ScrollPane`'s track click did exactly that
  (`GetMouseLocation() - GetGuiInset()`) and had to move to `InputBegan`'s
  `input.Position`, which is in `AbsolutePosition` space in either mode.

## Contract for feature subs
- Data IN: `AppRoot.Set(patch)` — fields: `calories, gems, settings, daily,
  shop, group, codesStatus, cake, stomach, gym, upgrades, pets,
  petReveal (+petRevealCount), combo, announceKey,
  matchmaking, checkpointFar, openPanel`. Works pre-mount. `checkpointFar` (default true;
  fed by BodySubsClient's proximity check) hides the TO CHECKPOINT button when
  false.
- **⚠ `Set` cannot CLEAR a field** — `{ field = nil }` is a silent no-op
  (`pairs` skips nils). Use `AppRoot.Clear(key)`; panel switching uses
  `AppRoot.Open(name?)` (assigns openPanel directly, nil closes).
- Actions OUT: `AppRoot.SetCallbacks({...})` (merges): onClaimDaily,
  onToggleSetting, onShopActivated, onRedeem, onBuyUpgrade,
  onEquipPet(petId, equip), onToggleUpgrades, onGymTap,
  onDismissReveal, onReturnCheckpoint, onEatDown/onEatUp (EAT button hold —
  CakeSubsClient drives `eating`), onCloseUpgrades (routes the hex-tree close
  through UpgradesSubsClient so blur + E-binding stay in sync). Wire to remotes
  in the feature's subs (R4).
- `onPanelChanged(panel|nil)` is NOT an action — AppRoot fires it whenever
  `openPanel` changes (never on mount) so ONE listener can react to every
  open/close. `AudioSubsClient` uses it for the panel whoosh
  (`features/audio.md`); a new panel cannot forget to fire it.
- Lobby actions: `onConfigureMatch(difficulty, maxPlayers)`, `onCancelMatch()`;
  `LobbySubsClient` owns their queue remote wiring.
- Feature subs NEVER call `UiRoot.Render` — `AppSubsClient` mounts once.

## View-models (R7)
`LocalRewardsService` (cards), `LocalShopService` (`BuildTabs(shop, group, gems)`
— the shop is a landscape TABBED grid window; the GEM BALANCE is an argument, not
decoration: it is what decides `buy` vs `unaffordable` on a gem-priced card,
`features/shop.md`. AppRoot also feeds the panel `balances`, which render inside
the shop's HEADER band, so gem packs have a balance anchor on screen),
`LocalSettingsService` (rows), `LocalPetsService` (pets panel props,
reveal props, odds line), `LocalStatsService` (upgrade costs/stat
formulas). AppRoot builds the upgrade rows + CakeBar/BellyBar strings
inline (locale keys `cake-*`, `belly-*`).

## Gotchas
- useEffect deps must never contain nil (jsdotlua positional compare) —
  booleans/counters only.
- **Each panel family needs its own viewport fit.** `calculateScale(aspect,
  maxFraction)` is per-aspect, and every scale must ALSO be recomputed in the
  refit effect or that panel stops resizing with the window. The shop is
  landscape now and has `shopScale`; it used to borrow `portraitScale`.
- `formatNumber` abbreviates at 10K (`37.1K`, `12.4M`) and stays exact below
  that. The switch-on threshold and the divisor are deliberately different for
  the K tier (10,000 vs 1,000) — collapsing them renders 37,051 as "3.7K".
- Combo state is throttled by CakeSubsClient (Set only on VALUE change);
  announceKey lifetime is `Theme.AnnounceBanner.Duration` (via CakeSubsClient's
pushAnnounce `task.delay`), Clear via `false`.
- petReveal uses `false` (not nil) for "dismissed"; `petRevealCount`
  increments per roll so back-to-back reveals re-spin.
- Layout numbers live in `Theme.AppHud` (+ new sections) — not in code. Menu
  columns = `Theme.AppHud.MenuColumns`; AppRoot derives rows/size from it.
- **Currency icons come from `Theme.AppHud.PillIcons`** (registry NAMES, checked
  against `Icons.lua` at load), shared with the shop's balance row so one currency
  can never show two glyphs on one screen. The game HUD was the last caller of
  `StatPill`'s legacy hand-vectored `bolt`/`coin` shapes — which is how the GEMS
  pill ended up wearing a COIN. `StatPill` still accepts the old `icon` strings
  for API compatibility; don't use them.
- Interaction juice is in the KIT, not here: press feedback in the button
  components, open/close pop in `PanelShell`, badge/bar/toggle animation in their
  components (all off `Theme.Feel`, ADR-0006). Don't re-add animation in AppRoot.
- Published project files map exactly one place marker. The combined development
  build maps both; `LobbySubs` still suppresses the lobby map when game
  `MapService` is present.

## Files
`modules/AppRoot.lua`, `modules/UiRoot.lua`, `subscriptions/AppSubsClient.lua`;
`subscriptions/BodySubsClient.lua` (feeds `checkpointFar`); kit components:
`HudMenuButton` (bare icon+label menu button), BellyBar, CakeBar (+`visible`),
ComboBadge, AnnounceBanner, `BossPrizeCard` (boss-phase prize, `Theme.BossPrize`;
fed by `LocalPetsService.BuildPrize` from `cake.pendingPet`),
UpgradeRow/UpgradesPanel, GymOverlay, EatButton
(touch hold-to-eat, `Theme.EatButton`), PetRevealOverlay,
MatchmakingPanel, StatRow (extracted). Shared press/hold feel: `Interaction`
(`usePressable` now also exposes `onPressStart`/`onPressEnd` HOLD callbacks).
Lobby contract: `features/lobby-matchmaking.md`.
