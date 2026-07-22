# 2026-07-20: Taller cake, lazy 2-layer render, textured wrapper + layer textures

Tags: cake-sim, config, map, upgrades, economy

## Task
1. Make the cake ~3× taller with more layers, rebalanced. 2. Stop generating ALL
layers at once (perf) — render only the current + next layer and hide the empty
bulk below behind a textured outer wrapper (random of 3 asset ids). 3. Add image
textures to some layers / a new layer type (frosting 432595379, chocolate
125382980, filling 5239367014).

## Context
The cake is one 64×64 u16 heightfield (`features/cake-sim.md`). `CakeRenderer`
built ONE slab MeshPart per composition band (up to `MAX_LAYER_MESHES=8`), the
sides drawn by per-band ring skirts — so more/taller layers blow the EditableMesh
vertex budget. The layer gate (`2026-07-19_layer-gate.md`) already forbids eating
below the active band's floor. Balance was sim-grounded on "solo clears one cake
in ~40 min" (`2026-07-19_easy-mode-balance.md`, `UpgradeConfig`).

## Plan
Keep the SIM unchanged (heightfield keeps full data). Render only
`composition[activeIndex]` + `composition[activeIndex-1]` as slabs; a new
`CakeWrapper` wall hides everything below. Rebalance same-pace: since the layer
gate meant only 2 slabs are ever visible anyway, the whole layer count is freed.
User chose *same pace* + *~10–14 chunky layers*.

## Changes

**Created:**
- `src/client/modules/CakeWrapper.lua` — textured rounded-rect outer WALL. One
  FixedSize-clone MeshPart (CakeWaxShell build pattern), random cake texture per
  cake (`Content.fromUri`, chosen by `cakeIndex`), top ring rides
  `composition[activeIndex-1].bottom` and drops as layers finish. Local/visual.
- `docs/decisions/0008-lazy-window-render-textured-wrapper.md` (ADR)

**Modified:**
- `src/client/modules/CakeRenderer.lua` — `assignBands`→`assignWindowBands(meta,
  windowIdx)` builds slabs ONLY for the windowed bands; `windowFor(activeIndex)`
  = `{activeIndex-1, activeIndex}`; `writeBandsGeometry` extracted; `rewindow`
  re-dresses the 2 slabs when the layer gate advances (polled in `editableStep`
  vs `renderedActiveIndex`). Rendered slabs now apply `layer.texture` if set.
- `src/shared/config/CakeConfig.lua` — `grid.maxHeight` 90→270, `totalHeight`
  {50,60}→{150,180}, `middleCount` 3-4→10-13, layer `calories` ×⅓, new `filling`
  layer + textures on frosting/chocolate, `middlePool` += filling, new
  `render.wrapper` block.
- `src/shared/config/UpgradeConfig.lua` — `biteDepth` ×3, `capacity` ×3.
- `src/client/subscriptions/CakeSubsClient.lua` — wire `CakeWrapper`.
- `src/client/modules/CakeWaxShell.lua` — birthY comment/verify note for the
  taller ride.
- `src/server/data/MapConfigData.lua` — `room.wallHeight` 110→300 (ceiling clears
  the 3× cake top ~272).

## Decisions
- **Same-pace rebalance is fully proportional** (so nothing else drifts): total
  volume ×3, so bite volume ×3 (`biteDepth` ×3, volume ∝ depth·radius²),
  `capacity` ×3 (same bite-count per belly), `calories`/stud³ ×⅓ (income/sec and
  per-cake stay flat). Upgrade COSTS and `perPlayerScale` unchanged (calorie rate
  is flat → progression pace preserved; the ~40-min clear-time still holds).
- **Window-render safety**: the layer gate can't dig below `active.bottom`, so the
  next band stays a flat floor (seen through holes) and everything below
  `next.bottom` is never exposed from the top — the wrapper only covers the SIDES.
- **`rewindow` runs in RenderStepped** but never yields (pool already ≥2 after the
  first rebuild; `Step` short-circuits during `rebuilding`).
- **Wrapper is a separate module** (reads `LocalCakeField` itself, like
  `CakeWaxShell`) — no cross-module coupling with the renderer.
- **Textures via `Content.fromUri`** on the slab/wall `TextureContent` — a new
  pattern here (only EditableImage `fromObject` existed). Cheap now: static
  reference, no per-cell paint (avoids the mobile trap that removed per-band
  textures, `2026-07-19_cake-rebuild-mobile-spike.md`).

## Open Questions / Followups
- **Studio verify** (pending): (a) only 2 `CakeLayer*` parts exist; (b) wrapper
  hides the void from the side + top, no seam/poke-through, window shifts as
  layers finish; (c) `Content.fromUri` textures load (else console warns —
  the 3 wall ids + 3 layer ids); (d) wax renders at the tall top (birthY
  culling); (e) clear-time + calories/sec still ~match the 40-min target; nudge
  `biteDepth`/`capacity`/`calories`.
- **Room walls are place-authored** (ADR-0007) — `MapConfigData` only reseeds the
  generator; if the authored Environment caps the ceiling at 110, raise it in
  Studio (or regenerate) or the tall cake clips it.

## Related
- Feature: `docs/features/cake-sim.md`
- ADRs: ADR-0008 (this), ADR-0003 (heightfield)
- Prior flow: `2026-07-19_layer-gate.md`, `2026-07-18_layer-meshes-crust-feel.md`,
  `2026-07-19_easy-mode-balance.md`, `2026-07-18_wax-shell.md`
