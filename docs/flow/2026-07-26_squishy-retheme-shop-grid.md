# 2026-07-26: Squishy re-theme — icon library, landscape grid shop, squishy collection

Tags: ui-kit, shop, pets, app-root, economy, theme, icons

## Task
"The entire game needs to be re-themed around squishies. I already have an
established visual style — create new elements in that style, improve the
existing windows and UI elements. The shop is very narrow and shows everything
in a single row; it should look like the shops in popular Roblox games — it can
still be a long scrollable list, but each category should contain multiple rows
(e.g. a game pass section as a 2×3 grid). Use popular Roblox games as
references. The interface should be intuitive enough that players immediately
understand where to click." Icons supplied in four local sprite packs.

Direction confirmed with the user before building: **squishy = the collectible
(pets → squishies)**; cake/eating gameplay unchanged. Priority: shop first, then
first-30-seconds clarity.

## Context
- `ShopPanel` was a portrait 512×727 list of identical 418×88 `ShopRow`s. On
  16:9 that is **36% of screen width** (`calculateScale(0.704, 0.92)`), one item
  per row, no icons, `subText` hardcoded `""` at `LocalShopService:26/:42`, and
  `ScrollWindowFraction 0.96 + ScrollBarWidth 0.05 = 1.01` (the bar overlapped
  the window).
- All eight HUD menu buttons rendered the SAME placeholder asset.
- `Theme.Rarity.Common` was an alias of `Theme.Button` — a Common card was
  pixel-identical to every button, row and chip in the kit.
- No icon assets existed beyond 5 HUD placeholders.

## Plan
1. Get the sprite packs onto Roblox and behind a named registry.
2. Rebuild the shop on the archetype the genre actually uses (hero banner +
   per-category grids in a long scroll), reusing the existing panel chrome.
3. Re-theme pets → squishies as **display-only** (ids are DataStore keys).
4. Verify each window in play mode; iterate.

Design was produced by four parallel briefs (shop / HUD / theme system /
retention audit), each passed through an adversarial critique, then synthesized.
Three critique findings changed the build materially — see Decisions.

## Changes

**Created:**
- `src/shared/UIKit/Icons.lua` — 145-entry icon registry (name → rbxassetid),
  exposed as `Theme.Icons`; `Theme.Icon(name)` resolves with an R8 warn-once and
  a visible fallback glyph.
- `src/shared/UIKit/Components/ShopSectionHeader.lua` — icon + label + count
  over an underline pill.
- `src/shared/UIKit/Components/ShopTile.lua` — 282×160 pass/product cell,
  icon left / name + perk + price right. Whole cell is the tap target.
- `src/shared/UIKit/Components/ShopPackCard.lua` — 208×248 currency pack,
  portrait, with a RESERVED ribbon band.
- `src/shared/UIKit/Components/ShopBanner.lua` — 870×200 hero cell, gold (paid)
  / green (free) accent.
- `src/shared/UIKit/Components/PriceButton.lua` — icon + amount; states
  buy / owned / **unavailable**.
- `src/shared/UIKit/Components/Ribbon.lua` — corner tag, kit primitives.

**Modified:**
- `src/shared/UIKit/Theme.lua` — `Icons` + `Theme.Icon()`; `Feel.Squish`;
  rarity block hoisted above its consumers; `Rarity.Common` restructured and
  re-hued; `Rarity.Secret` hue-shifted −42°; per-tier `Outline`/`Text`/
  `IconDisc`/`IconStar`; `ShopLayout` replaced with the landscape/deterministic
  version; new `ShopSectionHeader`/`ShopTile`/`ShopPack`/`ShopBanner`(+`Free`)/
  `ShopPrice`(+`Wide`)/`ShopPriceStates`/`ShopRibbon`; `AppHud.MenuIcons` given
  eight distinct icons; `Badge.IconInset`; `PetCard.IconInset`.
