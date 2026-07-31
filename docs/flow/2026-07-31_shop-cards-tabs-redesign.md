# 2026-07-31: Shop redesign — cards stop being buttons, one scroll becomes four tabs

Tags: shop, ui-kit, theme, app-root, monetization

## Task
"The UI and UX of the cards in the store are very poor. They look like
stretched-out buttons rather than actual cards. The whole interface feels
cluttered, unpolished and visually unappealing… pay attention to the card
outlines — they were clearly designed for buttons rather than cards… Figure out
why previous agents failed to notice these issues, and redesign everything
properly."

## Context
The 2026-07-30 pass (`2026-07-30_squishy-followers-shop-cards-purchases.md`)
had already replaced the button-styled `ShopTile`/`ShopPackCard` with
`ShopCard`/`ShopHeroCard`. It fixed the *palette* (per-item accent face, white
inner border) but kept the *structure*, and the structure was the problem.

## Why the previous passes missed it (the actual root cause)
`references/style-rules.md` §2 is the kit's ONE generative recipe for a new
element, and it is a BUTTON recipe:

> Outer visible: ~6% H top/left/right, **~12% H bottom** (bottom is always ~2x
> thicker — the "weight" that makes elements look physically thick).

Follow it mechanically for a card and you get a 282x296 cell with 8px of dark
outline at the top and **30px at the bottom — a 3.75x lip**, which is the
single strongest "I am a pressable slab" signal the kit owns. The kit had no
CARD recipe to follow instead, so every card in the shop inherited the button's
silhouette. The doc trail then hardened the mistake: two richer versions had
been rejected for putting a plate/well behind the icon, and the lesson was
written down as "nothing goes behind the icon", i.e. as *remove structure*. The
next pass removed the plate, kept the bevel, and shipped a flat colour field
with a bottom lip — a button, at card proportions.

Verification missed it because the panel was only ever screenshotted whole, at
which size a 30px lip reads as a drop shadow. Measuring one cell would have
shown it immediately; this pass now records the measurement (below).

## Plan
Two independent problems, fixed in order, each verified on screen:
1. **The cell** — give the kit a card recipe: even outline + internal zones.
2. **The window** — 16 items in one 5.6-screen scroll became four tabs.

## Changes

**Created:**
- `src/shared/UIKit/Components/ShopTab.lua` — category tab (gold when selected,
  muted slate when idle; gradient swap only, geometry fixed)
- `docs/flow/2026-07-31_shop-cards-tabs-redesign.md` — this doc

**Modified:**
- `src/shared/UIKit/Theme.lua` — new `ShopCardBody` (one neutral navy body +
  title/perk gradients + the gold premium frame), `ShopTab` + `ShopTabStates`;
  `ShopCard` 282x296 -> **282x338**, `ShopCardSmall` re-laid at 208x264, both
  rebuilt around an ART WINDOW; `ShopPriceCard` re-cut as a full-width shelf
  (246x52, shared by both card sizes and by the banner and hero);
  `ShopBanner` 870x200 -> 870x176 landscape card; `ShopHero` re-laid so the
  info column runs to the card's right edge; `ShopHeroItem` 138x50 -> 188x50 on
  a lightened face; `ShopSectionHeader` 56 -> 48; `ShopLayout` gained the tab
  row + `CanvasTopPadPx` and moved the balance chips into the header band;
  `ShopBannerFree` deleted (the accent is resolved inside the component now)
- `src/shared/UIKit/Components/ShopCard.lua` — rewritten
- `src/shared/UIKit/Components/ShopPanel.lua` — optional `tabs` prop (legacy
  `sections` still renders as one untabbed scroll), per-tab canvas, section
  headers suppressed inside single-section tabs, content centred when it fits,
  scroll remounted per tab
- `src/shared/UIKit/Components/ShopBanner.lua`, `ShopHeroCard.lua` — circular
  white plate -> art window; body from `ShopCardBody`; price shelf shared
- `src/shared/UIKit/init.lua` — registers `ShopTab`
- `src/client/common/modules/LocalShopService.lua` — `BuildSections` ->
  `BuildTabs`, returns Offers / Passes / Boosts / Gems
- `src/client/common/modules/AppRoot.lua` — passes `tabs`
- `src/client/common/data/LocaleData.lua` — `shop-tab-*`, `price-robux-short`
- `src/server/common/data/ShopData.lua` — small-card `desc` copy shortened to
  fit, gem packs given a perk line, the length constraint documented

## Decisions

**A CARD IS A FRAME, A BUTTON IS A SLAB.** The new rule, written into
`Theme.lua` next to the numbers so the next agent reads it before laying out a
cell: a button is one colour field with a bottom-weighted outline; a card has an
EVEN outline and INTERNAL ZONES. The card outline is now 7 top/sides and 10
bottom (1.4x — enough for the kit's physicality, far under the 2x that reads as
"press me"), and the composition is ART WINDOW / TITLE / PERK / PRICE SHELF.
Only the price shelf keeps the button recipe, because it is the only part that
is a button. Measured live: outline 5.37px top/left/right vs 8.05px bottom
(1.50x, was 3.75x).

**Colour is CONTAINED to the art window.** Six passes in six saturated hues gave
the grid no hierarchy — every cell shouted equally, which is what "cluttered"
means. The body is now one neutral navy for every card and the accent lives in
the art window alone, so a row reads as one object with N coloured windows and
the strongest local contrast sits around the product art.

