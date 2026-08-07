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
  `UpgradeStation` prompt, `LayerEater` + its `LayerEaterPrompt` (see LAYER EATER
  below — the ONE part whose authored pose is preserved rather than recomputed).
  Plate/machine/computer/screen may be a single BasePart
  **or a Model** (positioned via `PivotTo`, sized via `GetExtentsSize` — a resized
  authored model still aligns); LEGS stay single BaseParts (they telescope, Y
  code-driven). Ranges/names in `MapConfigData.checkpoint`.
  If the template is missing, `GenerateAssets` self-heals the default look (won't
  persist — save the place); a missing `CheckpointPlate`/`GymMachine` warns (R8)
  and the checkpoint degrades.
- **`UpgradeStationBody` also carries the "N Available" sign** — its authored
  `AvailableGui.Txt` billboard, written per-client by `UpgradeStationSubsClient`.
  Contract + the two-`Txt` trap: `features/upgrades.md`.
- **Legacy upgrade station** (the "computer"): still authored on the game
  checkpoint and rides its height, but its prompt is intentionally inactive in
  the published game after the place split. The lobby-owned replacement has not
  yet been authored; see `features/upgrades.md` / ADR-0009 Remaining.
- Placed on the cake's **+X** side: plate inner edge = `origin.x +
  footprint.hx*grid.cell (=46.65) + edgeGap`. ⚠ Since the cake went ROUND
  (2026-08-03) there is no straight edge: that gap is `edgeGap` (0.5) only at
  z=0 and opens to ~2.35 studs at the plate's z-ends (±13), measured in Studio.
  The crossing path (F-teleport landing + walk-back) runs along z≈0 and is
  unchanged; the two cake-side plate corners are a hop. Do not widen
  `plateWidth` without re-checking it. Legs drop to the floor (y=0).
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

## Driven by cake subscriptions
- **New cake (`CakeCycleSubs`)**: `SetCheckpointHeight(origin.y + composition[#].top)` (full
  height — frosting is the last/top band).
- **1 Hz scan (`CakeSimulationSubs`, eating phase only)**: `ScanStats()` returns `topBandIndex`;
  `SetCheckpointHeight(origin.y + composition[topBandIndex].top)`. `topBandIndex`
  = highest band still present, so the plate = the top of the current intact
  layer and steps down when a whole layer is consumed (auto-sweep collapses the
  last 10% so transitions are clean). No scan during boss/reward/spawning —
  plate holds until the next cake resets it up.

## LAYER EATER (paid one-shot layer clear, 9 R$)
An authored contraption (`ReplicatedStorage.Assets.Checkpoint.LayerEater`)
standing on the plate. Its `LayerEaterPrompt` ProximityPrompt offers the
**hidden** `layer-eater` dev product; the receipt clears the layer the cake is
currently on and pays the buyer the calories it was worth.
- **Placement is AUTHORED, not computed.** Every other checkpoint part is placed
  at a formula corner; this one keeps the pose it was modelled with. MapService
  captures its pivot offset from the plate (and its ROTATION) at resolve time,
  before the first `SetCheckpointHeight`, and re-applies both as the plate moves.
  `PivotTo(CFrame.new(pos))` would silently flatten the authored yaw — build the
  CFrame as `CFrame.new(pos) * authoredPivot.Rotation`.
- **The prompt self-heals.** `MapService.ensureLayerEaterPrompt` adopts an
  authored prompt of that name, or creates one on the model's BIGGEST BasePart
  (an authored prop is a pile of same-named `Part`s, so "first found" lands on a
  whisker and would move whenever the author re-orders anything).
- Server flow: prompt → `RequestPurchase("layer-eater")` (`ShopSubsClient`, from
  `ShopUiData["prompt-products"]`) → `MarketplaceService` → `ProcessReceipt` →
  the `eatlayer` grant kind, registered by `CakeSubs` (GAME partition only).
- What it removes: `CakeFieldService.ClearActiveBand()` collapses every in-cake
  cell above the TOP band's bottom onto it — geometrically the auto-sweep
  tail collapse, for the whole band. ⚠ The band is read from the FIELD (the same
  rule `ScanStats` uses), NOT from `activeBandIndex`, which only refreshes at
  1 Hz: two receipts inside one tick would otherwise both target the same band
  and the second buyer would pay for one that is already flat. It does NOT touch
  the gate: the 1 Hz
  `ScanStats` sees the flat surface, drops `activeBandIndex`, moves the plate and
  fires the "layer cleared" announce + beat, so a bought clear is celebrated
  exactly like an eaten one.
- What it pays: the volume ACTUALLY removed, priced through the same formula a
  bite uses (`removed × band.density × layer.calories × cake mult × biome mult ×
  CaloriesMult`). A half-eaten layer therefore pays for what was left — it cannot
  be farmed by buying twice on one band. The BELLY is deliberately not filled: a
  paid convenience that ends in a forced gym trip punishes the buyer.
- **It refuses rather than charging** when it cannot land: `RewardGrantSubs`
  readiness (see `features/shop.md`) blocks the Roblox prompt outside the eating
  phase, off-roster, on a finished cake, or when **less than
  `layerEaterMinRemainingFraction` (0.25) of the top band is left** — the prompt
  sits where a player arrives with a FULL belly, i.e. usually deep into the
  layer, and a fixed 9 R$ for the last scraps is a bad deal they cannot see
  before paying (and a dev product's price is permanent). A receipt that
  surfaces in the lobby is deferred, not consumed.
- Config: `MapConfigData.checkpoint.layerEater*`. Price/label: `ShopData`.
- ⚠ **`TopBandFill` never reads 1.0.** `ResetCake` seeds the surface with noise
  0.3 studs BELOW the nominal top, so a brand-new cake's topmost band measures
  ~0.95 of its nominal volume (measured, `layereater_scenario.lua`). Anything
  near 1.0 is therefore an unreachable threshold.
- **Verified without a receipt**: `SCENARIO_FILE=layereater_scenario.lua python
  tools/headless-sim/build_sim.py && luau tools/headless-sim/sim.luau` — 19
  assertions over the REAL `CakeFieldService`, including that the volume the
  buyer is paid for equals the volume actually removed, and that two purchases
  inside one 1 Hz window clear two different bands. Studio cannot reach this path
  until the dev product exists (a receipt is the only route to the handler).

### ⚠ Known consequences (read before tuning or re-pricing)
1. **THE CAKE IS SHARED, so one player's purchase removes the layer for
   everyone — and only the BUYER is paid.** In a 4-player match that deletes the
   other three players' income for that whole layer, and calories are the
   RUN-scoped upgrade currency (ADR-0013), so it directly costs them tree
   progress. The buried finds in that band are also freed at once and go to
   whoever is nearest (`features/treasures.md`), which is not necessarily the
   buyer. This is inherent to a shared cake, not a bug in the grant — but it is
   an unresolved DESIGN question, not an accepted trade-off. The obvious
   alternatives are: pay every participant (the per-head rule co-op finds
   already use), gate the purchase to solo/party-consent, or leave it as is.
2. **No server-side distance check.** The prompt is the intended buy surface,
   but `RequestPurchase("layer-eater")` is a plain remote: a modified client can
   fire it from anywhere. That is deliberate — the player pays either way, so
   there is nothing to steal, and requiring proximity at RECEIPT time would
   strand a deferred delivery for anyone who walked away. Do not describe the
   walk-to-the-contraption friction as enforced.
3. **A deferred receipt is invisible to the buyer.** The prompt path refuses
   before charging, so this only happens when the cake finishes between the
   Roblox dialog and the receipt: the player is charged, `NotProcessedYet` is
   returned, and Roblox re-delivers at some later moment — plausibly in a
   different match, where a layer they did not ask for evaporates. Nothing on
   the client is told. Needs a "purchase pending" push.
4. **While `devProductId` is 0 the prompt is a dead end** — press, hear the
   press cue, nothing happens. The shop grid has the "SOON" state for this;
   a world prompt has no equivalent because a hidden product is not in
   `ShopUpdate` at all. Resolves the moment the id is set.

## Remotes
- `ReturnToCheckpoint` (client→server, no args): teleport request. Server
  validates a started/participating round, `IsLoaded` + character, **0.5 s
  debounce** (anti rag-doll), then
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
(`SetCheckpointHeight`/`GetCheckpointCFrame`/`NearGym`/`ensureLayerEaterPrompt`),
`services/CakeFieldService` (`ClearActiveBand`), `subscriptions/CakeSubs`
(`ReturnToCheckpoint` + the `eatlayer` grant kind), `CakeCycleSubs`/`CakeSimulationSubs` (height drive),
`subscriptions/BodySubs` (prompt name).
Shared: `remotes/ReturnToCheckpoint`, `UIKit/Theme` (`CheckpointButton`,
`AppHud.Checkpoint*`). Client: `subscriptions/BodySubsClient` (F key + callback),
`modules/AppRoot` (button), `data/LocaleData` (`hud-burn-fat`),
`data/ShopUiData` + `subscriptions/ShopSubsClient` (the LayerEater prompt →
`RequestPurchase`).
