# tools/monetization — create the dev products + game passes

Creates this game's **5 developer products and 6 game passes** (11 ids) on
universe **10593425705**, attaches the experience icon to the passes, and pastes
the ids back into `src/server/common/data/ShopData.lua`.

**All 11 were created 2026-07-31 and verified live.** The ids are in
`docs/recipes/publish-readiness.md` and journalled in `id_map.json`. From here the
tool's job is mostly auditing — but it stays the way new ids get made.

Until an id is non-zero the shop renders that Robux cell as the disabled **"SOON"**
state — a retention problem, not only a revenue one
(`docs/recipes/publish-readiness.md`).

## ⚠ `id_map.json` is the only record of un-deletable ids

It is committed on purpose. Neither resource can be deleted, so a lost id is an
orphan that can never be found by key again. It is rewritten after **every single
create**, before the next call.

## ⚠ ROBUX PRODUCTS ONLY — the boosts must never get an id

The four boosts (`boost-15m`, `boost-bite`, `boost-speed`, `boost-capacity`) are
bought with in-game **GEMS** (`docs/features/shop.md`,
`docs/features/boosts.md`). They carry no `devProductId` and no `priceRobux`, and
creating dev products for them would put the same item on sale twice at two
unrelated prices — **permanently**. `lucky-egg`, `mega-egg` and `instant-burn`
were removed from the catalogue outright (2026-07-31) and are gone from the script
with them.

That is enforced, not just documented: `PRODUCT_COPY` lists only Robux keys, and
`read_shopdata_prices()` runs before **every** branch of `main()` — including
`--verify` and the dry run — and exits on the first key it cannot find, that has no
id field, or whose ShopData block says `currency = "gems"`. **One stale key bricks
the whole tool**, which is the only supported way to create the ids the shop is
blocked on. Do not re-add rows to make an error go away.

## ⚠ Creation is permanent, and a DEV PRODUCT is create-once

There is **no DELETE endpoint** for either resource, and **no UPDATE endpoint for
developer products at all** — seven candidates were probed live in the reference
project and none worked. A dev product's name, description and price are **final
at creation**. A game pass can be re-PATCHed (name / price / icon) and retired
(`--apply --retire <key>` → `isForSale=false`), which is the only undo that exists.

So the script is a **dry run by default** — read the plan it prints before passing
`--apply`, and get product-vs-pass right before the POST.

## Credentials

`--auth cookie` (default) — a `.ROBLOSECURITY` session cookie plus the XSRF
handshake. Point the tool at a file holding it (`--cookie-file <path>` or
`$ROBLOSECURITY_FILE`); it is read at runtime, never printed, never copied into
the repo, and pinned to the `.roblox.com` domain so the CDN icon fetch never
receives it. **A cookie is a full account session — keep that file OUTSIDE the
repo.**

`--auth key` uses an Open Cloud API key (`$ROBLOX_API_KEY`). These are **not**
`/cloud/`-prefixed Open Cloud endpoints, so a key is unlikely to be the credential
they accept: it is allowed for reads and **refused for any write**.

## Run

```bash
python tools/monetization/create_monetization.py --preflight   # who am I, which universe
python tools/monetization/create_monetization.py               # dry run
python tools/monetization/create_monetization.py --verify      # audit ids + live prices
```

`--preflight` proves the credential and that **both** `PlaceConfig` place ids
resolve to `--universe` — monetization ids, DataStores and the teleport handoff are
all universe-scoped, so a wrong universe is unrecoverable.

`--verify` compares live id **and** live price against `ShopData` and exits
non-zero on any mismatch. It writes nothing, not even the journal.

Then, once the plan looks right:

```bash
python tools/monetization/create_monetization.py --apply --write-shopdata
python tools/monetization/create_monetization.py --apply --fix-prices --icons
```

Other flags: `--only KEY[,KEY]` (restrict the catalogue), `--limit N`,
`--force` (overwrite a non-zero id in ShopData), `--retire KEY[,KEY]`,
`--place` (which place's icon to use).

### The price gate

`--apply` creates the **cheapest** dev product first (`PRODUCT_COPY` is ordered for
this — do not put `starterpack` back at the top), reads its live price back from
the listing, and **aborts the whole run** if it does not match. That is the only
cheap moment to discover a pricing surprise, because there is no dev-product repair
path. The first pass gets the same read-back, but a mismatch there is a warning —
`--apply --fix-prices` repairs it.

### Idempotency

Three layers, because a minted id is unrecoverable:
1. `id_map.json` is **authoritative** — an entry stamped with this universe is
   adopted and never re-created.
2. Anything the ledger does not know is matched against the live listing **by
   dashboard name**.
3. An unrecognised `200` from a listing is **FATAL**, never "the universe is
   empty" — that mistake would duplicate the whole catalogue permanently.

Re-running is therefore always safe, and is also how you recover the ids if
`ShopData.lua` is ever reverted (`--write-shopdata` alone, no `--apply`).

## Facts worth knowing

| | |
|---|---|
| Base URL | `https://apis.roblox.com` — the `/cloud/`-prefixed variants some docs show are **404** |
| Create | `POST /developer-products/v2/universes/{u}/developer-products` → `productId`; `POST /game-passes/v1/universes/{u}/game-passes` → `gamePassId`. The v2/v1 asymmetry is real |
| Body | `multipart/form-data`; `name`, `description`, `price`, `isForSale`, `isRegionalPricingEnabled` — all as **strings**, booleans as `"true"`/`"false"`. Only `name` is required |
| List | `GET …/developer-products/creator?pageSize=50[&pageToken=]` → `developerProducts` + `nextPageToken`; `GET …/game-passes?passView=Full&pageSize=100[&pageToken=]` → `gamePasses` + `nextPageToken`. ⚠ **not** `cursor`/`nextPageCursor` — that form appears in the reference's throwaway probes and never advances past page 1 |
| `passView=Full` | load-bearing: without it `price` / `userBasePriceInRobux` / `displayIconImageAssetId` are absent from the rows |
| Live price field | products → `priceInformation.defaultPriceInRobux`; passes → `userBasePriceInRobux` (**not** `price`, which is null when off sale) |
| Update pass | `PATCH /game-passes/v1/universes/{u}/game-passes/{id}` — price, `isForSale` and icon all ride this one call, partial PATCH accepted, returns `204` |
| Icon | multipart part named exactly **`File`**, `("icon.png", bytes, "image/png")`, **game passes only**. Dev-product icons have no working endpoint — set them in the Creator Dashboard. (An earlier doc said the part is `imageFile`; that was carried from Dices and is unsupported) |
| Regional pricing | forced **off** on create AND `PATCH`. With it on, `price` is a seed and the base price does not come back equal to what you asked; the card would then LIE about the cost. Verified 2026-07-31: `false` at create pins the exact amount |
| Rate limits | dev-product create 3/s, game-pass create 5/s; the script throttles to ~1.4/s |
| Availability | ids are usable immediately; a **game pass 404s on the web until the experience is published** — working as intended, not moderation |
| Price | minimum 1 Robux. `price = 0` is not "free" — off-sale is the separate `isForSale` flag |
| Prices are not duplicated | the script reads every `priceRobux` from `ShopData` (R1); only the dashboard-facing name/description live in the script |
| Cross-experience | selling one universe's items inside another was disabled 2026-05-29. Both places here resolve to universe 10593425705, so one set covers both |

Endpoint behaviour above is what was observed against universe 10593425705 on
2026-07-31 and, where noted, in the reference project
(`C:\Users\vladimir\Desktop\reuploader`, 53 items on another universe).
