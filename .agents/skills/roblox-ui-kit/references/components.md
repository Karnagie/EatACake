# Component catalog and APIs

Kit: `local UIKit = require(ReplicatedStorage.Shared.UIKit)` →
`UIKit.Theme`, `UIKit.Components.*`, `UIKit.Demos` (folder of reference apps).
All components are React function components created with
`React.createElement(UIKit.Components.X, props)`.

Common props on nearly everything: `name`, `anchorPoint`, `position`, `size`
(UDim2, Scale only), `zIndex`, `enabled`, `style` (Theme-section override).

## Primitives

| Component | Purpose | Key props |
|---|---|---|
| `OutlinedText` | ALL text. Scaled UIStroke outline (0.08) + one stroked shadow copy offset (-0.003, +0.1) + gradient fill | `text`, `textColor`, `textGradient`, `outlineColor` (default `Theme.Colors.TextOutline`), `textXAlignment`, `transparency`, `disabled` (legacy `outline*Multiplier`/`outlineCenter` props are accepted and ignored) |
| `Button` | Rect button, Outer/Rim/Face + label | `text`, `style` (default `Theme.Button`; centered text `Theme.ActionButton`; accents `Theme.EquipGreen` / `Theme.UnequipRed`), `textXAlignment`, `onActivated` |
| `IconButton` | Square 1:1 button | `iconImage` (rbxassetid) OR `icon` = `"sort" \| "gear" \| "paw"` (vector glyphs), `style` (default `Theme.IconButton`), `onActivated`, `children` (custom glyph slot) |
| `Toggle` | Pill switch, green on / red off | `value` (bool), `onChanged(newValue)`, `enabled`; default position/size from `Theme.Layout` (inside a SettingRow) |
| `CloseButton` | Red X button (4 layers + rotated-pill X) | `onActivated`, `enabled` |
| `StatPill` | Dark pill: icon + value (currency display) | `value` (string), `iconImage` OR `icon` = `"coin" \| "chevrons" \| "bolt"`, `valueGradient`, `valueOutline` |

## Motion / interaction (`Interaction.lua`, `Theme.Feel`) — ADR-0006

Press/hover feedback and pops are BUILT IN — don't hand-roll animation. Base
buttons (`Button`/`IconButton`/`CloseButton`/`HudMenuButton`) already bounce on
hover/press; `PanelShell` pops open/closed; `Badge` pops in; `BellyBar`/`CakeBar`
fills glide; `Toggle` knob slides. Tune everything in `Theme.Feel`.

`require(ReplicatedStorage.Shared.UIKit.Interaction)`:
- `usePressable(config) -> (scaleRef, handlers)` — `config = {enabled?,
  onActivated?, hoverScale?, pressScale?, feel?}`. Spread `handlers` onto the
  root `TextButton` (via `Interaction.merge(rootProps, handlers)`); the hook owns
  activation (`onActivated`).
- `pressLayer(scaleRef, zIndex, childrenDict)` — wraps visuals in a
  `(0.5,0.5)`-anchored transparent `Content` frame carrying the press `UIScale`,
  so the pop grows from CENTER while the root TextButton stays the unscaled hit
  target / layout cell. Keep the `UIAspectRatioConstraint` on the TextButton,
  NOT inside `pressLayer`.
- `useFillGlide(fill01) -> fillRef` + `ZeroFill` — glide a horizontal fill
  frame's width; give that frame `Size = Interaction.ZeroFill` and the `ref`.

**Iron rule (ADR-0006):** a property animated by TweenService on a `ref` must
NEVER also be written by React on re-render (the HUD re-renders ~14×/s → React
clobbers the tween). Pass NO prop (UIScale carries no `Scale`) or a CONSTANT
(`ZeroFill`, a module-level `KNOB_INITIAL`) the reconciler skips. A new
interactive component reuses `usePressable`/`pressLayer` rather than inventing
its own animation.

## Structure

