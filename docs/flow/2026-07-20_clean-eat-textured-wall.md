# 2026-07-20: Wall-covers-all-but-top + clean-cut eating

Tags: cake-sim, config, rendering, gameplay

## Task
Follow-up to `2026-07-20_taller-lazy-layers-wrapper.md`. (1) The textured wall
should cover the ENTIRE cake except the very top layer, be more
performance-friendly (not EditableMesh), and actually DISPLAY its texture (it
showed none). (2) Rework eating so small leftover pieces vanish and it feels
clean/satisfying — "after eating half a layer, one side completely cleared, the
other still full, a clean cut edge; small drips fine."

## Context
Round 1 rendered the current + next 2 layers as slabs and hid the bulk below with
an EditableMesh rounded-rect wall (`Content.fromUri` `TextureContent`, tiling UVs)
— which showed no texture. Eating used `CakeOps.ApplyBite`, a paraboloid crater
(`depth·falloff/hardness`) clamped to the layer-gate floor; thin sub-floor slivers
were impossible to eat (gate clamps at the floor) and looked messy.

## Changes

**Modified:**
- `src/client/modules/CakeWrapper.lua` — REWRITTEN as a plain textured Part
  (Block) instead of an EditableMesh: sized to the loaf, top at
  `composition[activeIndex].bottom`, shrinking as layers clear; `Texture` instances
  (reliable tiling) on 4 sides + top cap. No mesh budget, no async build.
- `src/client/modules/CakeRenderer.lua` — `windowFor` → `{activeIndex}` (render
  ONLY the top layer, not 2); header/comment updates.
- `src/shared/CakeOps.lua` — `ApplyBite` reworked: clear each cell TOWARD the floor
  by `clamp(falloff·(depthStuds/clearRefDepth)/hardness)`·(h−floor) — a clean scoop
  to the layer floor (soft rim), not a shallow dent. New `clearRefDepth` param.
- `src/server/services/CakeFieldService.lua` — pass `sim.biteClearRefDepth`;
  `ScanStats` sweeps active-floor slivers (`sim.sliverSweepStuds`) each scan.
- `src/client/modules/LocalCakeField.lua` — pass `sim.biteClearRefDepth` (client
  prediction stays in lockstep).
- `src/shared/config/CakeConfig.lua` — `render.wrapper` now Part fields
  (tileStuds/gloss/color); `sim.biteClearRefDepth=3.6`, `sim.sliverSweepStuds=1.5`,
  `autoSweepFraction` 0.1→0.12.
- `src/shared/config/UpgradeConfig.lua` — `biteRadius` base 3→1.7 (tiers scaled):
  the clean bite clears full depth, so a smaller scoop keeps ~the same volume/bite
  and pace.

## Decisions
- **Render ONLY the top layer** (not 2) so the wall covers "everything except the
  very top layer" as asked. A crater cleared to the floor shows the wall's top cap
  (wall texture), and the next layer pops in as a real slab at the layer
  transition — accepted per the "cover all but the top layer" directive.
- **Part(Block) wall, not EditableMesh** — cheaper (no mesh budget/async) and the
  `Texture` path reliably tiles the image (the mesh `TextureContent`-from-URI with
  tiling UVs did not). Trade: square corners poke ~6 studs past the rounded loaf
  (exact rounded corners need EditableMesh or untextured corner primitives). See
  ADR-0008 (revised).
- **Clean-cut bite** (`clear toward the floor`) is what produces "one side cleared,
  other full" — a paraboloid + sweep alone can't (it leaves a cratered surface).
  `biteDepth` becomes the clear STRENGTH (widens the full-clear core); `biteRadius`
  the scoop size. Balance is proportional-preserving in theory but **not
  sim-verified** — starting values, tune clear-time by feel in Studio.
- **Sliver sweep** (1 Hz) clears the thin sub-floor bits the gate makes
  un-eatable; threshold 1.5 studs leaves meaningful partial cake as the cut edge.

## Open Questions / Followups
- **Studio-verified** (2026-07-20): 1 slab + Part wall, no void; clean cut edge
  holds (no sweep-vs-settle flicker); slivers swept; balance sane. The texture IDs
  all failed to load (DECAL wrappers, not Image ids — a `Texture`/`TextureContent`
  needs the underlying image id; see env memory + upstream queue). Resolved by
  swapping in `InsertService:LoadAsset`-verified image ids for the wall + all 3
  layers, live-verified showing real cake photos.
- The always-on CakeWaxShell glaze covers the TOP layer's texture at rest (layer
  textures show on the sides / through wax cracks / when eaten). If the user wants
  the layer textures prominent on top, reduce the wax coverage / opacity.
- Square wall corners are a known cosmetic trade — revisit if the user wants the
  rounded loaf look back (a multi-primitive or re-textured mesh wall).
- Balance (biteRadius 1.7 / biteClearRefDepth / calories) are proportional starting
  values — tune clear-time by feel if it drifts from ~40 min.

## Related
- Feature: `docs/features/cake-sim.md`
- ADRs: ADR-0008 (revised)
- Prior flow: `2026-07-20_taller-lazy-layers-wrapper.md`, `2026-07-19_layer-gate.md`
