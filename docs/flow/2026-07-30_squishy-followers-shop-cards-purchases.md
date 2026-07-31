# 2026-07-30: Squishy followers, shop product cards, real purchases

Tags: pets, shop, ui-kit, app-root, persistence, monetization, config, tooling, split

## Task
Three requests, verbatim:
1. "Equipped squishies should fly behind the player, both in the lobby and during gameplay."
2. "Improve the shop UI. What I don't like: the item frames — for example, the
   Pass, 450 Gems, etc. — look bad because they use a button-style design. Create
   a new UI element for these items that fits better. Also, give the Starter Pack
   a unique design. Use references as much as possible for the UI and do not
   invent anything from scratch." (three competitor store screenshots supplied)
3. "Add purchases to the game." (dashboard link for experience 10593425705)

## Context
- Followers existed (`PetFollowers`) but rendered coloured primitives and were
  stepped from `BodySubsClient`, which early-returns without the game partition.
- Shop was the landscape sectioned grid from `2026-07-26_squishy-retheme-shop-grid`,
  with cells built on `Theme.Button` gradients.
- All 15 monetization ids were 0; `docs/recipes/publish-readiness.md` listed them.
- Opened with a 4-agent recon workflow (followers stack / shop UI stack /
  monetization audit / Open Cloud research) before touching code.

## Plan
1. Move the follower step to a common sub; rebuild the motion as a trailing arc
   behind the player; wire the authored 3D models the user pointed at.
2. New kit cell components derived from the references, per the roblox-ui-kit
   method (brief → check-sum zone arithmetic → build → visual iteration).
3. Fix the money path first, then create the ids via Open Cloud.

## Changes

**Created:**
- `src/shared/UIKit/Components/ShopCard.lua` — universal product cell
- `src/shared/UIKit/Components/ShopHeroCard.lua` — Starter Pack, with the bundle row
- `tools/monetization/create_monetization.py` + `README.md` — Open Cloud id creation
- `docs/decisions/0014-common-receipt-handling.md`

**Modified:**
- `src/client/common/modules/PetFollowers.lua` — rewritten: authored models, arc
  behind the player, trail/bob/bank, idle look-back, lazy prepared templates
- `src/client/common/subscriptions/PetsSubsClient.lua` — owns the RenderStepped step
- `src/client/common/subscriptions/BodySubsClient.lua` — step removed
- `src/shared/config/PetConfig.lua` — `follow` block; `model` on all 48 pets
- `src/shared/config/PlaceConfig.lua` — universe comment corrected to 10593425705
- `src/shared/UIKit/Theme.lua` — `ShopCard`, `ShopCardSmall`, `ShopCardAccents`,
  `ShopPriceCard`, `ShopHero`, `ShopHeroItem`, `ShopLayout` card metrics, freezes
- `src/shared/UIKit/Components/ShopPanel.lua` — `hero`/`card`/`smallcard` kinds,
  one `metricsFor` table shared by the height sum and the placement loop, full
  prop forwarding
- `src/shared/UIKit/init.lua` — exports the two new components
- `src/client/common/modules/LocalShopService.lua` — new kinds, `accent`, `bundle`
- `src/server/common/data/ShopData.lua` — `accent` per entry, `bundle` on the
  starter pack, `receiptLedgerSize`, duplicate-id warnings
- `src/server/common/data/ProfileSchema/ShopSection.lua` — `receipts` ledger
- `src/server/common/subscriptions/PassOwnershipSubs.lua` — `ApplyPerkAttributes`
- `.gitignore` — secret-file backstop

**Moved (lobby → common):**
- `src/server/lobby/services/ShopService.lua` → `src/server/common/services/`
  (+ `IsReceiptHandled` / `MarkReceiptHandled`)
- `src/server/lobby/subscriptions/ShopSubs.lua` → `src/server/common/subscriptions/`
  (+ release-nonce guard, receipt ledger, per-kind descriptor validation,
  mid-session pass perks, one-line boot report)

## Decisions

**Followers.** The lobby bug was structural, not a tuning miss: `PetFollowers.Step`
had exactly one caller, inside a `Start` that returns early without
`GameUiData`. Moving it to `PetsSubsClient` (common, unconditional) fixes both
places at once; the old call site had to be DELETED, not left, because the
combined dev build maps both partitions and would have stepped twice.

