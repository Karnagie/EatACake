# 2026-08-09: Arrow Until Purchase, CoreGui Safe Area, Slide Entrance

Tags: tutorial, app-root, ui-kit, upgrades, theme, onboarding

## Task
Three user requests:
1. In the tutorial, keep the arrow pointing at the upgrades until the player
   purchases at least one upgrade.
2. The calories panel in the top-left is hidden behind Roblox's GUI. Reposition
   it so it stays visible. Our GUIs should still IGNORE the Roblox inset — a
   full-screen dim must cover the whole screen — but PLACEMENT must account for
   it. Check the rest of the interface for the same problem and fix it too.
3. Animate the opening slides: make them appear one after another with smooth,
   engaging tween animations.

Follow-up round, same session, after seeing it run:
4. The tutorial beam must be STRAIGHT and WHITE.
5. Replace the arrow pointing at the upgrades with a BEAM that goes to the
   upgrades — always use the beam in the tutorial.
6. The slides are showing at the same time; they must appear strictly in order,
   1 then 2 then 3.

## Context
- Onboarding is five client-owned steps in `TutorialSubsClient` (ADR-0016,
  `features/tutorial.md`). The last one ended on the `UpgradeStation`
  ProximityPrompt firing, which also sent `TutorialComplete`.
- The root ScreenGui has been FULL-BLEED since 2026-07-30 so modal scrims cover
  the topbar strip (`2026-07-30_run-scoped-progression-pacing-ui.md`, harvested
  upstream as EAC-0133 → template TPL-0014). `AppRoot`'s `Hud` child re-applied
  `GetGuiInset()`; nothing else applied any inset.
- `TutorialSlides` rendered its four comic panels outright, with no motion. The
  kit's only animation contract is ADR-0006 (TweenService on a React `ref`,
  never a property React also writes); no component did a staggered reveal.

## Plan
Measure before changing anything — the report was about a specific panel, and
"top-left" has two candidates. Read Roblox's own CoreGui geometry out of a live
playtest, find every one of our rects that intersects it, and fix that list.
Then: move the tutorial's completion onto the purchase signal that already
exists; and add the entrance as a kit-level `Theme.Feel` primitive rather than
per-component animation.

## Changes

**Modified:**
- `src/client/common/subscriptions/TutorialSubsClient.lua` — the station prompt
  now only enters step `upgrades` (+ the one-shot `upgrades-open` beat); a new
  `UpgradesUpdate` watch ends the flow on the first owned tier. New
  `guidedStepRunning()` excludes `slides` from "any live step". Round 2: one
  `beamTarget()` serves both world steps and the HintArrow wiring is gone.
- `src/shared/config/TutorialConfig.lua` — beam straight + white +
  `stationExtraHeight`; the `arrow` block deleted.
- `src/shared/UIKit/Theme.lua` — new frozen `Theme.SafeArea` (the CoreGui
  measurements + pads) and `Theme.Feel.SlideIn` (entrance timings).
- `src/client/common/modules/AppRoot.lua` — `resolveTopInset` /
  `resolveTouchReserve` / `rootSize`; `topInset`, `touchReserve`, `viewportY`
  state; `appRef` on the `App` frame; safe-area props to three children;
  `MenuIsOpen` + late re-read added to the inset effect.
- `src/shared/UIKit/Components/HexTreeOverlay.lua` — `topInset01` on the
  calories chip and Close X, `bottomReserve01` lifting the zoom stack; the chip's
  glyph moved off StatPill's legacy `bolt` onto `Theme.AppHud.PillIcons`.
- `src/shared/UIKit/Components/GymOverlay.lua` — `bottomReserve01` lifts the tap
  button + bar + counter as one cluster.
- `src/shared/UIKit/Components/EatButton.lua` — bottom-anchored on
  `bottomReservePx` instead of a viewport-fraction Y.
- `src/shared/UIKit/Components/TutorialSlides.lua` — staggered entrance
  (`useEntrancePop`, `SlidePanel`, scrim fade).
- `docs/features/{tutorial,app-root,ui-kit}.md`, `docs/registries/data-keys.md`.

## Decisions

**The reported panel was not the one I expected.** The HUD calories pill is in
the inset `Hud` layer and measured clear (y 79.8..137.3 against a 58 px bar). The
element actually buried was the **hex tree's** calories chip — a FULL-BLEED child
at `y = 30/1080`, measured at y 28.6..89.7 with x 21.5..263.3, i.e. its top half
under Roblox's unibar chip (x 16..204, y 10..58). That is also exactly where the
player is standing when request 1 sends them. Measuring first is what found it;
a grep for "calories" would have landed on the HUD pill and fixed nothing.

