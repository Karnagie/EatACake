# Tutorial / onboarding

First-session guidance in the GAME place. Two independent halves:

- **The story slides play EVERY time** a player enters the game place — they
  are the game's premise, not a lesson.
- **Steps 2-5 run ONCE per account.** A persisted flag suppresses them
  forever after; the slides are never suppressed.

Entry points: `TutorialSubs` (server, game) / `TutorialSubsClient` (client,
common + place-gated), `AppRoot`, UIKit `TutorialSlides` / `TutorialHint` /
`InputGlyph` / `HintArrow`. Tuning: `Shared.config.TutorialConfig`.

## The five steps

| Step | Surface | Advances when |
|---|---|---|
| `slides` | 4-panel comic board, 2x2, one SKIP button | SKIP pressed |
| `eat` | instruction popup (mouse glyph on PC, EAT-button glyph on touch) | GOT IT pressed **or** the first bite lands |
| `belly` | nothing on screen | `fill / capacity >= TutorialConfig.bellyThreshold01` (0.90) |
| `path` | guidance BEAM player → checkpoint plate + the HUD TO CHECKPOINT button pulses | player stands on the plate |
| `upgrades` | world-tracking arrow at the upgrade computer | the `UpgradeStation` prompt fires → `TutorialComplete` |

Returning players: the slides show, SKIP ends the flow, nothing else runs.

## State

| Where | What |
|---|---|
| profile section `tutorial` | `{ done: boolean }` — `TutorialSection.lua`. **NOT run-scoped**: `RunResetSubs` wipes `upgrades`/`economy`/`stomach` on every profile load (ADR-0013), so parking this flag in any of those would replay the tutorial every match. |
| `AppRoot` state `tutorial` | `{ slides, hint, arrow, pulseCheckpoint }` — one table, one patch per step. |
| client-local | `step`, `serverDone` (tri-state: nil = not told yet), `completeSent` |

## Remotes

| Name | Dir | Payload |
|---|---|---|
| `TutorialUpdate` | s→c | `{ done = boolean }` — pushed once from `PushInitialState` |
| `TutorialComplete` | c→s | no arguments |

`TutorialComplete` is deliberately unauthenticated beyond a profile check (R6
still applies — it IS validated). The flag grants nothing; it only SUPPRESSES a
tutorial, and SKIP already offers that for free.

## World contract (place-authored, ADR-0007 — none of it is in the repo)

| Instance | Used for |
|---|---|
| `ReplicatedStorage.Assets.GuidanceTemplates.HintBeam` | cloned per beam (R5) |
| `workspace.Map.Checkpoint.CheckpointPlate` | beam target + arrival test |
| `workspace.Map.Checkpoint.UpgradeStationBody` | arrow target |
| its `UpgradeStation` ProximityPrompt | completion trigger |

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
- **The slides overlay is NOT an `openPanel`.** Routing it through `openPanel`
  would fire the audio whoosh, arm the scrim's shop-closing branch, and hide the
  touch EAT button (`eatButtonVisible` requires `openPanel == nil`). It carries
  its own dim, and it hides the whole `Hud` LAYER while up so nothing glows
  through — except the EAT button, which is *also* gated on its own `visible`
  prop, because `Interaction` releases a hold on `enabled` flipping, not on an
  ancestor's `Visible`.
- **The 90% threshold is LATCHED.** The belly falls the moment a gym drain
  starts (~8 Hz resyncs), so an un-latched test would blink the beam off at 89%
  while the player is still walking.
- **`StomachUpdate` has two payload shapes on one remote.** Per-bite carries
  `layerId`; join/gym resyncs do not. That field is the first-bite discriminator.
- **The prompt and the arrival zone DO NOT coincide.** The station's prompt is a
  10-stud sphere with no line-of-sight requirement, sitting ~3.5 studs from the
  loaf edge, so it lights up several studs back *onto the cake* — while
  `checkpointFar` stays true anywhere on the loaf by design. Completion
  therefore fires from ANY live step, not just `upgrades`; gating it on
  `upgrades` silently dropped the completion of every player who pressed E on
  the way in, and their tutorial replayed forever.
- **The authored beam is invisible in this game as authored.** `HintBeam` is a
  3-stud WHITE line; the guidance run is 80+ studs across a pastel sky over a
  near-white loaf. Measured in Studio: a hairline that cannot be found on
  screen. `TutorialConfig.beam.width` (7) and `.color` (candy magenta — the one
  hue nothing in the scene shares) are applied **to the clone**; set either to
  nil to defer to the template.
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
| `HintArrow` | `TutorialArrow` |
| `Button` `pulse` prop | `Theme.Feel.Pulse` |

zIndex ladder: HintArrow **45** (over the HUD, under panels), TutorialHint
**70**, TutorialSlides **95**.

`HintArrow` owns a `RunService.RenderStepped` connection — see ADR-0016 for why
that is the sanctioned shape and not an R4 violation.
