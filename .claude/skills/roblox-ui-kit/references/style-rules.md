# Style rules — how to generate new elements in the kit's style

These are GENERATIVE rules: follow them mechanically and the result matches the
existing UI. All numbers were extracted from the shipped components; when in
doubt, open `Theme.lua` and copy the closest analog.

## 1. Nominal pixel grid

Every element is designed on a nominal pixel grid and written into Theme as
`px / total` fractions (reads like a mockup, stays pure Scale):

| Element | Nominal grid |
|---|---|
| Portrait panel | 512 x 727 |
| Portrait header | 512 x 116 |
| Landscape panel | 1000 x 600 |
| Landscape header | 1000 x 120 |
| Row button | 418 x 103 |
| Toggle | 90 x 52 |
| Close button | 61 x 63 |
| Icon button | 48 x 48 |
| Card | 140 x 160 |
| Chip / stat pill | 190 x 48 |
| Inspector sidebar | 278 x 427 |
| HUD reference screen | 1920 x 1080 |

New element: pick a nominal grid of similar magnitude, lay out in nominal px,
write every Position/Size as `Vector2.new(x / W, y / H)` fractions.

## 2. Layer recipe (every element is a stack of rounded frames)

```
Outer  — dark outline, fills the whole element
Rim    — bright bevel highlight, inset
Face   — gradient surface, inset deeper
content (OutlinedText / vector glyphs / image icon)
```

Thickness for an element of nominal height H (button scale, H 48-160):
- Outer visible: **~6% H top/left/right, ~12% H bottom** (bottom is always
  ~2x thicker — the "weight" that makes elements look physically thick).
  Example (button 418x103): rim inset 6px top/side; face y 8..88.5 → outer
  bottom lip 14.5px vs 6px top.
- Rim: visible ring ~3% H between Outer and Face; its gradient flashes bright
  only near the top (see gradient recipes).
- Elements < 50px nominal may drop the Rim (2 layers: Outer + Face) — e.g.
  stat row inside inspector. Premium elements (close button) add an InnerRim
  (4 layers).

Panels use a different triple: `BodyShadow → BodyBorder → BodyFill`:
- Visible dark border ~1.6% of panel width on all sides (8/512, 10/1000).
- Shadow = same dark color, offset DOWN ~1% of height, extending ~2% of height
  below the border (513→727 vs 713 on the portrait grid) — a hard slab, not a
  soft shadow.
- Fill inset from border by the same border thickness.
- Header floats OVER the body: header spans full panel width, body top starts
  at ~72% of header height (overlap ~28% of header height). Body is narrower
  than the header by ~27px/512 per side.

Corners (`UICorner`, Scale component only, `UDim.new(k, 0)`; k is relative to
the SHORTER side): rectangles k = 0.20 outer, then 0.18 rim, 0.17 face (each
inner layer slightly smaller so gaps look even); cards 0.12-0.16; panel body
layers 0.05-0.07; pills/circles k = 1.

ZIndex ladder: within an element `z, z+1, z+2, z+3...` per layer. Within a
panel: BodyShadow 1 / Border 2 / Fill 3 / content 5 / Header 10 / Close
header+10. Whole-window stacking: HUD container zIndex 1, open panels 50
(pass via `zIndex` prop → PanelShell root).

## 3. Gradient recipes (all vertical, Rotation = 90)

- **Face**: brightest at keypoint 0-0.05, gentle plateau, then a hard dark
  "lip" at 0.93-1.0 (two-three keypoints dropping fast). Copy
  `Theme.Button.FaceGradient` structure.
- **Rim**: bright flash at 0.02-0.06, decays downward into face-like tones.
  Copy `Theme.Button.RimGradient`.
- **Outer**: nearly flat dark with a faint lighter blip at the very top
  (0-0.05). Copy `Theme.Button.OuterGradient`.
- **Panel fill**: white → pale blue through 10-15 soft keypoints (airbrush
  feel). Copy `Theme.Panel.FillGradient`.
- Rotated glyph parts (X arms, bolt strokes): counter-rotate the UIGradient
  (e.g. arm rotated 45° gets gradient Rotation 45 / 135) so the gradient stays
  screen-vertical.

## 4. Palette and accents

Base: sky-blue surfaces (`73,190,255 → 45,122,228`), dark navy outline family
(RGB 0-4 / 38-47 / 60-83), white-blue panel fill. Semantics: **green** =
on/positive/confirm/buy, **red** = close/off/danger, **blue** = neutral,
**gold** = selection/legendary.

