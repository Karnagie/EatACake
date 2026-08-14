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
| Global pointer continuation | `src/shared/UIKit/InputBridge.lua` is a callback fan-out only; `src/client/common/subscriptions/UiInputSubsClient.lua` owns the two `UserInputService` connections (R4). Used when a drag must still resolve after leaving its GuiObject |
| React root owner (client) | `src/client/common/modules/UiRoot.lua` — `Init()` by bootstrap, `Render(element)`, `Unmount()` |
| React packages | `ReactLua-Packages.rbxmx` — vendored model (React + ReactRoblox + node_modules), rojo-mapped to `ReplicatedStorage.Packages` |
| Demo selector | `UIKit.Demos.Selector` (`SHOW` constant: Hud / PetsInspect / Pets / Settings) |
| Match selector | `Components.MatchmakingPanel` + `CakeCard` + `MatchDifficultyChoice` + `MatchPartyChoice`; integration in `features/lobby-matchmaking.md`. Landscape 1000x600 child-first configurator inside 904x432: setup 452 + empty gutter 32 + cake carousel 420. Left: three 142x112 portrait Difficulty tiles (reward prose omitted), a 48px inter-group gap, then four 101x84 Party controls with the large numeral left and group glyph right; both centred headings use the same token as Cake. Right: title 28 + gap 12 + 420x300 horizontal peek pane. Footer: no status row, then a centred 760x76 START whose own label carries busy/error feedback. Header uses saturated `HeaderWide`; START uses a deep emerald and `Button.pulse` inside a headroom-inflated CanvasGroup (`StartPulseHeadroom`) because CanvasGroup clips. Content ends y564; `PanelWide`'s fill ends y573. START synchronously latches the session before dispatch, and every alternate setup/cake/close path consults that latch until authoritative busy completes. Composite pressables pass semantic `analyticsId` explicitly — their child is named `HitTarget` |
| Cake chooser (panel) | `Components.CakeSelectPanel` (`Theme.CakeSelectLayout`) — landscape 1000x600 on `PanelWide`/`HeaderWide`, a 3-column grid in `ScrollPane` (the catalogue GROWS, so it is a browsable gallery, not a fixed showcase — rebuilt from 2 fixed cells 2026-08-11, which left ~160px of dead margin and made the panel read as chrome). Deterministic grid math: rows -> `canvasHeightScale`, `FillDirectionMaxCells` set, cell wrapper carries the baked row gap. ⚠ `ScrollPane` DROPS its track when the canvas fits, so at ≤3 cakes there is no visible scrollbar BY DESIGN; it appears at the 4th (measured both ways). Integration in `features/cake-select.md` |
| Cake showcase cell | `Components.CakeCard` (`Theme.CakeCard`) — nominal 282x348, the CARD recipe (style-rules §2b): even outline, internal zones, colour only in the art window. FOUR states, COLOUR only, never geometry: selected = gold `Outer` gradient swap · unlocked = normal navy body (deliberately not quieted — grey is this kit's LOCKED language) · locked = grey body + grey art window + art faded via `ImageTransparency` (not tinted) + PADLOCK badge + unlock-hint line · comingSoon = the same grey language with a CLOCK badge, so one visual language carries two messages. Measured live: outline bottom/top 1.43x (card recipe), aspect 0.809, icon 33% of the cell by area — the art window took the space a price shelf would have used |
| Cake gallery tile (matchmaking) | `Components.CakeCard` with `Theme.MatchCakeCard` — fixed 264x292 portrait CARD-family tile: free-standing 190px rendered art (`ShowArtPlate = false`), wrapping name, optional wrapped requirement, and lock/clock badge only for unavailable states. Selected uses a gold perimeter plus the kit's royal-navy card Face; the mismatched purple/check disk are absent. Three cards, two 16px gaps, and 8px side padding make an exact 840px X canvas inside the 420px pane. Offset zero shows Classic fully plus exactly half Rainbow; selecting Rainbow centres it at offset 210. Placement and tap hit-testing share the same carousel geometry. The earnable rainbow requirement renders on its own card; the coming-soon title/clock are not duplicated, and no status row sits above START. `focusableWhenLocked` + `onLockedActivated` preserve controller dead-press telemetry. External `enabled` adds a busy overlay; pointer analytics are dispatched by the pane capture surface while real cards remain semantic controller buttons |
| Lock badge | `Theme.CakeLockBadge` — `Badge` geometry, grey on purpose: the default badge is GREEN, which in this kit means owned/claimed/available. Carries `UiLock` (earnable) or `BadgeClock` (coming soon) |
| Social offer window | `Components.SocialPanel` (`Theme.SocialLayout`) — art / headline / body / status / one CTA, portrait Panel family. Shared by Invite Friends and the community reward (`features/referrals.md`, `features/group-reward.md`) |
| Onboarding surfaces | `Components.TutorialSlides` / `TutorialHint` / `InputGlyph`; integration in `features/tutorial.md`. ⚠ `TutorialHint` is the kit's one deliberately NON-modal overlay (style-rules §9). `HintArrow` (a screen-space objective pointer that owns a RenderStepped, ADR-0016) is still exported but UNUSED since 2026-08-09 — onboarding's world guidance is a Beam |
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
  - **covering the screen and PLACING on it are different contracts**: scrims and
    dims stay `Size (1,1)`, but anything that places a CONTROL near an edge takes
    a safe-area inset. `AppRoot` resolves it once from `Theme.SafeArea` and hands
    it down (`features/app-root.md` owns the units and the CoreGui measurements).
    `GetGuiInset()` alone is not enough — it is the legacy value and can
    under-report the modern unibar, and Roblox's touch jump button owns the
    bottom-right corner. A full-bleed overlay that positions its own buttons and
    ignores this is the bug the rule exists to prevent (the hex tree's calories
    chip shipped under the unibar for months);
  - **pointer coordinates**: `InputObject.Position` (from `InputBegan` etc.) is in
    the same space as `AbsolutePosition` in EITHER inset mode — use it. Do NOT
    write `GetMouseLocation() - GuiService:GetGuiInset()`; that assumes an inset
    root and silently breaks by the topbar height. `ScrollPane`'s track click had
    to be converted; `HexTreeOverlay` already used the safe convention.
- Wiring: callbacks passed into props; remotes/state subscriptions live in
  `subscriptions/` (R4). Declarative `React.Event` / `React.Change` bindings
  stay inside components; engine-global input continuation is owned once by
  `UiInputSubsClient` and fanned into components through `InputBridge`.
- Kit buttons using `Interaction.usePressable` activate through
  `GuiButton.Activated`, not mouse-only click events, so the same callback works
  for mouse, touch and controller A/cross. Pointer press animation remains
  pointer-driven; controller/keyboard activation is cued and counted at release.
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
- **`CelebrationBanner`** (2026-08-13, `Theme.CelebrationBanner`, nominal
  900x260) is the transient splash for the three celebration beats — a cake
  layer cleared, a crumb monster down and the Cake Monster down
  (`features/food-burst.md`). ⚠ **It has NO background** — no Outer/Rim/Face
  stack, no fill of any kind. It shipped with a gold plate for one commit and it
  was cut: a slab that size sits over the cake for three and a half seconds, and
  §2c's "a dark outer pill under a lighter face reads PRESSABLE" is exactly
  wrong for a non-interactive splash shown to pre-readers. Contrast comes from
  size plus `OutlinedText`'s stroke, which is therefore load-bearing. It is NOT a
  replacement for `AnnounceBanner`, which still carries every informational
  announce; the two are mutually exclusive by construction. It is a NON-modal
  full-bleed sibling of `Hud` at zIndex 30 (the free 4-39 band) and deliberately
  brings no scrim: it is not interactive and must not steal a tap mid-run.
  Its motion is the kit's first one-shot timeline outside `Interaction` — a
  slam-in / breathe / launch-out driven by a single `useEffect` re-keyed on a
  `seq` prop. ⚠ Every property it tweens (`UIScale.Scale`,
  `CanvasGroup.GroupTransparency`, `CanvasGroup.Rotation`) is one React never
  writes (ADR-0006) — the HUD re-renders ~14x/s and would snap them back.
- **ScrollPane supports X or Y** (`scrollingDirection`, default Y) with
  deterministic `canvasWidthScale` / `canvasHeightScale`. It auto-hides its
  track when the configured axis scale is `<= 1` (a full-length thumb on a
  non-scrolling pane falsely advertises content);
  the legacy `AutomaticCanvasSize` path keeps its track. Optional `resetKey`
  resets deterministic panes in a layout effect, while `resetScrollFraction`
  chooses a clamped main-axis position instead of always returning to zero, so
  a mounted-hidden panel cannot reopen at a stale offset. Track taps and thumb
  drags accept mouse or touch; a touch drag is correlated to its initiating
  `InputObject`, so a second finger neither hijacks nor cancels it. Because the
  thumb is nested under the track, the ancestor's `InputBegan` ignores points
  inside the live thumb bounds; otherwise every grab first jumps the canvas.
  Track and thumb are deliberately `Selectable = false` until controller scroll
  actions exist, so gamepad navigation never lands on an inert focus target.
  `showScrollbar = false` removes the track without changing deterministic
  canvas math. Optional `contentDrag` adds a transparent, pointer-only capture
  surface over interactive children: it classifies an 8px mouse/touch gesture
  before `onTap(releasePoint01, inputType, startPoint01)` dispatch, so dragging a
  card leaks no press cue, analytics, or activation. Semantic grids validate
  that start and release resolve to the same cell; a sub-threshold gutter-to-card
  drift is not a tap. A wheel tick cancels any held pointer tap before it
  moves the canvas, so release cannot select the card that scrolled underneath.
  `scrollingEnabled = false` still captures while
  freezing movement (busy state); either enabled-state transition clears the
  pointer owner, so a press cannot begin disabled and release live. Global move
  and release continuation comes from subscription-owned `InputBridge`; each
  mounted pane no longer creates its own `UserInputService` connections. The surface
  is `Selectable = false`; real
  child buttons remain the controller focus/activation targets. This reuses the
  input-capture shape proven in `HexTreeOverlay`.
- **Animation** (ADR-0006): base buttons already carry press/hover feedback via
  `Interaction.usePressable` + `pressLayer`; panels pop (`PanelShell`), badges
  pop-in, belly/cake bars glide, the settings toggle knob slides. Tune via
  `Theme.Feel`. Animate a property with `TweenService` on a `ref` — NEVER also
  pass that property as a React prop that changes (React clobbers the tween on
  the next re-render, and the HUD re-renders ~14×/s). Pass no prop (UIScale) or a
  constant (`Interaction.ZeroFill`, `KNOB_INITIAL`). New kit buttons should reuse
  `usePressable`/`pressLayer` rather than hand-rolling animation.
  - **Attention PULSE** — a looping reversing tween on a SECOND UIScale, so the
    press bounce keeps working (Roblox applies at most one UIScale per
    GuiObject). `Components.Button` `pulse` (`Theme.Feel.Pulse`, 1.10),
    `Components.HexNode` `pulse` (`Theme.HexTree.Pulse`, 1.06 — the honeycomb is
    packed edge-to-edge) and `Components.HudMenuButton` `pulse`
    (`Theme.Feel.Pulse`). All mount the UIScale unconditionally so turning the
    pulse off can EASE back to 1 instead of freezing mid-breath, and all cancel
    + land on 1 on unmount.
    ⚠ **WHERE the second UIScale goes depends on who owns the position.** Button
    and HexNode put it on the ROOT, which grows about the root's AnchorPoint.
    `HudMenuButton` cannot: a `UIGridLayout` owns its cell Position, so a root
    UIScale swells the icon down-and-right into its neighbours. It nests a
    centre-anchored full-size `Pulse` frame INSIDE `pressLayer`'s `Content`
    instead — the two scales then compose (press pop × attention breathe) and the
    zone fractions inside are unchanged. Copy the recipe, not the placement.
  - **`Selectable` is part of a modal contract, and a scrim does not cover it.**
    A scrim stops POINTER access; controller selection is a separate channel.
    Every pressable ties `Selectable` to `enabled` — except `HudMenuButton`,
    which had no `Selectable` at all until 2026-08-13, so a D-pad could reach a
    HUD button under an open panel's own (deliberately `Selectable = false`)
    scrim. Any new kit button MUST set it; any HUD that can be covered must pass
    it down (`features/app-root.md`).
  - **Staggered ENTRANCE** (`Theme.Feel.SlideIn`) — a fixed set of sibling cards
    appearing one after another: each is HIDDEN until its `task.delay` elapses,
    then pops from `ClosedScale` on a UIScale inside an `Interaction.pressLayer`
    wrapper (a bare UIScale grows a top-left-anchored frame out of its gaps).
    Each piece owns its own effect keyed on `visible`, whose cleanup cancels its
    tween and lands BOTH properties on their rest values. First use: the
    onboarding comic (`features/tutorial.md`). ⚠ Two derived numbers, not tastes:
    `ClosedScale` is bounded by the layout's own gaps (Back-out overshoots ~10%
    of the travel, half of it on each side, so two neighbours must still clear at
    the peak), and a scrim fade needs the separate non-overshooting `FadeTween` —
    Back on a transparency drives it past the target and clips at 0.
  - ⚠ **A `CanvasGroup` clips to its own bounds**, so any pulse inside one needs
    the group inflated and the child deflated by the same factor (the
    matchmaking START button's recipe) — otherwise the breath is sliced off on
    all four sides.

## Icons
`Icons.lua` holds 170 `name -> rbxassetid` entries (`Ui*` glyphs, `Pass*`
badges, `Rarity{Disc,Star}*`, `Ribbon*`, `GemPack*`/`CoinPack*`/`Egg1..8`,
`Sq*` squishies). **Components take an icon NAME in props and resolve through
`Theme.Icon(name)`; a raw `rbxassetid://` literal in a component is forbidden.**
`Theme.Icon` warns ONCE on an unknown name (R8) and returns a visible fallback
glyph — never a blank ImageLabel, which is indistinguishable from a layout bug.
To add art: serve the sprite folder over http (`python -m http.server`) and use
the Studio MCP `upload_image` tool — it rejects local file paths (http/https
only) and times out past ~15 images per call — then add the rows here.
`Icons.CakeClassic` / `Icons.CakeRainbow` (2026-08-11) are PRODUCT art, not
chrome glyphs: drawn big inside `CakeCard`'s art window, and referenced by KEY
from the catalogue (`features/cake-select.md`), never by cake id — re-skinning a
cake is one row here. The same change gave the long-unused `Icons.UiLock` its
first call site: the cake lock badge.

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
