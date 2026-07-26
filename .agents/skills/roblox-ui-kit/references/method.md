# Method — the working process that produces good windows

This is the exact process that produced the kit's best window (Pets). Follow
the phases in order; do not skip B, C, or F — every observed failure (shop
that looked like a pets clone; grids collapsing; icons reading wrong) came
from skipping one of them. The catalog and style rules tell you WHAT; this
file is HOW.

Why Pets came out right, in one line each:
- Style preserved — every new value was DERIVED from an existing element, not
  invented (Phase D).
- New elements created — the design demanded a scrollbar, counter chip, cards,
  later an inspector; they didn't exist, so they were designed (Phases B-D).
- Structure genre-correct — landscape grid + action row, because that's what
  a collection window is in Roblox, not because an existing panel was portrait.
- It went through THREE verify-fix loops before it was called done (Phase F).

---

## Phase A — Study (before your first UI task in a project)

Read `Theme.lua` top to bottom and skim 2-3 components (Button, PetCard,
ScrollPane). Goal: hold the layer recipe and the px/total convention in your
head, not just on paper. If a style question comes up later, the SOURCE CODE
is the truth; references summarize it. Never modify what you haven't read.

## Phase B — Design brief (write it out BEFORE any code, ~10 lines)

Write, in the task log or a comment, answers to:

1. **Archetype**: which row of `window-archetypes.md` is this, and what do 2-3
   popular Roblox games show for this window? If unlisted — reason from the
   genre, don't default to an existing kit panel.
2. **Orientation**: derived from content shape (browsable collection → wide
   grid; read-and-act rows → portrait list; single action → small dialog).
3. **Zones**: header / action rows / content / sidebars — name each.
4. **States**: enumerate ALL of them now (empty, disabled, owned, selected,
   equipped, locked, not-enough-currency...). Every state named here must be
   visible in the final render.
5. **Data + callbacks shape**: the props table of the future panel.

Pets brief (the reference answer): collection archetype → landscape 1000x600;
zones: header, action row (counter chip + Equip Best + sort), 6-col grid with
scrollbar; states: equipped badge, gold selection, 4 rarity recolors, counter
x/4; data `{pets, equipped, selectedId, callbacks}`.

## Phase C — Zone arithmetic (check-sum discipline)

Lay out every zone in nominal px and WRITE THE SUMS. The layout is correct
when the sums close EXACTLY — if they don't, change the design, never fudge
the code.

Pets worked example (landscape 1000x600, content inset 48):
```
header 0..120; action row y 132..180 (h 48); grid zone y 192..559 (h 367)
grid width: 6*135 + 5*12 = 870  ✓ cells+gaps close exactly
pane:      870 + 12 + 22 = 904  ✓ window + gap + scrollbar = content width
canvas:    rows * (154.3 + 12) vs window 367 → 4 rows = 665 > 367 → scrolls ✓
```
(Compare Settings: 5*103 + 4*12 = 563 = rows zone height. Same discipline.)

Spacing taste (numbers that repeat across the kit — reuse them):
- gaps 12 between ~100-160px elements; margins 48 on a 1000-wide panel;
- action rows h 48; text zone ≈ 50-60% of its element's height;
- hit targets ≥ 44 nominal px; siblings share a common height, gap, or x-line;
- header overlaps body ~28% of header height; shadow slab ~2% below body.

Deliverable: `Theme.<Feature>Layout` table with the sums as comments.

## Phase D — New element derivation (ratio transfer, not invention)

For every element the brief needs that the catalog lacks:

1. **Pick the nearest relative** by role AND size class (a small solid pill →
   Toggle/Chip family; a clickable surface → Button family; a card → PetCard;
   a recessed area → Inspector).
2. **Transfer its ratios** to the new nominal grid: outline thickness stays in
   px terms for the same height class (6 top / 12 bottom at h~100), corners by
   min-dimension ratio, rim keeps the "bright only at top" rule, small
   elements (<50px) drop the Rim.
3. **Gradients**: same hue → reference the existing sequence literally
   (`Theme.Button.FaceGradient`); new semantic → hue-shift per style-rules §4.
4. **Write the Theme section first** (px/total of the element's OWN nominal
   grid, freeze it), then the component following conventions.

Real derivations from the kit (copy this way of thinking):
- **Chip (190x48)** = Toggle's dark Outer pill + deep-blue Face inset 4px +
  Button.TextGradient text. Two references, one new gradient.
- **Scrollbar** = track: 22-wide pill with Toggle.OuterGradient + light groove
  inset 4px; thumb = a MINI BUTTON (dark outer + blue face inset 3px), min
  size fraction 0.12.
- **PetCard (140x160)** = Button recipe turned portrait: outline 7-8 top/side
  and 16 bottom (2x rule kept), corners 0.14/0.13/0.12, plate circle d76,
  name zone h28.
- **Inspector stat row (238x52)** = Button minus Rim (small-element rule),
  face inset 3 top / 6.3 bottom.
- **HUD bolt glyph** = three rotated pills 25°/-38°/25° — and it took 3
  visual iterations to stop reading as a slash. Glyphs ALWAYS need Phase F.

## Phase E — Build order

1. Theme section(s) + Layout table (frozen, sums in comments).
2. Panel skeleton (PanelWithHeader + empty zones) — RENDER IT NOW. Catching a
   broken zone layout costs one screenshot here, five fixes later.
3. Elements into zones; demo/app shell copied from the nearest Demo (viewport
   scaling effect, state, callbacks) with mock data.
4. Mount through the single React root: `UiRoot.Render(...)`, `openPanel`
   pattern, panels `zIndex = 50` over HUD `zIndex = 1` — contract in
   `docs/features/ui-kit.md`.

## Phase F — Visual iteration loop (this is where quality comes from)

Loop until clean; 2-4 iterations is NORMAL, one-shot "done" is a red flag:

1. Play mode → screenshot → **zoom into every new element separately**.
2. Compare against: the Phase B brief (structure), the SKILL.md checklist
   (style physics), and the states list (all visible?).
3. Write the discrepancy list with px-level estimates, fix, run again.
4. Interactions: click EVERYTHING via instance paths
   (`user_mouse_input`, path like `LocalPlayer.PlayerGui.UiRoot...`), verify
   state changed both visually and numerically where possible (e.g. drag the
   scrollbar thumb 100px → read CanvasPosition, expected ≈ 73%, measured 74%).
5. Console after every run — must be silent.

Techniques that pay off:
- **Small element unreadable in a screenshot? Scale it up live** (set its
  Size in the running client via execute_luau, inspect, discard — play state
  is throwaway). This is how the bolt glyph was actually reviewed.
- Measure, don't squint: read `AbsoluteSize/AbsolutePosition` via
  execute_luau when a proportion looks off.
- Expect the classic traps (patterns.md pitfalls): grid cells collapsing to
  1x1, canvas wider than window, inset-shifted click math — all three occurred
  in this kit's history and were caught ONLY by this loop.
- Edit-mode `execute_luau` require() can serve stale modules — only play-mode
  runs count as verification.

## Phase G — Ship gate

Before reporting done, confirm in writing:
- [ ] Phase B brief exists and the final render matches its structure
- [ ] Layout sums written and closing exactly
- [ ] New-element count sane (new window type ⇒ usually 2-4 new components;
      0 means you probably cloned an existing panel — justify or redo)
- [ ] Every state from the brief demonstrated in the demo
- [ ] SKILL.md visual checklist green; interactions clicked; console silent
- [ ] Report names: archetype, new components created, iteration count and
      what each iteration fixed
