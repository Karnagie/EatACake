# 2026-07-15: OutlinedText — scaled UIStroke replaces the 8-clone outline

Tags: ui-kit, text, performance

## Task
User: the 8 outline TextLabel clones per text are wrong. Replace with: ONE
outline copy (Position `{-0.003,0},{0.1,0}`, Size full, Color 27,42,53)
holding a UIStroke (Color 27,42,53, LineJoinMode Bevel, StrokeSizingMode
ScaledSize, Thickness 0.06), plus a UIStroke on the main label itself (same
color/join/sizing, Thickness 0.08). Everything else unchanged.

## Context
The 8-clone approach existed only because classic UIStroke thickness was
pixel-fixed and didn't scale with TextScaled. `UIStroke.StrokeSizingMode =
ScaledSize` (post-May-2025 engine addition) removes that reason: scaled
strokes now track the text size. 2 labels + 2 strokes instead of 9 labels.

## Changes

**Modified:**
- `src/shared/UIKit/Components/OutlinedText.lua` — rewritten: main label with
  scaled stroke 0.08 + one stroked (0.06) shadow copy at (-0.003, +0.1);
  gradient/alignment/transparency/disabled behavior preserved; legacy props
  (`outlineMultiplier`, `outlineXMultiplier`, `outlineYMultiplier`,
  `outlineCenter`) accepted and ignored (API-compatible); legacy
  TextStroke* label properties dropped.
- `src/shared/UIKit/Theme.lua` — `Colors.TextOutline = (27, 42, 53)` added
  (new default text-outline color; per-hue overrides via `outlineColor` prop
  unchanged).
- Callers cleaned of the now-dead props (Button, Header, PetCard, PetsPanel,
  PetsInspectPanel, StatPill, Hud) so future components don't copy them.
- Skill docs updated: SKILL.md rule 6, components.md OutlinedText row,
  style-rules.md §5 (stroke recipe + history note), window-archetypes.md
  (multiplier mention removed).

## Decisions
- Default outline color moved to `Theme.Colors.TextOutline` rather than a
  literal in the component (iron rule 2). `Theme.Colors.Outline` (4,42,64)
  stays — it's the FRAME outline family; text outline is its own constant.
- Legacy props ignored instead of erroring: zero-risk backwards compatibility
  for any not-yet-cleaned caller.

## Open Questions / Followups
- **Studio verification pending** (Studio MCP wasn't connected during the
  change): run `Demos/Selector`, check all text (header titles, button
  labels, card names, chip counters, HUD values) against the SKILL.md
  checklist; confirm `Enum.StrokeSizingMode.ScaledSize` name matches the
  engine and 0.06/0.08 read well at all sizes.
- If verified good, consider the same review pass for `disabled` text
  (stroke fades to 0.45 — kept from the old behavior).

## Related
- Feature: `docs/features/ui-kit.md`
- Prior flow: `2026-07-15_ui-kit-port.md`
