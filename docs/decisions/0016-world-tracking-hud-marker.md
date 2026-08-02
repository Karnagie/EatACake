# ADR-0016: A world-tracking HUD marker owns its own per-frame loop

## Status
Accepted (2026-08-01)

## Context
The tutorial's step 4 needs an on-screen arrow that points at a world position
(the checkpoint's upgrade computer): floating above the target while it is
visible, pinned to the viewport edge and rotated toward it when it is not.

That is a **per-frame** screen position. Two existing rules pull in opposite
directions:

- **R4** — event subscriptions live only in `subscriptions/` modules.
- **ADR-0006** — a ref-tweened property is never also written by React.

The obvious R4-shaped implementation is a `RunService.RenderStepped` in
`TutorialSubsClient` pushing screen coordinates through `AppRoot.Set`. That
re-renders the ENTIRE composed App once per frame — including the shop's
~700-element memoized tree, at 60 Hz, for as long as the arrow is up. AppRoot's
own comments already treat a bite-rate (~14 Hz) re-render as a cost worth
memoizing around; 60 Hz is four times worse and permanent while the step runs.

The other option — a world-space `BillboardGui` — cannot do the off-screen
edge-pin, which is the behaviour that makes an objective marker useful, and R5
would require an authored template that does not exist.

## Decision
The marker component (`UIKit/Components/HintArrow.lua`) owns a
`RunService.RenderStepped` connection created in its own `useEffect`, keyed on
`visible` and disconnected on cleanup. It writes `Position`, `Rotation` and
`Visible` on its own ref'd children.

The ADR-0006 invariant is honoured by the **pass-a-CONSTANT** branch that
already sanctions `Interaction.ZeroFill` and `KNOB_INITIAL`: React writes each
of those three properties exactly once, with a module-level constant
(`PARKED = UDim2.fromScale(-1, -1)`, `START_HIDDEN = false`), and the
reconciler diffs them away forever after. The world target arrives as a
`getTarget` CALLBACK read through a ref, so a caller passing a fresh closure
every render reconnects nothing.

R4's boundary is read as it is written: *game and domain* events belong to
subscriptions. This connection observes no game event — it is the component
rendering itself against the camera, the same category of view-internal motion
ADR-0006 already moved out of React. The kit precedent exists:
`Interaction`/`ScrollPane` connect their own input events for their own visuals.

## Consequences
A world-tracking marker costs one connection while visible and zero React
renders, instead of 60 full-App reconciles per second. The pattern generalises
to any future objective/quest marker.

The cost: `RenderStepped` inside a shared component is a shape a reader will not
expect from R4 alone, so it is documented in the component header, in
`features/tutorial.md`, and here. Anything that needs to observe a GAME event
still belongs in a subscription — this exemption covers self-rendering against
the camera and nothing else.

Corollary found in review: coordinates must be taken in PIXEL space.
`WorldToViewportPoint` returns viewport pixels (the space of the FULL-BLEED
ScreenGui `UiRoot` renders into); deriving the edge-pin angle from viewport
FRACTIONS scales x and y by different lengths and mis-aims the arrow by up to
~20° on a wide viewport. And a target BEHIND the camera projects mirrored
through the centre — a straight-behind target lands exactly on the centre — so
the pin must push the point outward along its own direction to the boundary,
never clamp each axis independently (clamping leaves an interior point where it
is, parking the arrow mid-screen).
