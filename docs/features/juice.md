# Juice / ASMR layer (client)

## What it does
GDD §7 — priority #1. All client-side, all pooled (ZERO Instance.new in hot
paths, GDD §16.10). Tuning ONLY in `Shared/config/JuiceConfig`.

## Pieces
| Module | Owns |
|---|---|
| `SoundPool` | ALL sound — see `features/audio.md` (this doc no longer owns it) |
| `ParticlePool` | 12 pooled emitter-parts, `:Emit()` bursts, ≤200 active budget window |
| `CameraShake` | trauma-based impulse shake, applied post-Camera render step |
| `ComboMeter` | x1→x10, +1/2s continuous, reset >1.5s pause. FX-ONLY (never calories) |
| `FloatingNumbers` | 24 pooled BillboardGuis, size scales with combo |
| `FoodBurst` | 64 pooled screen-space food sprites — the CELEBRATION confetti, own doc: `features/food-burst.md` |

## Event → FX map
layer cleared / Cake Monster down: chime + camera punch + a burst of food
sprites across the screen and a random-cheer splash (`features/food-burst.md`);
bite (predicted): layer SFX + crumbs (palette color) + shake + the eat gesture
(flying layer piece, `EatGestureController` — see `features/cake-sim.md`);
chocolate adds shard burst + crack. Landing on a fresh cake: crust crack
ring + big snap (§7.1, once per cake, client-local). Server deltas ≠ own
prediction → slump loop volume + (renderer) smooth lerp avalanches. Gym
payout: whoosh + coin burst + green floating number. Stomach gain: floating
"+N" above head (hot color in glutton). Underfoot squish lives in
`CakeRenderer` (§7.2, display-only).

## Gotcha
Sound left this feature: samples, the key map, pitch/pool tuning and the slump
response all live in `AudioConfig` + `features/audio.md`. `JuiceConfig` now
holds only the non-audio numbers (particles, camera, combo, squish, chunks,
walk cadence). Layer `sfx` keys index `AudioConfig.sounds`.

## Files
`src/client/modules/` (five modules above), consumed by `CakeSubsClient` /
`BodySubsClient`; config `src/shared/config/JuiceConfig.lua`.
