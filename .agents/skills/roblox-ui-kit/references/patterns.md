# Patterns and pitfalls

Worked recipes proven in the reference implementations. Copy the math, swap
the content. **Window STRUCTURE is chosen first via
`window-archetypes.md`** — the patterns below implement structures, they do
not choose them (a shop is a sectioned vertical list, not a card grid).

## New window walkthrough (example: a collection window — pets/inventory)

1. **Archetype first** (`window-archetypes.md`): collection you browse →
   landscape grid; rows-you-act-on (shop, quests, upgrades) → vertical list
   (see the worked Shop example there); options → settings list; etc.
2. **Pick orientation + nominal grid.** Landscape grid → 1000x600
   (`Theme.PanelWide` + `Theme.HeaderWide`). Vertical list → 512x727
   (`Theme.Panel` + `Theme.Header`).
3. **Lay out content zones in nominal px** (landscape reference values:
   content x 48..952, y 132..559; action row y 132..180; grid zone
   y 192..559). Put every rect into `Theme.<Feature>Layout` as fractions.
4. **Element inventory**: which elements exist (components.md) and which must
   be CREATED for this archetype (style-rules recipes). New elements are
   normal — the kit's scrollbar, counter chip, cards, inspector were all
   invented this way when Pets needed them.
5. **Compose**: `PanelWithHeader { panelStyle, headerStyle, headerSize,
   title, zIndex = props.zIndex }` with children positioned by the layout
   table (children zIndex 5); collection cells built like `PetCard` (recolor
   via accent sets), grids per the math below.
6. **App/state**: copy the closest demo's shell (viewport scaling effect,
   state, callbacks) — replace mock data.
7. Mount, verify (SKILL.md protocol).

## Vertical list in a ScrollPane (shop/quests/upgrades archetypes)

Use `UIListLayout` + `AutomaticCanvasSize = Y` (ScrollPane default when
`canvasHeightScale` is nil). Rows: `Size = UDim2.fromScale(1, 0)` +
`UIAspectRatioConstraint` per row type (e.g. 384/96 item row, 384/44 section
header) — canvas width equals window width, so aspect-derived heights are
stable, unlike scale heights (which reference the growing canvas). Interleave
section headers and rows via `LayoutOrder`.

## Grid + custom scrollbar (THE way to do card collections)

Deterministic math — never AutomaticCanvasSize with scale cells:

```lua
-- Layout table (fractions of the panel nominal grid):
-- GridSize = pane rect; ScrollWindowFraction = window/pane; ScrollBarWidth = bar/pane
-- Columns, CellWidth = cellPx/windowPx, CellPaddingX = gapPx/windowPx
-- CellHeightWithGap = (cardH + gapY) / gridWindowH   (e.g. 166.3 / 367)

local rows = math.max(math.ceil(#items / layout.Columns), 1)
local canvasHeightScale = math.max(rows * layout.CellHeightWithGap, 1)

-- UIGridLayout inside ScrollPane children:
CellSize = UDim2.fromScale(layout.CellWidth, layout.CellHeightWithGap / canvasHeightScale),
CellPadding = UDim2.fromScale(layout.CellPaddingX, 0),
FillDirectionMaxCells = layout.Columns,  -- ALWAYS set explicitly
-- ScrollPane props: windowFraction, barWidth, canvasHeightScale
```

Vertical gap is BAKED INTO the cell: cell aspect includes the gap, the card
inside occupies the top ~93% of the cell (`CardHeightInCell`). Reference
column counts: 6 (full-width grid, cell 135px on 870px window), 4 (grid next
to inspector, window 576px).

## Inspector sidebar (details pane)

Recessed slot look: dark navy Outer (corner ~0.055) + light Fill (white-blue
3-keypoint gradient, inset 5px, bottom inset 8px). Content: circle plate with
dark ring (+3px), `OutlinedText` name, stat rows (Outer+Face only, label left
/ value right via `textXAlignment = Right`), accent action button at the
bottom (`Theme.EquipGreen` / `Theme.UnequipRed` swap by state). Copy
`PetsInspectPanel.inspector()`.

## HUD elements

- Stat row: icon (`ImageLabel`, ScaleType Fit) + `OutlinedText` value colored
  by the icon's hue (`Theme.Hud.*TextGradient/*TextOutline`).
- Menu button: icon `ImageButton` + label below, in a fixed-aspect container.
- Sizing: `Size = UDim2.fromScale(0.5, heightFraction)` + aspect constraint
  (fit box binds to height — survives any screen aspect).
- Panel toggling: single `openPanel` state ("Settings" | "Pets" | nil); one
  panel at a time; panels get `zIndex = 50`, HUD `zIndex = 1`; hidden panels
  keep their state (visible=false, not unmounted). Copy `Demos/HudDemo`.

## States

- Selected card: swap Outer→`SelectOuterGradient`, Rim→`SelectRingGradient`
  (gold). Geometry unchanged.
- Equipped/owned badge: green circle (dark ring + gradient fill) + vector
  check from two rotated pills. Copy `PetCard` badge block.
- Disabled: `CanvasGroup` wrapper, `GroupTransparency 0.22` + light gradient
  overlay. Copy `SettingRow`.
- On/off: gradient + position swap like `Toggle` (no tween).

## Pitfalls (all discovered the hard way — do not rediscover)

1. **`CanvasSize` Scale resolves against the ScrollingFrame's PARENT** (like
   Size), not the frame itself. If the scroll window is a fraction of a wider
   pane, `CanvasSize.X.Scale` must equal `windowFraction`, or content
   overflows horizontally. (`ScrollPane` already handles this.)
2. **`UIAspectRatioConstraint` inside `UIGridLayout` collapses cells** whose
   CellSize has 0 height (FitWithinMaxSize fits into (w, 0) → 1x1 px). Use the
   deterministic rows/canvas math above instead; never rely on the constraint
   for cell height and never use AutomaticCanvasSize for grids.
3. **Mouse event coordinate spaces differ by the gui inset (~58px).**
   For drags, use INCREMENTAL deltas between InputChanged events (`lastY`
   pattern in ScrollPane); for point clicks compare
   `UserInputService:GetMouseLocation().Y - GuiService:GetGuiInset().Y`
   against `AbsolutePosition`.
4. **Plugin-VM `require` cache**: checking modules via Studio-MCP
   `execute_luau` in Edit mode can return a STALE module. Only trust play-mode
   runs for verification.
5. **Equal ZIndex among siblings = undefined order** with React dict children.
   Always assign explicit zIndex when overlap matters (panels 50 over HUD 1).
6. **Exact-fit grids can wrap due to float rounding** — always set
   `FillDirectionMaxCells` and shave the cell width a hair if needed
   (0.155 instead of 0.15517 for 6 columns).
7. **UICorner Scale is relative to the shorter side** — a "0.2 corner" on a
   wide button and on a square icon button are different px; check visually.
8. **External selection rings clip** at scroll-window edges — selection is a
   gradient swap, never extra geometry outside the card bounds.
