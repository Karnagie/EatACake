# 2026-07-19: HUD juice + menu grid (press feedback, panel/badge pops, bar glide)

Tags: ui-kit, app-root, ui, juice

## Task
Two player-facing polish asks:
1. The left HUD icon menu ran in one tall column all the way to the bottom of
   the screen — arrange it into multiple rows so it stops higher up.
2. The buttons all work but give NO visual feedback (no animations/reactions).
   Add tweens + effects so the UI feels polished and responsive, to modern
   Roblox-game standard.

## Context
- HUD is the one React tree in `client/modules/AppRoot.lua`. The menu was 8
  `HudMenuButton`s in a vertical `UIListLayout` (`Theme.AppHud`, y 172→1056 on
  the 1080 reference — nearly full height). See prior
  `docs/flow/2026-07-19_hud-ui-polish.md` (which created `HudMenuButton`).
- The kit (`src/shared/UIKit/`) had ZERO interaction animation — every button
  was a static React tree; the skill even forbade ad-hoc hover/press animation
  (iron rule 8) unless a task explicitly asks. This task explicitly asks.
- Kit idioms already present (ScrollPane): `React.useRef` + `ref=` on host
  instances, `useBinding`, `useEffect` cleanup, imperative instance edits via
  refs. `ComboBadge` already used a `UIScale` pulse (snap, not tween).

## Plan
Kit-first, one shared primitive so the whole UI gets a consistent feel from a
single implementation, all timings in `Theme.Feel`:
- Menu → `UIGridLayout` (config-driven `MenuColumns`, default 2 → 2×4 block).
- New `Interaction.lua`: `usePressable` (hover/press UIScale bounce via
  TweenService), `pressLayer` (center-anchored `Content` wrapper), `merge`,
  `useFillGlide`. Apply press feedback to Button / HudMenuButton / CloseButton /
  IconButton. Panel open/close pop in `PanelShell` (covers all 7 HUD panels).
  Badge pop-in, belly/cake fill glide, settings toggle knob slide.

## Changes

**Created:**
- `src/shared/UIKit/Interaction.lua` — `usePressable(config) -> (scaleRef,
  handlers)`; `pressLayer(scaleRef, zIndex, children)`; `merge(base, extra)`;
  `useFillGlide(fill01) -> fillRef`; `ZeroFill`. See `features/ui-kit.md` +
  ADR-0006 for the "ref-owned tween vs React reconciliation" contract. Includes
  a `useEffect` keyed on `enabled` that resets scale/flags when a button is
  disabled (review fix — see Decisions).

**Modified:**
- `Theme.lua` — new frozen `Theme.Feel` (all tween/scale constants). `AppHud`:
  `MenuColumns=2`, `MenuButtonWidth`, `MenuGapX`; removed dead `MenuWidth`.
- `client/modules/AppRoot.lua` — menu container `UIListLayout` → `UIGridLayout`
  (`FillDirectionMaxCells = MenuColumns`, cell size/padding as fractions of the
  Menu frame); Menu frame sized `menuTotalWidth × menuTotalHeight`
  (rows = ceil(count/cols)); buttons drop their explicit `size` (grid owns it).
- `Components/Button.lua`, `HudMenuButton.lua`, `CloseButton.lua`,
  `IconButton.lua` — visuals moved into `Interaction.pressLayer` (a centered
  `Content` frame carrying the press `UIScale`); `usePressable` handlers merged
  onto the root `TextButton`; `Aspect` stays on the TextButton (the stable,
  unscaled hit target). The hook owns activation (`MouseButton1Click`).
- `Components/PanelShell.lua` — open = springy pop `PanelClosedScale→1`; close =
  quick shrink then hide (internal `shown` state gates `Visible` so the shrink
  is seen); `OpenScale` UIScale + `useEffect` keyed on `visible`.
- `Components/Badge.lua` — pop-in from scale 0 (`useLayoutEffect` keyed on
  `visible`, pre-paint so no full-size flash); hooks moved above the early
  return.
- `Components/BellyBar.lua`, `CakeBar.lua` — Fill width glides to fill via
  `useFillGlide` (ref + tween); constant `Size = Interaction.ZeroFill`.
- `Components/Toggle.lua` — knob slides across the track (`useLayoutEffect`
  keyed on `value`, snap on first mount); `KnobFill` nested UNDER `Knob` so it
  rides along; only the constant `KNOB_INITIAL` is ever written by React.