| Component | Purpose | Key props |
|---|---|---|
| `PanelShell` | Panel body (Shadow/Border/Fill) + aspect + open/close pop | `style` (`Theme.Panel` portrait / `Theme.PanelWide` landscape), `visible`, `zIndex`, `children` |
| `Header` | Header bar with title + close | `title`, `style` (`Theme.Header` / `Theme.HeaderWide`), `showTitle`, `showClose`, `closeEnabled`, `onClose`, `size` |
| `PanelWithHeader` | PanelShell + Header composed | `title`, `panelStyle`, `headerStyle`, `headerSize`, `onClose`, `visible`, `zIndex`, `children` (content is positioned in panel-grid fractions, zIndex 5) |
| `ScrollPane` | Scroll window + custom kit scrollbar | `windowFraction`, `barWidth`, `canvasHeightScale` (REQUIRED for grids — rows math, see patterns), `scrollbarStyle`, `children` (put UIGridLayout/UIListLayout + items here) |

## Composites (reference implementations — copy their structure)

| Component | Shows how to build |
|---|---|
| `SettingRow` | Row = Button surface + Toggle + disabled CanvasGroup fade |
| `SettingsPanel` | Portrait panel with UIListLayout of rows; props `rows` `{id,label,enabled}`, `values` map, `onToggle(id,value)`, `zIndex` |
| `PetCard` | Grid card: rarity recolor (`rarity` = Common/Rare/Epic/Legendary), `selected` (gold swap), `equipped` (badge + vector check), `petName`, `onActivated(id)`, cell wrapper with baked bottom gap |
| `PetsPanel` | Landscape panel: action row (Chip counter + ActionButton + sort IconButton) + 6-col grid in ScrollPane; `pets`, `equipped`, `equippedCount`, `maxEquipped`, callbacks |
| `PetsInspectPanel` | Same + 4-col grid + inspector sidebar (plate, name, stat rows, green/red equip button); extra props `selectedId`, `selectedPet`, `onEquipToggle`, `onPetActivated` |
| `Hud` | Screen overlay: 3 stat rows (icon+colored text) + 2 labeled menu buttons; props `speedText/goldText/energyText`, `onSettings`, `onPets`; `BARE_STATS`/`BARE_BUTTONS` switches at top of file |

## Theme section inventory (Theme.lua)

Style tables: `Colors`, `Gradients`, `Font`, `Toggle`, `Header`, `HeaderWide`,
`Panel`, `PanelWide`, `Button`, `ActionButton`, `EquipGreen`, `UnequipRed`,
`Exit` (close), `IconButton`, `Scrollbar`, `Rarity.{Order,Common,Rare,Epic,
Legendary}`, `PetCard` (+ `SelectOuterGradient`/`SelectRingGradient`),
`Inspector`, `StatRow`, `Chip`, `Hud` (+ `Icons`, per-stat text colors).
Layout tables (per-screen geometry): `Layout` (settings portrait),
`PetsLayout`, `PetsInspectLayout`, `Hud`.
Everything is `table.freeze`d — add new sections in Theme.lua before the
freeze block, plus a `table.freeze(Theme.NewSection)` line.

## Mounting (client)

```lua
-- in a client module or subscription (bootstrap runs modules' Init first):
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local UiRoot = ... -- data/services wiring per bootstrap; module src/client/modules/UiRoot.lua

UiRoot.Render(React.createElement(MyRootComponent))
```

- `UiRoot.Init()` (called by bootstrap) creates the ScreenGui: ResetOnSpawn
  false, CoreUISafeInsets, ClipToDeviceSafeArea, ZIndexBehavior Sibling,
  DisplayOrder 100.
- Quick visual check without wiring: `UiRoot.Render(React.createElement(
  require(UIKit.Demos.Selector)))` — Selector's `SHOW` constant switches
  between Hud / PetsInspect / Pets / Settings demos.
- Real features: copy a demo app's structure (state + callbacks) into a feature
  root component; replace mock tables with data from remoteUpdates; send user
  actions through remotes inside the callbacks you pass as props (wired in a
  subscription module per R4).

## Requirements

`ReplicatedStorage.Packages.React` / `.ReactRoblox` must exist: React is
VENDORED as `ReactLua-Packages.rbxmx` (a `Packages` folder with `React`,
`ReactRoblox`, and `node_modules`), rojo-mapped to `ReplicatedStorage.Packages`
in `default.project.json`. No npm / build step — present in every copy. If the
mapping is broken, UiRoot logs a warning and kit UI is disabled.
