# 2026-07-20: 2-layer render, wax-every-layer, sharper textures, cleaner cut, no code lighting

Tags: cake-sim, config, rendering, map, gameplay

## Task
Round-3 follow-ups: (1) small pieces + thin "puddle" leftovers still remain; (2)
the frosting texture `104319784921009` looks blurry/smeared; (3) stop changing
Lighting from code — remove it; (4) render the NEXT layer too (not only the
current); (5) wax should be above EVERY layer — when you reach the current layer's
floor there's a crackable wax skin on the next layer that doesn't fully break
until that layer becomes active.

## Context
Follows `2026-07-20_clean-eat-textured-wall.md` (1-layer render + Part wall +
clean-cut bite + sliver sweep). Layer textures mapped 0..1 across the loaf (blurry);
the sliver sweep was conservative (isolated-only) to avoid a settle flicker, which
left edge puddles; the wax hid where eaten (bare next layer showed); MapService set
Lighting on boot + biome recolor.

## Changes (all in existing files)
- **(4) 2-layer render** — `CakeRenderer.windowFor` → `{activeIndex-1, activeIndex}`;
  `CakeWrapper.wrapperTopStuds` → `composition[activeIndex-1].bottom` (wall below the
  NEXT band). The round-2 "1 slab" comments reverted.
- **(2) Sharp textures** — `render.layerTextureTiles = 4`; slab UVs baked ×tiles so
  layer textures tile instead of stretching once. Single (palette) fallback now uses
  FLAT color (tiled UVs would repeat a per-cell palette image).
- **(3) No code lighting** — removed all `Lighting.*` writes (Build + ApplyBiome) and
  the `Lighting` service ref from `MapService`. Biome recolor now touches only part
  colors; lighting is authored in Studio.
- **(1) Cleaner cut** — `SettleStep` GUARD: the settle won't ooze INTO the cleared
  zone (cells within `sim.sliverSweepStuds` of the active floor) → cleared cake stays
  clean (no puddle refill), the cut edge is a sharp cliff, the drip forms ABOVE the
  zone. With the guard preventing the refill flicker, the sliver sweep reverted to
  AGGRESSIVE (every thin cell in the zone → floor, no neighbour check).
- **(5) Wax every layer** — `CakeWaxShell` hide reference changed from `maxH -
  hideDepth` to the ACTIVE-BAND FLOOR (`LocalCakeField.ActiveFloorStuds`): the wax
  rides the surface DOWN to the current layer's floor, so cleared spots show the next
  layer's wax skin (not bare cake). It hides only below the active floor (gate-
  forbidden) or at the base; `hideDepth` local removed (unused).

## Decisions
- The puddles came from the SETTLE oozing into cleared craters, not the sweep being
  too weak. Guarding the settle (don't fill the cleared zone) fixes the root cause
  AND removes the sweep-vs-settle flicker, so the sweep can be aggressive again.
- Tiling the slab UVs breaks the single-mode palette IMAGE (it would repeat); since
  single mode is a rare weak-device fallback, it now renders a flat tinted slab.
- Wax-every-layer = ride the surface to the active floor instead of hiding — the
  layer gate guarantees the surface never drops below it, so it "coats every layer"
  and only breaks when a layer becomes active and its floor drops.

## Open Questions / Followups
- **Studio-verified (2026-07-20, all 7 checks pass)**: no puddles (flat cleared
  floor, sharp edge, 0 flicker); frosting texture sharp (the tiled
  `TextureContent`-from-URI on the slab DID render — the WALL's "tiling UVs = no
  texture" failure did NOT reproduce on the slab's horizontal planar UVs); no code
  lighting (`ClockTime` stayed as set in Studio); both layers visible (next shows as
  a distinct floor slab in craters); wax coats the cleared floor.
- ⚠ The always-on wax glaze fully HIDES the (now-sharp) layer textures from a normal
  top view — they only read on the cut walls / rim / crater cross-section. If the
  user wants the layer photos prominent on TOP, thin the wax coverage / opacity.
- `ensureImage` + the palette-image paths in `CakeRenderer` are now dead (single mode
  is flat color) — harmless; a future cleanup could drop them.
- Pace values (biteRadius/biteClearRefDepth/calories) remain tune-by-feel.

## Related
- Feature: `docs/features/cake-sim.md`; ADR-0008 (iterated)
- Prior flow: `2026-07-20_clean-eat-textured-wall.md`, `2026-07-18_wax-shell.md`
