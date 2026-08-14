# Tutorial / onboarding

First-session guidance in the GAME place. Two independent halves:

- **The story slides play EVERY time** a player enters the game place — they
  are the game's premise, not a lesson.
- **Steps 2-5 run ONCE per account.** A persisted flag suppresses them
  forever after; the slides are never suppressed.

Entry points: `TutorialSubs` (server, game) / `TutorialSubsClient` (client,
common + place-gated), `AppRoot`, UIKit `TutorialSlides` / `TutorialHint` /
`InputGlyph`. World guidance is a cloned `HintBeam`, owned by the client sub —
no GUI component. Tuning: `Shared.config.TutorialConfig`.
Step 3's affordability gate reads `LocalUpgradeTree.CanAffordNext` +
`LocalStatsService.GymEfficiency` (features/upgrades.md owns both).

## The five steps

| Step | Surface | Advances when |
|---|---|---|
| `slides` | 4-panel comic board, 2x2, one SKIP button | SKIP pressed |
| `eat` | instruction popup (mouse glyph on PC, EAT-button glyph on touch) | GOT IT pressed **or** the first bite lands |
| `belly` | nothing on screen | they can AFFORD their first upgrade — `calories + floor(stored × gymEff) >= cost(TutorialConfig.burnPromptStat)`. Safety net: `fill / capacity >= TutorialConfig.bellyThreshold01` (0.90) |
| `path` | guidance BEAM player → checkpoint plate + the HUD TO CHECKPOINT button pulses | player stands on the plate |
| `upgrades` | the SAME guidance beam, now running player → upgrade computer — it KEEPS pointing while the tree is opened and browsed | the player BUYS their first tier (`UpgradesUpdate` carries a level ≥ 1) → `TutorialComplete`. The `UpgradeStation` prompt only moves the step here |

## The tree has TWO openers, and only one of them moves a step (2026-08-13)
The game HUD gained an Upgrades button beside the checkpoint prompt
(`features/app-root.md`). Onboarding needed one thing to already be true and one
thing added:
- **True already** — completion tests the STATE (`UpgradesUpdate` carries any tier
  ≥ 1) from ANY live guided step, never a prompt transition. A tier bought through
  the HUD therefore ends onboarding exactly like one bought at the computer.
  Nothing about the exit was ever prompt-shaped.
- **Added** — the TUTORIAL funnel's `upgrades` step (`reportTreeOpened`), which
  used to ride the prompt alone. It fires from the prompt, from the flow's own
  0.5 s tick when `AppRoot.GetOpenPanel() == "Upgrades"`, and from the purchase
  watch as a backstop (you cannot buy without the tree being open, so a
  open-buy-close inside one tick interval is still caught). Latched, and gated on
  `step == "upgrades"` so an early HUD open can never assert step 5 out of order.
  ⚠ The player-flow step `upgrades-open` was NOT at risk and is not this sub's
  to fix: `AnalyticsSubsClient` polls the open PANEL and reports it for any
  opener. Measured on the live `AnalyticsBeat` remote before believing either way.
- **The HUD open moves NO step.** The prompt proves the player is AT the station;
  the button is reachable from anywhere, including step `eat` with an empty
  balance. Advancing there would tear down the eat popup and run the beam to a
  computer across the cake for a player who has not eaten yet.
- ⚠ **One cohort can now finish without ever standing on the plate.** An
  Auto-Gym/VIP owner banks calories anywhere on the cake (`features/body-gym.md`),
  so they can buy from step `belly`. `finish()` logs which step it ended on; the
  `checkpoint`/`arrived` beats are deliberately NOT back-filled — asserting an
  arrival that did not happen would corrupt the one thing the funnel measures.

Returning players: the slides show, SKIP ends the flow, nothing else runs.

## State

| Where | What |
|---|---|
| profile section `tutorial` | `{ done: boolean }` — `TutorialSection.lua`. **NOT run-scoped**: `RunResetSubs` wipes `upgrades`/`economy`/`stomach` on every profile load (ADR-0013), so parking this flag in any of those would replay the tutorial every match. |
| `AppRoot` state `tutorial` | `{ slides, hint, pulseCheckpoint }` — one table, one patch per step. (`arrow` was dropped 2026-08-09 with the HintArrow.) |
| client-local | `step`, `serverDone` (tri-state: nil = not told yet), `completeSent` |

## Remotes

| Name | Dir | Payload |
|---|---|---|
| `TutorialUpdate` | s→c | `{ done = boolean }` — pushed once from `PushInitialState` |
| `TutorialComplete` | c→s | no arguments |
| `UpgradesUpdate` | s→c | READ-ONLY here: `{ levels }`, the completion trigger. Owned by `features/upgrades.md`. ⚠ Client subs Start alphabetically, so this sub's handler runs one step AHEAD of `UpgradesSubsClient` on the same remote — read the payload, never `LocalStatsService`, which has not been fed yet. |

`TutorialComplete` is deliberately unauthenticated beyond a profile check (R6
still applies — it IS validated). The flag grants nothing; it only SUPPRESSES a
tutorial, and SKIP already offers that for free.

