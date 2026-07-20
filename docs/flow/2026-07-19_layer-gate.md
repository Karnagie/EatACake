# 2026-07-19: Top-down layer gate (eat one layer at a time)

Tags: cake-sim, cake-cycle, config, ui

## Task
Until the TOP cake layer is eaten, the next layer must be unavailable. Trying
to eat the locked layer beneath pops up a message: "eat the top layer first".

## Context
The cake is ONE shared heightfield (`features/cake-sim.md`): one height per XZ
cell = the surface; `composition` bands (bottom-up, index 1 = inedible core,
index `#` = frosting) are horizontal strata the surface passes through. Before
this, `CakeFieldService.ApplyBite` clamped bites only to `state.floorUnits`
(core top), so a single deep chomp could slice through several layers at once.
`ScanStats` already tracked `topBandIndex` (top band with material) + auto-swept
a band's last 10% (§7.6).

## Plan
Gate bites to the bottom of the current TOP edible band (the "active floor").
Advance the floor down as each layer is consumed (reuse `topBandIndex` +
auto-sweep). Server enforces the clamp authoritatively; client mirrors the same
floor in its bite prediction and raises the popup locally (no new remote).

## Changes

**Modified:**
- `src/shared/config/CakeConfig.lua` — new `CakeConfig.layerGate`
  `{ enabled, lockEpsilon, cueInterval }`.
- `src/server/data/CakeStateData.lua` — new `activeBandIndex`, `activeFloorUnits`.
- `src/server/services/CakeFieldService.lua` — `ResetCake` seeds the active band
  to the top; `ApplyBite` clamps to `activeFloorUnits` (gate on) instead of the
  core floor; `ScanStats` advances the active band (one lower when the band was
  just auto-swept, same scan, so the fresh floor isn't spuriously "locked");
  `Snapshot` meta carries `activeBandIndex`.
- `src/server/subscriptions/CakeSubs.lua` — `broadcastCycle` adds
  `activeBandIndex`; the `removed<=0` no-op comment notes the gate.
- `src/client/modules/LocalCakeField.lua` — stores `activeBandIndex`
  (snapshot + `SetActiveBand`), `ActiveFloorStuds()`; `PredictBite` clamps to
  the active floor so no phantom crater is cut below a locked layer.
- `src/client/subscriptions/CakeSubsClient.lua` — cycle handler calls
  `SetActiveBand`; `doBite` cues `announce-layer-locked` + soft sound and skips
  the bite when the surface ahead is at the active floor (`>=` edible band,
  debounced by `cueInterval`, cue only for HELD input so Auto-Eat never nags).
- `src/client/data/LocaleData.lua` — `announce-layer-locked` = "Eat the top
  layer first!".

## Decisions
- **Reuse `topBandIndex` as the active band**, don't add a parallel tracker: the
  active floor is exactly the bottom of the highest band with material. The
  monotonic-decreasing floor comes for free as layers are eaten/swept.
- **Client-authoritative popup, server-authoritative gate.** The physical block
  is the server clamp (can't cheat past it). The popup is a purely local UX cue
  from the client's own mirror + broadcast `activeBandIndex` — no extra remote,
  instant feedback. The server clamp holds regardless.
- **Push `activeBandIndex` the instant it changes**, not only on the periodic
  1 Hz cycle tick (review catch). The scan tick and cycle tick phase-drift after
  a boss (boss runs the cycle at 4 Hz), so the swept-flat surface (fast 12 Hz
  delta) could reach the client ~1 s before the new active band (slow cycle),
  briefly re-locking the just-cleared layer and flashing a false cue. Fix:
  `CakeSubs` scan block compares `state.activeBandIndex` before/after `ScanStats`
  and `broadcastCycle(nil)` immediately on change.
- **Advance the active band in the SAME scan as an auto-sweep.** Otherwise the
  just-leveled floor reads as "locked" for one scan and fires a spurious cue.
- **Reuse the `AnnounceBanner`** (via `pushAnnounce`) for the popup — no new
  component. Conflicts with cake-cycle announces are effectively impossible
  during eating (only "new-cake" at spawn, when nothing is locked yet).
- **Config flag** `layerGate.enabled` keeps the old free-dig behavior one bool
  away — template-friendly, easy playtest rollback.

## Open Questions / Followups
- `lockEpsilon` (0.3 studs) / `cueInterval` (1.2 s) are first-pass tuning.
- Popup message is generic; naming the specific layer ("Finish the Frosting!")
  would need per-layer display-name locale keys.

## Related
- Feature: `docs/features/cake-sim.md`, `docs/features/cake-cycle.md`
- Prior flow: `docs/flow/2026-07-18_eat-in-front-ball-roll.md` (full-belly gate,
  the analog for this client cue), `docs/flow/2026-07-19_checkpoint-platform.md`
  (checkpoint rides `topBandIndex`)
