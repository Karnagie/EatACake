# AppRoot (composed UI root: HUD + panels + overlays)

## What it does
The ONE React tree rendered through `UiRoot.Render` (single-root contract,
`docs/features/ui-kit.md`). HUD: calories + gems StatPills, 9-button menu
column (badges on Rebirth-affordable / Quests-claimable / Daily / Time),
CakeBar (top center, phase-aware), BellyBar (bottom center, glutton state),
ComboBadge, AnnounceBanner. Panels toggled by ONE `openPanel` (zIndex 50):
Pets (PetsInspectPanel), Upgrades, Rebirth, Quests, Shop, Daily, Time,
Codes, Settings. Overlays: GymOverlay (40), PetRevealOverlay (90).

## Contract for feature subs
- Data IN: `AppRoot.Set(patch)` — fields: `calories, gems, settings, daily,
  time, shop, group, codesStatus, cake, stomach, gym, upgrades, pets,
  petReveal (+petRevealCount), rebirth, quests, combo, announceKey,
  openPanel`. Works pre-mount.
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
- Layout numbers live in `Theme.AppHud` (+ new sections) — not in code.

## Files
`modules/AppRoot.lua`, `modules/UiRoot.lua`, `subscriptions/AppSubsClient.lua`;
new kit components: BellyBar, CakeBar, ComboBadge, AnnounceBanner,
UpgradeRow/UpgradesPanel, GymOverlay, PetRevealOverlay, RebirthPanel,
QuestRow/QuestsPanel, StatRow (extracted).