## World contract (place-authored, ADR-0007 — none of it is in the repo)

| Instance | Used for |
|---|---|
| `ReplicatedStorage.Assets.GuidanceTemplates.HintBeam` | cloned per beam (R5) |
| `workspace.Map.Checkpoint.CheckpointPlate` | beam target (step `path`) + arrival test |
| `workspace.Map.Checkpoint.UpgradeStationBody` | beam target (step `upgrades`) |
| its `UpgradeStation` ProximityPrompt | enters step `upgrades` (NOT completion — see below) |

All resolved LAZILY every tick and never cached — `Assets` is place content and
can replicate late. Misses go through `Log.GraceOnce`, so a genuinely missing
instance warns once and the step degrades (no beam / no arrow) instead of
stalling.

## Gotchas

- **The eat popup brings NO scrim and NO click-catcher.** PC eating is a global
  `UserInputService.InputBegan` guarded by `gameProcessed` (`CakeSubsClient`),
  so any full-screen `Active` surface over it swallows the exact left-click the
  popup is teaching. Only its CTA is a button. Verified live: belly rose 0→495
  while the popup was up.
- **…but it HIDES while any panel or overlay is open** (2026-08-13). It renders at
  zIndex 70, i.e. above every panel (50) and the hex tree (60), so it floated over
  whatever the player opened — reachable in the game place ever since the HUD grew
  three more buttons. Hiding costs the step nothing: its two exits are its own CTA
  (unreachable behind a modal by design) and the first bite (which cannot land
  either — the scrim is a full-screen TextButton, so every PC click is
  `gameProcessed`, and the touch EAT button is already gated on `openPanel == nil`).
  It returns the moment the panel closes.
- **The slides overlay is NOT an `openPanel`.** Routing it through `openPanel`
  would fire the audio whoosh, arm the scrim's shop-closing branch, and hide the
  touch EAT button (`eatButtonVisible` requires `openPanel == nil`). It carries
  its own dim, and it hides the whole `Hud` LAYER while up so nothing glows
  through — except the EAT button, which is *also* gated on its own `visible`
  prop, because `Interaction` releases a hold on `enabled` flipping, not on an
  ancestor's `Visible`.
- **Step 3 fires on AFFORDABILITY, not on a full belly** (2026-08-05, user
  request). "Your stomach is full" is a punishment cue that arrives exactly when
  the game stops responding to the button it just taught; "you have earned a
  bigger bite, go and collect it" is the same walk with a reward at the end, and
  it puts the player at the station holding enough to buy something. With the
  2026-08-05 belly curve it fires ~74% of the way through the very first belly
  (≈7.4 s in), i.e. EARLIER than the old 90% gate.
- **The calories it tests are UNBANKED.** A player who has never been to the gym
  has `economy.calories == 0` (`RunResetSubs` wipes it on every profile load) and
  everything they earned in `stomach.stored`. The gate therefore tests
  `calories + floor(stored × gymEff)` — exactly what `GymService` will bank on the
  trip it is sending them on. Testing the banked balance alone would never fire:
  the only thing that banks calories is the gym trip the step exists to prompt.
- **`bellyThreshold01` is now a SAFETY NET, not the trigger.** If the gate cannot
  open — a re-priced `biteRadius`, a config typo, a stat already maxed — the
  player would sit at a full belly that refuses to eat with no guidance at all.
  ⚠ The margin is only ×1.36: a full base belly of frosting is worth ~612
  calories against a 450 cost. `pacing_scenario.lua` section D asserts ≥ ×1.2 so a
  re-price fails in the tool, not in a playtest.
- **Both gates are LATCHED** (structurally: `evaluateBurnPrompt` returns unless
  `step == "belly"`, and `setStep` only moves forward). Each un-latches itself the
  moment it fires — the belly falls as the gym drain starts (~8 Hz resyncs) and
  banking SPENDS `stored` — so an un-latched test would blink the beam off behind
  a player who is already walking.
- **`StomachUpdate` has two payload shapes on one remote.** Per-bite carries
  `layerId`; join/gym resyncs do not. That field is the first-bite discriminator.
- **The flow ends on a PURCHASE, not on the prompt** (2026-08-09, user request).
  Opening the computer is not learning the loop — eat, burn, SPEND is. Under the
  old trigger a player who pressed E, looked at the honeycomb and walked away had
  "completed" onboarding, and the arrow that would have brought them back was
  already gone. `UpgradesUpdate` is the only channel carrying owned tiers to the
  client and its payload is identical for a join snapshot, a successful buy and a
  refused-buy resync — so the test is the STATE (any tier ≥ 1), never a
  transition. That is safe because `RunResetSubs` zeroes every tier on each
  profile load (ADR-0013) and the server sends every configured id zero-filled:
  the first push of a run is provably all-zeros for veterans and newcomers alike.
  No new analytics key was needed — `upgrades-open` still fires at the prompt and
  now means exactly what it says, and the server still owns `tutorial/done`.