- `src/shared/UIKit/Interaction.lua` — opt-in squash: `FullSize`,
  `resolveSquash`, third `squashRef` return, squash reset in the disabled path.
  (`squishLayer`/`useIdleBreath` and the panel/reward/idle poses were built, then
  removed in review: no call sites, and `Squish.PanelOpenTween` shadowed the live
  `Feel.PanelOpenTween` that `PanelShell` reads.)
- `src/shared/UIKit/Components/ShopPanel.lua` — rewritten (deterministic canvas).
- `src/shared/UIKit/Components/Badge.lua` — optional `iconName` (owned check).
- `src/shared/UIKit/Components/PetCard.lua` — optional `iconName`.
- `src/shared/UIKit/Components/PetsInspectPanel.lua`, `PetRevealOverlay.lua` —
  pass squishy art through (reveal shows art only once the spin lands).
- `src/shared/UIKit/init.lua` — register the six new components.
- `src/shared/config/PetConfig.lua` — roster 12 → 30 with `icon` per entry; dead
  `rarities[].color` removed.
- `src/server/common/data/ShopData.lua` — `desc`, `icon`, `best` per entry;
  `featured` split into `featured` / `eggs` / `gems`.
- `src/server/lobby/subscriptions/ShopSubs.lua` — payload carries
  `desc/icon/best/configured`.
- `src/client/common/modules/LocalShopService.lua` — rewritten view-model
  (sections carry `kind`, cells carry state/ribbon/icon).
- `src/client/common/modules/LocalPetsService.lua` — `iconName` through.
- `src/client/common/modules/AppRoot.lua` — `shopScale` (landscape) + refit;
  `shopBalances`.
- `src/client/common/data/LocaleData.lua` — squishy rename (display only) + 18
  new roster names + `btn-soon` / `ribbon-*` / `shop-section-gems|eggs`.

## Decisions

**Reused `PanelWide` instead of a new 1280×800 panel family.** The shop brief
specified `Theme.PanelBig`. `calculateScale` pins height to
`maxFraction × viewportH` regardless of aspect, so on 16:9 a 1.6 panel renders
1624×1015 while the existing `PanelWide` at the same fraction renders
**1692×1015** — the bespoke family would have been NARROWER while costing a
second chrome family to maintain. Verified against `AppRoot.lua:152-160` before
discarding it. The synthesis doc kept `PanelBig` on a "grid granularity"
argument; the 870-px canvas divides cleanly for both grids (below), so that
argument does not hold either.

**The canvas is deterministic, not automatic — and this was measured, not
assumed.** The list-with-aspect-constraints version was built FIRST and failed:
an aspect constraint fits within `(windowWidth, seedFraction × canvas)`, the
canvas is what the cells are growing, and the fixed point that converges is one
where the height binds. Measured: 377-px rows inside a 596-px window, all four
row kinds collapsed to the same height. `ShopPanel` now sums the section heights
in nominal px, sets `canvasHeightScale`, and positions every cell by explicit
fraction. Consequence: **no `UIListLayout`, no `AutomaticCanvasSize`, no
`UIGridLayout` and no aspect constraints inside the scroll** — all three of the
kit's grid pitfalls are structurally impossible here rather than worked around.

**Zone arithmetic (all sums close).**
```
panel 1000x600 (PanelWide + HeaderWide), maxViewportFraction 0.92
content x 48..952 (904), y 132..559 (427)
  balance 48 · gap 12 · pane 367            48 + 12 + 367 = 427 ✓
  pane:  window 870 + gap 12 + bar 22       = 904 ✓
canvas 870 wide:
  tiles  3*282 + 2*12 = 846 + 24            = 870 ✓
  packs  4*208 + 3*12 = 832 + 36            = 868 (2px slack, pitfall 6)
  tile   282x160  banner 870x200  pack 208x248  section header 870x48
```

**Only `Rarity.Common` and `.Secret` moved.** `Rarity.Rare` IS `EquipGreen`,
`.Epic` IS `EatButton`, `.Legendary` IS `HexTree.available`, `.Uncommon` IS
`HexTree.back` — re-hueing any of those four re-skins the gym, the eat button,
the upgrade tree and every confirm button in the game. Verified by grep before
touching anything. Common was re-hued to **warm foam cream (H 30°, S≈0.13)**,
not grey: a cool grey satisfied "stop looking like a button" but landed straight
in the hex tree's locked/disabled palette (`hexGrayFace` H 215°, S 0.16). Both
separations are published in the Theme comment. Secret went −42° to violet-void
because it sat only 11.9° from Epic magenta.

