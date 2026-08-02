# ui-kit

Candy-style ReactRoblox UI kit. Single source for the game's UI look.
**HOW to build UI with it lives in the skill:** `.claude/skills/roblox-ui-kit/SKILL.md`
(+ its `references/` — style rules, component APIs, patterns/pitfalls). This
doc covers integration only; do not duplicate the skill here.

## Entry points

| Piece | Path |
|---|---|
| Kit (Theme + component catalog + demos) | `src/shared/UIKit/` → `ReplicatedStorage.Shared.UIKit` (exact list: `UIKit.init` Components table) |
| Icon registry | `src/shared/UIKit/Icons.lua` — flat `name -> rbxassetid`, published as `Theme.Icons`; resolve via `Theme.Icon(name)` |
| Interaction primitive (press/tween juice) | `src/shared/UIKit/Interaction.lua` — `usePressable`, `pressLayer`, `merge`, `useFillGlide`, `ZeroFill`, `FullSize`; timings in `Theme.Feel` (+ `Feel.Squish`). ADR-0006 |
| React root owner (client) | `src/client/common/modules/UiRoot.lua` — `Init()` by bootstrap, `Render(element)`, `Unmount()` |
| React packages | `ReactLua-Packages.rbxmx` — vendored model (React + ReactRoblox + node_modules), rojo-mapped to `ReplicatedStorage.Packages` |
| Demo selector | `UIKit.Demos.Selector` (`SHOW` constant: Hud / PetsInspect / Pets / Settings) |
| Match selector | `Components.MatchChoice` + `Components.MatchmakingPanel`; integration in `features/lobby-matchmaking.md` |
| Onboarding surfaces | `Components.TutorialSlides` / `TutorialHint` / `InputGlyph` / `HintArrow`; integration in `features/tutorial.md`. ⚠ `TutorialHint` is the kit's one deliberately NON-modal overlay (style-rules §9); `HintArrow` owns a RenderStepped (ADR-0016) |
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
- **The root ScreenGui is FULL-BLEED** (`IgnoreGuiInset = true`,
  `ScreenInsets = DeviceSafeInsets`, 2026-07-30). It was inset by the CoreUI
  topbar, which shrank the entire tree — so every modal SCRIM stopped ~36 px short
  of the top and a "modal" left the world visible in that strip. Consequences any
  UI work must respect:
  - anything that must not slide under the topbar insets ITSELF by
    `GuiService:GetGuiInset()`; `AppRoot`'s `Hud` layer does this and reproduces
    the old space exactly (`features/app-root.md`);
  - **pointer coordinates**: `InputObject.Position` (from `InputBegan` etc.) is in
    the same space as `AbsolutePosition` in EITHER inset mode — use it. Do NOT
    write `GetMouseLocation() - GuiService:GetGuiInset()`; that assumes an inset
    root and silently breaks by the topbar height. `ScrollPane`'s track click had
    to be converted; `HexTreeOverlay` already used the safe convention.
- Wiring: callbacks passed into props; remotes/state subscriptions live in
  `subscriptions/` (R4). React-internal events are library-internal (R4
  exemption, same as ProfileStore signals — ADR-0001 precedent).
- R5 note: the React tree is the kit's declarative "template"; do not
  hand-build Instance trees for kit UI. Studio-authored UI (UiData resolver)
  remains valid for non-kit bespoke visuals.
- **Tonal-hierarchy gate**: new/changed screens are measured with
  `tools/tonal-hierarchy/` per skill `.claude/skills/tonal-hierarchy/`
  (part of the ui-kit verification checklist). Chrome recedes kit-wide:
  `Theme.Scrollbar` thumb + track are a light slate family on purpose —
  the dark button-well versions measurably out-shouted card titles.
- **Modal scrim**: AppRoot renders `Theme.PanelScrim` (zIndex 40) under
  every open panel except Upgrades (HexTreeOverlay carries its own) — dims
  the world + HUD (panels floated over the full-brightness scene) and
  closes the panel on tap-outside. New full-screen overlays either ride it
  or bring their own; never neither.
- **ScrollPane auto-hides its track** when `canvasHeightScale <= 1` (a
  full-height thumb on a non-scrolling pane falsely advertises content);
  the legacy `AutomaticCanvasSize` path keeps its track.
- **Animation** (ADR-0006): base buttons already carry press/hover feedback via
  `Interaction.usePressable` + `pressLayer`; panels pop (`PanelShell`), badges
  pop-in, belly/cake bars glide, the settings toggle knob slides. Tune via
  `Theme.Feel`. Animate a property with `TweenService` on a `ref` — NEVER also
  pass that property as a React prop that changes (React clobbers the tween on
  the next re-render, and the HUD re-renders ~14×/s). Pass no prop (UIScale) or a
  constant (`Interaction.ZeroFill`, `KNOB_INITIAL`). New kit buttons should reuse
  `usePressable`/`pressLayer` rather than hand-rolling animation.

