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

⚠ **This is the BUTTON recipe. A CARD uses a different one — see §2b.**
Applying the thickness table below to a card is how the shop shipped cells that
"looked like stretched buttons": measured 8px of outline at the top and 30px at
the bottom on a 282x296 cell.

Thickness for a PRESSABLE element of nominal height H (button scale, H 48-160):
- Outer visible: **~6% H top/left/right, ~12% H bottom** (bottom is always
  ~2x thicker — the "weight" that makes elements look physically thick).
  Example (button 418x103): rim inset 6px top/side; face y 8..88.5 → outer
  bottom lip 14.5px vs 6px top.
- Rim: visible ring ~3% H between Outer and Face; its gradient flashes bright
  only near the top (see gradient recipes).
- Elements < 50px nominal may drop the Rim (2 layers: Outer + Face) — e.g.
  stat row inside inspector. Premium elements (close button) add an InnerRim
  (4 layers).

## 2b. Card recipe — A CARD IS A FRAME, A BUTTON IS A SLAB

A **button** is a slab: ONE colour field, outline bottom-weighted 2x+, squat.
A **card** is a container: EVEN outline, and INTERNAL ZONES. Get either half
wrong and the card reads as a big button no matter what colour it is.

```
Outer     dark outline, EVEN: ~2.5% of H top/left/right, ~3.5% bottom (≤1.5x —
          enough weight for the kit, far under the 2x+ that says "press me")
 Face     the card BODY — one neutral for the whole grid
  ArtRing accent-coloured window, FULL content width, ~50% of the card height
  ArtFace inset by an EVEN ring (3-5px) — a window, not a bevel
   Icon   square, centred, ~85% of the window's SHORT side
  Title / one perk line
  Shelf   the price button — the ONLY part drawn with the §2 button recipe,
          because it is the only part that is a button
```

- **Portrait, not square.** 0.78-0.85 (w/h). The shop's 282x296 (0.95) was the
  second "button" tell after the bevel.
- **Colour belongs in the ART WINDOW, not the body.** N cards in N saturated
  hues have no hierarchy — every cell shouts equally. One neutral body + N
  coloured windows reads as one object, and puts the strongest local contrast
  around the product art, where the eye should land.
- **The art window is load-bearing, not decoration.** `ScaleType.Fit` draws an
  image at the SHORTER side of its box, so art of different aspect ratios drawn
  straight on the face renders at wildly different visual sizes. One window
  normalises them. (Worked example + measured before/after:
  `docs/features/shop.md`.)
- **Every zone shares one left and one right edge** — a single content column
  for art, title, perk and price. Most of "tidy" is that alignment.
- State changes colour, never geometry (the PetCard rule): selection/premium is
  a gradient swap on the Outer.

## 2c. Tag recipe — a TAG is FLAT

Three surface languages, one per interaction class:
**button** = slab (one field, bottom-weighted outline, rim flash) ·
**card** = frame (even outline, internal zones) · **tag** = FLAT.

A passive label (bundle chip, badge, counter, "what you get" row) never
wears the button recipe — a dark outer pill under a raised lighter face
reads PRESSABLE no matter how small it is (the hero's bundle chips shipped
that way and the user tried to read them as buttons). A tag is ONE flat
fill (if the geometry has two layers, give both the same gradient), a
near-flat vertical shade at most, no bright top flash, no dark bottom lip,
and a soft mid-value text outline. Separate it from its surface by VALUE
(~one band, dL* ~ +12-15), not by chrome. Prototype: `Theme.ShopHeroItem`.

The inverse holds for quieting INTERACTIVE elements: lighten their own hue
family but KEEP the rim flash + bottom lip — strip those (or drain the
saturation) and the element reads DISABLED (the kit's locked-gray
language), which is how the idle shop tabs briefly shipped looking locked.

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

**QUIET means close in VALUE to the surface, not merely low chroma.** A
desaturated slate that is still dark reads dL* −58 on the white panel and
out-shouts the selected gold tab in grayscale (measured — the shop's idle
tabs shipped that way twice). Idle/inactive/chrome states are LIGHT washes
of the surface they sit on (target |dL*| ≤ ~15); verify with the
`tonal-hierarchy` skill, not by eye.

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
- No HAND-ROLLED animation. (This line used to read "no animations, tweens or
  sounds (current art direction)" — that is STALE and was contradicted by
  ADR-0006, SKILL.md iron rule 8, the shipped `Interaction` primitive and every
  press/pop/glide in the kit. The live rule: motion comes from `Interaction`
  and `Theme.Feel`; a component may own a ref-driven tween of a property React
  never writes; nothing animates a prop React recomputes.)
- No API-breaking edits to shipped components.

## 9. Instruction surfaces must not consume the input they teach

A popup that says "click to eat" / "press this button" is the one overlay class
that must NOT be modal.

Roblox sets `gameProcessed = true` on `UserInputService.InputBegan` for any
click that lands on an `Active` GUI surface. Gameplay input in this project is
read exactly that way (`CakeSubsClient`), so the kit's usual full-screen click
catcher — `PetRevealOverlay.ClickCatcher`, `Active = true` — silently swallows
the very click the popup is pointing at. Nothing about the component looks
wrong; the feature just stops working while the lesson is on screen.

- Teaching surface: **no scrim, no catcher.** Only its CTA is a `TextButton`;
  everything else is an inert Frame. Position it clear of the control it names.
  It should also self-dismiss the first time the taught action succeeds.
- Blocking surface (a story board, a reveal): take the catcher deliberately,
  and hide the whole **HUD layer** rather than element-by-element — a
  translucent scrim shows every element you forgot. A HOLD button still needs
  its own `visible` gate: `usePressable` releases a hold when `enabled` flips,
  not when an ancestor's `Visible` does.

Worked example: `TutorialHint` vs `TutorialSlides` (`features/tutorial.md`).
