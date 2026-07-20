# ADR-0006: UI animation via ref-owned TweenService, not React-driven props

## Status
Accepted (2026-07-19)

## Context
The kit had no interaction animation — every button/panel/bar was a static
React (jsdotlua/react-lua) tree. A task asked for kit-wide press feedback,
panel/badge pops, and gliding bars. Two properties of the setup make naive
approaches wrong:

1. **The HUD re-renders at bite frequency (~14×/s).** Any animation state kept
   in React state and set each frame would thrash rendering.
2. **React OWNS the props it sets.** If a property is passed as a prop AND
   tweened imperatively, React overwrites the tween on the next reconcile —
   the animation snaps back every re-render.

Options considered: (a) animate via `useState` + per-frame `RunService` loops
(heavy, re-renders); (b) a spring/motion library (none vendored; adds a
dependency); (c) `TweenService` on the real Instance via a React `ref`
(standard Roblox, GC-friendly, no per-frame Lua).

## Decision
A single shared primitive, `src/shared/UIKit/Interaction.lua`, animating real
Instances with `TweenService` through refs, with a hard rule for coexisting
with React:

- **A ref-tweened property is NEVER also written by React on re-render.** Two
  sanctioned ways to satisfy this:
  - **Don't pass the prop.** The press/pop `UIScale` carries no `Scale` prop —
    it defaults to 1 at creation and only the tween ever writes it.
  - **Pass a CONSTANT.** Where React must set an initial value, pass a stable
    value the reconciler skips: `Interaction.ZeroFill` (bar fill `Size`) and
    `KNOB_INITIAL` (toggle knob `Position`). react-lua compares props with `==`;
    Roblox datatypes compare by value, so an unchanged constant is not re-applied
    and the tween is preserved.
- **`usePressable(config) -> (scaleRef, handlers)`** — memoised handlers
  (stable across renders; latest `onActivated` read through a ref) so nothing
  reconnects at bite rate. Desktop: hover (MouseEnter/Leave) + press
  (MouseButton1Down/Up); touch: press via InputBegan/Ended Touch; activation via
  MouseButton1Click (fires for both).
- **Center-origin pop via `pressLayer`** — a `UIScale` scales its parent around
  that parent's `AnchorPoint`; button roots are top-left anchored (and must stay
  so under `UIGridLayout`). So the visuals live in a `(0.5,0.5)`-anchored,
  full-size, transparent `Content` frame that carries the `UIScale`; the root
  `TextButton` stays the unscaled hit target / layout cell. Non-Active `Content`
  doesn't intercept the button's input.
- **All timings/scales in `Theme.Feel`** (kit rule 2); animation is driven off
  existing props (`visible`, `value`, `fill01`) so no component API changed
  (kit rule 8: backward-compatible only).

## Consequences
Every kit button gets consistent, centered press/hover feedback and panels/
badges/bars animate, from one implementation and one tuning table — no
per-component animation code, no new dependency, no per-frame Lua loops. The
"ref owns the prop, React never writes it (or writes only a constant)" rule is
the load-bearing invariant: violating it (passing a changing prop for an
animated property) reintroduces the snap-back bug. Corollary (adversarial
review): a disabled button drops ALL its pointer handlers, so no release event
can spring its scale back — `usePressable` therefore resets scale + flags via a
`useEffect` keyed on `enabled` whenever a button is disabled mid-hover/press.
Layout effects (`useLayoutEffect`) set pre-paint initial values (badge scale 0,
knob position) to avoid a one-frame flash. Hover is desktop-only by nature; touch gets press
only. The kit skill's iron rule 8 now permits press feedback through this
primitive (still bars ad-hoc per-component animation).
