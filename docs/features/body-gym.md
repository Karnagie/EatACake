# Body & gym (stomach, morph, ball, mash minigame)

## The loop (GDD §8)
Bites add VOLUME to `stomach.fill` (capped at the capacity stat) and
CALORIES to `stomach.stored` (unbanked). The gym converts stored → banked
calories (`× gymEff stat × mash bonus`) and empties the belly. As fill rises
the body INFLATES (morph). **At full you can't eat** — `StomachService.IsFull`
makes `CakeSubs` drop the bite before it carves the cake (the client gates
too, with a soft cue), WalkSpeed is −40% (linear with fill), and the rig
becomes a rolling **ball** (below). The gym is the only release valve.
Glutton ×2 fires once — on the single bite that TOPS YOU OFF
(`glutton = fill + volume ≥ capacity`), never on sustained overeating (now
impossible).

## State
Profile section `stomach` `{fill, stored}` (persists across rejoins).
Runtime: `PlayerRuntimeData.gymSessions/lastAutoBurn/lastMorphFill`.

## Replication
- `StomachUpdate` (per bite / on join): `{fill, capacity, stored, gained,
  glutton, layerId}` → HUD belly bar + floating numbers. The client also
  reads `fill ≥ capacity` from it to gate eating (CakeSubsClient `isFull`).
- **Body morph = only the TORSO scales** (bigger + fatter with fill) — arms,
  legs and head keep their NATURAL size. NO proxy mesh, NO added parts. We
  can't use Humanoid BodyScale (it scales the WHOLE body); instead we grow each
  torso part's `OriginalSize` (the auto-scaler enforces `Size = OriginalSize ×
  BodyScale`, so scaling only the torso's OriginalSize grows only the torso and
  HOLDS). R15: UpperTorso + LowerTorso; R6: Torso. ⚠ MUST be written on the
  SERVER (client part-size writes are reverted by replication — see gotcha), so
  it is LERPED SERVER-SIDE in `BodySubs` (15 Hz, from `StomachService.Fullness`;
  `BodyConfig.morph` factors are the torso scale at full; snap within `minStep`
  to reach full / return to natural). The true natural size is captured once
  per torso part (never compound the scaled value); rigs without `OriginalSize`
  skip. ⚠ The huge torso can engulf the third-person camera at close zoom.
- Server also writes attribute `StomachFill` (0..1, rounded 0.01) — HUD + the
  tumble driver below.
- **Tumble** (`BallRollController`, `BodyConfig.tumble`): past `tumbleFill`
  EVERY client tumbles that character's whole (scaled) body forward as it MOVES,
  and settles it UPRIGHT when stopped, by rotating the ROOT joint's STATIC
  offset — `Motor6D.C0`, or on AnimationConstraint avatars the Root
  constraint's `Attachment0.CFrame` (the one channel the Animator never
  overwrites; see gotcha). Rolls by real ground distance. VISUAL ONLY — the
  HumanoidRootPart (physics/collision/camera) is never touched, so WalkSpeed &
  jump are unchanged. Same replicated `StomachFill`, zero network.
- WalkSpeed is server-authoritative: `BodySubs.RefreshBody` = runSpeed stat
  × fill penalty × caramel slow (1 Hz surface check). NOTE: the scaled body's
  HRP collision also scales — it walks fine on flat ground but can catch on the
  cake's craters (jump to unstick).

## Gotchas (rig — verified in Studio)
- **AnimationConstraint avatars**: modern/layered-clothing avatars use
  `AnimationConstraint` joints, NOT `Motor6D` (there is no `RootJoint` Motor6D;
  `RightShoulder` etc. are AnimationConstraints). The Animator overwrites any
  joint `.Transform` EVERY frame at EVERY `RenderStepped`/`BindToRenderStep`
  priority — you cannot pose a joint via Transform. The channel that HOLDS is
  the joint's STATIC offset: `Motor6D.C0`, or the constraint's
  `Attachment0.CFrame` (Animator never touches it). That's how the tumble works;
  it's also why the eat gesture poses NO joints (rig-agnostic flying piece).
- **Scaling only ONE body region (torso) = scale its `OriginalSize`, SERVER-
  side.** Humanoid `BodyScale` NumberValues scale the WHOLE body. The auto-
  scaler (AutomaticScalingEnabled) continuously enforces `part.Size =
  OriginalSize × BodyScale` — so a direct `part.Size` write is reverted, BUT
  growing a part's `OriginalSize` (leaving BodyScale alone) grows ONLY that part
  and HOLDS. Must be SERVER-side (client part/scale writes are reverted by
  replication — probe: client BodyWidthScale=4 → no change; server=3 → armspan
  2.1→5.9). PITFALL: capture the TRUE natural `OriginalSize` ONCE per part —
  re-reading the already-scaled value each frame COMPOUNDS it (saw torso blow up
  to 112 studs; a weak-key cache silently dropped the capture — use a strong
  table + prune). (This is why the old client-side `BodyMorphController` never
  scaled this avatar.)

## Gym
Machines built by MapService carry a ProximityPrompt (`GymPrompt`). Server
`PromptTriggered` (+ range re-check) → `GymService.StartSession` → client
`GymUpdate {event="started", duration}` opens the mash UI. Taps =
`GymTap` remote, counted server-side, capped at `tapsPerSecondCap ×
elapsed` (§13). After `duration`, the 4 Hz payout loop closes the session:
bonus 1..maxBonus by taps → `StomachService.Burn` → `EconomyService.
AddCalories` → `GymUpdate {event="result", banked, bonus}` + coins FX.
Auto-Gym pass: background burns every 6 s at bonus 1. Reward kind
`burn` (instant fat burn dev product) reuses the same payout.

## Files
`ProfileSchema/StomachSection`, `services/StomachService` (`IsFull`),
`GymService`, `subscriptions/BodySubs` (server body morph lerp); shared
`config/BodyConfig` (`morph`/`tumble`/`eatGesture`); client
`BallRollController` (tumble), `BodySubsClient`, kit `GymOverlay`. Full-belly
bite block lives in `CakeSubs` (see `features/cake-sim.md`).