**Not one persisted identifier changed.** `pets.owned` is keyed by PetConfig
`id`, so ids are DataStore keys. The re-theme edits only the right-hand side of
`LocaleData`. The roster grew 12 → 30 by **adding** ids, which needs no
migration (a new id is simply absent from everyone's `owned`); `PetsSection`
stays v1. Renaming or removing an id would have required a version bump plus a
`migrations[1]` remap — deliberately avoided.

**The `unavailable` price state is a bug fix, not decoration.** Every
dev-product and gamepass id in this project is still `0`. The old shop rendered
a live green BUY button whose purchase `ProcessReceipt` refused, so pressing it
did nothing visible — a silent failure, which R8 calls a bug. The server now
sends `configured`, and the button renders a grey disabled "SOON".

**Owned no longer dims the whole cell.** `ShopRow` wrapped the entire row in a
`CanvasGroup` at 0.22, fading the product name with it; `UpgradeRow:68` already
documents that as the wrong pattern. Owned now = blue "OWNED" button + a green
check badge, name fully readable.

**The corner tag is drawn, not imaged.** `Ribbon*.png` turned out to be a
square 257×257 rosette; at the tag's 4:1 aspect `ScaleType.Fit` rendered it as a
40×40 blob behind the label (seen in iteration 1). Rebuilt from the kit's own
Outer/Face/OutlinedText recipe, which is also closer to the kit's rule that
chrome is frames and images are icons.

**Squash rides `Content.Size`, opt-in.** `UIScale` is uniform and cannot squash.
`Interaction.pressLayer`'s `Content` frame is the one ADR-0006-safe carrier:
React writes its `Size` exactly once with the constant `Interaction.FullSize`
and then diffs it away forever. `config.squash` is read through a REF, never the
memo deps, so handlers stay stable across the HUD's ~14 re-renders/second. The
disabled-reset path restores `Size` as well as `Scale`, or a button gated mid-press
would stay permanently flattened.

## Verify
Play mode, lobby place, 4 iterations. Console silent (no React errors, no icon
misses; the remaining warnings — unconfigured product ids, unset `groupId`, and
the pre-existing `burn` grant-handler gap — are all correct and pre-existing).
Measured: passes render 3 columns × 2 rows at x 0/201/403, gems 4 columns at
x 0/151/301/452, canvas 989 in a 251 window.

Fixed across iterations: header `Size` passed as a number not a UDim2 (React
threw); rows collapsing under aspect constraints; ribbon art blob; green "SOON";
perk copy wrapping to two lines (TextScaled forces TextWrapped — copy shortened
to ≤26 chars); price button off-centre in its column; gem pack art not reading
as a progression (L/XL were a crate and a bag — repointed to 4/6).

## Open Questions / Followups
- **HUD first-30-seconds is only half done.** Menu icons + labels landed (the
  biggest single win — eight identical placeholders → eight distinct glyphs).
  The new-player objective/nudge element from the HUD brief is NOT built.
- Currency pills still use the vector bolt/coin glyphs. Swapping the calories
  icon to an image also desynchronises `HexTreeOverlay`, which reads the same
  StatPill icon — do both together or neither.
- `Theme.Accents` semantic layer (decoupling `Rarity.*` from `EquipGreen` /
  `EatButton` / `HexTree`) is designed but NOT applied: it is a refactor of
  working code with no player-visible change. Queued upstream instead.
- Squash is wired into the new shop cells only. `PanelShell` jelly open/close,
  idle breathing and `DayCard` press feedback are NOT built: shipping unused
  animation API is what the review removed. `PanelShell`'s root `Size` is a live
  React prop, so its variant needs an inner constant-sized frame — build it with
  its caller, and do not name its tween `PanelOpenTween` (that shadows the live
  `Theme.Feel.PanelOpenTween`).
- Gems still have no in-game sink, so the shop's "not enough currency" state is
  currently unreachable.

## Related
- Features: `docs/features/shop.md`, `docs/features/pets.md`,
  `docs/features/ui-kit.md`, `docs/features/app-root.md`
- ADRs touched: ADR-0006 (animation ownership — squash extends it)
- Prior flow: `docs/flow/2026-07-22_lobby-matchmaking-rounds.md`

---

## Follow-up pass: sizing + real squishy art (same day)

User feedback: "1 icons on hud too small · 2 icons everywhere too small ·
3 for example time rewards: panel is big, but buttons too small, so many free
space · 4 here's icons for squishies" (renders in a local `Squishy renders` folder).

**Measured first, then fixed.** Every number below is from play mode, not taste.

| | before | after |
|---|---|---|
| HUD menu cell / drawn icon | 48px / **35px** | 64px / **48px** |
| shop tile plate / icon | 54 / 37 (68%) | 60 / **53 (88%)** |
| shop pack plate / icon | 52 / 39 (76%) | 62 / **56 (90%)** |
| banner plate / icon | 115 / 101 | 115 / **101 (88%)** |
| squishy card plate / icon | 49 / 39 (80%) | 56 / **52 (92%)** |
| reward card | 78x90 | **143x114** |
| reward grid fill | 100% w, **37% h** | 100% w, **98% h** |

**Why the icons were small: `ScaleType.Fit` letterboxes a square image into the
zone's SHORTER side**, so a short-and-wide icon zone throws its width away. The
HUD menu icon zone was `(1, 86/118)` of a roughly square button — the height
capped the glyph at 73% of the button. Fixed by growing the button (92x100 ->
124x132 on the 1920x1080 grid) AND making the zone near-square (100x96 nominal).
Everything else was an over-cautious `IconInset`: 0.16/0.12/0.10 -> 0.06/0.05/0.04,
plus bigger plates (tile 80->88, pack 76->92, banner 150->168, PetCard 76->88).

**Time Rewards was the worst case, and it was a LAYOUT bug, not a scale one.**
`RewardsLayout` reserved a 904x360 grid zone and then put a single row of
118x135 cards in it, so 62% of the zone was empty. N columns across a fixed
canvas caps the card WIDTH regardless of how much vertical room exists — 7
columns on 904 caps a card at 117px — so the fix was fewer columns over two rows
(4 cols, `4*214 + 3*16 = 904` OK; `2*172 + 16 = 360` OK) with the card re-cut
LANDSCAPE (214x172) and the reward band turned into art + amount. The portrait
118x135 `DayCard` was deleted rather than left beside its replacement: two live
definitions of one Theme key is a trap even when the later one wins.
Residual, accepted not overlooked: 6 time-reward cards in a 4-wide grid leave two
empty slots on row 2. `UIGridLayout` left-aligns a partial row and cannot centre
it, and the cards are already at the maximum size the panel height allows.

**Real squishy art replaced the food-vector placeholders.** 48 character renders
(256x256, already carrying the kit's thick dark outline) uploaded and swapped in.
The 30 existing ids were RE-POINTED at a render of the same tier (ids are
DataStore keys — untouched) and 18 costumed ones added as new ids, so the roster
is 48 with no migration. Display names were rewritten to describe the art:
leaving "Grid Waffle" on a sun-hat squishy is worse than the placeholder was.
**Two renders were deliberately NOT used** — `Decalpart102` (Naruto) and
`Decalpart152` (All Might) are recognisable third-party characters and risk a
moderation takedown of the asset and the place.

**A regression the screenshot caught.** `AppHud.MenuIcons.Squishies` pointed at
`Icons.SqGummyBearRed`, a name the art swap retired, so it resolved to nil and
the button silently fell back to the generic placeholder — a cardboard box on the
collection button, i.e. precisely the unreadable state this task existed to fix.
Repointed, and Theme now WARNS at load for any menu icon that does not resolve,
because that failure is invisible in code review and looks like a design choice
in the running game.
