# ui-kit

Candy-style ReactRoblox UI kit. Single source for the game's UI look.
**HOW to build UI with it lives in the skill:** `.claude/skills/roblox-ui-kit/SKILL.md`
(+ its `references/` — style rules, component APIs, patterns/pitfalls). This
doc covers integration only; do not duplicate the skill here.

## Entry points

| Piece | Path |
|---|---|
| Kit (Theme + component catalog + demos) | `src/shared/UIKit/` → `ReplicatedStorage.Shared.UIKit` (exact list: `UIKit.init` Components table) |
| Interaction primitive (press/tween juice) | `src/shared/UIKit/Interaction.lua` — `usePressable`, `pressLayer`, `merge`, `useFillGlide`, `ZeroFill`; timings in `Theme.Feel`. ADR-0006 |
| React root owner (client) | `src/client/common/modules/UiRoot.lua` — `Init()` by bootstrap, `Render(element)`, `Unmount()` |
| React packages | `ReactLua-Packages.rbxmx` — vendored model (React + ReactRoblox + node_modules), rojo-mapped to `ReplicatedStorage.Packages` |
| Demo selector | `UIKit.Demos.Selector` (`SHOW` constant: Hud / PetsInspect / Pets / Settings) |
| Match selector | `Components.MatchChoice` + `Components.MatchmakingPanel`; integration in `features/lobby-matchmaking.md` |
| Effect template | `Templates.UpgradeTreeBlur`; cloned by the lobby upgrade modal (R5) |

## Setup

React is VENDORED as `ReactLua-Packages.rbxmx` (one model: `Packages` folder
holding `React`, `ReactRoblox`, and `node_modules`), mapped to
`ReplicatedStorage.Packages` via `default.project.json`. Rojo syncs it
automatically — **no npm, no build step**. Copies get React out of the box.
To update React: replace the `.rbxmx` (re-export the jsdotlua packages under a
`Packages` folder). `require(ReplicatedStorage.Packages.React)` /
`.ReactRoblox` are the entry points.

## Contract

- All player-facing UI is composed from `UIKit.Components` and styled ONLY via
  `UIKit.Theme` (skill iron rules). New style sections go into `Theme.lua`.
- Mounting: feature root components are rendered through `UiRoot.Render(...)`.
  One React root; windows toggle via state (`openPanel` pattern, panels
  `zIndex = 50`, HUD `zIndex = 1`) — see `UIKit.Demos.HudDemo`.
- Wiring: callbacks passed into props; remotes/state subscriptions live in
  `subscriptions/` (R4). React-internal events are library-internal (R4
  exemption, same as ProfileStore signals — ADR-0001 precedent).
- R5 note: the React tree is the kit's declarative "template"; do not
  hand-build Instance trees for kit UI. Studio-authored UI (UiData resolver)
  remains valid for non-kit bespoke visuals.
- **Animation** (ADR-0006): base buttons already carry press/hover feedback via
  `Interaction.usePressable` + `pressLayer`; panels pop (`PanelShell`), badges
  pop-in, belly/cake bars glide, the settings toggle knob slides. Tune via
  `Theme.Feel`. Animate a property with `TweenService` on a `ref` — NEVER also
  pass that property as a React prop that changes (React clobbers the tween on
  the next re-render, and the HUD re-renders ~14×/s). Pass no prop (UIScale) or a
  constant (`Interaction.ZeroFill`, `KNOB_INITIAL`). New kit buttons should reuse
  `usePressable`/`pressLayer` rather than hand-rolling animation.

## Gotchas

- The skill's `references/patterns.md` pitfall list (ScrollingFrame CanvasSize
  parent quirk, grid cell collapse, gui-inset input coords, plugin require
  cache) — read before touching grids/scroll/drag.
- `Theme.Hud.Icons` are placeholder asset ids; per-game replacements expected.
- Demos are mock-state reference compositions, not shippable features.