**Full-bleed was only half a contract.** The 2026-07-30 change is right and stays
— a modal that does not cover the screen is not modal. What was missing is the
other half: a surface may cover everything, but anything that PLACES A CONTROL
must still keep off CoreGui furniture. That rule now lives in
`features/app-root.md` and `features/ui-kit.md`, with the numbers in
`Theme.SafeArea` and AppRoot as the only reader of the engine APIs.

**`GetGuiInset()` is the legacy answer; `GuiService.TopbarInset` is the honest
one.** The first is the pre-unibar 36 px bar and can under-report the modern
chip; the second is a **Rect** whose `Max.Y` is the strip's real bottom and whose
`Min.X` is where Roblox's own chip ends. The resolver takes the max of the two so
a client answering only one still gets the right number, clamps it against a
nonsense report, and adds a PIXEL pad — because the HUD's own top margin is a
FRACTION of the region under the bar and collapses from ~23 px at 1080p to ~8 px
on a phone while the bar stays fixed. That pad moves every HUD element down,
which falsifies the old "the inset fix moved no HUD element" claim; the doc now
says so rather than leaving a future agent to trust it.

**Three collisions found, not one.** Measured live at 1375x1031 with touch
controls on, against Roblox's own rects read out of `CoreGui`/`PlayerGui`:

| Ours | Before | After | Roblox |
|---|---|---|---|
| hex tree calories chip | y 28.6..89.7 | y 96.6..157.7 | unibar chip y 10..58 |
| hex tree Close X | y 33.4..107.9 | y 101.4..175.9 | topbar strip y 0..58 |
| hex tree zoom "1x" | y 813.9..876.9 | y 742.0..805.0 | JumpButton y 821..941 |
| gym tap button | corner-clipped 37x15 px | lifted with its cluster | JumpButton |
| EAT button | y 601..799 (22 px margin) | bottom pinned to 805 | JumpButton |
| HUD pills | y 79.8..137.3 | y 89.4..146.5 | — |

**Two unit families, and the suffix is the unit.** `…Px` for children of the
shortened `Hud` layer (fractions there resolve against `H - inset`, so only
pixels are exact); `…01` for full-bleed overlays, whose height IS the root's.
Mixing them silently is the kind of bug that only shows up at one aspect ratio.

**The purchase signal already existed; no new remote and no new analytics key.**
`UpgradesUpdate` is the only channel carrying owned tiers, and its payload is
identical for a join snapshot, a successful buy and a refused-buy resync — so the
tutorial tests the STATE (any tier ≥ 1) rather than a transition. That is only
safe because `RunResetSubs` zeroes every tier on each profile load (ADR-0013) and
the server sends every configured id zero-filled, making the first push of a run
provably all-zeros for veterans and newcomers alike; both halves were verified by
pushing a zero-filled resync and watching the arrow stay. `upgrades-open` keeps
firing at the prompt and now means exactly what its name says, and the gap the
change is meant to close (`upgrades-open` → `first-upgrade`) is already two
separate steps in the catalog, so it is measured for free.

**"Any live step" had to become "any live GUIDED step".** The documented reason
completion fires from any step is that the station's prompt reaches back onto the
cake. But the comic plays for EVERY account including finished ones, and the
prompt is a keyboard press the comic does not swallow — so with the naive port, a
veteran tapping E during the comic got a first-session arrow. Caught in the
playtest, not by reading.

**The entrance is a kit primitive, not component code.** `Theme.Feel.SlideIn`
holds the timings; the pop rides a UIScale inside `Interaction.pressLayer`
because the panel frames are top-left anchored and a bare UIScale would grow them
out of the board's 20 px gaps. `ClosedScale = 0.68` is derived, not chosen:
Back-out overshoots ~10% of the travel and it lands half on each side, so with a
426 px panel and a 19.4 px measured gap the peak may not exceed ~1.045; 0.68
gives 1.032 → 6.8 px per side. React never passes `Scale`, which matters more
here than usual — the locale repaint lands 0.5-3 s after boot and re-renders the
board mid-animation, swapping the title and CTA text.

**A degenerate viewport is a real state, not a Studio artifact.**
`Camera.ViewportSize` reports `(1,1)` for a session's first frames; dividing a
58 px inset by 1 put the hex tree's chip 40,000 px down the screen — observed,
not theorised. The fractions now divide by the `App` frame's own `AbsoluteSize`
(the surface actually being placed into, which stays honest when the camera does
not) and report 0 below the threshold.

