---
name: tonal-hierarchy
description: Evaluate and fix the TONAL HIERARCHY of any UI — where the eye actually goes vs where it should go. MUST be used when a task asks to review/improve UI readability, visual hierarchy, contrast, clutter ("too noisy", "unclear where to look", "buttons don't stand out", "everything blends"), and as the verification step after building or restyling any panel/HUD with the roblox-ui-kit skill. Measures screenshots objectively with tools/tonal-hierarchy/tonal.py (L* value bands, saliency, per-region attention ranks, findings, 0-100 score) and gates fixes with a before/after IMPROVED verdict. Works on Roblox Studio captures and any other UI screenshot.
---

# Tonal hierarchy — make the eye land where it should

The brain processes **tonal value** (perceptual lightness, L*) before color
or detail. Squint at a screen — or look at its grayscale — and whatever holds
the strongest value contrast is what the player sees first. That contrast is
a BUDGET: spend it on the Buy button and the active tab, and the screen reads
itself; spend it on decor plates, inactive tabs and busy backgrounds, and the
screen is a "visual mess" no matter how pretty the components are.

Never argue hierarchy from the color view or from taste. **Measure it**:
`tools/tonal-hierarchy/tonal.py` (usage + metric glossary:
`tools/tonal-hierarchy/README.md`).

## Iron rules (each is measurable; the analyzer enforces them)

1. **One leader per screen.** The primary action is attention rank #1-2 with
   |dL*| >= 22 vs its surround. More than ~3 elements within 80% of the top
   saliency = nothing leads (`crowded-top`).
2. **Contrast tracks intent.** A lower-priority element never measurably
   out-shouts a higher one (`inverted-hierarchy`). If a decoration ranks #1,
   it is an `attention-sink` — quiet it; never fix by shouting louder
   elsewhere (that arms race is how screens turn into noise).
3. **Surfaces recede.** Backgrounds and card/panel bodies: internal L* std
   <= 16, decoration within ONE value band (`noisy-background`).
4. **Active state out-contrasts inactive.** The selected tab/option carries
   MORE value separation than its unselected siblings — pull inactive states
   toward the surface value; do not crank the active one up.
5. **Hue is not hierarchy.** A saturated patch whose VALUE matches its
   surround still mushes in grayscale (check `bands.png`, not the color
   view) — and a value-matched gold element vanishes even though it is
   "bright yellow". Value first, hue second.
6. **Genre conventions define intent, not taste.** A Roblox red close X is
   EXPECTED to be prominent → annotate it level 2 rather than "fixing" it.
   Write the expected reading order down BEFORE looking at the results.
7. **Every fix is gated by `tonal.py compare`** on a like-for-like
   recapture: never ship REGRESSED; a fix aimed at CRITICALs must end
   IMPROVED (they cleared, none introduced); FLAT is acceptable only when
   zero CRITICALs remain on both sides.
8. **Tonal fixes must preserve AFFORDANCE language.** Quiet an interactive
   element by lightening ITS OWN hue family while keeping its pressable
   cues (rim flash, bottom lip) — a desaturated flat wash reads DISABLED /
   locked, which is worse than loud. Conversely, a passive tag or plate
   must not wear the pressable recipe at all (flatten it — style-rules
   §2c), and a decorative backing that does no layout job is better
   REMOVED than recolored. The analyzer cannot see affordance; this rule
   is checked by eye against the kit's interaction recipes.

## Workflow

1. **Capture** the screen state to analyze — `references/capture.md`
   (Studio play mode, the edit-mode React preview harness, or any
   screenshot; includes where Studio saves captures and the DPI-scale trap).
2. **Annotate intent** — a regions JSON assigning each visible element its
   INTENDED level: 1 primary action, 2 second read (active nav, hero, key
   info, conventional controls), 3 supporting, 4 chrome/background.
   Format + role vocabulary: `tools/tonal-hierarchy/README.md`. Dump exact
   rects live from Studio via `dump_regions.luau` + `tonal.py listen`
   (see capture.md); always hand-edit levels/roles after. 15-25 regions is
   the sweet spot; wrappers get `role: container`; off-window (clipped)
   content is excluded or clipped to the visible strip.
3. **Analyze**:
   `python tools/tonal-hierarchy/tonal.py analyze SHOT.png --regions R.json`
4. **Read in this order**: `bands.png` (the squint test — do the value
   layers match intent?), `hotspots.png` (what actually grabs the eye),
   `annotated.png` (per-region intended level vs measured rank vs dL*),
   then the findings in `report.md`.
5. **Fix** per `references/fix-recipes.md` — smallest-change-first, style
   tokens only (in this project: `Theme.lua`, per ui-kit iron rules).
6. **Recapture and gate**:
   `python tools/tonal-hierarchy/tonal.py compare BEFORE.png AFTER.png --regions R.json`
   Judge the verdict by iron rule 7. 2-3 fix loops are normal.

## Reading the numbers

- `dL* vs surround` — the tonal step the eye actually gets: ~10 subtle,
  ~25 clearly separate, 40+ shouts. The shop's broken tab row measured:
  inactive tabs dL −58, ACTIVE tab dL −16 — 3.6x inverted.
- Text zones are judged by internal glyph spread (`text_contrast`,
  want >= 30), not zone mean — white-on-navy text in a navy zone is fine
  even though the zone mean blends.
- A busy world/screenshot BEHIND a panel legitimately trips
  `noisy-background` on the screen region — judge the panel's own regions
  first; consider a scrim only if hotspots actually land outside the panel.
- Kit panels with airbrush gradients run internal std ~20-30 by design;
  tune per-project via `--config` overrides rather than chasing WARNs the
  art direction accepts. CRITICALs are never "art direction".

## Scope

Applies to ANY UI screenshot (Roblox, web via the Browser pane, desktop
apps). Capture paths differ (capture.md); analysis, rules and the gate are
identical. For Roblox work this skill VERIFIES what the roblox-ui-kit skill
BUILDS — run it at that skill's Phase F/G (visual iteration / ship gate).
