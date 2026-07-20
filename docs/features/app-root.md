# AppRoot (composed UI root: HUD + panels + overlays)

## What it does
The ONE React tree rendered through `UiRoot.Render` (single-root contract,
`docs/features/ui-kit.md`). HUD: calories + gems StatPills, 8-button menu
GRID — bare icon + label-BELOW buttons, NO background (`HudMenuButton`;
badges on Rebirth-affordable / Quests-claimable / Daily / Time). The menu is a
`UIGridLayout` (`Theme.AppHud.MenuColumns`, default 2 → 2×4 block that stops
mid-screen, not a full-height column). CakeBar (top
center, phase-aware — **hidden during normal eating**, shown only for
boss/spawn/reward), BellyBar (bottom center, glutton state), ComboBadge,
AnnounceBanner, TO CHECKPOINT button (bottom-center, shown only when away from
the checkpoint — see `features/checkpoint.md`). Panels toggled by ONE
`openPanel` (zIndex 50):
Pets (PetsInspectPanel), Upgrades, Rebirth, Quests, Shop, Daily, Time,
Codes, Settings. Overlays: GymOverlay (40), PetRevealOverlay (90).

## Contract for feature subs
- Data IN: `AppRoot.Set(patch)` — fields: `calories, gems, settings, daily,
  time, shop, group, codesStatus, cake, stomach, gym, upgrades, pets,
  petReveal (+petRevealCount), rebirth, quests, combo, announceKey,
  checkpointFar, openPanel`. Works pre-mount. `checkpointFar` (default true;
  fed by BodySubsClient's proximity check) hides the TO CHECKPOINT button when
  false.
- **⚠ `Set` cannot CLEAR a field** — `{ field = nil }` is a silent no-op
  (`pairs` skips nils). Use `AppRoot.Clear(key)`; panel switching uses
  `AppRoot.Open(name?)` (assigns openPanel directly, nil closes).
- Actions OUT: `AppRoot.SetCallbacks({...})` (merges): onClaimDaily,
  onClaimTime, onToggleSetting, onShopActivated, onRedeem, onBuyUpgrade,
  onEquipPet(petId, equip), onDoRebirth, onClaimQuest, onGymTap,
  onDismissReveal. Wire to remotes in the feature's subs (R4).
- Feature subs NEVER call `UiRoot.Render` — `AppSubsClient` mounts once.

## View-models (R7)
`LocalRewardsService` (cards), `LocalShopService` (sections),
`LocalSettingsService` (rows), `LocalPetsService` (pets panel props,
reveal props, odds line), `LocalStatsService` (upgrade costs/stat
formulas). AppRoot builds upgrade/quest rows + CakeBar/BellyBar strings
inline (locale keys `cake-*`, `belly-*`).

## Gotchas
- useEffect deps must never contain nil (jsdotlua positional compare) —
  booleans/counters only.
- Combo state is throttled by CakeSubsClient (Set only on VALUE change);
  announceKey lifetime is `Theme.AnnounceBanner.Duration` (via CakeSubsClient's
pushAnnounce `task.delay`), Clear via `false`.
- petReveal uses `false` (not nil) for "dismissed"; `petRevealCount`
  increments per roll so back-to-back reveals re-spin.
- Layout numbers live in `Theme.AppHud` (+ new sections) — not in code. Menu
  columns = `Theme.AppHud.MenuColumns`; AppRoot derives rows/size from it.
- Interaction juice is in the KIT, not here: press feedback in the button
  components, open/close pop in `PanelShell`, badge/bar/toggle animation in their
  components (all off `Theme.Feel`, ADR-0006). Don't re-add animation in AppRoot.

## Files
`modules/AppRoot.lua`, `modules/UiRoot.lua`, `subscriptions/AppSubsClient.lua`;
`subscriptions/BodySubsClient.lua` (feeds `checkpointFar`); kit components:
`HudMenuButton` (bare icon+label menu button), BellyBar, CakeBar (+`visible`),
ComboBadge, AnnounceBanner, UpgradeRow/UpgradesPanel, GymOverlay,
PetRevealOverlay, RebirthPanel, QuestRow/QuestsPanel, StatRow (extracted).
