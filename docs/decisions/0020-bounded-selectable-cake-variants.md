# ADR-0020 — Bounded selectable cake variants

Date: 2026-08-11
Status: accepted
Superseded in part by: ADR-0021 (rainbow silhouette, renderer and checkpoint reach)
Supersedes in part: ADR-0007 (`workspace.Map` owns a swappable room child),
ADR-0011 (the silhouette is fixed only *within* a selected variant)

## Context

The second catalogue entry had persistence and unlock UI but no runtime cake.
The requested rainbow cake needed six same-colour layer runs, a pyramid profile,
1.5× physical size and duration, no wax/crust, another authored environment and
1.5× find rewards.

The existing classic disc already uses radius 31.1 of the 64×64 field's 31.5-cell
limit. Scaling diameter by 1.5 would require roughly a 96×96 field (2.25× cells,
mesh work and scans) and would exceed the authored 100×88 `CakePlate` shared by
both rooms. Height can grow from 170 to 255 inside `grid.maxHeight=340` without
changing the simulation resolution or authored footprint.

A second coupling appeared in the progression model: multiplying bite work by
1.5 did not make total wall time 1.5× because gym/UI time is fixed. With the
actual fixed colour masks, 1.5× work measured only ~1.36× total duration.

## Decision

1. `CakeSelectConfig` remains the catalogue/unlock source;
   `CakeConfig.variants` is the separate source for playable runtime behavior.
   At launch the lobby snapshots the leader's persisted selection into
   protocol-v2 TeleportData `cakeId`. The destination validates it, stores
   `RoundStateData["cake-id"]`, and includes it in later-arrival matching.
2. “1.5× size” means edible height: classic 170, rainbow 255. The base remains
   the classic disc; rainbow bands carry local footprints that grow from .62 to
   1.00 radius top-to-bottom. All field initialization, cleanup, find placement
   and wrapper rendering consume those masks.
3. `durationScale` names the player-facing target. A separately named calibrated
   `durationWorkScale=1.79` controls scoop area; density is compensated so food
   and belly milestones stay at comparable cake depth. Five seeded ramped runs
   measure 52.21 vs 34.86 minutes (1.4980×).
4. Variant metadata also owns authored room name, find-reward multiplier and
   wax/crust/rare flags. `workspace.Map` becomes a stable container whose
   `Environment` child can be replaced without destroying Checkpoint/CakeSpawn.
5. Rainbow uses opaque `SmoothPlastic`, no flow and `squishMult=2.6`, enabled by
   its variant-level `useLayerSquishMultiplier` opt-in. Classic remains on its
   shipped uniform non-rigid dent. This is the allowed “regular and soft”
   material option; no jelly transparency is added.

## Consequences

- One party plays the leader's cake. Other members need not own/unlock it; the
  entitlement is enforced when selecting, not again when joining that leader.
- Direct joins use `CakeConfig.defaultVariantId`. The lobby warns/falls back for
  corrupt or catalogue-only selections; the destination rejects missing or
  unknown `cakeId` values.
- Protocol v1 is intentionally incompatible because it has no authoritative
  cake. Lobby and game places must be published/drained coherently.
- Classic keeps its footprint, coatings, random zones, rare rolls and reward
  scale. Per-band footprints are an additive composition field.

## Alternatives rejected

- **96×96 field and a 1.5× diameter.** It multiplies the hottest simulation and
  render paths by 2.25 and still requires both authored rooms' plates to be
  rebuilt.
- **Treat 1.5× height as 1.5× duration.** Height is visual because bites clear to
  a band floor; it does not provide the requested time increase.
- **Use `durationWorkScale=1.5`.** The ramped model measures total session time,
  including fixed gym time, and showed it misses the target materially.
- **Overload `rareKind="rainbow"`.** That id already means a random classic-cake
  skin; selectable `cakeId="cake-rainbow"` has a different persistence and
  protocol lifetime.
