# 2026-07-31: Monetization ids created LIVE (5 dev products + 6 game passes)

Tags: monetization, shop, tooling, publish

## Task
"Implement developer products and game passes in the game. You can see how it's
done here: `C:\Users\vladimir\Desktop\reuploader`" — i.e. actually CREATE the 11
Robux ids on the universe (the game-side code already existed) using the approach
proven in that reference project, and wire them in.

## Context
Everything on the code side was already built and shipped: `ShopData` catalogue,
`ShopSubs` as the single `ProcessReceipt` owner (COMMON, receipt ledger,
ADR-0014), `PassOwnershipSubs`, the four-tab shop UI. What was missing was the
**11 dashboard ids**, all still `0`, which render every Robux cell as the disabled
"SOON" state (`docs/recipes/publish-readiness.md`). `tools/monetization/` existed
but had **never been run against anything** — `id_map.json` was `{}`, `tools/` was
untracked, and its header's "verified, 53/53 items created" claim was inherited
from a different project on a different universe.

The reference `reuploader` is the project that verification actually came from: a
set of Python scripts that created 53 items on universe 10332389163 with cookie
auth. Reading it settled what the tool had guessed at. Prior flow:
`2026-07-30_squishy-followers-shop-cards-purchases.md` (money path),
`2026-07-31_gem-boosts-and-feature-cuts.md` (why the boosts must never get an id).

## Plan
1. Survey the reference and adversarially audit the existing tool — do not run it
   until the delta is known, because every create is permanent.
2. Fix the tool.
3. Read-only preflight + dry run, confirm the plan with the user.
4. Create in stages, cheapest-first, with a price read-back gate.
5. Wire, verify, document.

## Changes

**Created:**
- `docs/flow/2026-07-31_monetization-ids-live.md` — this doc

**Modified:**
- `tools/monetization/create_monetization.py` — rewritten around the proven
  endpoints; 19 defects fixed (see Decisions). New: `--preflight`, `--fix-prices`,
  `--retire`, `--only`, real price auditing in `--verify`, non-zero exit codes.
- `tools/monetization/id_map.json` — the id ledger, now 11 entries. **This file is
  the only record of un-deletable ids.**
- `src/server/common/data/ShopData.lua` — 11 ids, digits only.
- `docs/recipes/publish-readiness.md` — ids are live; the `imageFile` claim was wrong.
- `docs/features/shop.md`, `docs/MAP.md`, `tools/monetization/README.md`
- `.gitignore` — `__pycache__/`, `*.pyc`
- `docs/upstream/QUEUE.md` — 4 rows (U1)

## The ids (universe 10593425705, "Eat the Cake", HBs Interactive)

| key | kind | id | R$ |
|---|---|---|---|
| `gems-s` | dev product | 3612534244 | 100 |
| `gems-m` | dev product | 3612534248 | 400 |
| `gems-l` | dev product | 3612534252 | 900 |
| `gems-xl` | dev product | 3612534255 | 2000 |
| `starterpack` | dev product | 3612534258 | 99 |
| `x2calories` | game pass | 1933472819 | 199 |
| `x2gems` | game pass | 1930993460 | 299 |
| `autoeat` | game pass | 1933322816 | 399 |
| `autogym` | game pass | 1932437169 | 349 |
| `capacity2` | game pass | 1931927238 | 249 |
| `vip` | game pass | 1934984583 | 799 |

Every live price was read back and matches `ShopData.priceRobux`. All six passes
carry the experience icon (distinct `displayIconImageAssetId` each). The four
gem-priced boosts were verified to have received **no** dashboard id.

## Decisions

