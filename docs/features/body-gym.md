# Body & gym (stomach, morph, ball, fat-burn)

## The loop (GDD §8)
Bites add VOLUME to `stomach.fill` (capped at the capacity stat) and
CALORIES to `stomach.stored` (unbanked). The gym **DRAINS** the belly from its
start fill to empty while you stand at the machine, banking `stored → calories`
(`× gymEff`) as it goes (see Gym below). As fill rises the body INFLATES
(morph); as the gym drains it, the body slims back down. **At full you can't
eat** — `StomachService.IsFull` makes `CakeSubs` drop the bite before it carves
the cake (the client gates too, with a soft cue), WalkSpeed is −40% (linear
with fill), and the rig becomes a rolling **ball** (below). The gym is the only
release valve. Glutton ×2 fires once — on the single bite that TOPS YOU OFF
(`glutton = fill + volume ≥ capacity`), never on sustained overeating (now
impossible). **Easy-mode**: `capacity` is large (base 2600 = ~50 s of eating per
fill, ~50–160 bites — not the old ~4), so the loop is EATING-dominant and the gym
is an occasional quick beat; see `features/upgrades.md` + `2026-07-19_easy-mode-balance.md`.

## State
Profile section `stomach` `{fill, stored}` (persists across rejoins).
Runtime: `PlayerRuntimeData.gymSessions/lastAutoBurn/lastMorphFill`.

## Replication
- `StomachUpdate` → HUD belly bar + floating numbers. The full shape
  `{fill, capacity, stored, gained, glutton, layerId}` is the PER-BITE payload
  (CakeSubs). The on-join push, each gym-DRAIN tick (~stepHz), and the
  stop/complete resync go through `BodySubs.SendStomach` and carry only
  `{fill, stored, capacity, gained}` (no `glutton`/`layerId`). The client also
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
- Server also writes attribute `StomachFill` (0..1, rounded 0.01) — read by
  the client tumble driver below (the HUD belly bar reads the `StomachUpdate`
  payload above, not this attribute).
- **Tumble** (`BallRollController`, `BodyConfig.tumble`): past `tumbleFill`
  EVERY client tumbles that character's whole (scaled) body forward as it MOVES,
  and settles it UPRIGHT when stopped, by rotating the ROOT joint's STATIC
  offset — `Motor6D.C0`, or on AnimationConstraint avatars the Root
  constraint's `Attachment0.CFrame` (the one channel the Animator never
  overwrites; see gotcha). Rolls by real ground distance. VISUAL ONLY — the
  HumanoidRootPart (physics/collision/camera) is never touched, so WalkSpeed &
  jump are unchanged. Same replicated `StomachFill`, zero network.
- WalkSpeed is server-authoritative: `BodySubs.RefreshBody` = runSpeed stat
  × fill penalty × caramel slow (1 Hz surface check). NOTE: the collision rework
  (Task 4, `features/cake-sim.md`) makes eating move in a roughly straight line
  — one walkable surface (server safety slabs sit BELOW the fine client columns),
  rate-limited column rise (refilling cake doesn't punt you up — jump to climb
  out), and no bounce/jump-boost while eating.

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

## Gym (fat-DRAIN session)
The gym machine lives on the **checkpoint platform** beside the cake (it moved
off the old floor zone — see `features/checkpoint.md`; you return to it with
F / the HUD button). It carries a ProximityPrompt (`GymPrompt`).
Client gym-tap/checkpoint callbacks and prompt availability fail closed through
`PlayerControlService.IsLocked`, so modal/teleport handoffs cannot fire custom
gameplay input after movement controls are disabled.

**Model** (GymService owns the session math; BodySubs orchestrates): pressing
the prompt captures the belly's START `fill`/`stored` as a baseline (and LOCKS
`gymEff`) and opens a session with one **burn progress** `burned01` 0..1. At
`burned01 = 1` the whole captured baseline is burned and ALL captured stored has
banked. Each tick the drain reports its OWN delta (`dFill`/`dStored`) and
BodySubs SUBTRACTS it from the current belly (not an overwrite), so a bite taken
mid-session — the cake edge is reachable from the plate — survives instead of
being clobbered. Progress advances two ways every server tick (`stepHz = 8`):
- **passive** — `burnSpeed` stat (fraction of the belly per second)
- **per TAP** — `burnPerTap` stat (fraction per registered tap; base 0.10 → 10
  taps clear a full belly)

`instantBurn` stat SEEDS `burned01` at start (a slice removed on press; the
final tier seeds 1.0 = whole belly instantly, no session opened). Banking is
monotone via a banked-so-far integer marker (`bankTarget = floor(startStored ×
gymEff × burned01)`, credit the DELTA each tick) so the session total is exactly
`floor(startStored × gymEff)` — no drift, no double-count.

