# 2026-07-19: Gym fat-burn rework (timed mash → fill-drain)

Tags: body-gym, upgrades, gym, checkpoint, ui-kit, economy

## Task
Rework fat burning: press the gym prompt and the belly drains gradually
(visually), banking currency; step away and it all stops. Each TAP adds a
percentage (default 10% → 10 taps clears the belly). Upgrades: increase % per
tap and the default (passive) burn speed; add an "instant burn on press"
upgrade (3-4 expensive tiers, final = whole belly instantly). Move the tap
button RIGHT (phone thumb). Rename the HUD "BURN FAT" button to "TO CHECKPOINT".

## Context
The gym was a fixed-duration MASH minigame: `GymService` timed a window,
counted taps → a bonus multiplier, and `StomachService.Burn` emptied the whole
belly at once on completion (`BodySubs` 4 Hz payout loop). Overlay
(`GymOverlay`) had a draining TIMER bar + centered tap button. Six upgrade
stats; gym category held only `gymEff`. Read `docs/features/body-gym.md`,
`upgrades.md`, `checkpoint.md` first.

## Plan
Replace the timed model with a **baseline-drain session**: capture start
fill/stored, run one `burned01` 0..1, belly = `start × (1-burned01)`, bank the
integer delta of `floor(startStored × gymEff × burned01)` each tick (exact
total, no drift). Passive `burnSpeed` + per-tap `burnPerTap` advance it;
`instantBurn` seeds it on press. Stop on leaving `NearGym`. 3 new gym upgrades.
Overlay → right-thumb tap button + eased "fat left" bar. Locale label swap.

## Changes

**Modified:**
- `shared/config/BodyConfig.lua` — `gym` retuned: `stepHz`, `tapsPerSecondCap`,
  `minStartFill`, `autoBurnInterval`, `minStoredToBurn` (dropped duration/
  maxBonus/perfectTaps/cooldown).
- `shared/config/UpgradeConfig.lua` — +`burnSpeed`/`burnPerTap`/`instantBurn`
  (gym category); added to `.order` and `rebirth.resets`.
- `shared/config/UpgradeTreeConfig.lua` — gym sub-tree stats = 4.
- `server/data/ProfileSchema/UpgradesSection.lua` — new ids in `defaults.levels`
  (no version bump — reconcile fills them, all consumers read missing = 0).
- `server/data/PlayerRuntimeData.lua` — new `gymSessions` shape.
- `server/services/GymService.lua` — full rewrite (drain-session math).
- `server/services/StomachService.lua` — +`SetBelly(fill, stored)`.
- `server/services/StatsService.lua` — +`BurnSpeed`/`BurnPerTap`/`InstantBurn`.
- `server/subscriptions/BodySubs.lua` — gym orchestration + stepHz drain loop,
  `creditResult`/`burnAll`; stop-on-leave; instant-burn-on-press.
- `server/subscriptions/RebirthSubs.lua` — `GymService.EndSession` before wipe.
- `client/subscriptions/BodySubsClient.lua` — GymUpdate events
  started/progress/result/stopped/auto/instant; per-tap sound.
- `client/modules/AppRoot.lua` — GymOverlay gets `remain01`/`fatText`; dropped
  the local tap counter.
- `shared/UIKit/Components/GymOverlay.lua` — eased fat-left bar + right-thumb
  tap button (Timer* → Bar* / FatBar).
- `shared/UIKit/Theme.lua` — `GymOverlay` repositioned bottom-right; Bar* keys.
- `client/data/LocaleData.lua` — `hud-burn-fat` → "TO CHECKPOINT";
  `gym-taps-n` → `gym-fat-left`; 3 new upgrade name/desc/hex-name keys.
- Docs: `features/body-gym.md`, `features/upgrades.md`, `features/checkpoint.md`.

## Decisions
- **Baseline-relative taps, not fraction-of-current.** "10 taps = 100%" is only
  exact if each tap burns a fixed 10% of the SESSION-START fill. So the session
  captures `startFill`/`startStored`; a single `burned01` maps them to 0. Taps
  on current-remaining would be Zeno (never reach 0) and wouldn't match the spec.
- **Monotone integer banking marker** (`bankedInt`): credit
  `floor(startStored×gymEff×burned01) − bankedInt` per tick → total is exactly
  `floor(startStored×gymEff)`, matching the old single Burn, with no rounding
  drift or double-count even if a tap overshoots `burned01` past 1.
- **No tap anti-cheat panic.** Taps only drain the player's OWN bounded belly;
  banking can't exceed `startStored×gymEff` however fast taps arrive → no
  calorie exploit. Kept a light `tapsPerSecondCap×elapsed` cap for pacing only.
- **Instant-burn = seed `burned01`.** The upgrade is just the session's starting
  progress; the final tier seeds 1.0 → completes on press (no overlay, fires
  `instant`). Re-pressing an active session is ignored (`HasSession` guard) so it
  can't re-seed the instant slice.
- **Re-inflate guard.** The drain rewrites fill from the baseline each tick, so
  any external belly-empty (rebirth, auto-gym, `burn` reward) `EndSession`s first
  — otherwise the next tick would restore the belly.
- **New upgrade ids need no version bump** (P2): they're new `levels` fields with
  default 0; reconcile fills them and every reader treats missing as tier 0.
- **Overlay stays non-modal.** The root frame is not Active, so walking away
  (left stick) still works — that's the "step away and it stops" mechanism,
  enforced server-side by the per-tick `NearGym` re-check.

## Open Questions / Followups
- Tuning: burnSpeed/burnPerTap/instantBurn tier values + costs are first-pass
  guesses — playtest and balance.
- Right-thumb tap button (0.82, 0.70) may sit near the mobile jump button on
  some aspect ratios — verify on a phone / in Studio device emulator.
- Studio verification pending (studio-verifier): burn drains smoothly, currency
  ticks, leaving stops it, instant-burn tiers, morph slims back down.

## Related
- Feature: `docs/features/body-gym.md`, `docs/features/upgrades.md`,
  `docs/features/checkpoint.md`
- Prior flow: `docs/flow/2026-07-19_checkpoint-platform.md`,
  `docs/flow/2026-07-19_hex-upgrade-tree.md`