**Follow-up (same session):**
- `Components/GymOverlay.lua` — the round fat-burn TAP button was a hand-built
  `TextButton` (no feedback); converted to a component using `usePressable` +
  `pressLayer` so every tap squishes/springs. (Activation moved from
  `[React.Event.Activated]` to the hook's MouseButton1Click — fires for mouse +
  touch, the overlay's inputs.)
- `subscriptions/BodySubsClient.lua` — hide the world `GymPrompt` ("Burn it
  off!") for this player while the belly is empty: track local `fill` from
  `StomachUpdate`, set the prompt's `Enabled` locally (resolved by class under
  `Map.Checkpoint.GymMachine`) from the ~5 Hz loop + on each `StomachUpdate`.
  Mirrors the server's `fill < minStartFill` guard. See `features/body-gym.md`.
- `modules/AppRoot.lua` — new `AppRoot.GetOpenPanel()` getter (see below).

**Follow-up review fix (adversarial-reviewer on the gym changes):** the reviewer
caught a real regression — `updateGymPrompt` ran every frame and would re-enable
the gym prompt even while the upgrade-tree modal had deliberately disabled ALL
checkpoint prompts (so E-to-close can't also start a gym session behind the
overlay). Fix: the gate SKIPS while `AppRoot.GetOpenPanel() == "Upgrades"` (new
getter). Also added an R8 `Log.GraceOnce` for a never-resolving gym prompt
(matching the sibling checkpoint-plate check). Verified live: with a full belly,
opening the tree keeps the gym prompt disabled; closing re-enables it. Accepted
as-is: activation moved to MouseButton1Click drops gamepad-A on the mash button
(now consistent with every other kit button); `lastFill` init 0 hides the prompt
until the first `StomachUpdate` (desirable).

## Decisions
- **Center-origin pop via an inner `Content` frame, not on the TextButton.** A
  `UIScale` scales its parent around that parent's `AnchorPoint`. Button roots
  are anchored top-left (and under `UIGridLayout` must stay so), which would
  make the pop lean to a corner. Fix: wrap visuals in a `(0.5,0.5)`-anchored,
  full-size, transparent `Content` frame and put the `UIScale` there — the pop
  grows from the middle while the root TextButton stays the fixed layout cell /
  hit target. Non-Active `Content` doesn't steal input (Studio-verified: hover
  1.05, click still opens the panel).
- **Ref-owned tween must never fight React.** Any property animated by
  TweenService via a ref must not also be written by React on re-render (the HUD
  re-renders ~14×/s), or React clobbers the tween. Two guards: (a) never pass
  the prop — the `UIScale` carries NO `Scale` prop (defaults to 1, only the
  tween touches it); (b) pass a CONSTANT value — Fill uses `Interaction.ZeroFill`
  and the toggle knob uses `KNOB_INITIAL`, both stable references that react-lua
  skips. Captured as ADR-0006.
- **Grid via `UIGridLayout`, cell math closes.** Menu 2×4 (92+12+92 wide,
  4·100+3·12 tall on the 1080 ref); `HudMenuButton` has NO aspect constraint
  (pitfall #2: aspect-in-grid collapses cells), so cells are safe; icon
  `ScaleType.Fit` self-squares in any cell shape. `FillDirectionMaxCells` set
  (pitfall #6). Columns is a `Theme.AppHud.MenuColumns` knob.
- **One `PanelShell` change animates all 7 panels** — every HUD panel routes
  through PanelWithHeader → PanelShell, so the pop is defined once.
- **Skipped a StatPill value bump** — calories tick continuously while eating,
  so a per-change bump would vibrate constantly. Bars glide instead.
- **All timings in `Theme.Feel`** (kit rule 2). Backward-compatible: no
  component API changed; animation is driven off existing props (`visible`,
  `value`, `fill01`).
- **Disabled-while-hovered reset (adversarial-review fix).** A 4-lens review
  (react-lua / kit-rules / perf / ux-edge, each finding adversarially
  re-verified) confirmed ONE real defect: when a button's `enabled` flips false
  mid-hover/press, `usePressable`'s memo returns `{}` → react-lua disconnects the
  pointer handlers → nothing can spring the `UIScale` back, so it stays stuck at
  1.05/0.93 (reachable via every affordability-gated button: RebirthPanel
  `canAfford`, UpgradeRow `canBuy`, ShopRow `owned`, QuestRow `canClaim`,
  HexTreeOverlay `affordable`). Fix: a `useEffect` keyed on `enabled` resets the
  flags + tweens scale→1 on disable. Every other flagged item (menu cell width
  summing to exactly 1.0; fill/menu GC churn; touch stuck-squish; IconButton
  `children` now inside `Content`) was REJECTED on verification — notably the
  exact-1.0 menu cell, which a verifier live-swept across 2000+ viewport widths
  with 0 column collapses (`FillDirectionMaxCells=2` + no `UIPadding` → cells are
  fractions of exactly the container, never overflow).

## Open Questions / Followups
- The kit skill's iron rule 8 ("no hover/press animations… unless asked") is now
  partly superseded: base buttons carry press feedback via the sanctioned
  `Interaction` primitive. `references/components.md` documents it; rule 8 still
  bars *ad-hoc* per-component animation outside the primitive.
- Hover is desktop-only (MouseEnter/Leave); touch gets the press squish. Fine
  for a mobile-first sim.

## Related
- Feature: `docs/features/ui-kit.md`, `docs/features/app-root.md`
- ADR: `docs/decisions/0006-react-lua-animation-primitive.md`
- Prior flow: `docs/flow/2026-07-19_hud-ui-polish.md`
- Upstream: `docs/upstream/QUEUE.md` (Interaction primitive + grid menu)
