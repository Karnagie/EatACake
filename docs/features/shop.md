# Shop (Robux dev products + gamepasses + the GEM row)

## What it does
Catalogue-driven shop in **TWO currencies**: Robux developer products
(consumables, one-time packs) and gamepasses (permanent perks), plus the BOOSTS
row, which is bought with in-game **gems** and has no Creator Dashboard id at
all. `ShopSubs` is the SINGLE owner of `MarketplaceService.ProcessReceipt` AND
the cashier for the gem path, and it is **COMMON** — it runs in BOTH places (see
Money-path guarantees).

## Tuning
`src/server/common/data/ShopData.lua` — the single tuning point: `products[key]`
(`currency` — absent/`"robux"` = dev product, `"gems"` = in-game currency;
`priceGems` (gem products only — unlike `priceRobux` this one is AUTHORITATIVE,
our server charges it), `devProductId` — **0 = not configured, purchase refused
+ boot warn + a grey disabled "SOON" button**, `priceRobux` reference-only,
`label`, `desc` (the perk line — see Gotchas for the length limits), `icon` (a
`Theme.Icons` key), `accent` (a `Theme.ShopCardAccents` key — the CARD COLOUR),
`premium` (gold halo + gold frame), `bundle` (featured/hero only: array of
`{icon, text}` chips), `section` "featured"/"boosts"/"gems", `order`, `best`
(BEST VALUE ribbon), `oneTime`, `grant`/`grants` descriptors),
`gamepasses[key]` (`gamePassId`, `priceRobux`, `label`, `desc`, `icon`, `accent`,
`premium`, `order`), `receiptLedgerSize`, and `gemPurchaseWindowSeconds` /
`gemPurchaseBurst` (the gem remote's rate limit).
Ids are PER GAME. **All 11 are LIVE as of 2026-07-31** (universe 10593425705) —
the ids, and how to create/audit more with `tools/monetization/`, are in
`docs/recipes/publish-readiness.md`. ⚠ A developer product is CREATE-ONCE: no
delete endpoint and no update endpoint, so its name/description/price are
permanent. A gamepass can be re-PATCHed and retired (`isForSale=false`).

⚠ **`ShopData.IsGemProduct(def)` is the ONLY correct currency test** — it reads
`currency`, nothing else. Testing "has no `devProductId`" instead makes any Robux
product whose id is 0 read as a gem product, i.e. **free**. All 11 ids are live
now, so the trap is no longer standing — but it re-arms the moment a new Robux
product is added, or the template is copied into a game whose ids start at 0. The
predicate is shared by the payload, the boot report and both purchase remotes so
they cannot drift into disagreeing.
Consequences the code already encodes: a gem product must never appear in the
`NOT ON SALE` boot list (it needs no dashboard id — its equivalent
misconfiguration is a missing `priceGems`, reported on its own line), and
`configured` means "nonzero dashboard id" for Robux and "nonzero price" for gems.
The boosts' price and pacing rule live in `features/boosts.md`.

## Money-path guarantees
- **ProcessReceipt is armed in BOTH places.** `ShopSubs` was lobby-only, so a
  receipt surfacing in a game server (in-experience Store, a re-delivery, a
  purchase completed across the teleport) was dropped with no console trace.
  Roblox retries forever so nothing was stolen, but the player saw nothing.
  It is now COMMON and logs `ProcessReceipt armed in the <place> place` (Sum).
- **Receipt ledger.** `profile.shop.receipts` remembers the last
  `ShopData.receiptLedgerSize` (50) `PurchaseId`s. Roblox re-delivers a receipt
  until it sees `PurchaseGranted`, so a server that granted and then died hands
  the SAME id to the next one — which double-granted every consumable (the gem
  packs; only `oneTime` products were protected). The id is
  recorded in the same no-yield stretch as the grant, before the save.
- **Never grant mid-handoff.** `PersistenceService.Save` is a NO-OP while a
  teleport release nonce is set, so a receipt arriving in that window took the
  Robux, consumed the receipt and lost the reward with the released session. It
  now returns `NotProcessedYet`; the destination server grants it.
- Receipt grant is ALL-OR-NOTHING: the whole grants list is validated
  (`HasHandler` + per-kind `descriptorValid`) BEFORE the first grant — a
  partial-failure retry can never re-mint earlier grants.
- A product with no grants, or a descriptor that fails its per-kind rule
  (`gems`/`calories` amount > 0, `boost` needs a `boostId`, unknown kind), is
  refused + warns. Money is never taken for a no-op.
- **A grant kind registered only by the GAME partition** (`burn`) is deferred
  with `NotProcessedYet` in the lobby and granted when Roblox re-delivers it in
  a game server. Self-healing, but not instant — boot logs the kinds affected.
- Receipt before profile load: bounded wait (15s) then NotProcessedYet.
- Unknown ProductId: NotProcessedYet + `Log.Once` (R8 — never silent).
- `oneTime` enforced by us via `profile.shop.oneTimePurchased[key]` (Roblox has
  no one-time semantics): prompt refused when owned, stray duplicate receipts
  consumed WITHOUT re-granting.
- Duplicate `devProductId`/`gamePassId` across two entries warns at Init — it
  used to be last-writer-wins over `pairs`, i.e. the shop silently selling the
  wrong product.
- **`PurchaseGranted` only after the write CONFIRMS.** `Save` is fire-and-forget,
  so the receipt path uses `PersistenceService.SaveAndWait` (bounded wait on
  `OnAfterSave`) and returns `NotProcessedYet` if it does not land — otherwise a
  crash between the grant and the DataStore write takes the Robux permanently,
  with no retry, because Roblox already saw PurchaseGranted (P5, ADR-0014).

### GEM path (`RequestGemPurchase`) — the order the handler runs in
**Our server is the cashier**, so the safety net the Robux path leans on —
*Roblox re-delivers a failed receipt forever* — **does not exist**. Nothing
re-delivers spent gems, so the hard problem inverts: not "never grant twice" but
**never charge for a no-op**. WHY each of these, plus the rejected alternatives:
ADR-0015. What the handler does, in order:
1. **Rate limit** — a BURST BUCKET (`gemPurchaseBurst` fires per
   `gemPurchaseWindowSeconds` per player, cleared on leave), checked BEFORE any
   push or warn. Not a flat cooldown: the four boosts are four adjacent cards at
   one price and none is `oneTime`, so buying two in succession is NORMAL — a
   cooldown dropped the second one while the client had already played its press
   feedback for both, and the player ended up with one boost believing they
   bought two. Over the burst, the drop is `Log.Once`d per player (R8): no human
   reaches it, so whoever does is scripting or hitting a client bug.
2. **A Robux key here is refused LOUDLY** (`Log.Warn` per attempt, not
   `Log.Once` — the count matters). `RequestPurchase` carries the mirror guard
   for a gem key, quietly.
3. **Refused — not deferred — mid-teleport-release**, and when the profile is
   not loaded. `Save` is a NO-OP in that window, so a spend would lose the gems
   AND the boost with the released session, and there is no retry to defer to.
4. **Validate the WHOLE grants list BEFORE spending** (`HasHandler` + per-kind
   `descriptorValid`, including that a `boost` names a real
   `TreasureConfig.boosts` def — `features/boosts.md`).
5. **`EconomyService.TrySpendGems` — atomic check+deduct**, then the grants with
   **no yields** between.
6. **A late decline is COMPENSATED**: the price is refunded, saved and re-pushed.
7. **Every refusal re-pushes the catalogue**; a success also re-pushes the
   balance via `EconomySubs.SendCurrency` (a SPEND fires no `CurrencyUpdate` of
   its own — only a GRANT does). `EconomySubs` is reached through the
   subscriptions registry and guarded, so a partition move degrades to a stale
   pill plus a console line, never a nil call (R3/R8).
⚠ **The refund is all-or-nothing AT THE PRICE, so a gem product may carry exactly
ONE grant.** With two, a second-grant failure refunds in full while the first
grant stands — free loot on repeat. Boot warns on any gem product with
`#grants > 1`.
⚠ The gem path needs **no receipt ledger** (nothing re-delivers); its equivalent
risk is the double click, covered by the atomic spend plus the cooldown.

## Gamepasses
Ownership is Roblox-side; common `PassOwnershipSubs` fetches it on join in both
places (`UserOwnsGamePassAsync`, async re-push; aborts if the player leaves
mid-fetch). It lives in `ShopData.passOwnership`. Game code reads perks via
`StatsService` (`CaloriesMult`/`GemsMult`/`Capacity`/`HasAutoEat`/`HasAutoGym`/
`PetSlots`), which reads the cache DIRECTLY (StatsService cannot call
ShopService — R3); the client reads the `AutoEat`/`AutoGym` player attributes.
**A pass bought mid-session applies immediately**: `PromptGamePassPurchaseFinished`
calls `PassOwnershipSubs.ApplyPerkAttributes`, without which the cell flipped to
OWNED while the attribute the client gates on stayed false until the next place
transition. No grants on passes — they are permanent flags, not loot.

## Payloads
`ShopUpdate` = `{ products = ARRAY {key,label,desc,icon,accent,premium,bundle,
currency,priceRobux,priceGems,section,order,best,oneTime,owned,configured},
passes = ARRAY {key,label,desc,icon,accent,premium,priceRobux,order,owned,
configured} }` — pushed on join, after ownership refresh and after every
purchase (including every gem-path refusal, so a stale client corrects itself).
`configured` = sellable: a nonzero dashboard id for Robux, a nonzero `priceGems`
for a gem product.
**The payload is an explicit field whitelist** (`ShopSubs.shopPayload`): a new
field in `ShopData` never reaches the client until a line is added there.
⚠ Both gem fields are load-bearing on the client and omitting either is SILENT:
`currency` routes the click to the right remote and picks the price glyph,
`priceGems` is what the affordable/unaffordable state is computed against — a
missing one just renders as an unpriced Robux product.
Client → server: `RequestPurchase(key)` (Robux) / `RequestGemPurchase(key)`
(gems) / `RequestGamepass(key)`. `ShopSubsClient` picks between the first two by
reading `currency` off the same snapshot the cells were built from.

## UI — landscape TABBED shop of product CARDS
Kit `ShopPanel` on `PanelWide`/`HeaderWide` (1000×600, maxViewportFraction
0.92). Balance chips (gems + calories) sit in the HEADER band left of the title;
under it a tab row, then one scroll showing only the active tab.

| Tab | Sections (in order) | `kind` | Cell | Grid | Canvas |
|---|---|---|---|---|---|
| Offers | Free Stuff, Featured | `banner`, `hero` | `ShopBanner` 870×176, `ShopHeroCard` 870×260 | 1 × full width | 1.6 screens |
| Passes | Game Passes | `card` | `ShopCard` 282×338 | 3 cols | 1.9 screens |
| Boosts | Boosts (GEM-priced) | `smallcard` | `ShopCard` 208×264 | 4 cols | fits |
| Gems | Gems | `smallcard` | `ShopCard` 208×264 | 4 cols | fits |

### The cell — A CARD IS A FRAME, A BUTTON IS A SLAB
This is the rule the shop exists to demonstrate, because breaking it is what
made every earlier version look like "stretched buttons":

> **button** = one colour field, outline bottom-weighted 2x+ (style-rules §2)
> **card** = EVEN outline, and INTERNAL ZONES

`style-rules.md` §2 is the kit's only generative recipe and it is the BUTTON
one, so cards built by following it mechanically got an 8px top / **30px bottom**
outline (3.75x) under a flat colour field at a squat 0.95 aspect — the kit's
strongest "pressable slab" signal, under every product. Now: outline 7 top/sides
/ 10 bottom (**measured live: 5.37 vs 8.05 px = 1.50x**), portrait 0.834, and the
composition is

    ART WINDOW  ·  TITLE  ·  PERK LINE  ·  PRICE SHELF

Only the price shelf keeps the button recipe — it is the only part that is a
button.

**Colour is CONTAINED to the art window.** The body is ONE neutral navy
(`Theme.ShopCardBody`) on every card; `ShopData.accent` colours the art window
only (via `Theme.ShopAccent`, which warns once on an unknown key). Six passes in
six saturated hues gave the grid no hierarchy — every cell shouted equally,
which is what "cluttered" means. `ShopData.premium` swaps the card's outline to
the kit's gold selection accent (gradient swap, no geometry) and is on `vip` and
`gems-xl` only; the hero wears it by default.

**The art window is NOT the twice-rejected "plate behind the icon".** Those put
a BADGE under the glyph (a white circle; then a well + full-bleed shelf + 2
gloss bands + contact shadow + gold halo, five layers at once). The window is
the card's top ZONE at full content width, and it does a job nothing else can:
`ScaleType.Fit` draws at the SHORTER side of its box, so a tall flame, a wide
gem cluster and a square pack drew at wildly different visual sizes when placed
straight on the face. Icon area 13.5% → **22.0% measured**, identical on both
card sizes. Anything richer than this window still belongs in the ICON ART.

**Two card sizes on purpose**: passes (6) at 3 across, boosts (4) and gems (4) at
4 across. It is the only split where every row is FULL (6 over 4 columns = 4+2,
4 over 3 = 3+1), and the permanent perks earning the bigger cell is the right
hierarchy anyway.

**The Starter Pack gets its own cell.** A bundle rendered as one icon and one
line is indistinguishable from a single product at four times the price, so
`ShopHeroCard` spells the contents out as a ROW OF CHIPS (`bundle`). Its info
column runs to the card's right edge and the buy shelf is CENTRED under the
chips — packing it into a 416-wide column left a 160×160 void in the
bottom-right, the only dead area in the panel.

### The window — four tabs, not one 5.6-screen scroll
Stacked, the five sections were 2046 nominal px in a 367px window: the shop
opened on the balance chips, one section header and one banner, and every other
category was below the fold. The tab row costs 56px and is paid for by moving
the balance chips into the header band, which was empty either side of the
centred title.
- **A single-section tab draws NO section header** — the tab already names it.
- **First tab is "Offers", not "Featured"** — it holds the *Free Stuff* and
  *Featured* sections, and a tab repeating one of its own headers reads as a bug.
- **Content that fits is centred** in the window; otherwise the canvas keeps
  `ShopLayout.CanvasTopPadPx` at the top (see Gotchas for what sizes it).
- Switching tabs REMOUNTS the scroll (the child's React key carries the tab id):
  a `ScrollingFrame` keeps `CanvasPosition` across a re-render, so a 2-row → 1-row
  jump used to land past the new tab's content, on blank canvas.
- A tab whose sections are all empty is DROPPED (no group configured, empty
  category) — a tab that opens onto nothing is worse than no tab.
- `tabs` is a new optional prop; the legacy `sections` prop still renders one
  untabbed scroll (kit iron rule 8).

**The canvas is DETERMINISTIC and must stay that way.** `ShopPanel` sums the
active tab's section heights in nominal px, sets `canvasHeightScale`, and
positions every cell by explicit fraction — no `UIListLayout`, no
`AutomaticCanvasSize`, no `UIGridLayout`, no aspect constraint inside the scroll.
Per-kind metrics live in ONE `metricsFor` table read by BOTH the height sum and
the placement loop; a kind added to only one desyncs the canvas silently.
Sums: `3*282 + 2*12 = 870` ✓, `4*208 + 3*12 = 868` (2px slack on purpose),
`window 870 + gap 12 + bar 22 = 904` ✓, tab row `4*217 + 3*12 = 904` ✓,
content column `56 tabs + 10 + 370 pane = 436` ✓.

Cell states colour the SHELF: `buy` (green + the currency glyph — Robux or gem —
+ the bare amount) / `owned` (blue "Owned" + a green check badge on the art
window's top-right corner — the cell is NOT dimmed) / `unavailable` (grey
"SOON", the id is still 0) / `unaffordable` (the same grey and disabled, but it
KEEPS the glyph and the amount — a gem product the player cannot pay for yet, and
the price is exactly the information they need, so it is not replaced by a word).
View-model: `LocalShopService.BuildTabs(shop, group, gems)` — the third argument
is the player's BALANCE, without which a gem card cannot choose between `buy` and
`unaffordable`.
`ShopRow` / `ShopTile` / `ShopPackCard` and `Theme.ShopPrice` /
`Theme.ShopPriceWide` remain on disk and exported, unused, for API
compatibility (kit iron rule 8).

## Gotchas
- **`desc` LENGTH IS A LAYOUT CONSTRAINT.** `TextScaled` fits BOTH axes, so on a
  narrow cell the WIDTH binds and long copy SHRINKS instead of truncating —
  "One squishy, better odds" rendered at ~8px. Limits: **~22 chars** on the big
  pass card (246px perk zone), **~15** on the small boost/gem card (176px). The
  same rule binds `label` on the small card's 176×28 title zone: past ~11
  characters the TITLE renders smaller than the 16px perk line under it, which
  inverts the card's hierarchy — that is why the boosts ship as "Extra Bite" /
  "2x Stomach" and not the requested "Extra Bite Size" / "2x Stomach Capacity"
  (15 chars → 15.6px). One name per perk everywhere: the daily card and the hero
  chip are NARROWER than this zone, so a long form there only moves the problem.
  The arithmetic is in the `ShopData` header where the copy is written.
- **The price label must NOT carry a currency word.** The shelf draws the glyph,
  so `price-robux` ("R$ {n}") beside it rendered "⬡ R$ 199" on every card. Buy
  state uses `price-robux-short` / `price-gems-short` (both "{n}"); OWNED / SOON
  keep full words (no glyph). Two keys, not one, so a translation can format the
  numeral differently per currency.
- **The ribbon overhangs the card's TOP edge** into the row gap (y −12/−9), so it
  no longer competes with the perk line and no longer covers the art — both
  earlier placements were measured and rejected. Top-only: the first and last
  grid columns sit flush against the canvas edges, so a horizontal overhang
  would be clipped by the scroll window. **`ShopLayout.CanvasTopPadPx` is what
  keeps that overhang inside the canvas** now that single-section tabs have
  no section header above row 1 — shrink it and BEST VALUE gets clipped.
- A section whose cell height changes must have its `ShopLayout.*Px` updated in
  the SAME edit; the panel positions by fraction of a summed canvas, so a
  mismatch silently overlaps cells rather than erroring.
- ⚠ **A grid cell may not GROW on hover or press.** A `ScrollingFrame` clips,
  and the columns pack to the canvas edges exactly (`3*282 + 2*12 = 870`), so
  there is zero horizontal slack: the kit's default card squash
  (`1.05 * 0.970` hover, `0.93 * 1.10` press) shaved ~3px off the outer columns'
  outline and ~10px off a full-width banner's, every time the pointer touched
  one. All three cells therefore pass `hoverScale = 1, pressScale = 1` with
  `Theme.Feel.Squish.GridCell*Pose`, whose X never exceeds 1. Measured overhang
  is now negative everywhere (big card −2.1 hover / −0.7 press; banner −6.5 /
  −2.2). The squash still runs — on Y, which has budget.
- ⚠ **`ShopLayout.CanvasTopPadPx` is 20, and it is sized against the DEFORMED
  ribbon**, not the static one: the cell grows about its centre, so the tag's
  offset from that centre (169 + 12 = 181 on the big card) is what scales —
  `181 * 1.03 - 169 = 17.4`, rounded up to 20 for margin. This is the ONLY place
  the number is written down; everywhere else refers to the constant by name.
- Empty sections/tabs are reported ONLY once at least one tab is live. Before
  `ShopUpdate` lands every section is empty, and `Log.Once` on that first render
  would permanently claim the catalogue is broken (R8's late-arriving-dependency
  false positive). The "nothing at all" case is a `Log.GraceOnce` instead.
- `ShopPanel` is `React.memo`'d, so AppRoot must pass STABLE `onActivated` /
  `onClose` (it `useCallback`s both with empty deps). Inline closures there make
  the memo pure overhead — a shallow compare fails on every bite-rate render.
- ⚠ **`local a, b = if c then f() else g()` truncates the call to ONE value** in
  Luau. It shipped once here and the price label rendered at zero height — an
  invisible price on a shop card, with no error. Use a statement.
- ⚠ Three conditions together trigger a `UIGradient` rotation artefact: a SQUARE
  element, a 45°-multiple rotation, and a keypoint at exactly t = 0.5. The face
  is 262×260, the sheens run at 115°/128°, and their peaks sit at 0.41/0.57 and
  0.69/0.73 — all three avoided deliberately. Keep it that way.
- `ShopHeroCard` draws at most `Theme.ShopHero.BundleColumns` chips and
  `Log.Once`s when a bundle lists more (an offer that under-sells itself is worse
  than a truncated one). It is **4** since the Starter Pack went to four grants,
  and the row was RE-CUT rather than squeezed: chips `4*140 + 3*12 = 596` ✓,
  closing on the card edge (`250 + 3*152 = 706, +140 = 846 = 250 + 596`), shelf
  `266` centred in that column at `415..681`, horizontal
  `22 + art 206 + 22 + column 596 + 24 = 870` ✓. Height is unchanged — the fourth
  chip is paid for in WIDTH. Chip copy is now capped at ~8 characters (the text
  zone lost 38px), which is why the bundle reads "200 / x2 Cal / Bite+ /
  x2 Speed".
- A new per-item field needs a line in `ShopSubs.shopPayload` or it silently
  never reaches the client.

## Files
Server (all COMMON): `ShopData`, `ShopSection`, `ShopService`, `ShopSubs`,
`PassOwnershipSubs`. Client: `ShopSubsClient`, `LocalShopService`. Kit:
`ShopPanel`, `ShopTab`, `ShopCard`, `ShopHeroCard`, `ShopSectionHeader`,
`PriceButton`, `Ribbon`, `ShopBanner`. Remotes: `RequestPurchase`,
`RequestGemPurchase`, `RequestGamepass`, `ShopUpdate`. Id creation + audit:
`tools/monetization/` (ledger: `tools/monetization/id_map.json` — the only record
of ids that cannot be deleted) — ⚠ the gem-priced boosts must NEVER be given one
(`docs/recipes/publish-readiness.md`). What the boosts DO: `features/boosts.md`.
