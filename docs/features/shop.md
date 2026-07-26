# Shop (Robux dev products + gamepasses)

## What it does
Catalogue-driven Robux shop: developer products (consumables, one-time packs)
and gamepasses (permanent perks). `ShopSubs` is the SINGLE owner of
`MarketplaceService.ProcessReceipt`.

## Tuning
`src/server/common/data/ShopData.lua` — the single tuning point: `products[key]`
(`devProductId` — **0 = not configured, purchase refused + boot warn + a grey
disabled "SOON" button**, `priceRobux` reference-only, `label`, `desc` (the perk
line — keep ≤26 chars, see Gotchas), `icon` (a `Theme.Icons` key), `section`
"featured"/"eggs"/"gems", `order`, `best` (BEST VALUE ribbon), `oneTime`,
`grant`/`grants` descriptors), `gamepasses[key]` (`gamePassId`, `priceRobux`,
`label`, `desc`, `icon`, `order`). Ids are PER GAME (create on the universe,
fill in). Icon-upload gotcha: Open Cloud multipart file part must be named
`imageFile`.

## Money-path guarantees
- Receipt grant is ALL-OR-NOTHING: the whole grants list is validated
  (`HasHandler`, gold amount > 0, non-empty) BEFORE the first grant — a
  partial-failure retry can never re-mint earlier grants.
- A product with no grants is refused (NotProcessedYet) + warns — money is
  never taken for a no-op.
- Receipt before profile load: bounded wait (15s) then NotProcessedYet
  (Roblox retries; never burned).
- Unknown ProductId: NotProcessedYet + `Log.Once` (R8 — never silent).
- `oneTime` enforced by us via profile `shop.oneTimePurchased[key]`
  (Roblox has no one-time semantics): prompt refused when owned, stray
  duplicate receipts consumed WITHOUT re-granting.
- `PersistenceService.Save` right after a paid grant (P5).

## Gamepasses
Ownership is Roblox-side: common `PassOwnershipSubs` fetches it on join in both
places (`UserOwnsGamePassAsync`, async re-push; aborts if the player leaves
mid-fetch); lobby `ShopSubs` updates the cache after
`PromptGamePassPurchaseFinished`. It lives in `ShopData.passOwnership`.
Game code reads perks via `StatsService` (`CaloriesMult`/`GemsMult`/`Capacity`/
`HasAutoEat`/`HasAutoGym`/`PetSlots`), which reads the `ShopData.passOwnership`
cache DIRECTLY (StatsService cannot call ShopService — R3); the client reads the
`AutoEat`/`AutoGym` player attributes set by `PassOwnershipSubs`.
`ShopService.OwnsPass` is
the shop domain's own owned-flag/resync check, NOT the gameplay perk-read path.
No grants on passes — they are permanent flags, not loot.

## Payloads
`ShopUpdate` = `{ products = ARRAY {key,label,desc,icon,priceRobux,section,
order,best,oneTime,owned,configured}, passes = ARRAY {key,label,desc,icon,
priceRobux,order,owned,configured} }` — pushed on join, after ownership refresh
and after every purchase. `configured` = the id is nonzero; the UI needs it to
render "SOON" instead of a live BUY button the server will refuse.
`RequestPurchase(key)` / `RequestGamepass(key)` from the client.

## UI — landscape sectioned grid
Kit `ShopPanel` on `PanelWide`/`HeaderWide` (1000×600, maxViewportFraction
0.92). Balance chips (gems + calories) over a scroll whose sections each carry
their own grid, ordered **Free → Featured → Passes → Eggs & Boosts → Gems**
(the give before the sell).

| Section | `kind` | Cell | Grid |
|---|---|---|---|
| Free (group reward) | `banner` | `ShopBanner` green | 1 × full width |
| Featured | `banner` | `ShopBanner` gold | 1 × full width |
| Game Passes | `tile` | `ShopTile` 282×160 | 3 cols |
| Eggs & Boosts | `tile` | `ShopTile` | 3 cols |
| Gems | `pack` | `ShopPackCard` 208×248 | 4 cols |

**The canvas is DETERMINISTIC and must stay that way.** `ShopPanel` sums the
section heights in nominal px, sets `canvasHeightScale`, and positions every
cell by explicit fraction — there is no `UIListLayout`, no
`AutomaticCanvasSize`, no `UIGridLayout` and no aspect constraint inside the
scroll. The obvious alternative (list + one aspect constraint per cell) was
built and measured to FAIL: the constraint fits within
`(windowWidth, seed × canvas)`, the canvas is what the cells grow, and the fixed
point that converges is one where the height binds — 377-px rows inside a 596-px
window. Sums: `3*282 + 2*12 = 870` ✓, `4*208 + 3*12 = 868` (2px slack on
purpose), `window 870 + gap 12 + bar 22 = 904` ✓.

Cell states: `buy` (green + Robux icon) / `owned` (blue "OWNED" + green check
badge — the cell is NOT dimmed, the name stays readable) / `unavailable` (grey
"SOON"). View-model: `LocalShopService.BuildSections`.
`ShopRow` + `Theme.ShopRow` remain on disk unused, for API compatibility.
The Shop server/UI is lobby-owned; the authored chocolate world opener belongs
to `features/lobby-matchmaking.md`.

## Gotchas
- `TextScaled` implies `TextWrapped`: a `desc` longer than ~26 chars wraps to
  two lines inside a 24-px zone and shrinks to unreadable. Shorten the copy.
- The BEST VALUE ribbon has a RESERVED band on every pack, tagged or not, so all
  four cards keep the same height and the tag can never overlap art or price.

## Files
Server: common `ShopData`, `ShopSection`, `PassOwnershipSubs`; lobby
`ShopService`, `ShopSubs`. Client:
`ShopSubsClient`, `LocalShopService`. Remotes: `RequestPurchase`,
`RequestGamepass`, `ShopUpdate`.
