---
name: roblox-ui-kit
description: Build ANY player-facing UI (panel, window, shop, settings, inventory, pets, HUD, buttons, popups, dialogs) using the project's candy-style ReactRoblox UI kit at ReplicatedStorage.Shared.UIKit. MUST be used whenever a task creates or modifies game UI. Covers designing window structure from Roblox genre conventions, inventing new components in the kit's style, panel geometry, grids with custom scrollbars, HUD elements, and Studio verification.
---

# Roblox UI Kit — candy style

Every piece of player-facing UI in this project is built with the UI kit
(`src/shared/UIKit/` → `ReplicatedStorage.Shared.UIKit`). The kit produces the
"candy / cartoon simulator" look (Pet Simulator 99 family): chunky dark
outlines, vertical gradients, Fredoka One sticker text — built entirely from
`Frame + UICorner + UIGradient` (no images except explicitly provided asset ids).

**You are a UI designer here, not an assembler.** The kit fixes the STYLE
(palette, layer recipe, text, theme discipline). It does NOT fix window
structure: each feature gets the layout the Roblox audience expects for that
feature type, and INVENTING NEW COMPONENTS IS THE NORMAL PATH — the kit itself
grew that way (Pets needed a scrollbar, a counter chip, cards, an inspector —
none existed; they were designed by the rules, not copied). A new window that
looks like an existing kit panel with relabeled cards means the design step
was skipped — that is a failure, not reuse.

## Iron rules (violating any of these = wrong result)

1. **Design the window structure from Roblox genre conventions first**
   (`references/window-archetypes.md`). Different feature types have different
   canonical layouts — a shop is NOT a pets grid with new labels.
2. **ALL style values live in `Theme.lua`** (colors, gradients, geometry as
   `px / total` fractions, per-component style tables). Components never
   hardcode colors or magic numbers. New elements get a new Theme section.
3. **New elements follow the layer recipe** in `references/style-rules.md`
   (Outer/Rim/Face stack, thickness table, gradient keypoint recipes, nominal
   pixel grid). Inside a component, frames are built per that recipe — what's
   forbidden is ad-hoc UI that ignores the recipe and Theme, and re-inventing
   an element that already exists in the catalog.
   ⚠ **§2's thickness table is the BUTTON recipe. Cards use §2b** — even
   outline + internal zones. Applying the button bevel (bottom lip 2x+) to a
   card is exactly how the shop shipped cells that read as stretched buttons.
4. **Scale only. Zero `Offset` anywhere.** Every self-contained element holds
   its proportions with its own `UIAspectRatioConstraint`.
5. **All gradients are vertical** (`Rotation = 90`). On rotated parts,
   counter-rotate the gradient so it stays screen-vertical.
6. **Text = `OutlinedText` component only** (scaled UIStroke outline + one
   shadow copy). Never a bare TextLabel, never ad-hoc strokes — outline
   thickness/color/offset live inside OutlinedText and Theme.
7. **New accent colors** (buy-green, danger-red, rarities, gold selection) are
   made by hue-shifting an existing gradient while keeping its keypoint
   positions and lightness curve; the element's outline becomes a DARK version
   of the same hue. Never invent unrelated palettes.
8. **Do not change existing component APIs** (backwards-compatible optional
   props only, pattern: `props.style or Theme.X`). Press/hover feedback + pops
   are BUILT IN via the `Interaction` primitive (`usePressable`/`pressLayer`,
   timings in `Theme.Feel`; see `references/components.md` "Motion" + ADR-0006) —
   reuse it, never hand-roll per-component animation. No sounds, and no NEW
   animation beyond that primitive, unless the task explicitly asks.
9. **Verify visually in Studio before reporting done** (protocol below). UI
   that was never seen running is not done.

## Workflow for any UI task — follow `references/method.md`

`references/method.md` is the MANDATORY spine — the exact process that
produced the kit's best window (Pets), phase by phase, with real numbers.
Summary (details and worked examples live in method.md):

1. **Phase B — Design brief, in writing, before code**: archetype from
   `references/window-archetypes.md` + what 2-3 popular Roblox games do;
   orientation from content shape; zone list; FULL state list (empty /
   disabled / owned / selected / locked...); props shape.
2. **Phase C — Zone arithmetic**: nominal-px layout whose sums CLOSE EXACTLY
   (`6*135 + 5*12 = 870` style), written as comments in the
   `Theme.<Feature>Layout` table. Sums that don't close = redesign.