Three numbers were measured in play rather than reasoned, and all three were
wrong on the first guess: `yawOffsetDegrees` (faces came out at −1.00 dot the
player's look), `heightStuds` (at +3.0 the formation completely hid the player;
even +0.8 covered the torso — the camera sits behind and above), and the welding
strategy (several models nest parts inside other parts, so a welded assembly
left every mesh at its authored map coordinates while only the root flew;
`Model:PivotTo` on 1–6 anchored parts is both correct and cheap).

Facing blends on speed — forward while running, turned to look at the player
while idle — interpolated as a yaw ANGLE, because the two ends are exactly
opposite and a direction-vector lerp is zero-length at the midpoint.

**Shop cards.** The user's diagnosis was exactly right and the cause was one
line per style table: `ShopTile`/`ShopPack` pointed Outer/Rim/Face at
`Theme.Button.*`. The fix keeps the kit's layer recipe and repurposes the RIM as
the white inner border the reference art has, freeing the FACE to carry a strong
per-item colour. Every accent is an existing kit set (rarity ladder + Button
blue) — no new palette, per style-rules §4/§7.

Two card sizes (3-across passes, 4-across eggs/gems) because it is the only
split where every row is full; a shared column count always left an orphan.

Colour is DATA (`ShopData.accent`), not a lookup table in the view-model — which
product wears which colour is a catalogue decision (R1). It needed a line in
`ShopSubs.shopPayload` too: that whitelist silently drops anything not listed.

The BEST VALUE ribbon started over the art and was moved into the empty band
above the price after the screenshot showed it covering a quarter of the gem
cluster — the exact bug `ShopPack`'s reserved band was written to prevent.

**Money path.** ADR-0014. The blocking finding was that `ProcessReceipt` existed
only in the lobby, so any receipt surfacing in a game server was dropped with no
console trace; the deeper one was that re-delivered receipts double-granted
every consumable. Both fixed before touching the dashboard, on the principle
that turning on real money over a path with known silent-loss cases is the wrong
order.

**Id creation.** Roblox shipped Open Cloud create endpoints on 2025-12-04
(verified live: the routes 403 without auth, and the `/cloud/`-prefixed variants
some docs show are 404). The script is idempotent, dry-run by default and reads
the key from the environment, because there is NO delete endpoint — a mistyped
product is permanent.

## Adversarial review (40 agents, 4 lenses, every finding refutation-checked)
36 findings raised, 18 confirmed, 18 refuted. Fixed here, all confirmed:

| Sev | What | Fix |
|---|---|---|
| CRITICAL | `PetFollowers.prepare` cached the placeholder fallback FOREVER when `Assets.Squishes` was merely LATE — one replication race would have degraded every follower for the session, defeating the lazy resolve it sits next to | only SUCCESS (and the genuinely-empty-model config error) is cached; not-found retries |
| WARN | `PurchaseGranted` was returned before the write was durable — `Save` is a `task.spawn`, so a crash in that window took the Robux with the grant only ever in memory, and no retry (Roblox had already seen PurchaseGranted) | new `PersistenceService.SaveAndWait`; `NotProcessedYet` when it does not confirm, in the already-handled branch too |
| WARN ×2 | `ShopCard`/`ShopHeroCard` headers promised a one-shot warn on an unknown `accent` and never warned; hero bundle chips past `BundleColumns` vanished silently | new `Theme.ShopAccent(name)` (same contract as `Theme.Icon`); `Log.Once` on bundle overflow |
| CRITICAL (pre-existing) | `instant-burn` can never deliver where it is sold: lobby-only shop, game-only `burn` handler, and the run reset empties the belly anyway | excluded from the creation script with the reasoning inline — no irreversible id gets made for it |
| NIT ×4 | stale comments: `-- optional (LOBBY only)` in PassOwnershipSubs, a weld reference in PetFollowers, `168x56` in `Theme.ShopPriceCard`, the ShopUpdate payload shape missing `accent`/`bundle` | corrected |

