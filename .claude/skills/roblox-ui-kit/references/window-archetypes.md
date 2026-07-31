# Window archetypes — what the Roblox audience expects

Read this BEFORE designing any window. Pick the archetype by feature TYPE and
copy its STRUCTURE (zones, flow), then build it in the kit's style. Structure
comes from genre conventions of popular Roblox games (Pet Simulator, Adopt Me,
Blox Fruits-era menus), not from whichever kit panel already exists.

Rule of thumb: **cards/grid for collections you browse; vertical rows for
things you read and act on one-by-one; sections with headers when content has
categories; sidebar inspector when one item has rich details.**

| Archetype | Orientation | Structure the audience expects | Typical new elements |
|---|---|---|---|
| **Shop (Robux: passes + dev products)** | LANDSCAPE, TABBED card grid (see ⚠ below) | Category tabs (Offers / Passes / Boosts / Gems) over one grid per tab; item = portrait CARD (art window, title, one perk line, price shelf); featured bundle + free reward as full-width landscape cards; price shelf states buy / owned (blue "OWNED" + check badge) / unavailable (grey "SOON") / unaffordable (grey but KEEPS the glyph + amount — for a soft-currency price) | ShopTab, ShopCard, ShopHeroCard, ShopBanner, PriceButton, ShopSectionHeader |
| **Currency/coin shop tab** | Same panel, own section/tab | 2-3 columns of value-pack cards (icon, amount, price button), "BEST VALUE" ribbon on one card | PackCard, RibbonTag |
| **Inventory / Pets / Collection** | LANDSCAPE, grid | Action row (counter chip, Equip Best / Sort), 4-6 col card grid with custom scrollbar, optional inspector sidebar for selected item; rarity recolor, equipped badges, gold selection | (exists: PetsPanel / PetsInspectPanel) |
| **Settings** | PORTRAIT, list | Vertical rows: label left + toggle right (sliders later); no scroll until >6 rows | (exists: SettingsPanel) |
| **Quests / Missions** | Portrait or landscape, VERTICAL LIST | Row per quest: name + description, progress bar with "3/10" text, reward icon + amount, CLAIM button (green when ready, gray/blue when not) | build the row (the kit has NO quest row — `QuestRow`/`QuestsPanel` were deleted with the feature); ProgressBar, ClaimButton state |
| **Daily rewards** | Landscape, grid strip | 7+ day cards in a row/grid; past days checked, today highlighted (gold selection swap), future locked; big CLAIM button bottom-center | DayCard, lock/check badges |
| **Promo codes** | Small centered dialog | Text input field + green SUBMIT button, status line under input (success/error) | TextInput field (kit-styled slot + TextBox), StatusText |
| **Egg / Crate preview** | Small landscape or square | Left: egg/crate plate; right: drop list rows (pet mini-plate + name + % chance); bottom: buy buttons (1x / 3x) | ChanceRow, multi-buy button pair |
| **Upgrades / Skills** | Portrait list | Row per upgrade: name, level pips or "Lv 3/10", effect text, price button right | UpgradeRow, LevelPips |
| **Teleport / Worlds** | Landscape grid | Large location cards (image plate, name, unlock requirement), locked cards dimmed with lock badge | LocationCard, LockBadge |
| **Confirm / purchase dialog** | Small centered | Title, one line of text, item plate, two buttons: green confirm / red cancel; dims everything behind (full-screen 40% black frame) | DimOverlay |
| **HUD** | Screen overlay | Stat rows top-left (icon + colored value), menu buttons left column (icon + label), event/timer chips top-center, panels open ABOVE hud | (exists: Hud) |

If several archetypes mix (shop with tabs: Passes / Products / Coins), add a
tab column or top tab row — tabs are IconButtons/Buttons where the active tab
uses the gold selection swap (`SelectOuterGradient`/`SelectRingGradient`).

---

## Worked example: Shop (passes + dev products) — the expected design

