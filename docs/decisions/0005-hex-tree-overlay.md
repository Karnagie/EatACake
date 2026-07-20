# ADR-0005: Hex-tree UI is a full-screen overlay with a sprite-stacked hex node

## Status
Accepted (2026-07-19)

## Context
The upgrades feature needed a hexagon skill-tree (honeycomb) that gradually
unlocks, with nested drill-down sub-trees. Two things conflict with the kit's
defaults:
1. Kit chrome is `Frame + UICorner + UIGradient` (rounded rectangles) — UICorner
   cannot make a hexagon.
2. Kit windows are `PanelWithHeader` panels; a sprawling honeycomb wants the
   whole screen (the reference is a blurred full-screen layer, not a window).

## Decision
- **Full-screen OVERLAY** (`HexTreeOverlay`, zIndex 60), not a panel: an Active
  scrim (blocks click-through to the world), a centred SQUARE canvas of hex
  nodes + connector bars, a calories chip, a Close button, and a hover tooltip.
  Opened from a world ProximityPrompt (the checkpoint computer), closed by E /
  the Close button. Analogous to `GymOverlay`/`PetRevealOverlay`.
- **Hex NODE = a hex SPRITE** (`Theme.HexTree.HexImage`, a white flat-top hexagon
  PNG, aspect 512/444) stacked Outer/Rim/Face as three `ImageLabel`s, each tinted
  by a vertical `UIGradient` per state — the kit's bevel recipe applied to a
  shape UICorner can't produce. This is the ONE place chrome uses a provided
  asset id, exactly like `Theme.Hud.Icons`. Chosen over runtime `EditableImage`
  because a normal texture avoids the Editable* memory budget (tight on the
  low-RAM dev machine).
- **Auto-fit layout** (`LocalUpgradeTree`): author nodes in AXIAL (q,r), lay them
  on a unit hex grid, then normalise the tree's bounding box into the square
  canvas (uniform scale, centred). A SQUARE canvas keeps Scale positions and
  connector-bar rotations undistorted (mixing non-square Scale with `Rotation`
  skews rotated frames). Every tree — compact root, spread sub-tree — fills the
  view with big hexes.
- Axial hex math lives in `src/shared/HexUtil.lua` (sibling to `GridUtil`), from
  the canonical Red Blob Games formulas.

## Consequences
A reusable honeycomb-tree pattern built entirely from kit primitives + one
sprite; recolour-per-state via one gradient; responsive via a single aspect-
locked canvas; no hand-positioned nodes. Cost: one uploaded asset (the hex
sprite) the template must carry, and a per-project layout config
(`UpgradeTreeConfig`). Style-rule note: the "chrome from Frames only" rule now
has a documented hexagon exception (sprite-stacked, still gradient-tinted,
OutlinedText labels).