**Flow**: `PromptTriggered` (name `GymPrompt`) → IsLoaded gate → HasSession
re-press guard → `MapService.NearGym` range → empty-belly guard
(`fill < minStartFill`) → `GymService.StartSession(fill, stored, instantBurn,
gymEff)`. BodySubs applies the result (`SetBelly` + bank the instant slice) and
fires `GymUpdate {event="started"}` + `{event="progress", remain01}`. Taps =
`GymTap` remote → `RegisterTap` (counted server-side, capped `tapsPerSecondCap ×
elapsed`; note fast tapping only drains the player's OWN bounded belly, so there
is no calorie exploit). The stepHz drain loop calls `GymService.Advance` →
`creditResult` (SetBelly + AddCalories(bankDelta) + ProgressService lifetimeCalories
+ SendCurrency + SendStomach) → `{event="progress"}`; on `burned01 ≥ 1` it ends
the session with `{event="result", banked}`.

**Treadmill run (user req)**: the `GymMachine` is a **treadmill** (an invisible
collider Part carrying the authored treadmill Model; both ride the plate via
`PivotTo`). On `PromptTriggered` (a real session, not the instant-final tier),
BodySubs **mounts** the player on the belt: teleports the HRP to
`MapService.GetGymMountCFrame()`, **anchors** it in place, and plays a looping
**run animation** SERVER-side on the Animator (replicates to everyone; the
character's own `Animate.run` when present, else
`BodyConfig.gym.treadmill.runAnimationId`). The belly drains as usual — passive
`burnSpeed` finishes it hands-free, taps still speed it up. On `burned01 ≥ 1`
BodySubs **unmounts** (stops the anim, restores the anchor, teleports the player
beside the treadmill via `MapService.GetGymDismountCFrame()`) and fires
`{event="result"}`. Mount geometry lives in `MapConfigData.checkpoint`
(`treadmillStandHeight`/`FaceYaw`/`DismountBack`/`DismountHeight`, relative to the
plate top, Studio-verified). `treadmill.enabled=false` restores the old STANDING
burn.
**Committed run / walk-away**: a treadmill run is COMMITTED — the player is
ANCHORED on the belt, so the old "walk away to stop" rule (the user's earlier
rule) is SUPERSEDED for a run; it ends only when the belly empties (or death /
rebirth / an instant burn, which all release the mount). The walk-away stop
still applies to the STANDING fallback (`treadmill.enabled=false` or a failed
mount): that path re-checks `NearGym` each tick and ends on leaving
(`{event="stopped"}`, no payout, the drained belly is kept). **Robust release**:
a per-tick safety net unmounts any player who is still mounted but has NO session
(so an external ender like **rebirth** `GymService.EndSession` can never leave
them stuck anchored), firing `{event="stopped"}` to close the overlay;
`CharacterRemoving` (death/reset) and `PlayerRemoving` also clear the mount.

**Full burns** (`burnAll`, EndSession-first so a live session can't re-inflate
the belly): Auto-Gym pass burns the whole belly every 6 s (`{event="auto"}`);
reward kind `burn` (instant-burn dev product) does the same anywhere
(`{event="instant"}`). Rebirth also ends any live session before emptying.

**Overlay** (`GymOverlay`, kit): a full-screen transparent layer with a
bottom-**RIGHT** round TAP button (phone thumb), a "fat left" bar that eases
toward the streamed `remain01`, and a `{n}% FAT` label. The root frame is NOT
Active, so the player can still walk (left stick) — which is how you leave to
stop the burn. The TAP button squishes/springs on every tap via the shared
`Interaction` press primitive (ADR-0006).

**Prompt hidden when empty (per-player).** The world `GymPrompt` ("Burn it
off!") would otherwise show even with nothing to burn. `BodySubsClient` mirrors
the server's `fill < minStartFill` no-op guard: it tracks the local belly `fill`
(from `StomachUpdate`) and, from the ~5 Hz proximity loop, sets the prompt's
`Enabled` **locally** (resolved by class under `Map.Checkpoint.GymMachine`, so it
affects only this client and needs no prompt-name coupling). Empty → prompt
hidden; ≥ `minStartFill` → shown. The server guard still stands regardless
(defense in depth). ⚠ The gate SKIPS while the upgrade tree is open
(`AppRoot.GetOpenPanel() == "Upgrades"`) — that modal disables ALL checkpoint
prompts so the E-to-close press can't also start a gym session behind the
overlay (`UpgradesSubsClient`); the gate must not re-enable the prompt and fight
it. The modal restores prompts on close and the gate re-applies next tick.

## Files
`ProfileSchema/StomachSection`, `services/StomachService` (`IsFull`,
`SetBelly`, `Burn`), `services/GymService` (drain-session math),
`services/StatsService` (`BurnSpeed`/`BurnPerTap`/`InstantBurn`/`GymEfficiency`),
`subscriptions/BodySubs` (gym orchestration + drain loop + treadmill
mount/anchor/run + body morph lerp), `services/MapService`
(`GetGymMountCFrame`/`GetGymDismountCFrame`), `data/MapConfigData`
(`checkpoint.treadmill*`);
shared `config/BodyConfig` (`gym`/`morph`/`tumble`/`eatGesture`),
`config/UpgradeConfig` (`burnSpeed`/`burnPerTap`/`instantBurn` gym stats — see
`features/upgrades.md`); client `BallRollController` (tumble), `BodySubsClient`,
`modules/AppRoot` (overlay props), kit `GymOverlay`. Full-belly bite block lives
in `CakeSubs` (see `features/cake-sim.md`).
