# Upgrades (hexagon tier tree)

## What it does
Nine calorie-bought stats bought as discrete **TIERS** in a **hexagon
honeycomb** UI (GDD §10), grouped in three categories:
- **eating** — biteRadius / biteDepth / eatSpeed
- **body** — capacity / runSpeed
- **gym** — gymEff (calories per burn) + the fat-burn stats **burnSpeed**
  (passive drain rate), **burnPerTap** (fat per tap), **instantBurn** (fat
  removed on press; final tier = whole belly). See `features/body-gym.md`.

`upgrades.levels[id]` = tiers OWNED (0 = none, `#tiers` = maxed). Tier values +
costs ONLY in `Shared/config/UpgradeConfig`; ALL derived numbers come from
`StatsService` (server) / `LocalStatsService` (client mirror). The tree is a
full-screen lobby overlay reserved for an authored `UpgradeStation`, NOT a HUD
button; that lobby station is not placed yet, so the published opener remains
intentionally unavailable (ADR-0009 Remaining).

## Progression (easy-mode retune 2026-07-19)
Each stat is ~5 tiers (`instantBurn` 4). `StatsService.upgradeValue` returns
`tier==0 and def.base or def.tiers[min(tier,#tiers)].value`. Values + costs were
retuned for the EASY-MODE loop (`2026-07-19_easy-mode-balance.md`), NOT to
reproduce the old per-level formula:
- **`capacity` base 150 → 2600** — the belly holds ~50–160 BITES (was ~4), so a
  full belly is ~50 s of eating; THE fix for "1 bite = full".
