# Checkpoint (return-to-gym platform)

## What it does
A platform on 4 legs standing BESIDE the loaf whose TOP surface tracks the
current **top cake layer** — it steps DOWN one layer at a time as the cake is
eaten. It carries the gym machine (fat extraction), so it is the ONE place you
burn fat; it **replaces the old floor gym zone**. Press **F** or the HUD
**TO CHECKPOINT** button to teleport onto it (belly full = slowed + rolling, so the
gym is seconds away at your eating height).

## Geometry & height (server, MapService)
- ONE platform per server (like the cake). **CLONED** once in `MapService.Build`
  from the editable `ReplicatedStorage.Assets.Checkpoint` template (place-authored,
  ADR-0007) into `workspace.Map.Checkpoint`. **Named-part contract** (edit the
  look/size, KEEP these names — code resolves + POSITIONS them by name as the
  plate tracks the cake): `CheckpointPlate`, 4× `CheckpointLeg`, `GymMachine` +
  its `GymPrompt`, `UpgradeStationBody` + `UpgradeStationScreen` + the
  `UpgradeStation` prompt. Plate/machine/computer/screen may be a single BasePart
  **or a Model** (positioned via `PivotTo`, sized via `GetExtentsSize` — a resized
  authored model still aligns); LEGS stay single BaseParts (they telescope, Y
  code-driven). Ranges/names in `MapConfigData.checkpoint`.
  If the template is missing, `GenerateAssets` self-heals the default look (won't
  persist — save the place); a missing `CheckpointPlate`/`GymMachine` warns (R8)
  and the checkpoint degrades.
- **Upgrade station** (the "computer"): a terminal on the plate's cake-side +Z
  corner (clear of the centre landing + the walk-back path). Its `UpgradeStation`
  ProximityPrompt opens the upgrades hex-tree — handled CLIENT-side
  (`UpgradesSubsClient`, `features/upgrades.md`); no server round-trip. Rides the
  plate height in `SetCheckpointHeight` like the gym machine.
