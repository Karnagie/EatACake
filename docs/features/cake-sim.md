# Cake simulation (granular heightfield)

## What it does
ONE shared cake per server: a 64×64 u16 heightfield (fixed-point 0.01
studs, `GridUtil` layout), FIXED rounded-rect "loaf" footprint
(`composition.footprint`, 84×57 studs, ~200k studs³ — Drain-the-Lake
scale), layered composition. Bites rip out craters INSTANTLY; the torn
cells are held for `sim.settleDelayAfterBite`, then the angle-of-repose
automaton slowly oozes the walls back (GDD §4). Digging a shaft is
impossible by construction.

## State & config
- `CakeStateData` — field buffer, composition, queues, phase (ALL runtime state)
- `Shared/config/CakeConfig` — grid, sim budgets, net rates, layers (§5),
  composition rolls, cycle timings. Server accesses it via `CakeConfigData`
  (which also owns anti-cheat caps).

## Server pipeline (CakeSubs Heartbeat, one connection)
| Job | Rate | Call |
|---|---|---|
| settle automaton | 20 Hz | `CakeFieldService.SettleStep` (≤ 1500 cells/tick) |
| delta flush | 12 Hz | `CollectDelta` → `CakeDeltaUpdate` — up to 3 packets/flush, each ≤ 150 cells + 40 repair (UnreliableRemoteEvent drops fires over ~900 B!) |
| collision | 5 Hz | `CakeCollisionService.UpdateHeights` (8×8 invisible parts) |
| treasures | 2 Hz | `TreasureService.Tick` |
| progress scan | 1 Hz | `ScanStats` (progress %, auto-sweep §7.6, bottom check) |

## Remotes / updates
- `EatAt` (client→server, Vector3): bite intent. Anti-cheat: token bucket from
  eat-rate stat, reach check, type/NaN check. Volume/layer/calories are
  computed SERVER-side — the client can spoof nothing but position.
- `CakeSnapshotUpdate`: full buffer + meta `{cakeIndex, radiusCells,
  composition, rareKind, biome, phase, progress}` on join (via lifecycle
  push) and on every new cake.
- `CakeDeltaUpdate` (Unreliable): `(cakeIndex, buffer[u16 idx, u16 h]*n)`.
  Losses self-heal via the rotating repair cursor (full sweep ≈ 9 s).

## Client
- `LocalCakeField` — mirror + LOCAL BITE PREDICTION with the same shared
  `CakeOps` math; deltas plain-overwrite (reconcile). Non-predicted delta
  energy drives the slump loop SFX.
- `CakeRenderer` — EditableMesh is THE renderer (65×65 verts, 1 draw call):
  strata come from a 1×256 palette TEXTURE (EditableImage) sampled by
  height via per-vertex UVs (crisp layer bands on sides + crater walls);
  crust band (lighter/glossier top 0.8 studs); BITE FEEL = drops >
  `render.snapDropStuds` snap instantly, refills ooze at `lerpSpeed`;
  jelly wobble; underfoot squish §7.2. Invisible 32×32 collision columns
  (CanCollide+CanQuery, snapped to server truth) always exist; with
  `render.forceFallback` (or no EditableMesh) the same columns become the
  visible "keycap" fallback. ⚠ Engine gotchas (Precise vs Automatic LODs,
  raw-origin vertex mapping, creation-time bounds, two-pass normals,
  3×3-neighborhood skirt faces, palette-image upvalue order) are
  documented in the flow docs (`2026-07-16_eat-the-cake-v1.md` Cake 2.0
  section) — read before touching.
- `CakeSubsClient` — sync wiring, tap/hold input (raycast vs CakeColumns/
  CakeCollision, char-forward fallback, zero pixel-hunting), bite FX,
  walk-crunch (footstep-cadence layer SFX + crumb puffs), crust-crack on
  landing.

## Gotchas
- Chocolate never flows (`repose = huge`) — it's eaten through (hardness 3)
  with client shatter FX; the GDD's "convert to crumb" state is NOT simulated.
- Auto-sweep forfeits the swept volume (nobody gets calories for it).
- Cake radius scales with population (`composition.playerScaling`) so solo
  sessions still clear a cake in ~5 min.
- Server collision (16×16 slabs) is a SAFETY net only — precise walking
  collision is the client columns; never validate bite Y against slabs.
- New cakes materialize around players standing in the footprint —
  CakeSubs lifts them onto the fresh frosting at spawn.

## Files
Server: `CakeStateData`, `CakeConfigData`, `services/CakeFieldService`,
`CakeCollisionService`, `subscriptions/CakeSubs`. Shared: `GridUtil`,
`CakeOps`, `config/CakeConfig`. Client: `LocalCakeField`, `CakeRenderer`,
`CakeSubsClient`. Cycle/boss/pets: `features/cake-cycle.md`.
