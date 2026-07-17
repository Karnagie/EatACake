# Body & gym (stomach, morph, glutton, mash minigame)

## The loop (GDD §8)
Bites add VOLUME to `stomach.fill` (capped at the capacity stat) and
CALORIES to `stomach.stored` (unbanked). The gym converts stored → banked
calories (`× gymEff stat × mash bonus`) and empties the belly. At full:
fill stops, WalkSpeed −40% (linear with fill), calorie gain ×2 (glutton).

## State
Profile section `stomach` `{fill, stored}` (persists across rejoins).
Runtime: `PlayerRuntimeData.gymSessions/lastAutoBurn/lastMorphFill`.

## Replication
- `StomachUpdate` (per bite / on join): `{fill, capacity, stored, gained,
  glutton, layerId}` → HUD belly bar + floating numbers.
- Body morph: server writes player attribute `StomachFill` (0..1, rounded
  0.01); EVERY client lerps EVERY character's Humanoid scale NumberValues
  locally (`BodyMorphController`) — smooth, zero network. R6 rigs skip
  gracefully. Cartoonish, non-sexualized targets in `BodyConfig.morph`.
- WalkSpeed is server-authoritative: `BodySubs.RefreshBody` = runSpeed stat
  × fill penalty × caramel slow (1 Hz surface check).

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
`ProfileSchema/StomachSection`, `services/StomachService`, `GymService`,
`subscriptions/BodySubs`; shared `config/BodyConfig`; client
`BodyMorphController`, `BodySubsClient`, kit `GymOverlay`.