To create an accent variant (worked example — how `Theme.Rarity.Rare` green was
derived from Button blue):
1. Take the blue prototype's three gradients (Outer/Rim/Face).
2. Keep keypoint POSITIONS and the light-to-dark curve; replace hues:
   Face 0 = brightest green (85,225,140), mid plateau (65,200,120), lip
   (30,145,75); Rim flash (80,225,140); Outer = very dark green (0,45,24 area).
3. Element outline color = dark version of the SAME hue (green button outline
   (0,60,24); red close button outline is dark maroon (61,0,10), never navy).
4. Text gradient on accent surfaces: white → light tint of the hue
   (e.g. white → (168,240,196) on green).

Existing accent sets to reuse before inventing: `Theme.Rarity.{Common,Rare,
Epic,Legendary}`, `Theme.EquipGreen`, `Theme.UnequipRed`, `Theme.PetCard.
SelectOuterGradient/SelectRingGradient` (gold selection).

## 5. Text (OutlinedText)

- Font: Fredoka One (`Theme.Font`), always `TextScaled`.
- Outline = `UIStroke` with `StrokeSizingMode = ScaledSize` (scales with
  TextScaled text), `LineJoinMode = Bevel`: thickness **0.08** on the main
  label. Plus ONE shadow copy of the label (same text, color =
  outline color) at `Position = UDim2.new(-0.003, 0, 0.1, 0)` with its own
  stroke, thickness **0.06** — this gives the downward drop-shadow weight.
  All of this lives inside the `OutlinedText` component; never rebuild it.
  (History: before ScaledSize existed the outline was 8 offset clones —
  retired; `outline*Multiplier`/`outlineCenter` props are ignored no-ops.)
- Default outline color: `Theme.Colors.TextOutline` (27, 42, 53); accent
  surfaces override via `outlineColor` with the dark version of their hue
  (per §4), e.g. green button, red close, HUD stat colors.
- Fill gradient: white-blue → deeper blue (`Theme.Button.TextGradient`) on
  blue surfaces; neutral white → light gray (`Theme.PetCard.NameGradient`) on
  colored cards; hue-tinted per §4 on accent surfaces; per-stat colors in HUD
  (`Theme.Hud.*TextGradient/*TextOutline` — icon hue, dark outline same hue).

## 6. Sizing on screen

- Panels: computed from viewport with max fraction (0.92 portrait, 0.9
  landscape) preserving aspect — copy `calculatePanelScale` from any demo.
- HUD elements: fractions of screen height on the 1920x1080 reference —
  stat rows 64/1080 high, menu button icons 132/1080 + 40/1080 label.
  Sizing trick for fixed-aspect HUD elements: `Size = UDim2.fromScale(0.5, h)`
  + `UIAspectRatioConstraint` (FitWithinMaxSize fits to height; width follows
  aspect on any screen ratio).
- Hit targets: keep interactive elements ≥ 44 nominal px on their grid.

## 7. Component code conventions

- Functional React components; props: `name, anchorPoint, position, size,
  zIndex, visible, enabled, style` (style table override, default own Theme
  section), callbacks `onActivated / onChanged / onClose`.
- Buttons: `TextButton` with `Text = ""`, `AutoButtonColor = false`,
  `Active/Selectable = enabled`, `[React.Event.MouseButton1Click]` guarded by
  `enabled`.
- Local `roundedFrame(...)` helper per component file (accepted duplication).
- `props.children` merged into the element's children table via `for k, v in
  pairs(props.children)`.
- State: `useState`; connections in `useEffect` with cleanup; high-frequency
  values (scroll) via `useBinding` + `:map()`; instance access via `useRef`.
- Disabled state: wrap in `CanvasGroup`, `GroupTransparency = 0.22`, plus a
  light overlay with gradient transparency (copy `SettingRow`).
- Selection state: swap Outer/Rim gradients to gold (copy `PetCard`) — never
  add an external ring (it clips in scroll windows).

## 8. Do not

- No `Offset`, no images for chrome (only provided `rbxassetid://` icons in
  `Theme.Hud.Icons` or ids the task supplies), no UIStroke on big text.
- No hardcoded colors in components; no new palettes.
- No `AutomaticCanvasSize` with scale-sized grid cells (see patterns pitfalls).
- No hover/press animations, tweens, or sounds (current art direction).
- No API-breaking edits to shipped components.