**Create with `isRegionalPricingEnabled=false` — now VERIFIED, and it is the
single most important fact here.** The reference always created with `true` and
its price audit then found mismatches on every item; it repaired the passes with a
follow-up `PATCH … false` and **never repaired the dev products, because dev
products have no update endpoint at all**. So creating a dev product with regional
pricing on permanently mis-prices it. The tool now sends `false` at create — which
nothing had ever tested — and proves it before it can do damage: the first
dev product created is the cheapest (`gems-s`, 100 R$), its live price is read back
from the listing, and a mismatch **aborts the whole run** with instructions to fall
back to the Creator Dashboard. It came back at exactly 100. Same gate on the first
pass, but there a mismatch is only a warning (`--fix-prices` can repair it).

**`PRODUCT_COPY` order is load-bearing.** The first entry is the one that proves
the pricing hypothesis, so it must be the cheapest, least important product.
`starterpack` (the hero card, 4 grants) was moved to last for exactly this reason.

**The ledger is authoritative for idempotency, the live listing is only a
fallback.** The tool used to decide "does this exist?" purely by matching the
dashboard NAME against the live listing. Two ways that permanently duplicates the
catalogue: a name Roblox normalises or moderation rewrites, and — worse — a 200
response whose body shape we do not recognise, which read as "the universe is
empty". Now: a `id_map.json` entry stamped with this universe wins outright, name
matching is the fallback, and **an unrecognised 200 from a listing is FATAL**. The
reference had the right contract all along (`create_backrooms.py`: "a key with a
truthy id is skipped — dev products & passes cannot be deleted, so never
double-create"); the port had drifted off it.

**Pagination was wrong and would have silently truncated.** The tool used
`?cursor=` + `nextPageCursor`; the working endpoints take `pageSize` + `pageToken`
and return `nextPageToken`. The reference contains BOTH forms — the `cursor` form
only in throwaway probe scripts that never had more than one page. Harmless today
(0 items), catastrophic on the second run against a populated universe.

**Icons: game passes only, and that is not a limitation we can code around.**
`PATCH …/game-passes/v1/universes/{u}/game-passes/{id}` with a multipart part named
exactly `File` is the one proven path — price, sale flag and icon all ride it, and
a partial PATCH is accepted. For **developer products the reference probed seven
candidate icon/update endpoints and adopted none**; it went on creating dev products
icon-less afterwards, which is the evidence that they were abandoned rather than
pending. The tool no longer attempts a dev-product icon; it prints where to do it
by hand. `publish-readiness.md` previously asserted the part must be named
`imageFile` — that was carried from Dices and is not supported by anything here.

**Writes are gated on `--apply`, including the ones that are not creates.**
`--icons` used to PATCH `isForSale=true` + a price onto every resolved item — even
adopted ones, even on a dry run. That silently re-enables anything deliberately
retired. Icons and price fixes are now separate, both need `--apply`, and icon-only
mode touches neither price nor sale state.

**The credential is pinned to `.roblox.com`.** `session.cookies[".ROBLOSECURITY"] =`
creates a domain-less cookie that `requests` sends to every host the session
touches — which included the rbxcdn URL the icon bytes come from. It is now set
with `domain=".roblox.com"`, and the CDN fetch uses a separate plain `requests.get`.

**`--auth key` cannot write.** These are not `/cloud/`-prefixed Open Cloud
endpoints, so an API key is very unlikely to be the credential they accept. It is
allowed for reads (cheap to find out) and refused for anything irreversible.

**`entry_span` is now scoped to its own table.** It spanned to EOF for the last
entry of each table (`["vip"]` ran to the end of the file), so a missing id line
would have spliced a digit into unrelated code. Correct before only by luck.

## Review pass — 13 findings confirmed, all fixed
A fan-out review (4 lenses) produced 32 findings; each was handed to an
independent agent prompted to REFUTE it. 19 were refuted, 13 survived.

**Tool** (would have bitten on the NEXT run, not this one):
- `--retire` performed a live PATCH **without `--apply`**, and then fell through
  into the create path — so `--apply --retire vip` on a fresh universe would have
  printed "nothing to retire" and permanently minted the whole catalogue,
  including the pass being retired. It is now a MODE that returns, gated on
  `--apply`, with a dry-run preview.
- `--fix-prices` sent `isForSale=true` to **every** pass, not just drifted ones —
  silently un-retiring anything `--retire` had taken off sale, on the README's own
  routine command. Price and icon PATCHes are now independent and neither carries
  `isForSale`; retired passes are skipped and said so.
- A dry run against a mistyped `--universe` **overwrote the ledger entry** for an
  id minted elsewhere. Reads were universe-guarded; the write was not.
- A stale ledger id borrowed the live namesake's row (`or found`), so "NOT IN THE
  LIVE LISTING" never printed and `--write-shopdata` would wire a dead id, exit 0.
- The XSRF-rotation retry had no attempt guard, so a **permission** 403 (Roblox
  attaches `x-csrf-token` to those too) span the loop and returned `(0, "")`,
  slipping past the `status in (401, 403)` credential check.

**Money path** (pre-existing, but these products are now real):
- **VIP's advertised "5 slots" was never delivered to the client.**
  `PassOwnershipSubs.PushInitialState` yields on its first
  `UserOwnsGamePassAsync`, so when `PetSubs.SendPets` ran (alphabetically later,
  same synchronous hook chain) the ownership cache was still empty and `slots`
  went out as the base 3. Nothing re-pushed it. Deterministic, every join, on the
  799 R$ product. `applyOwnership` now re-pushes pets as well as the shop.
- **One throttled `UserOwnsGamePassAsync` disabled a paid perk for the whole
  session** — absent is indistinguishable from false everywhere downstream and
  there was no retry. A full lobby teleports 4 players = 24 sequential calls in a
  burst, so the throttle is routine. Now 3 attempts with backoff, and the
  give-up warns per occurrence.
- **`RequestPurchase` had neither the profile-loaded nor the teleport-release
  guard** that the gem path has carried since ADR-0015. `IsOneTimeOwned` returns
  false when the profile is absent, so an owner could be prompted to buy the
  one-time Starter Pack again. Both guards added, ahead of the `oneTime` check.

**Docs:** `shop.md` still asserted every Robux id was 0 eight lines under the new
"all 11 are LIVE"; five QUEUE rows were missing the Status column that harvest
filters on; `.gitignore` named the API key as the tool's secret while the real one
is now a session cookie (patterns added for it).

## Open Questions / Followups
- **Dev-product icons are still unset** — no working API endpoint exists; add the
  5 icons via Creator Dashboard → Monetization → Developer Products.
- `SocialData.groupId` is still `0` (group-join reward hidden). Out of scope here.
- Game passes **404 on the web until the experience is published**. Expected, not
  moderation.
- Pass icons are all the experience icon. Per-product art would read better on the
  Store page; the same `--icons` path takes any PNG.
- **A gamepass bought OUTSIDE our own prompt** (Roblox website, a share link, the
  in-experience Store) does not register until the next place transition —
  ownership refreshes only on join and on `PromptGamePassPurchaseFinished`, and
  there is no re-poll. Largely masked by the frequent lobby↔game teleports, which
  is why it was left; a periodic re-check is the fix if it ever bites.
- No purchase/revenue analytics beat is emitted (`AnalyticsSubs` is wired for the
  onboarding funnel only), so the Creator Dashboard is the only revenue view.
- Not yet playtested in Studio against a real purchase prompt — the ids are
  verified live via the API, not yet via `MarketplaceService`.
- `create_monetization.py` is ~1100 lines. It stays ONE file deliberately (it is
  copied wholesale into a new game), but that is well past the R7 guideline.

## Related
- Feature: `docs/features/shop.md`, `docs/recipes/publish-readiness.md`
- ADRs touched: ADR-0014 (receipt safety), ADR-0015 (gem path)
- Prior flow: `2026-07-31_gem-boosts-and-feature-cuts.md`,
  `2026-07-30_squishy-followers-shop-cards-purchases.md`
- Reference project: `C:\Users\vladimir\Desktop\reuploader` (not in this repo)