**The art window is not the rejected "plate behind the icon".** Both rejected
attempts put a BADGE under the glyph (a white circle; then a well + shelf +
gloss + shadow + halo, five layers at once). The window is the card's top zone
at full content width, and it does a job nothing else can: `ScaleType.Fit` draws
at the SHORTER side of the box, so a tall flame, a wide egg cluster and a square
pack drew at wildly different visual sizes straight on the face. Icon area went
13.5% -> **22.0% measured**, identical on both card sizes.

**Tabs.** The stacked scroll was 2046 nominal px in a 367px window = **5.6
screens**, whose first screen was the balance chips, one section header and one
banner. Four tabs cap the worst at 1.9 screens and let two of the four render
with no scroll at all. The 56px the tab row costs is paid back by moving the
balance chips into the header band, which was empty either side of the title.
The tab is the section's name, so a single-section tab draws no section header.

**"Offers", not "Featured"**, as the first tab's label — that tab contains the
Free Stuff and Featured *sections*, and a tab repeating one of its own section
headers reads as a rendering bug.

**Copy length is a layout constraint.** `TextScaled` fits BOTH axes, so on a
narrow cell the WIDTH binds and long copy shrinks rather than truncating: "One
squishy, better odds" rendered at ~8px. Limits are now in the `ShopData` header
(~22 chars big card, ~15 small) and the copy was cut to fit.

**The price label lost its "R$".** `price-robux` is "R$ {n}" and the shelf also
draws the Robux glyph, so every card read "⬡ R$ 199". Buy state now uses a new
`price-robux-short` ("{n}"); OWNED / SOON keep full words because they have no
glyph.

**Content that fits is centred, and the canvas always keeps a 14px top pad.**
Four egg cards left 106px of empty panel below them and none above. The top pad
is load-bearing rather than cosmetic: a ribbon overhangs its card by up to 12px,
and with section headers gone from single-section tabs the first row starts at
canvas y = 0, where the tag would be clipped by the scroll window.

## Verification
Built an EDIT-MODE preview harness (clone `Shared.UIKit` into
`ReplicatedStorage.Shared`, require the clone, `ReactRoblox.createRoot` into a
`CoreGui` ScreenGui) so a card could be re-rendered and screenshotted in ~5s
without a playtest — the clone is what defeats `execute_luau`'s persistent
require cache, and the clone must be parented INSIDE `Shared` or every
`script.Parent.Parent.Log` require fails. Then a real playtest: clean boot
(`[Client/Bootstrap] complete`, 15/15 subscriptions, zero warnings), all four
tabs clicked through, geometry measured off the live instances.

## Adversarial review (findings fixed)
`adversarial-reviewer` over the whole change; 3 WARN + 5 NIT actioned, and its
"clean" list independently re-derived every zone sum, the freeze list, the
payload whitelist and the React key remount.
1. **Grid cells GREW past the canvas on hover/press** and a `ScrollingFrame`
   clips. The kit's card squash is `1.05 * 0.970 = 1.019` (hover) and
   `0.93 * 1.10 = 1.023` (press) about the cell centre, against ZERO horizontal
   slack — shaving ~3px off the outer columns' outline and ~10px off a
   full-width banner's, i.e. exactly the outline this pass exists to fix. Added
   `Theme.Feel.Squish.GridCell{Hover,Press}Pose` (X ≤ 1) and pinned
   `hoverScale = pressScale = 1` on all three cells. Measured after: overhang
   negative everywhere (big card −2.11 hover / −0.70 press; banner −6.52 /
   −2.17). Vertically the ribbon needs the DEFORMED offset cleared —
   `(169 + 12) * 1.03 - 169 = 17.4` — so `CanvasTopPadPx` 14 → 20. Was invisible
   only because every id is 0, so the cells are disabled and no handlers attach.
2. **`React.memo(ShopPanel)` never hit**: AppRoot passed inline `onActivated` /
   `onClose` closures, so the shallow compare failed every render. Both are now
   `useCallback`s with empty deps, and the memo comment says the contract out loud.
3. **"three of four tabs fit" was wrong** (Offers is 1.6 screens) in three code
   comments; the docs already said two.
4. **R8 gaps**: `ShopPanel` did not require `Log` at all. Added zone guards for
   the tab and balance rows (both close at EXACTLY their designed count and
   neither container clips, so an extra entry renders somewhere wrong rather
   than being cut), a warning on an unknown section `kind` (which silently
   rendered the retired button-style `ShopTile`), per-section/per-tab empties,
   and a `GraceOnce` for "no live tabs at all".
   ⚠ The first version of that logging false-positived on the pre-payload render
   — eight confident warnings per join. Empties are now collected and only
   reported once at least one tab is live; the nothing-arrived case is the
   GraceOnce. Console at steady state is exactly one accurate line
   (`section 'free' has no items` — the group reward is unconfigured).
5. **Tab selection moved from index to id** (index shifts under the player when
   an earlier tab appears/disappears), with the clamp kept as the fallback.
6. Stale comment numbers (`870x367` → `370`; `ShopPack` 248 → 264),
   `group-reward.md` still naming `BuildSections`, `price-robux` marked
   RESERVED in the registry.

## Open Questions / Followups
- Every cell still renders "SOON" — the 9 dev-product and 6 gamepass ids are 0
  (`docs/recipes/publish-readiness.md`). The buy/owned visuals were verified
  with mock data through the preview harness, not against live ids.
- `ShopTile` / `ShopPackCard` / `ShopRow` and `Theme.ShopPrice` /
  `ShopPriceWide` remain on disk, exported and unused (kit iron rule 8).

## Related
- Feature: `docs/features/shop.md`, `docs/features/ui-kit.md`
- Prior flow: `docs/flow/2026-07-30_squishy-followers-shop-cards-purchases.md`,
  `docs/flow/2026-07-26_squishy-retheme-shop-grid.md`