3. **Phase D — Element inventory + derivation**: what exists
   (`references/components.md`) vs what must be created. New elements are
   DERIVED from the nearest kit relative by ratio transfer
   (`references/method.md` §D, `references/style-rules.md` for recipes) —
   2-4 new components for a new window type is expected; zero is suspicious.
4. **Phase E — Build order**: Theme section → panel skeleton → RENDER THE
   SKELETON → fill elements; grids/scroll per `references/patterns.md`
   (read its pitfalls before any ScrollingFrame code).
5. **Phase F — Visual iteration loop**: play → screenshot → zoom EVERY new
   element → fix → repeat; 2-4 loops is normal, one-shot done is a red flag.
   Click every interaction via instance paths; console silent.
6. **Phase G — Ship gate**: method.md checklist; report archetype, new
   components, iteration count.

Mount & wire (Phase E detail): single React root via `UiRoot.Render(...)`
(client module `src/client/modules/UiRoot.lua`, contract in
`docs/features/ui-kit.md`); real data/remotes wired in subscription modules by
passing callbacks into props. Panels above HUD: panel `zIndex = 50`, HUD
`zIndex = 1`; one `openPanel` at a time (HudDemo pattern).

## Verification protocol (mandatory)

With Studio MCP connected: start play mode, screenshot, zoom into each new
element, and check against this list; exercise every interaction (instance-path
clicks via `user_mouse_input` work well: `LocalPlayer.PlayerGui.UiRoot...`).

- [ ] Dark outline visibly THICKER at the bottom (~2x top) on BUTTONS; on CARDS
      it is EVEN (≤1.5x) — **measure it off the live instances** (`Face.AbsolutePosition
      - Outer.AbsolutePosition` vs the same at the bottom), do not eyeball a
      whole-panel screenshot, where a 30px lip reads as a drop shadow
- [ ] Bright rim flash at the TOP edge of buttons/headers
- [ ] Face gradient darkens sharply near the bottom edge (dark "lip")
- [ ] Panel: shadow slab pokes out below the body; header overlaps body top
- [ ] Text: thick uniform dark outline, readable at game size, gradient on fill
- [ ] Corners consistent (pills fully round; rectangles ~0.2 of height)
- [ ] Aspect held at 3 window sizes (resize viewport); nothing distorts
- [ ] Scroll: wheel + thumb drag + track jump all work; grid doesn't overflow
- [ ] Open panels render above HUD; close buttons work; no console errors
- [ ] **Tonal hierarchy measured** (skill `tonal-hierarchy` +
      `tools/tonal-hierarchy/`): analyze the new/changed screen — no
      CRITICAL findings; fixes gated by `compare` per that skill's iron
      rule 7 (never REGRESSED; CRITICALs must clear)
- [ ] **Squint test passed** (skill `squint-test`): heavy-blur the capture
      — the CTA / active state / key icons survive as masses; every
      interactive element carries a GLYPH (icon-first: this audience may
      not read); no `blur-invisible` CRITICAL

## References (read what the step needs)

- `references/method.md` — THE PROCESS (mandatory spine): design brief,
  check-sum zone arithmetic, ratio-transfer derivation of new elements with
  real worked derivations (Chip, scrollbar, PetCard), build order, the
  visual iteration loop with Studio techniques (live scale-up inspection,
  numeric drag verification), ship gate.
- `references/window-archetypes.md` — REQUIRED at the design step: canonical
  Roblox window structures per feature type (shop, inventory, settings,
  quests, codes, eggs, upgrades...), with a fully worked Shop example
  (zones, new elements, nominal px).
- `references/style-rules.md` — generative visual rules: layer recipe with
  exact thickness/corner/gradient numbers, palette, accent derivation method,
  text outline math, nominal-grid workflow, panel geometry.
- `references/components.md` — every component's props + Theme section
  inventory + mounting snippet.
- `references/patterns.md` — worked patterns (collection-grid walkthrough,
  vertical-list-in-ScrollPane, grid + scrollbar math, inspector, HUD,
  selection/badges) and the pitfall list (CanvasSize parent quirk, grid aspect
  collapse, gui-inset coordinates, plugin require cache). Read pitfalls BEFORE
  writing any ScrollingFrame/grid code.
