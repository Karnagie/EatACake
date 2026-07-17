# 2026-07-17: Cake grounding — floating mesh, corner slits, candle clipping

Tags: cake-sim, juice, map

## Task
User feedback pass 3 (screenshots): "я внутри торта, он висит в воздухе,
по углам острые дырки". Three distinct bugs, all fixed and verified live.

## Root causes & fixes
1. **Floating cake (30 studs above the tray)** — `CakeRenderer` positioned
   the MeshPart at `origin.y + maxHeight/2`, assuming rendered geometry is
   recentered on the part's bounding-box center. Verified live: parts from
   `CreateMeshPartAsync` render vertices at their RAW mesh coordinates
   relative to `part.CFrame` — mesh y=0 lands exactly at `part.Position.Y`.
   Part now sits at `grid.origin` directly. This also explains "я внутри":
   collision columns were at TRUE heights, so players collided with an
   invisible cake while the visible one hung 30 studs overhead.
2. **Full-height see-through slits at rounded corners** — mesh faces were
   created for cells passing an analytic "+1 ring" rounded-rect test
   (`hx+1, hz+1, corner+1`); its discrete arc disagrees with the footprint
   arc at corner staircase steps, dropping quads next to full-height
   boundary vertices. Faces are now created for every cell whose 3×3
   neighborhood touches the footprint — the same rule as vertexTarget, so
   a closed skirt is guaranteed by construction.
3. **Candles inside the loaf** — `MapConfigData.candles` predated the big
   footprint; striped candle bodies clipped through the mesh walls and
   read as glitches/spikes. Moved to the tray corners, outside the loaf
   (±46, ±32) but inside the plate.

Also corrected a WRONG prior conclusion (v1 flow doc + QUEUE):
RenderFidelity **Precise does render live EditableMesh edits** (bites,
vertex moves — verified via carved test trench + live crater). It is
**Automatic** that breaks runtime-edited meshes: it swaps in LODs generated
from CREATION-time content by distance/quality (stale "canopy"). The
earlier "Precise freezes edits" reading was the camera-inside-mesh
illusion. Runtime-edited meshes ⇒ Precise.

## Verification (live, scripted cameras — NOT grazing/top-down angles)
- Ground-level + wide + far shots: loaf sits on the tray, strata walls
  continuous around all corners, no slits, no canopy, no distance culling
  loss (part box moved 30 studs down but culling follows creation
  geometry — verified from 200+ studs).
- Walk-into-wall test: character walking from x=50 into the cake stops at
  x=42.7 (wall at 42) — cannot enter the cake.
- 20 live `EatAt` bites → crater renders on the top under Precise.
- Console: no new warnings/errors (only the known dashboard-ids pending).

## Gotcha for future verification sessions
High/top-down cameras HIDE a floating-cake gap (the loaf occludes it; the
tray margin looks like a normal border). Verify grounding from a LOW
outside camera pointed at the base seam. Two earlier "verified OK" passes
missed the float because of camera choice.

## Files
`src/client/modules/CakeRenderer.lua` (part CFrame, cellHostsFaces,
debug probes removed), `src/server/data/MapConfigData.lua` (candles).

## Related
- Feature: `docs/features/cake-sim.md`
- Prior flow: `2026-07-16_eat-the-cake-v1.md` (Cake 2.0 section — engine
  gotchas list corrected there)