Confirmed but OUT OF SCOPE (they belong to the previous, still-uncommitted
session — reported, not touched): `TreasureService.lua` is 1005 lines against
R7's ~300; `TreasureConfig.spawn.perBandJitter` and `model.sourceParent` are dead
config; the reveal/free threshold comment says MAX where `coverStats` returns
MIN; find emitters/lights switch on at `loaded` while still buried; the
`find-<id>` locale keys the registry promises do not exist; and AppRoot's header,
`UpgradesUiData`'s header and `features/upgrades.md` still describe an Upgrades
HUD button that was removed.

## Second pass on the cards — "still basically the same buttons"
The user rejected the first redesign, correctly. Recolouring the kit's three
button layers is not a card. Measured, that version:
- split its chrome ink 18.4 / 5.5 / 76.0 % against `Theme.Button`'s
  20.3 / 4.9 / 74.8 — INSIDE the button family's own spread;
- used `Theme.Button` BY REFERENCE as its default accent;
- drew the product at 10.50 % of the cell and the buy button at 10.47 %;
- CONTAINED a `PriceButton` — a brighter, more saturated pressable firing the
  same callback as the card;
- resolved to 2 separable surfaces, with the "art plate" only a 14.4-14.8 %
  luminance step on Common and Legendary (7 of 16 products are Legendary).

Researched the genre (Pet Sim 99, Steal a Brainrot, Clash Royale, Royal Match,
sim UI asset packs) plus the pure-gradient technique for faking depth. The fix
is COMPOSITION, not colour — five zones, and two of them do the work:
- **a recessed art WELL**, landscape, gradient inverted DARK-top → LIGHT-bottom
  (a recessed surface catches light at its floor). Derived per accent from that
  accent's own `Outer`, so contrast is guaranteed: 55-71 % vs 14-30 %. Secret
  overrides to a light well because its face is already dark.
- **a full-bleed price SHELF** flush with the card's own edges, replacing the
  nested `PriceButton`. Flush = zone; inset with margin = control.
Plus two unequal non-parallel gloss bands, a contact shadow, art at 15.6/19.7 %
(up from 10.5/11.4) overhanging the well, the ribbon moved to overhang the card's
top edge, and a gold `premium` halo on `vip` + `gems-xl` only.

Three bugs found by rendering it, not by reading it:
1. `local a, b = if c then f() else g()` **truncates to one value** in Luau — the
   price label got a nil size and rendered at zero height. Invisible price, no
   error. Now a statement.
2. The perk band ran INTO the divider band (190..208 vs 204..208).
3. Peak sheen alpha 0.14/0.08 was invisible over a saturated face; lifted to
   0.26/0.16.
Also re-spread the accents — `boost-15m` was gold sitting next to the gold gem
row, so the two sections bled together.

Verified in play: all three states, the gold premium frame, the Secret light-well
override, BEST VALUE overhanging without covering art, console clean — and the
card CLICK end-to-end (`RequestGamepass fired: x2gems`, server refused it for the
unset id), which was the one thing left unverified last pass.

## Open Questions / Followups
- **The 15 ids are not created yet**: the user chose the Open Cloud route but
  the API key has to be generated by them (`tools/monetization/README.md`).
- `instant-burn` is worth reconsidering as a product: `RunResetSubs` empties the
  belly on every profile load, and the shop is opened from the lobby where the
  belly is already empty. It now delivers (deferred to a game server) rather
  than failing, but its value is thin.
- The `PetConfig.model` → `Squishy N` map is a visual best-effort; plain colour
  drops are worth a second pass. Models 34 and 48 are unused.
- Studio MCP dropped mid-session before the shop cell CLICK could be confirmed
  end-to-end (the render, all three states and the console were verified). The
  wiring is byte-identical to the shipped `ShopTile`, but it is unverified.
- `priceRobux` is still display-only; nothing reconciles it against the
  dashboard. One deferred `GetProductInfo` per configured id would.

## Related
- Features: `docs/features/shop.md`, `docs/features/pets.md`
- ADRs: ADR-0014 (new), ADR-0009, ADR-0007, ADR-0002
- Recipe: `docs/recipes/publish-readiness.md`; tool: `tools/monetization/`
- Prior flow: `docs/flow/2026-07-26_squishy-retheme-shop-grid.md`
