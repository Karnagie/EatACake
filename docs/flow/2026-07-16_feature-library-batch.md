# 2026-07-16: Feature library batch (time/group/shop/codes/settings + AppRoot)

Tags: time-rewards, group-reward, shop, promo-codes, settings, app-root, economy, ui-kit

## Task
Finish plan item 2+3: the recurring-feature library (time rewards, group
reward, shop with dev products AND gamepasses, promo codes — net-new) plus
the glue (composed React root with gold HUD, menu, badges; settings
persistence).

## Context
UI kit + settings window landed the day before (`2026-07-15_ui-kit-port.md`);
the single-root constraint (`UiRoot.Render` replaces the tree) forced the
composed-AppRoot design before any second kit feature. Server logic ported
from Dices (scout reports), grants centralized via RewardGrantSubs (ADR-0002)
instead of Dices' per-domain grant copies.

## Changes (headline)
**Server:** 4 new profile sections (timeRewards/social/shop/codes), 4 config
data modules, 4 services (TimeReward/Social/Shop/Codes), subs:
GroupRewardSubs, ShopSubs (sole ProcessReceipt owner), CodesSubs,
SettingsSubs; RewardsSubs extended (time claims + flush loop);
PlayerLifecycleSubs pushes 6 domains + Begin/EndSession. 6 new remotes,
5 new remoteUpdates.
**Kit:** 7 new components (Badge, DayCard, RewardsPanel, ShopRow, ShopPanel,
TextInput, CodesPanel) + 9 Theme sections with zone-arithmetic comments.
**Client:** AppRoot (single composed root: state bridge Set/SetCallbacks/Open,
HUD pill + menu + badges, 5 panels), view-models (LocalRewardsService /
LocalShopService / LocalSettingsService rewritten), 6 feature subs. Old
Studio-authored daily path (UiData.guiNames, imperative RefreshDaily) retired.

## Decisions
- **AppRoot state bridge**: module-level `current` + callbacks, component
  mirrors via captured setState; works pre-mount. Subs never call
  UiRoot.Render (single-root contract).
- **Group reward lives in the Shop's Free section** — no dedicated window.
- **Gamepasses**: ownership is Roblox-side, cached runtime
  (`ShopData.passOwnership`), perks read via `ShopService.OwnsPass`; no grants.
- **oneTime generalized**: `shop.oneTimePurchased[key]` set replaces Dices'
  single boughtStarterPack flag.
- **Time session anchor is runtime-only** (`TimeRewardsData.sessionStarts`):
  schema persistence saves the whole profile, a persisted anchor would
  corrupt `today` after a crash. Flush loop keeps `today` fresh for
  ProfileStore autosave; rollover re-anchors (no cross-day leakage).

## Post-review hardening (adversarial pass, 28 findings)
CRITICAL fixed: (1) ProcessReceipt double-grant on partial failure — grants
list now validated whole BEFORE granting (all-or-nothing); (2) product with
no grants took money for nothing silently — refused + boot warn; (3) dead 1s
ticker — jsdotlua deps must never contain nil (`{nil}` has length 0,
positional compare never re-runs) — boolean dep; (4) ShopPanel scale-Padding/
scale-height sections inside AutomaticCanvasSize inflate — gaps baked into
cell aspects (PetCard recipe). Also: receipt waits (bounded) for profile
load; unknown-ProductId receipts Log.Once; group claim not consumed when
grant declines + post-yield IsLoaded re-check; pass-ownership leak on
mid-fetch leave; settings optimistic toggle seeded from defaults; tuning
constants moved to data modules (R1); rewards grid cell shaved (exact-fit
wrap); rollover re-anchor; claimed-set sanitize hardening; LocalShopService
extracted (R7); lazy useState initializers; Theme.AppHud.MenuWidth; menu
count derived.

## Open Questions / Followups
- **Studio verification pending** — new kit windows are built to the skill's
  rules but NOT visually verified (no Studio connected this session). Run
  studio-verifier: boot contract + open each panel + claim/redeem clicks.
- Rate limiting for resync-answering remotes (queued, U1).
- Celebration/FX layer (toast keys reserved), sound effects.
- Number formatting unification (label-gold-n vs HUD formatGold).
- Localization toolchain port remains next big rock.

## Related
- Features: time-rewards, group-reward, shop, promo-codes, settings,
  app-root, daily-rewards (UI section rewritten), economy (HUD)
- ADRs: 0002 (grant registry — now consumed by 5 features)
- Prior flow: `2026-07-15_ui-kit-port.md`
