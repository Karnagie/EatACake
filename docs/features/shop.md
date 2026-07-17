# Shop (Robux dev products + gamepasses)

## What it does
Catalogue-driven Robux shop: developer products (consumables, one-time packs)
and gamepasses (permanent perks). `ShopSubs` is the SINGLE owner of
`MarketplaceService.ProcessReceipt`.

## Tuning
`src/server/data/ShopData.lua` — the single tuning point: `products[key]`
(`devProductId` — **0 = not configured, purchase refused + boot warn**,
`priceRobux` reference-only, `label`, `section` "featured"/"gems", `order`,
`oneTime`, `grant`/`grants` descriptors), `gamepasses[key]` (`gamePassId`,
`priceRobux`, `label`, `order`). Ids are PER GAME (create on the universe,
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
Ownership is Roblox-side: fetched on join (`UserOwnsGamePassAsync`, async
re-push; aborts if the player leaves mid-fetch) and after
`PromptGamePassPurchaseFinished`; cached runtime in `ShopData.passOwnership`.
Game code reads perks via `ShopService.OwnsPass(userId, key)`. No grants on
passes — they are permanent flags, not loot.

## Payloads
`ShopUpdate` = `{ products = ARRAY {key,label,priceRobux,section,order,
oneTime,owned}, passes = ARRAY {key,label,priceRobux,order,owned} }` —
pushed on join, after ownership refresh and after every purchase.
`RequestPurchase(key)` / `RequestGamepass(key)` from the client.

## UI
Kit `ShopPanel`: portrait sectioned list (Featured / Passes / Gold / Free —
Free hosts the group-reward row). Rows via `ShopRow` (gap baked into cell
aspect — no scale Padding in AutomaticCanvasSize lists). View-model:
`LocalShopService.BuildSections`.

## Files
Server: `ShopData`, `ShopSection`, `ShopService`, `ShopSubs`. Client:
`ShopSubsClient`, `LocalShopService`. Remotes: `RequestPurchase`,
`RequestGamepass`, `ShopUpdate`.