## Icons
`Icons.lua` holds 145 `name -> rbxassetid` entries (`Ui*` glyphs, `Pass*`
badges, `Rarity{Disc,Star}*`, `Ribbon*`, `GemPack*`/`CoinPack*`/`Egg1..8`,
`Sq*` squishies). **Components take an icon NAME in props and resolve through
`Theme.Icon(name)`; a raw `rbxassetid://` literal in a component is forbidden.**
`Theme.Icon` warns ONCE on an unknown name (R8) and returns a visible fallback
glyph — never a blank ImageLabel, which is indistinguishable from a layout bug.
To add art: serve the sprite folder over http (`python -m http.server`) and use
the Studio MCP `upload_image` tool — it rejects local file paths (http/https
only) and times out past ~15 images per call — then add the rows here.

## Squash (the squishy motion signature)
`UIScale` is uniform and cannot squash, so the deform rides the `Size` of
`Interaction.pressLayer`'s `Content` frame — the one ADR-0006-safe carrier,
because React writes that prop exactly once with the constant
`Interaction.FullSize` and then diffs it away forever. Opt in per surface with
`usePressable{ squash = true | {press=, hover=, ...} }` and pass the third
returned ref into `pressLayer(..., squashRef)`. Poses live in
`Theme.Feel.Squish`. Two rules that are load-bearing: the squash config is read
through a REF (never the memo deps, or handlers rebuild on every HUD
re-render), and the disabled path resets `Size` as well as `Scale` (or a button
gated mid-press stays flattened).
Panels can NOT use this — a panel's root `Size` is a live React prop, so the
squash would need an inner constant-sized frame. That variant, and idle
breathing, were designed but deliberately not shipped: they had no call site,
and one of the panel poses would have shadowed the live `Theme.Feel.
PanelOpenTween` that `PanelShell` actually reads. Add them WITH a caller.

## Gotchas

- The skill's `references/patterns.md` pitfall list (ScrollingFrame CanvasSize
  parent quirk, grid cell collapse, gui-inset input coords, plugin require
  cache) — read before touching grids/scroll/drag.
- **A grid inside a scroll wants a DETERMINISTIC canvas.** Aspect-constrained
  cells + `AutomaticCanvasSize` converge on a fixed point where the height binds
  and every row renders narrower than the window (measured: 377px rows in a
  596px window). Sum the content in nominal px, set `canvasHeightScale`, and
  position cells by explicit fraction — see `ShopPanel`.
- **`ScaleType.Fit` draws at the zone's SHORTER side.** A square glyph in a
  short, wide zone wastes all its width — the drawn size is `min(w, h)`, not the
  zone. Icon zones should be near-square, and `IconInset` IS the drawn size:
  0.06 means the art fills 88% of its plate. Measure with
  `min(icon.AbsoluteSize.X, icon.AbsoluteSize.Y)`, never by eye.
  Corollary: art of MIXED aspect ratios (a tall flame, a wide egg cluster, a
  square pack) drawn straight onto a face renders at wildly different visual
  sizes. Give them a shared art window and they normalise — that is the job the
  shop card's window does (`features/shop.md`).
- **A card is not a recoloured button.** `style-rules.md` §2's thickness table
  is the BUTTON recipe (bottom lip 2x+); §2b is the CARD one (even outline,
  internal zones, portrait). Applying §2 to a card is how the shop twice
  shipped cells the user called "stretched-out buttons" — measure the split off
  the live instances, it reads as a drop shadow in a whole-panel screenshot.
- **A grid zone taller than one row of cards is dead space, not breathing room.**
  N columns across a fixed canvas caps the card WIDTH regardless of height, so
  "cards too small in a big panel" is fixed by fewer columns over more rows, not
  by scaling. (Rewards: 7x1 of 118x135 in a 904x360 zone left 62% empty; 4x2 of
  214x172 fills it.)
- **`Theme.AppHud.MenuIcons` values are checked at load** and warn if one fails
  to resolve: a nil silently falls back to the generic placeholder, which reads
  as a design choice rather than a broken reference.
- **`TextScaled` implies `TextWrapped`.** Copy longer than its zone silently
  wraps to two lines and shrinks instead of truncating.
- **Check supplied art's real shape before designing a zone around it.** The
  `Ribbon*` "ribbons" are square 257×257 rosettes; at a 4:1 aspect
  `ScaleType.Fit` renders a centred blob. Chrome is frames; images are icons.
- `Theme.Hud.Icons` are placeholder asset ids; per-game replacements expected.
  `Theme.AppHud.MenuIcons` are real and must stay one-distinct-icon-per-button.
- **`rojo build` is NOT a syntax check.** It packages files without parsing
  Luau, so a malformed module builds cleanly and only fails at `require`
  time. After editing a shared module, start play and read the boot report
  — `[Client/Bootstrap] complete` plus zero `require FAILED` lines is the
  real gate. (A stray `return` left outside a function passed three builds.)
- Demos are mock-state reference compositions, not shippable features.
