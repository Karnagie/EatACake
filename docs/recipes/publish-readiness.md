# Publish readiness — what must be filled in before the game goes live

Retention is the one metric no amount of local work produces: it is a measurement
of real players returning across real days, and it only starts existing once the
place is published. This is the checklist that stands between "built" and
"measurable".

## 1. Monetization ids — ALL 11 ARE LIVE (created 2026-07-31)

Why it mattered: `LocalShopService` renders a cell with an unset id as the
**disabled "SOON" state**, so a player who opened the shop on their first session
saw a wall of dead buttons — an abandoned-looking game at the exact moment
first-session retention is decided. (The Boosts tab was the exception: gem-priced,
works before publish.)

**The universe is `10593425705`** — both `PlaceConfig` place ids
(`126172008675265` lobby, `136881957250247` game) resolve there via
`GET https://apis.roblox.com/universes/v1/places/{placeId}/universe`. Re-check any
time with `python tools/monetization/create_monetization.py --preflight`.

The ids were created with **`tools/monetization/`** (cookie auth, one idempotent
script, dry-run by default, writes the ids straight into `ShopData.lua`) and are
journalled in `tools/monetization/id_map.json` — **the only record of ids that
cannot be deleted; do not lose that file.** Audit at any time:

```
python tools/monetization/create_monetization.py --verify --cookie-file <path>
```

which compares live id AND live price against `ShopData` and exits non-zero on any
mismatch. The by-hand path (Creator Dashboard → the game → Monetization → Passes /
Developer Products → Create; icon, name, description and category all required in
the UI, price minimum 1 Robux) remains valid for anything added later.

The boot report is the in-game check: ShopSubs logs ONE
`NOT ON SALE — N product id(s) and M gamepass id(s) are still 0: …` line, which
should now be absent. Gem products are deliberately NOT in it (they need no id);
their own failure mode is a missing `priceGems`, reported on a separate
`GEM product(s) with no priceGems` line.

⚠ **The four BOOSTS (`boost-15m`, `boost-bite`, `boost-speed`, `boost-capacity`)
must NEVER be given a dashboard id.** They are bought with in-game GEMS
(`features/shop.md`, `features/boosts.md`), so creating dev products for them
puts the same item on sale twice at two unrelated prices — and **creation is
irreversible** (no delete endpoint, see below). They are absent from the table
below and from `tools/monetization/PRODUCT_COPY` on purpose; that tool hard-exits
if a gem-priced key is listed. Do not "fix" either omission by re-adding the rows.

| key in ShopData | kind | field | live id | R$ | dashboard name |
|---|---|---|---|---|---|
| `gems-s` | Dev Product | `devProductId` | 3612534244 | 100 | 100 Gems |
| `gems-m` | Dev Product | `devProductId` | 3612534248 | 400 | 450 Gems |
| `gems-l` | Dev Product | `devProductId` | 3612534252 | 900 | 1,050 Gems |
| `gems-xl` | Dev Product | `devProductId` | 3612534255 | 2000 | 2,500 Gems |
| `starterpack` | Dev Product | `devProductId` | 3612534258 | 99 | Starter Pack |
| `x2calories` | Game Pass | `gamePassId` | 1933472819 | 199 | x2 Calories |
| `x2gems` | Game Pass | `gamePassId` | 1930993460 | 299 | x2 Gems |
| `autoeat` | Game Pass | `gamePassId` | 1933322816 | 399 | Auto-Eat |
| `autogym` | Game Pass | `gamePassId` | 1932437169 | 349 | Auto-Gym |
| `capacity2` | Game Pass | `gamePassId` | 1931927238 | 249 | x2 Stomach |
| `vip` | Game Pass | `gamePassId` | 1934984583 | 799 | VIP |

The descriptions live in `tools/monetization/create_monetization.py`'s
`PRODUCT_COPY` / `PASS_COPY`, which is what the scripted path actually sends.
Prices are not repeated there at all: it reads them from `ShopData` (R1).

⚠ **A developer product is CREATE-ONCE. There is no delete endpoint and no update
endpoint either** — seven icon/update candidates were probed live in the reference
project and none worked. Its name, description and price are permanent. A game
pass CAN be re-PATCHed (name / price / icon) and retired
(`--apply --retire <key>` → `isForSale=false`), which is the only undo that exists
for either resource. Get product-vs-pass right BEFORE the POST.

⚠ **Regional pricing must be OFF at create.** With it on, Roblox treats `price` as
a seed for its own ladder and the base price does not come back equal to what you
asked — the card would print `ShopData.priceRobux` while Roblox charged something
else. Verified 2026-07-31: `isRegionalPricingEnabled=false` at create pins the
exact amount (all 11 read back correct).

⚠ **Dev-product icons cannot be set over the API — these 5 are still unset.** Add
them by hand: Creator Dashboard → Monetization → Developer Products. Game-pass
icons are set (the experience icon) via the `File` multipart part on the pass
PATCH; the previously documented `imageFile` part name was carried from Dices and
is not supported by any evidence here.

Game passes **404 on the web until the experience is published** — working as
intended, not moderation.

Also `SocialData.groupId` (`src/server/lobby/data/SocialData.lua`) — `0` means the
group-join reward is refused and its row is hidden. Still unset.

## 2. Both places must carry the place-authored content
`ReplicatedStorage.SFX`, `SoundService.BackgroundMusic`, `Assets.Environment`,
`Assets.Checkpoint` and `Assets.Items` are PLACE content (ADR-0007), not Rojo
content — they exist per place and must be present in **both** the lobby and the
game place or that place boots silent / bare. Boot warns for each (R8).

## 3. Confirm the funnel reports
Analytics is wired and verified firing (`features/analytics.md`). After publish,
check the Creator Dashboard for:
- the 6-step onboarding funnel (Joined → First Bite → First Find → First Layer →
  First Fat Burned → First Upgrade) against D1/D7 retention
- `place_minutes_game` — **this is the engagement number**, not `place_minutes_lobby`
- counters `find_collected`, `layer_cleared`, `gym_banked`, `upgrade_bought`

Where the funnel falls off is where the game leaks. That diagnosis is the whole
point of having built it, and it cannot be read before publishing.

## 4. Known-good baseline to compare against
Measured locally (`tools/headless-sim`, `pacing_scenario`): one cake is
**126 min fresh / 33 min fully upgraded**, eating + forced gym trips, excluding
boss, upgrade stops and walking. If live `place_minutes_game` comes in far under
that, players are leaving mid-cake rather than running out of content — check the
funnel step where they stop.