- Placed on the loaf's **+X** side: plate inner edge = `origin.x +
  footprint.hx*grid.cell (=42) + edgeGap`; z-span stays inside the straight
  edge (clear of the rounded corners). Legs drop to the floor (y=0).
- `MapService.SetCheckpointHeight(topY)` — sets the plate TOP to world Y `topY`,
  resizes the 4 legs (floor→plate bottom), rides the machine on top. Skips
  redundant moves (`|Δ| < 0.01`) so the 1 Hz re-assert doesn't re-replicate.
- `MapService.GetCheckpointCFrame()` — teleport target: standing on the plate
  facing the cake (walk forward = step back onto the loaf). nil until built.
- `MapService.NearGym(pos)` — gym-start range check now uses the (moving)
  machine's current position vs `checkpoint.maxUseDistanceStuds` (16 ≥ prompt's
  MaxActivationDistance 10).
- **Authored VISUALS ride the plate**: `SetCheckpointHeight` moves the machine /
  station with `PivotTo`, which rigidly moves the Part AND its descendant parts —
  so a user can author the machine LOOK as child parts of the collider (e.g. the
  **treadmill** Model under the invisible `GymMachine` Part) and it rides the
  plate with the collider. (`.CFrame =` would NOT move children — use `PivotTo`.)
- `MapService.GetGymMountCFrame()` — where to STAND on the treadmill belt during a
  fat-burn run (user req 4): the machine XZ + `checkpoint.treadmillStandHeight`
  above the plate top, facing along the belt (`treadmillFaceYaw`). BodySubs anchors
  the HRP here + plays the run animation (see `features/body-gym.md`).
- `MapService.GetGymDismountCFrame()` — step-off spot beside the treadmill after a
  completed run (`treadmillDismountBack` toward the plate centre, facing the cake).

## Driven by (CakeSubs)
- **New cake**: `SetCheckpointHeight(origin.y + composition[#].top)` (full
  height — frosting is the last/top band).
- **1 Hz scan** (eating phase only): `ScanStats()` returns `topBandIndex`;
  `SetCheckpointHeight(origin.y + composition[topBandIndex].top)`. `topBandIndex`
  = highest band still present, so the plate = the top of the current intact
  layer and steps down when a whole layer is consumed (auto-sweep collapses the
  last 10% so transitions are clean). No scan during boss/reward/spawning —
  plate holds until the next cake resets it up.

## Remotes
- `ReturnToCheckpoint` (client→server, no args): teleport request. Server
  validates `IsLoaded` + character, **0.5 s debounce** (anti rag-doll), then
  `root.CFrame = MapService.GetCheckpointCFrame()`. The destination is server
  truth — the client supplies nothing to spoof. Owner: `CakeSubs`.
- Gym start still flows through the `GymPrompt` ProximityPrompt on the machine
  (`BodySubs`, unchanged) — see `features/body-gym.md`.

## Client (BodySubsClient)
- **F key** via `ContextActionService` → `ReturnToCheckpoint`; suppressed while
  a kit TextBox is focused (`GetFocusedTextBox`) so typing "f" never teleports.
- HUD **TO CHECKPOINT** button (AppRoot, bottom-center above the belly bar) →
  `onReturnCheckpoint` callback → same remote. Style `Theme.CheckpointButton`
  (EquipGreen family); position `Theme.AppHud.CheckpointPosition/Height`. Locale
  key `hud-burn-fat` (its VALUE is now "TO CHECKPOINT"; key name kept).
- **Proximity-gated visibility**: a throttled (~5 Hz) check in BodySubsClient's
  `RenderStepped` reads the live `CheckpointPlate` and pushes `checkpointFar`
  to AppRoot (which sets the button `Visible`). "Near" = the player's XZ inside
  the plate footprint (`|dx| ≤ Size.X/2 + margin`, same Z; plate is unrotated
  so `Size` maps to world axes) expanded by
  `Theme.AppHud.CheckpointHideMarginStuds` (1.5). The cake and plate footprints
  don't overlap in X (the `edgeGap` sits between them), so a player on the cake
  always reads "far". Pushes ONLY on a near↔far flip (no per-tick re-render);
  `Log.GraceOnce` warns if the plate never replicates (button stays visible).

## Config
`MapConfigData.checkpoint` (was `MapConfigData.gym`): `edgeGap, plateDepth,
plateWidth, plateThickness, legSize, legInset, minLegHeight, machineSize,
standHeight, promptName ("GymPrompt"), promptRange (prompt
MaxActivationDistance), maxUseDistanceStuds, plate/leg/machine colors,
treadmillStandHeight/FaceYaw/DismountBack/DismountHeight (treadmill mount, req 4)`. Gym
reachability is all here — keep `promptRange ≥ landing→machine distance` and
`maxUseDistanceStuds ≥ promptRange` (see the config comment). Gym SESSION tuning
stays in `BodyConfig.gym` (duration/taps/bonus).

## Gotchas
- The platform is **anchored** — a player standing on it when it steps DOWN (a
  layer finished) does NOT ride it; they briefly fall to the new height. Steps
  are infrequent (a few per cake) and only fire when a whole layer is gone.
- On a **new cake** the plate jumps UP (to the fresh top layer); an anchored
  plate would strand a player standing on it far below. `spawnNewCake` handles
  this: players over the plate (`MapService.IsOverCheckpoint`) are re-seated onto
  it (`GetCheckpointCFrame`) alongside the on-cake lift.
- Removing the floor gym means the ONLY manual gym is here — reachable by
  teleport or by walking/jumping off the cake edge. The HUD button (shown
  whenever you're away from the platform — see Client) keeps it discoverable;
  the F key works regardless.

## Files
Server: `data/MapConfigData` (`checkpoint`), `services/MapService`
(`SetCheckpointHeight`/`GetCheckpointCFrame`/`NearGym`), `subscriptions/CakeSubs`
(height drive + `ReturnToCheckpoint`), `subscriptions/BodySubs` (prompt name).
Shared: `remotes/ReturnToCheckpoint`, `UIKit/Theme` (`CheckpointButton`,
`AppHud.Checkpoint*`). Client: `subscriptions/BodySubsClient` (F key + callback),
`modules/AppRoot` (button), `data/LocaleData` (`hud-burn-fat`).