⚠ **SUPERSEDED (2026-07-31). The shipped shop is a LANDSCAPE TABBED CARD GRID —
`docs/features/shop.md` is the live spec; read that, not this.** Three things
this section got wrong, kept here because each cost a rebuild:
1. **"NOT a card grid."** With 17 items in 5 categories a one-column list is
   the wrong archetype — this catalogue is comparison content, and the genre
   renders comparison content as per-category grids.
2. **`ShopItemRow` "layer recipe like Button"** — that instruction is why the
   cells read as buttons for two whole passes. Product cells follow the CARD
   recipe (`style-rules.md` §2b), not the button one.
3. **No tab step.** Any catalogue whose stacked canvas passes ~2 window-heights
   needs category tabs; the shop's was 5.6 and every category but the first sat
   below the fold.

Original text (portrait list, ~8 items) follows — still a fine answer for a
SMALL catalogue:

**Panel:** `PanelWithHeader`, portrait `Theme.Panel` + `Theme.Header`
(512x727 nominal), title "Shop". Content zone x 47..465, y 128..691.

**Zones (nominal px on 512x727):**
- Currency chip (player's coins, StatPill/Chip) top-right of content: y 128..168.
- Scroll list (`ScrollPane`): x 47..465, y 180..691 (window 384 wide + 12 gap
  + 22 scrollbar; track height 511). List built with `UIListLayout` inside —
  for lists use `AutomaticCanvasSize = Y` (ScrollPane default when
  `canvasHeightScale` is nil); scale-height rows are relative to canvas width
  so they are safe, unlike grids.

**New elements to create (Theme sections + components):**

1. `SectionHeader` — nominal 384x44: OutlinedText left-aligned (h 30) sitting
   on a thin underline pill (h 6, full width, dark navy `Colors.Outline`,
   corner 1) at the bottom; text uses `Header.TitleGradient`. One per section:
   "FEATURED", "GAME PASSES", "PRODUCTS".
2. `ShopItemRow` — nominal 384x96, the workhorse:
   - Layer recipe like Button (Outer corner 0.2, Rim, Face blue gradients).
   - Icon plate: light circle d 68 at x 14..82 (like PetCard.Plate).
   - Name: OutlinedText left-aligned, x 96..250, y 14..46 (h 32).
   - Description: smaller OutlinedText x 96..250, y 50..78 (h 24, neutral
     white→gray gradient `PetCard.NameGradient`).
   - Price button right: x 258..370, y 24..72.
3. `PriceButton` — nominal 112x48, aspect 2.33: green accent
   (`Theme.EquipGreen` gradients, dark green outline), coin icon
   (`Theme.Hud.Icons.Coin` ImageLabel, d 30) + amount OutlinedText, or "R$"
   prefix for Robux prices. States: normal green BUY/price; `owned` → blue
   (`Theme.Button` gradients) disabled "OWNED"; `notEnough` optional red tint.
4. `FeaturedBanner` (optional, if a featured item exists) — nominal 384x120
   full-width card: bigger plate, name + price button, Legendary gold
   gradients (`Theme.Rarity.Legendary`) for the frame.

**List assembly:** children of ScrollPane = `UIListLayout` (Padding 12/511
scale) + interleaved SectionHeaders and ShopItemRows with `LayoutOrder`.
Row height in scale: rows are scale-width 1; height = rowPx/canvas — for
AutomaticCanvasSize lists give rows a fixed scale height relative to the
WINDOW: `UDim2.new(1, 0, rowPx / windowPx, 0)` is NOT valid (scale-Y refers to
canvas). Instead give each row `Size = UDim2.fromScale(1, 0)` +
`UIAspectRatioConstraint` (aspect = 384/96 = 4.0 for rows, 384/44 for
headers) — width is stable (canvas width = window width), so aspect-derived
height is stable too. This is the LIST equivalent of the grid rows math.

**Data/props shape:** `sections = { { id, title, items = { { id, name,
description, price, kind = "gamepass"|"product", owned } } } }`, callbacks
`onBuy(id, kind)`. Purchase flow (MarketplaceService prompts) stays in
subscriptions/services — the panel only renders and calls back.

**Why not a grid:** players scan a Robux shop by reading names/prices and
comparing — a vertical list with sections is the norm in the genre; grids are
for collections of same-shaped things you already own.
