# 2026-08-01: Tonal-hierarchy toolkit + skill; shop tonal retune

Tags: tooling, ui-kit, shop, theme, skill

## Task
"The brain processes tonal value first — grayscale a UI and the wrong
elements grab attention (inactive tabs louder than the active Offers tab,
the Starter Pack internally mushy, the yellow gift plate out-shouting the
buy button; Passes a visual mess). Create a skill and tools to evaluate
tonal hierarchy, identify problems and improve interfaces."

## Context
Shop UI per `2026-07-31_shop-cards-tabs-redesign.md`; kit style rules in
`.claude/skills/roblox-ui-kit/`. No objective way existed to measure where
a screen pulls the eye.

## Changes

**Created:**
- `tools/tonal-hierarchy/tonal.py` — analyzer CLI (PIL+numpy, no other
  deps): CIELAB L* value maps, 5-band posterization, multi-scale
  center-surround Lab saliency, per-region metrics vs intent annotations,
  findings engine (8 rule codes), 0-100 hierarchy score, before/after
  `compare` with IMPROVED/FLAT/REGRESSED gate, 13-check `selftest` on
  synthetic fixtures (exit 1 on fail), one-shot HTTP `listen` receiver.
- `tools/tonal-hierarchy/dump_regions.luau` — Studio GUI rect dumper
  (execute_luau → POST to `listen`); skeleton for region annotation.
- `tools/tonal-hierarchy/README.md` — CLI, region format, metric glossary,
  findings table, score composition.
- `.claude/skills/tonal-hierarchy/` — SKILL.md (iron rules, workflow,
  reading the numbers) + `references/capture.md` (Studio play/edit-preview
  capture paths, DPI + inset traps) + `references/fix-recipes.md`
  (per-finding fixes + the shop worked example with measured numbers).

