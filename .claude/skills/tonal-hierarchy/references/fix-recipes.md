# Fix recipes — per finding code

Order of operations: **quiet the loud wrong thing first**, then (only if
still needed) strengthen the right thing. Boosting the leader while the
noise stays is an arms race that ends in a louder mess.

In this project every fix is a `Theme.lua` token change (ui-kit iron rule 2)
— gradients/colors only, geometry untouched. Derive quiet variants with the
kit's accent method (style-rules §4): keep keypoint positions, move
lightness; outline = dark version of the same hue.

## `inverted-hierarchy` / rule 4 (active vs inactive states)

Pull the LOSER of the inversion toward its surround; don't crank the winner.

- **Inactive tabs / list rows**: face → a light, desaturated tint of the
  panel surface (target |dL*| vs panel <= 15-20); outline → mid, not black;
  text → mid-contrast. The selected sibling keeps the saturated face + dark
  outline and instantly leads.
- **Sibling cards all shouting**: one neutral body for every card, accent
  confined to the art window (the shop card rule — `features/shop.md`).

## `attention-sink` (decor out-ranks content)

The offender is usually a saturated PLATE behind an icon, a ribbon, or a
glow. Keep the hue, drop the VALUE contrast: darken/desaturate the plate
toward its card's value (or lighten if the card is light) until the plate
sits one band from the body, not three. The product ART stays readable —
it is the flat backing field that was shouting, not the art.

## `flat-primary` (the CTA doesn't lead)

- Give the CTA the largest value step on screen: |dL*| >= 22 vs surround
  (brighter face top + darker outline usually buys 10-15 alone).
- Its accent hue (buy-green here) appears ONCE per screen — a second green
  element halves the button's pull.
- If it still loses to something, that something is the real bug (see
  attention-sink).

## `noisy-background`

- Flatten: fewer gradient stops, decoration within one value band
  (dL* <= 10 between a surface and its ornament).
- Panel over a busy world: scrim (40-60% dark overlay) is the honest fix —
  but only if hotspots actually land outside the panel.
- Container residual noise usually = internal separators/wells too dark.

## `low-separation` (important element blends)

- Non-text: move the element's mean L* one band away from its ring
  (>= 12 dL*). Prefer moving the ELEMENT, not its surround (smaller blast
  radius).
- Text zones (`text_contrast` < 30): the glyphs, their outline, or the
  backdrop must move — the kit's OutlinedText dark outline usually fixes
  this for free; check the backdrop isn't mid-value (mid kills both light
  and dark text).

## `crowded-top`

List the competitors from the finding, pick the ONE intended leader, demote
each other competitor with the recipes above. Re-run; the leader's rank
should now be #1-2 without touching it.

## `stray-hotspot`

Open `hotspots.png`, find what the box actually contains (often: a clipped
content sliver at a scroll edge, a fallback glyph, a debug element, the
world behind the panel). Quiet or remove; if it is genuinely important,
annotate it with its real level instead.

## `level-blend` (INFO)

Assign each level a home band and check in `bands.png`:
L1 accent extremes, L2 ~one band off the surface, L3 near-surface,
L4 = the surface. Levels sharing a band is acceptable when hue separates
them AND neither carries a CRITICAL.

## Affordance recipes (iron rule 8 — the analyzer cannot see these)

- **Quiet-but-alive (interactive)**: lighten the element's OWN hue family;
  KEEP the rim flash and dark bottom lip. A desaturated flat wash on a
  button reads DISABLED/locked — measured-quiet but broken (the idle shop
  tabs shipped that way for one round; the user read them as locked).
- **Flat tag (passive)**: chips/badges/labels never wear the pressable
  recipe (dark outer pill + raised face) — flatten per style-rules §2c,
  separate from the surface by ~one value band.
- **Delete, don't recolor — then RE-CUT**: a decorative backing with no
  layout job (the hero's plate — nothing to size-normalise on a
  single-item card) is removed, not tempered. Recoloring a useless surface
  just picks a new wrong color ("dirty" antique gold was round one's
  mistake). And removal is only half the job: the freed space must be
  reabsorbed by re-running the zone arithmetic (bigger art, bigger CTA) or
  the element floats in a layout hole and the card reads as dead space.
- **Text outlines never soften.** The kit's sticker text is self-contained
  (white glyph + FULL-dark outline reads on any face). Softening the
  outline "to match a quiet surface" washes readability — flatness lives
  in the FILL, never in the text.

## Worked example (this project's shop, tonal audit 2026-08-01, 2 rounds)

Measured on the shop (`analyze`, viewport 1003x583), original -> shipped:

| Element | intent | original | shipped | fix |
|---|---|---|---|---|
| inactive tabs | L3 | dL −58, sal 0.48 | sal ~0.33, leads nothing | round 1: light wash — measured fine, READ AS LOCKED; round 2: light SKY-BLUE BUTTONS (own hue family, rim + lip kept) |
| active tab | L2 | dL −16 (gold ~ panel in L*) | dL −22, leads row | own deeper-gold face (Legendary hue, V x0.85) — a VALUE anchor, not more brightness |
| hero gold art plate | — | brightest+most saturated patch on the tab | REMOVED (`ShopHero.ArtPlate = false`) | round 1 antique gold read "dirty"; the plate had no job on a single-item hero — art sits on the body |
| hero chips | L2 | dL +6 (mush), chip recipe | flat tags, dL ~ +14 | round 1 lifted value but kept the BUTTON look; round 2 flattened per §2c |
| scrollbar | L4 | out-shouts card titles | rank last-third | thumb AND track ring pulled to the groove's value family |
| red close X, balances | L2 | rank #1 / dL −36 | unchanged | genre-conventional anchors — annotated L2, not "fixed" |

Gate (production-faithful capture, single live section => no header):
Offers `compare` = **IMPROVED** (58.7 -> 60.0, CRITICALs 2 -> 0, WARNs
10 -> 6); Passes = FLAT with 0 CRITICALs both sides. Accepted WARNs,
documented: airbrush panel/header internal std (~24-31, art direction),
art-zone low-separation (zone mean diluted by the art asset — judge by
hotspots), crowded-top on an equal-priority grid (3 identical price CTAs
are supposed to tie).
⚠ Capture fidelity lesson: a mock section that production drops (empty
"Free Stuff" => headerless tab) manufactured the only persistent CRITICAL —
make the preview match production before trusting the gate.
