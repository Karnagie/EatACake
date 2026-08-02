---
name: squint-test
description: The BLUR TEST for game UI — heavily blur a screenshot (grayscale AND color) and check which elements survive and which dissolve into the background. MUST be used when evaluating or fixing visual hierarchy for icon-first audiences (children's games — players may not read text at all), when a UI "doesn't pop", when deciding whether backgrounds interfere, and alongside the tonal-hierarchy skill on any UI review. Uses tools/tonal-hierarchy/tonal.py (`blur` for images, `analyze` for per-region squint survival + blur-invisible findings). Fix levers are color, tone, SIZE — never outlines or text, which do not survive blur.
---

# Squint test — what survives heavy blur IS the interface

Blur a screen hard and you see it the way a child glancing at it does: as
colored MASSES. Text dissolves first, thin outlines next, then small
glyphs; what remains — big color fields, strong value steps, large icons —
is the interface a non-reader actually navigates. If the wrong things
survive (or the right things dissolve), no amount of copy fixes it.

Companion to the `tonal-hierarchy` skill (saliency measures where the eye
is PULLED; blur measures what a low-attention/non-reading pass RETAINS).
Same tool, same regions, same gate.

## Iron rules (icon-first, child-first)

1. **Icons carry meaning; text reinforces.** This audience may not read.
   Every interactive element gets a GLYPH or a distinctive color-shape
   mass that survives the heavy blur. A text-only control is a failure
   even if the text is beautiful (tab rows, "Owned" labels, price shelves
   all need their glyph).
2. **The squint ranking must match intent.** In `analyze`'s region table,
   the `squint` column (blur dL* / blur chroma) must read VISIBLE for
   every level-1/2 element and its icon, and the loudest surviving masses
   must be the CTA and the primary icons — never a background, plate, or
   decor. `blur-invisible` on a `cta`/`tab-active` region is CRITICAL.
3. **Unblurred text must stay legible** (tonal skill rules — sticker text,
   full-dark outlines), but text may never be the ONLY carrier of a
   meaning: state = glyph first (owned = check, can't afford = red price
   beside the currency glyph, buy = green mass + currency glyph).
4. **Backgrounds never interfere.** A backing field that neither survives
   blur as intended structure nor does a layout job (size-normalising a
   grid, seating a row) is REMOVED, not recolored. Blur the screen: if a
   background competes with content masses, it goes.
5. **Fix levers, in order: COLOR (hue + saturation mass), TONE (value
   step), SIZE (bigger icon / element).** Outlines, strokes and copy do
   not survive blur — never answer a blur-invisible finding with them.
6. **One glyph per concept, everywhere.** The same currency/perk uses the
   same icon in the HUD, the shop, chips and rewards — a non-reader
   navigates by matching shapes.

## Workflow

1. Capture the screen (capture paths, DPI/inset traps:
   `.claude/skills/tonal-hierarchy/references/capture.md`).
2. Quick look: `python tools/tonal-hierarchy/tonal.py blur SHOT.png` →
   `blur_color_heavy/extreme.png`, `blur_gray_heavy/extreme.png`.
   Eyeball: name what you can still identify in each. If you cannot find
   the buy button / active tab / key icons in `heavy`, they are failing.
3. Measure: `analyze SHOT.png --regions R.json` — the region table's
   `blur dL*` / `blur chroma` / `squint` columns + `blur-invisible`
   findings (thresholds: |dL*| ≥ 8 or chroma ≥ 10 post-blur = survives).
4. Fix per rule 5, re-capture, gate with `compare` (tonal skill rule 7).

## Reading the blurred images

- **color_heavy** is the main read: surviving masses = the real interface.
  Count them and name them; the list should be the intent list (CTA,
  active tab, product art, currency anchor).
- **gray_heavy** shows which of those survive by VALUE alone — anything
  that only survives in color vanishes for value-blind contexts (bright
  sun, grayscale accessibility); level-1 elements should register in BOTH.
- **extreme** is the across-the-room read: only the composition's 2-3
  biggest statements remain — they should be the panel itself, the CTA,
  and the hero art.