- **The prompt and the arrival zone DO NOT coincide.** The station's prompt is a
  10-stud sphere with no line-of-sight requirement, sitting ~3.5 studs from the
  loaf edge, so it lights up several studs back *onto the cake* — while
  `checkpointFar` stays true anywhere on the loaf by design. Both the prompt and
  the purchase are therefore honoured from ANY live GUIDED step, not just
  `upgrades`; gating completion on `upgrades` silently dropped it for every
  player who pressed E on the way in, and their tutorial replayed forever.
  ⚠ "Any live step" EXCLUDES `slides`: the comic plays for every account
  including finished ones, and the station prompt is a keyboard press the comic
  does not swallow — without that test a veteran who taps E during the comic
  would be handed a first-session arrow, and a purchase would dismiss the comic
  under them.
- **ONE beam, two destinations — there is no arrow** (2026-08-09, user request).
  Steps `path` and `upgrades` draw the same line; only `beamTarget()` changes
  (plate → computer, the latter lifted by `beam.stationExtraHeight`). The flow
  used to switch to a screen-space `HintArrow` for the last step, which taught
  the player to follow a line and then asked them to follow something else.
  `Components.HintArrow` is still in the kit but nothing renders it, and
  `AppRoot`'s `tutorial.arrow` / `onTutorialArrowTarget` are gone.
  ⚠ `setStep` now clears the beam on EVERY transition, including `path` →
  `upgrades`: the destination Attachment is parented to the target part, so
  moving the beam means rebuilding it (the next tick does, ≤ 0.5 s later).
- **The beam is STRAIGHT and WHITE** (2026-08-09, user request):
  `TutorialConfig.beam.curveSize = 0` (it used to bow upward by 12) and
  `.color = white`. ⚠ `.width` (7) stays overridden and should not be dropped
  too: `HintBeam` is authored as a 3-stud line, and over 80+ studs of pastel sky
  above a near-white loaf that measured as an unfindable hairline — width is the
  only legibility lever left now the hue is white. Set any of the three to nil
  to defer to the template.
- **Arrival is read from `AppRoot.Get("checkpointFar")`**, which `BodySubsClient`
  owns — one definition of "on the platform", not a second copy that can drift.
  Client subs Start alphabetically, so Body arms before Tutorial.

## UI

Kit components (`roblox-ui-kit` skill, geometry + check-sums in `Theme.lua`):

| Component | Theme section |
|---|---|
| `TutorialSlides` | `TutorialSlides` (board 900x958) + `TutorialPanel` (440x336) |
| `TutorialHint` | `TutorialHint` (620x260) |
| `InputGlyph` | `TutorialGlyph` — vectored mouse / EAT-button miniature |
| `Button` `pulse` prop | `Theme.Feel.Pulse` |

zIndex ladder: TutorialHint **70**, TutorialSlides **95**. World guidance is not
in this ladder at all any more — it is a Beam in the workspace, so the hex tree
opening over it cannot hide it.

**Slide ENTRANCE** (2026-08-09, user request): the comic assembles one piece at
a time — title, panels 1-4 a step apart, then the CTA after an extra beat. Each
is HIDDEN until its turn and then pops from `Theme.Feel.SlideIn.ClosedScale`,
over a scrim that fades in under them. Hiding is the half that makes it an
arrival: 0.68 is fully opaque, so scaling alone leaves the whole board legible
from frame one. It rides ref-owned UIScales inside `Interaction.pressLayer`
wrappers (the panel frames are top-left anchored, so a bare UIScale would grow
them out of the board's 20 px gaps) and React writes neither `Scale` nor the
live `Visible` — which matters more here than usual, because the locale repaint
lands 0.5-3 s after boot and re-renders the board mid-animation. Keyed on
`visible` alone.

⚠ **The clock starts at `game.Loaded`, not at mount** — the single most
important line in the entrance. A LocalScript runs long before the session is on
screen and this project ships no custom loading screen (no `ReplicatedFirst`),
so Roblox's default one covers the whole choreography: the board mounts, all six
pieces play out behind it, and the player's first sight is the FINISHED board.
Reported twice as "the slides show at the same time" while the stagger was
provably working (measured 0.55 s apart in Studio, Skip last) — no amount of
retiming fixes it, because the clock has to start when the player can SEE.
⚠ Three derived numbers in `Theme.Feel.SlideIn`: `ClosedScale` is bounded by the
board's gaps (Back-out overshoots ~10% of the travel, half on each side);
`StepSeconds` (0.55) is deliberately LONGER than the pop (0.32), so each piece
lands before the next starts; and `LeadDelay` (0.25) keeps the first pop from
already being underway on the first rendered frame. 0.12 and then 0.38 were both
still read as simultaneous — the gap has to be long enough to be COUNTED.

The flow's own throttled `RunService.RenderStepped` tick (0.5 s) drives both beam
steps — see ADR-0016 for why a guidance marker owning its own render step is the
sanctioned shape and not an R4 violation.
