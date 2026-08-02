# tonal-hierarchy — measure where a UI pulls the eye

The brain reads **tonal value** (perceptual lightness) before anything else.
Convert a screen to grayscale and the contrasts that grab attention become
obvious — and they frequently point at the WRONG elements: inactive tabs
louder than the active one, a decorative patch louder than the Buy button,
backgrounds full of noise. This tool measures that objectively and gates
fixes with a score.

**Workflow doc (mandatory for UI evaluation tasks):**
`.claude/skills/tonal-hierarchy/SKILL.md` — capture, region annotation,
fix recipes, verification loop. This README covers the tool itself.

Requires Python 3.9+ with Pillow + numpy (both present on this machine).

## Commands

```bash
python tools/tonal-hierarchy/tonal.py analyze SHOT.png --regions regions.json
python tools/tonal-hierarchy/tonal.py blur SHOT.png      # squint-test images only (gray+color, 2 strengths)
python tools/tonal-hierarchy/tonal.py compare BEFORE.png AFTER.png --regions regions.json
python tools/tonal-hierarchy/tonal.py selftest            # built-in fixtures, exit 1 on fail
python tools/tonal-hierarchy/tonal.py listen --out regions.json --timeout 120   # receive dump_regions.luau POST (JSON-validated)
```

`analyze` without `--regions` still produces the value maps + auto hotspots
(useful for a first look); findings + score need regions.

## Outputs (`<image>_tonal/`)

| File | What it shows |
|---|---|
| `gray.png` | L* (CIELAB) grayscale — the squint-test image |
| `bands.png` | L* posterized into 5 value bands + share legend — the value LAYERS |
| `saliency.png` / `saliency_overlay.png` | multi-scale center-surround contrast in L\*, a\*, b\* — where the eye is pulled (catches saturated color even when its L\* blends in) |
| `hotspots.png` | auto-extracted attention magnets (≥ P97 saliency, absolute floor 0.30), ranked by mass |
| `annotated.png` | region boxes: `name  L<intended level> -> #<measured rank>  dL<contrast>`; red halo = in a CRITICAL finding |
| `blur_color_heavy/extreme.png`, `blur_gray_heavy/extreme.png` | the SQUINT TEST as files (linear-light blur at 2.5%/5% of dim) — what survives is the interface a non-reader navigates; workflow in skill `.claude/skills/squint-test/` |
| `report.md` / `report.json` | score, findings with fixes, per-region metrics (incl. `blur dL*`/`blur chroma`/`squint` survival) |

## Regions JSON

```json
{
  "viewport": [1920, 1080],
  "regions": [
    {"name": "buy-button",  "rect": [330, 250, 190, 60], "level": 1, "role": "cta"},
    {"name": "offers-tab",  "rect": [20, 24, 120, 52],   "level": 2, "role": "tab-active"},
    {"name": "passes-tab",  "rect": [20, 90, 120, 52],   "level": 3, "role": "tab-inactive"},
    {"name": "panel",       "rect": [0, 0, 600, 400],    "level": 4, "role": "background"},
    {"name": "avatar",      "rect": [500, 10, 80, 80],   "ignore": true}
  ]
}
```

- `level` — INTENDED attention: **1** the eye must land here first (primary
  CTA — at most 1-2 per screen), **2** second read (active nav, hero, key
  info), **3** supporting (inactive nav, body copy, decor), **4**
  chrome/background (must recede).
- `role` (optional, informs rules): `cta`, `tab-active`, `tab-inactive`,
  `title`, `content`, `container`, `background`, `decor`, `chrome`. Mark
  wrappers that hold other annotated regions as `container`/`background` —
  they are measured on their OWN pixels (children masked out, rect inset)
  and skip element-vs-element rules. `chrome` (scrollbars, dividers,
  frames) also skips element-vs-element rules: infrastructure is judged by
  the background rules, not as an attention rival.
- `rect` is `[x, y, w, h]` in image px, or viewport px if `viewport` differs
  from the screenshot size (auto-rescaled).
- `ignore: true` — excluded from ranks/score (photos, avatars).
- Skeletons can be dumped live from Studio: `dump_regions.luau` via
  `execute_luau` → `tonal.py listen`. Always hand-edit levels/roles after.

## Findings

| Code | Sev | Fires when |
|---|---|---|
| `inverted-hierarchy` | CRITICAL | a lower-priority element measurably out-shouts a higher-priority one |
| `flat-primary` | CRITICAL | a level-1 element has < 22 dL* vs surround or isn't in the attention top-2 |
| `attention-sink` | CRITICAL | a level-3+ element is the #1 attention magnet (or holds >18% of saliency at high density) |
| `noisy-background` | WARN | a background/container is busy on its own pixels (L* std > 16 or saliency density > 1.3x image mean) |
| `low-separation` | WARN | a level-1/2 element sits < 12 dL* from its surround; for `title`/`text` roles the test is glyph spread instead (P95−P5 L* < 30) |
| `crowded-top` | WARN | > 3 elements within 80% of the top saliency — nothing leads |
| `stray-hotspot` | WARN | a top-2 auto hotspot lands outside any level-1/2 region |
| `blur-invisible` | CRITICAL (`cta`/`tab-active`) / WARN | a level-1/2 element dissolves under heavy blur (post-blur \|dL*\| < 8 AND chroma < 10); `title`/`text` roles exempt — text always dissolves, the ELEMENT must survive |
| `level-blend` | INFO | two adjacent levels occupy the same value band |

Thresholds live in `DEFAULT_THRESHOLDS` (tonal.py) and can be overridden per
run with `--config overrides.json`.

## Hierarchy score (0-100)

- **45** rank agreement — every (higher, lower) intent pair where measured
  saliency agrees (containers/nested pairs excluded)
- **25** primary leads — best level-1 region's attention rank (#1 = full)
- **20** background quiet — loudest background vs the top element
- **10** value layering — adjacent levels' median L* gap (target >= 12)

Components without applicable regions are dropped and the rest renormalized.
`compare` verdicts: **IMPROVED** = no new CRITICALs AND (CRITICAL count
dropped OR score +3); **REGRESSED** = more CRITICALs, or score −3 (with new
CRITICALs, or none resolved); else **FLAT**. The score is a trend indicator;
the findings are the gate.

Inversion findings are additionally gated by perceptibility: the louder
element must sit at or above the MEDIAN element saliency of its screen
(saliency is max-normalized per image, so two elements at the quiet end of
the ranking are rank noise, not a hierarchy violation).

## Interpreting metrics

- `dL* vs surround` — mean L* minus a ring around the region (~perceptual
  contrast step; 10 is subtle, 25 clearly separate, 40+ shouts)
- `sal share` — fraction of the image's total saliency inside the region
- `internal std` — L* spread inside the region (flat field ~0, busy ~20+)
- WCAG ratio vs surround is reported per region in `report.json` (text
  legibility is a separate concern from hierarchy — check both)