**ROUND 2 — the arrow went away entirely.** Asked for a straight white beam and
for the last step to use a beam too, which collapsed two guidance mechanisms into
one: `beamTarget()` now returns the plate for `path` and the computer for
`upgrades` (lifted by `beam.stationExtraHeight`, since a prop is taller than a
slab), `curveSize` 12 → 0 and the colour magenta → white. Width 7 stays: the
authored `HintBeam` is a 3-stud line and over 80+ studs of pastel sky it was
measured unfindable, and width is the only legibility lever left once the hue is
white. `HintArrow`, `state.tutorial.arrow` and `onTutorialArrowTarget` are gone
from the app (the component stays in the kit, unused). One consequence worth
writing down: `setStep` must now clear the beam on EVERY transition, not just on
leaving `path` — the destination Attachment is parented to the target part, so
moving the beam means rebuilding it. And the throttled tick that used to be
narrowed to `path` had to re-admit `upgrades`, because that step is no longer a
state with nothing to do.

**ROUND 2 — "the slides show at the same time" was two bugs, one of them mine.**
The first cut only SCALED each panel from 0.68, and 0.68 is fully opaque: the
whole board was legible from frame one and merely grew in sequence. Each piece is
now HIDDEN (React writes the constant `AWAITING_TURN`, the entrance owns it from
there — the HintArrow `START_HIDDEN` pattern) until its own delay. The second was
pacing: at `StepSeconds = 0.12` against a 0.36 s pop, four panels were in flight
at once and the eye saw ONE event. The step is now 0.38 s — deliberately LONGER
than the 0.30 s pop, so each piece has landed before the next starts, which also
removes the overshoot coupling entirely (two neighbours can no longer peak
together). Verified by slowing the step to 4 s and sampling `Visible`: panel 4
appeared at its 16.0 s slot and the CTA 4.12 s later, matching 4·Step and
5·Step+Tail to 20 ms.

⚠ **A Studio measurement trap cost real time here.** With the stagger slowed
down, a probe reported every UIScale frozen at 0.68 and every piece already
visible — which reads exactly like "the entrance is broken". It was the known
no-frames artifact: `RunService.RenderStepped` was ticking 23×/1.5 s against
Heartbeat's 91, so TweenService was not advancing while `task.delay` was. The
tell is that `Visible` flips (Heartbeat) were perfectly sequential while `Scale`
(render step) was not moving at all — so verify a stagger on the property that
does not need the renderer.

**ROUND 3 — "still showing at one time", and the stagger was never the problem.**
Measured it properly this time by shifting `LeadDelay` to 20 s so the probe could
watch the sequence from its start instead of catching the tail: the pieces WERE
appearing one at a time, 0.53 / 0.53 / 0.77 s apart, Skip last, exactly as
configured. So retiming could not have been the fix, and two rounds of retiming
were the wrong instinct. The real cause is that the clock started at MOUNT: a
LocalScript runs long before `game.Loaded`, this project ships no
`ReplicatedFirst` loading screen, so Roblox's default one covers the entire
choreography and the player's first sight of the board is the finished board.
The entrance now waits on `game.Loaded` inside its `task.spawn` before counting,
with a 0.25 s lead so the first pop is not already underway on frame one; the
step went to 0.55 s because a gap has to be long enough to be COUNTED, not merely
long enough to measure. Studio Play Solo loads instantly, which is precisely why
every earlier verification here looked fine — the bug only exists where there is
a loading screen to hide behind, i.e. on every real join and every teleport in.

## Open Questions / Followups
- The bottom-right reserve is derived from Roblox's own sizing rule
  (`min(0.20·shorterAxis, 120)`, measured exact at 1375x1031) rather than read
  from `PlayerGui.TouchGui.JumpButton` at runtime. Reading the live rect would be
  exact on every device but couples a kit component to Roblox's instance names.
  Revisit if a phone playtest shows drift.
- Verified in Studio at ONE viewport (1375x1031, touch emulation on). The phone
  aspect is arithmetic, not measurement — worth a real device pass.
- `docs/upstream/QUEUE.md`: 1 pending row before this task, 2 after. No U1b
  threshold trips (depth 2/25, oldest 1 day, no P1, changelog 24 days).

## Related
- Feature: `docs/features/tutorial.md`, `docs/features/app-root.md`,
  `docs/features/ui-kit.md`, `docs/features/upgrades.md`
- ADRs touched: ADR-0006 (animation ownership), ADR-0013 (run-scoped upgrades),
  ADR-0016 (marker owns its own RenderStepped)
- Prior flow: `docs/flow/2026-08-01_onboarding-tutorial.md`,
  `docs/flow/2026-07-30_run-scoped-progression-pacing-ui.md`