**Modified:**
- `src/shared/UIKit/Theme.lua` — `ShopTabStates.idle` rebuilt as a light
  WASH (was a dark slate: desaturated but dL* −58 vs the white panel — the
  three idle tabs tonally out-shouted the selected one 3.6x);
  `ShopTabStates.selected` face = own deeper-gold literal (Legendary hue,
  V ×0.85 — a VALUE anchor; the bright gold sat in the panel's own L* band);
  `Scrollbar` thumb AND track ring pulled into a light slate family (chrome
  was out-shouting card titles); `ShopHeroItem.FaceGradient` +1 value band
  (chips measured only dL* +6 after the first raise); `ShopHero` gained
  OPTIONAL `ArtFaceGradient` (antique gold plate — the full Legendary field
  behind the gift was the loudest patch on the tab and it is not the buy
  button).
- `src/shared/UIKit/Components/ShopHeroCard.lua` — ArtFace uses
  `style.ArtFaceGradient or accent.FaceGradient` (backwards-compatible).
- `.claude/skills/roblox-ui-kit/SKILL.md` — verification checklist gained
  the tonal-hierarchy gate line.

## Decisions
- **Perceptual math, not RGB**: tonal value = CIELAB L*; saliency = multi-
  scale center-surround on L*, a*, b* (catches saturated patches whose L*
  blends — the Passes art windows — AND value-blind gold that vanishes in
  grayscale — the old active tab). Both directions of "hue is not
  hierarchy" showed up in this one screen.
- **Containers get residual metrics** (children masked out, rect inset):
  raw share/mean on a container is dominated by its children; without this
  every panel region false-fired as an attention sink.
- **Inversions are median-gated**: saliency is max-normalized per image, so
  an absolute floor is not comparable across screens; the louder element
  must be ≥ the median element saliency or it's rank noise. Calibrated on
  this shop (real offenders measured 0.45+; the quieted scrollbar at 0.31
  vs a tab at 0.25 is not a violation).
- **Verdict is findings-aware**: clearing CRITICALs without introducing new
  ones = IMPROVED even when the structure score moves < +3 (two score
  components saturate on this art direction: bg-quiet vs airbrush panel
  gradients, primary-leads capped by the conventional red close X).
- **Genre conventions define intent** (skill rule 6): red close X, balance
  pills (the shop doc calls them the affordability anchor), BEST VALUE
  ribbon, bundle chips → annotated level 2, not "fixed". Clipped scroll
  slivers → `ignore`.
- **Quiet means close in VALUE, not merely low chroma** — the idle-tab
  lesson, now in `style-rules.md` §4 and the skill.
- Verified end-to-end: edit-preview harness captures (before), Theme token
  fixes, like-for-like recapture, `compare` gate: **Offers IMPROVED 58.7 →
  64.6, CRITICALs 2 → 0, WARNs 10 → 6; Passes FLAT with 0 CRITICALs both
  sides**; also live play-mode captures with real catalogue confirmed the
  fixes (inactive tabs sal 0.48 → 0.25, active leads row 2x). Clean client
  boot (zero require FAILED).

## Adversarial review (1 CRITICAL, 4 WARN — all fixed)
- CRITICAL: `dump_regions.luau` inset gate was flag-based; AbsolutePosition
  can be inset-relative even on an IgnoreGuiInset gui (play PlayerGui +
  DeviceSafeInsets reports 58px high). Now OFFSET-based
  (`physical = child − screenGui.AbsolutePosition + physical origin`),
  `insetOffset` emitted in the payload.
- WARNs: ignored regions now masked out of container residuals AND
  attributable as hotspot hosts (no more false noisy-background /
  stray-hotspot around an ignored avatar); hero plate override
  accent-guarded (a Rare-accent hero keeps its green face — verified live:
  give-hero 85,225,140, starter 172,136,52); dumper recursion no longer
  pruned by MIN_SIZE (zero-size anchor frames keep their subtrees); gate
  semantics single-sourced to skill rule 7.
- INFO fixes: inversion median over ELEMENTS (matches README), listener
  validates JSON + no double-timeout, degenerate-slice clamp (no NaN in
  report.json), stale ShopTab header comment rewritten, README/docstring
  omissions. Deliberately NOT fixed: box-radius formula ~1px wide (reviewer
  agreed: recalibrate-with, thresholds are calibrated against it).
- Post-fix: selftest 13/13; gates re-run and hold (Offers IMPROVED
  58.7→64.6; Passes FLAT, 0 CRITICALs). The one residual offers-after
  CRITICAL (`featured-header` vs `hero-title`) is a MOCK artifact — the
  real Offers tab is single-section and draws no header (play capture
  confirms).

## Round 2 — user feedback: tonal numbers passed, AFFORDANCE failed
The user read the round-1 result as: tabs look LOCKED, the antique-gold
plate looks DIRTY (and is useless), the bundle chips look like BUTTONS.
All three were affordance failures the analyzer cannot see:
- Idle tabs → LIGHT SKY-BLUE BUTTONS: quiet an interactive element by
  lightening its OWN hue family, keeping rim flash + bottom lip; the
  desaturated wash had landed in the kit's locked-gray language.
- Hero plate → REMOVED (`ShopHero.ArtPlate = false`, ShopHeroCard skips
  the frames): the grid card's window normalises mixed-aspect art — a
  single-item hero has nothing to normalise, so ANY plate color is a
  useless attention magnet. Art sits directly on the navy body.
- Bundle chips → FLAT TAGS (`ShopHeroItem`: same fill both layers, no
  lip/flash, soft outline): passive labels must not wear the pressable
  recipe. New generative rule: style-rules **§2c** (slab/frame/FLAT) +
  tonal skill iron rule 8 (affordance).
Gate re-run on a production-faithful preview (the mock's phantom second
section had manufactured the only persistent CRITICAL — empty sections are
dropped in production, so the tab draws no header): Offers **IMPROVED**
58.7 → 60.0, CRITICALs 2 → 0, WARNs 10 → 6; Passes FLAT, 0 CRITICALs.

## Round 3 — user feedback: "bad sizes and positions, hard to read"
Two causes, both self-inflicted in earlier rounds:
- **Removing the plate left a LAYOUT HOLE.** The 168px gift floated in the
  206px zone the plate used to fill — dead navy space, small art, small
  shelf. Deleting a surface is only half the job: **re-run the zone
  arithmetic so the freed space is reabsorbed.** `ShopHero` re-cut
  870x260 → 870x300 (art 220 fills the left zone, shelf 302x64 matching
  ShopPriceCard's aspect, sums close: 30+220+20+576+24 = 870 ✓,
  38+46+4+28+12+50+14+64+44 = 300 ✓), `ShopLayout.HeroPx` 300 — the card
  now also fills the single-hero Offers window (35px symmetric margin)
  instead of floating in it.
- **Soft text outlines washed readability.** Round 2 softened the chip and
  idle-tab text outlines "to match the quiet surfaces" — wrong: the kit's
  sticker text is SELF-CONTAINED (white glyph + full-dark outline reads on
  any face). Flatness lives in the FILL, never in the text. Outlines
  restored to full dark.
Gate: Offers v0 → v3 **IMPROVED** (CRITICALs 2 → 0, WARNs 10 → 5); Passes
0 CRITICALs; clean client boot.

## Rounds 4-5 — "perfect" mandate: four-lens design review + UX loop fixes
User goal: "Improve ui and ux until it become perfect" (after confirming the
earlier rounds WERE live — the "no changes" report was a stale play session /
published-place view). Ran a 4-agent workflow review (genre conventions /
composition / readability / affordance-UX) over live captures of all four
tabs; 37 findings, strong convergence. Shipped:
- **Get-gems loop** (the genre's worst omission): gems pill in the shop
  header carries a green "+" and the whole chip taps through to the Gems tab
  (`balances[].jumpTabId`, ShopPanel); unaffordable prices are RED on the
  grey shelf (`ShopPriceStates.unaffordable` is its own table now, not an
  alias of `unavailable`) — "too expensive", never "disabled". Verified
  live: clicking the pill from Boosts lands on ShopTab_gems.
- **Modal scrim** (`Theme.PanelScrim`, AppRoot zIndex 40, tap-outside-to-
  close, Upgrades excluded — HexTreeOverlay brings its own): panels floated
  over the full-brightness world and the HUD out-shouted panel content in
  every measurement. The single biggest readability lever found all session.
- **Passes → smallcard 4-across** (same grid as boosts/gems): at 3-across,
  row 2 ended exactly at the window bottom — passes 4-6 were INVISIBLE.
  Now ~66px of row 2 peeks (the genre's scroll cue). Pass descs rewritten
  effect-first and <=15 chars for the smaller zone.
- **OWNED = flat stamp** (three lenses flagged the raised sky-blue shelf as
  a false affordance rhyming with the tabs); **chips = dark engraved
  insets** (the light flat pills still read pressable / the gem chip read
  as a second price); **hero shelf full-width** on the column rails via new
  `Theme.ShopPriceHero` fractions (the centred 302px shelf sat on a third
  alignment axis); **copy unified** (x2 prefix, "(15m)" durations, comma
  thousands via `withCommas`, gem tiers advertise real "+12/17/25% bonus",
  hero pitches "Over x4 the value"); **calories pill removed** from the
  shop header (nothing there is calorie-priced and the run-scoped balance
  read "0"); **ScrollPane hides its track** when the deterministic canvas
  fits (dead full-height thumb advertised scrolling on three tabs);
  **centering pad capped** (`CanvasMaxTopPadPx`) so content doesn't jump
  between tabs.
- Tool: new region role `chrome` (scrollbars/dividers) — excluded from
  element-vs-element inversion like containers; infrastructure is judged by
  the background rules. Model note: the saliency model has NO luminance
  prior — a scrim-dimmed HUD keeps its local contrast, so annotate occluded
  UI as `ignore` (it is literally non-interactive under the scrim).
- Gates (play-vs-play, like-for-like): Offers **IMPROVED 44.2 → 63.4,
  CRITICALs 3 → 0**; Passes **IMPROVED 54.3 → 57.5, CRITICALs 1 → 0**.
  Clean boots throughout. Remaining WARNs are the documented accepted
  classes (airbrush surfaces, art-zone dilution, equal-priority grids).
- Deliberately NOT taken from the review: tab icons (needs art), value
  starburst asset (copy carries it for now), gems-tab ribbon recolor (gold
  stays the single superlative), red exit-vs-promo split (positions
  disambiguate), canonical per-currency product art (needs art).

## Rounds 4-5 adversarial review (1 CRITICAL, 4 WARN — all fixed)
- CRITICAL: the scrim's blanket `Open(nil)` BYPASSED close contracts —
  Matchmaking's tap-outside would abandon the panel without firing
  `onCancelMatch` (server session stays enrolled → teleported into a match
  the player believes dismissed), and Codes kept its stale status line.
  Closing is a CONTRACT: named closers (`closeMatchmaking`, `closeCodes`)
  now serve both the X and the scrim via per-panel dispatch. Verified live
  (shop path).
- WARNs fixed: `LocaleData` perk names updated to the x2 convention (the
  daily card and shop card must never disagree); `math.clamp` min>max guard
  on the public `layout` prop (one bad custom layout must not kill the
  panel); shop.md's three stale facts (calories chip, "two card sizes",
  old hero arithmetic) rewritten; peek number single-sourced in shop.md
  (~72px).
- NITs fixed: stale comments (Theme hero header, ShopData label table),
  `withCommas(nil)` floors to 0, StatPill vertically centred in its chip
  slot, jump-chip hit zone 1.06 (inside the stride).

## Round 6 — the SQUINT TEST skill + icon-first (children may not read)
User: blur the screen heavily (gray AND color) to see what stands out;
text stays legible unblurred but ICONS carry meaning — a children's game.
- Tool: `tonal.py blur` + blur survival metrics in `analyze`
  (`compute_blur_maps`: linear-light color blur + L* blur at 2.5%/5% of
  dim; per-region `dl_blur`/`chroma_blur`; `squint` VISIBLE/GONE column;
  `blur-invisible` finding — CRITICAL on cta/tab-active, text roles exempt
  because text ALWAYS dissolves; the ELEMENT must survive). Selftest 16/16.
- New skill `.claude/skills/squint-test/` — icon-first iron rules (icons
  carry, text reinforces; squint ranking matches intent; backgrounds never
  interfere; fix levers COLOR/TONE/SIZE — never outlines/text; one glyph
  per concept everywhere).
- Ground truth on the live shop: the heavy-blur read shows the intended
  masses — green buy bar loudest, gift art second, gold active tab third.
  Gaps found and fixed ICON-FIRST: **tab glyphs** (gift/badge/boost/gem —
  `ShopTab` optional `iconName`, new Theme fractions 20+34+8+139+16=217 ✓;
  ⚠ ShopPanel's `liveTabs` rebuild silently ATE the new field — carried
  through explicitly now); **OWNED leads with a green check glyph**
  (`priceIcon = "UiCheck"`, also on the claimed group banner); **price
  glyphs sit on a faint light disc** (`IconPlateTransparency` on all three
  price styles — the dark Robux mark nearly vanished on green); **hero
  chip icons grown 28→34** (the glyphs ARE the bundle for a non-reader).
- Gates: play-vs-play r5→r6 FLAT with **0 CRITICALs both sides** on both
  tabs (rule 7 pass — glyph-size changes don't move zone means, and that
  is correct). Accepted blur WARNs, documented: small elements (chips,
  balance pill, ribbon, close X) mathematically dissolve under a 27px
  sigma — their meaning carriers are size-capped by layout; the PRIMARY
  path (buy / art / active tab) survives in both gray and color.

## Open Questions / Followups
- The red ONE TIME ribbon (live data) measures loud in play captures —
  merchandising choice for a one-time offer; left as-is, annotated L2.
- `analyze` WARNs accepted as art direction: airbrush panel/header internal
  std ~24-31; art-window low-separation (zone mean diluted by the art
  asset — judge via hotspots.png); crowded-top on equal-priority grids.
- Studio MCP: edit-mode `screen_capture` can wedge (timeouts) while
  execute_luau works; captures flush LATE to `tmp-capture-storage`; a
  reconnect restores it; play-mode capture kept working (memory updated).

## Related
- Feature: `docs/features/shop.md`, `docs/features/ui-kit.md`
- Skill: `.claude/skills/tonal-hierarchy/`
- Prior flow: `docs/flow/2026-07-31_shop-cards-tabs-redesign.md`