- **Eating stats flattened**: `biteDepth` max 26 → 1.8, `biteRadius` 12 → 4.2,
  `eatSpeed` 41 → 5.2 — total eating power grows ~4× over the tree (was ~2000×),
  so endgame no longer eats the whole cake in a handful of bites ("reduce final
  sizes").
- **`gymEff` max 4.32 → 2.35**; gym drain stats (`burnSpeed`/`burnPerTap`/
  `instantBurn`) keep their VALUES, only costs rescaled.
- **Costs pace the ~5-tier ramp across the full ~40-min solo cake.**

Tier COUNT and the remote contract are unchanged → **no profile migration** (a
returning save's `levels[id]` still means tier count). Rebirth block
(`UpgradeConfig.rebirth`) unchanged (still resets these ids).

## Honeycomb (UpgradeTreeConfig + LocalUpgradeTree)
- **root** tree: centre LOGO hex + one CATEGORY hex per group (eating / body /
  gym) at alternating neighbours so they TOUCH the logo. A category shows a
  notifier BADGE when it holds an affordable next-tier. Tapping drills in.
- **sub-tree** per category: centre BACK hex, then the category's stats PACKED
  into a dense honeycomb blob — each stat gets an angular SECTOR (its tiers form
  one connected wedge-clump, tier 1 nearest the centre), so hexes touch
  edge-to-edge with NO connectors (`packSectors(counts)`). Tier k unlocks when
  k-1 owned. Only tiers 1..**min(owned+2, #tiers)** are shown per stat (owned +
  available + the next preview); deeper tiers appear as you buy.
- Hexes are edge-to-edge (`UpgradeTreeConfig.hex.nodeFill = 1`, dark Outer
  layers meet like a comb). `LocalUpgradeTree.BuildTree(treeId, levels,
  calories)` lays nodes on a unit hex grid then AUTO-FITS the bounding box into
  the square canvas (uniform scale) so every tree fills the view. Returns
  `{ nodes, nodeWidth, nodeHeight }` (Scale); each node carries `detail`
  (name/desc/status/buyText/affordable) for the tap panel, categories a `badge`.
- Node states: `locked` (gray) / `available` (gold, the next buy) /
  `owned` (blue) / `category` (purple) / `back` (teal) / `logo`.

## Flow
`BuyUpgrade` remote (statId) → UpgradeSubs: `IsLoaded` gate → `NextCost` gate
(nil = maxed → resync) → `EconomyService.TrySpendCalories` → `ApplyLevel` (tier
+1) → pushes `UpgradesUpdate {levels}` + `CurrencyUpdate` + `BodySubs.RefreshBody`.
Clicking the gold `available` hex fires `BuyUpgrade(statId)` (advances that stat
one tier). Costs recomputed client-side — only levels travel. **Remote contract
UNCHANGED** by the tier rework (still `BuyUpgrade(statId)`).

## Open/close + modal (UpgradesSubsClient — R4)
The station `ProximityPrompt` ("UpgradeStation") fires client-side →
`ProximityPromptService.PromptTriggered` → `AppRoot.Open("Upgrades")`. Opening a
menu is LOCAL UI — no server round-trip. On open it becomes MODAL: the cloned
`Shared.UIKit.Templates.UpgradeTreeBlur` dims the world, the camera is frozen
(`CameraType = Scriptable`) and character
movement is locked through `PlayerControlService`'s `upgrade-overlay` reason so
nothing shifts behind
the tree, and ALL prompts under the active `LobbyMap`/`Map` are disabled (station + nearby prompts may share E — an
enabled one would re-fire on the E-to-close press and hide behind the overlay).
**E** (ContextAction, suppressed while a TextBox is focused) or the red **X**
top-right closes (restores camera/prompts and releases only its own movement
lock; an active teleport lock remains). Reopening resets the
nav-stack to root (AppRoot effect on `openPanel=="Upgrades"`).

**Place-split status:** the subscription, overlay, and server handler are
lobby-only, but the authored `LobbyEnvironment` does not yet contain an
`UpgradeStation` prompt. Therefore the published lobby currently has no world
opener; the old game checkpoint prompt is intentionally inactive. Re-author the
station in the lobby before advertising this entry point (ADR-0009 Remaining).

## GUI contract
`HexTreeOverlay` (zIndex 60, above panels): dim scrim + a clipped square
`Viewport` holding a `World` frame whose Position/Size are ZOOM/PAN bindings +
calories `StatPill` top-left + red X `CloseButton` top-right + +/-/1x zoom buttons
bottom-right + a **Detail card** shown NEXT TO a tapped tier. `HexNode` is a pure
VISUAL (no input): flat-top hex SPRITE (`Theme.HexTree.HexImage`, 512/444) stacked
Outer/Rim/Face tinted per state by UIGradient + OutlinedText name/status +
optional red "!" `Notifier`.
- **Pan/zoom**: hexes live in a `World` frame (Position/Size = zoom/pan bindings)
  inside a SQUARE `Viewport` (coordinate ref) inside a FULL-SCREEN `Clip` — so the
  tree pans across the whole screen and only clips at the screen edges, not a
  small window.
- **Single input surface**: a transparent full-screen Active `InputSurface`
  (zIndex z+7, ABOVE hexes z+2..z+5 and the "!" badge layer z+6, BELOW controls
  z+8 / card z+10). Press-start is detected here; DRAG/pinch/END run on
  `UserInputService` (global) so a release over a control doesn't leak. DRAG to
  pan, scroll / 2-touch pinch / +-/1x buttons to zoom, TAP to act. A press that
  moves > threshold is a pan (not a tap). A tap is **hit-tested** to the nearest
  hex; tier → focus + Detail card next to it (Active, so it's inert to the pan
  surface), category → drill in, back → up. Zoom keeps the cursor point fixed;
  pan clamped; zoom/pan/focus reset on tree change. The card DISMISSES on drag,
  empty-space tap, or tapping the open tier again.
- Interaction is identical on PC + touch. AppRoot holds `treeStack`; overlay
  `onNodeActivated(action)`: `open`→push, `back`→pop, `buy`→`onBuyUpgrade`
  (from the card's green Buy, dimmed when unaffordable); tier focus + pan/zoom
  are overlay-local.

## Persistence (P2)
`UpgradesSection` v2. `migrations[1]` rescales v1 linear levels → v2 tiers
(`round(oldLevel/oldCap * 5)`, clamped) so returning saves keep ~their power.
The gym fat-burn stats (`burnSpeed`/`burnPerTap`/`instantBurn`) are NEW `levels`
ids added later, defaulting to 0 — reconcile fills them for existing profiles,
so NO version bump/migration is needed (every consumer reads a missing id as
tier 0).
Idempotent: only a stored-v1 profile runs it. StatsService clamps reads
(`min(tier,#tiers)`) so an over-cap value can't inflate a stat; NextCost/ApplyLevel
return nil past the last tier (no further buy). ⚠ **Deploy caveat**: `levels[id]`
changed MEANING (linear level → tier) without changing the KEY, so during a
rolling deploy an old v1 server reads a migrated profile's tier count as a linear
level and lets it be re-bought at old per-level prices (a transient cheap-max
exploit, not corruption). **Drain/shut down v1 servers before the v2 push.** The
bulletproof alternative (if ever needed) is to store tiers under a NEW key so old
servers see it absent.

## Files
Server: `ProfileSchema/UpgradesSection` (v2), `services/UpgradeService`,
`StatsService`, `subscriptions/UpgradeSubs`; `data/MapConfigData` (station),
`services/MapService` (builds/rides the computer). Shared:
`config/UpgradeConfig` (tiers), `config/UpgradeTreeConfig` (honeycomb), `HexUtil`
(axial math), `UIKit/Theme` (`HexTree`), `UIKit/Components/HexNode` +
`HexTreeOverlay`. Client: `LocalStatsService`, `LocalUpgradeTree` (view-model),
`AppRoot` (overlay + nav-stack), `subscriptions/UpgradesSubsClient` (prompt
open/close), lobby `LobbyUiData` (modal config/state),
`PlayerControlData`/`PlayerControlService`, `UIKit/Templates/UpgradeTreeBlur`,
`data/LocaleData` (`hex-*`, `cat-*`, `upgrade-*-desc`).
The old flat `UIKit/UpgradesPanel`/`UpgradeRow` are now UNUSED (kept, not wired).
