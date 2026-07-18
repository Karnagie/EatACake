# 2026-07-18: Per-layer slab meshes, textured crust cracks, layer feel

Tags: cake-sim, juice, config

## Task
User feedback: "слои вообще не отличаются — просто цвета на разной
высоте" + on a second laptop the EditableMesh pool died on the memory
budget ("Failed to create empty EditableMesh…") and the cake fell back to
rectangles. Wanted: one mesh per layer, maximally different feel per layer
(higher jumps, translucent marmalade, faster/slower flow), a butter-style
crust between layers that cracks under feet, thicker layers.

## Root cause of the budget failure (research-scout, primary sources)
A DYNAMIC EditableMesh reserves the WORST-CASE budget (60k verts/20k tris)
regardless of content — a typical desktop client fits ~8, a low-RAM laptop
fewer. The old pool created 13 dynamic meshes → guaranteed death on most
machines. FixedSize clones (`CreateEditableMeshAsync {FixedSize=true}`)
cost their ACTUAL complexity and still allow SetPosition/SetNormal.
`CreateEditableMesh`/`CreateEditableImage` return **nil** (no throw) on
budget exhaustion; `CreateMeshPartAsync` throws.

## What landed
- **CakeRenderer rewrite**: ONE MeshPart per sim layer (was: layer bands +
  separate crust bands). Pool built LAZILY per composition (typ. 6, cap 8)
  by building ONE dynamic scratch mesh, cloning it N× as FixedSize, then
  destroying the scratch (peak = 1 worst-case reservation instead of 13).
  Probe-verified in Studio: source vertex/normal ids remain valid on the
  clones; live SetPosition/SetNormal works after CreateMeshPartAsync and
  after the source is destroyed. Verts cut 4225 → 2371 (footprint-hosted
  corners only — out-of-footprint verts were never referenced by faces).
- **Crust merged into the layer texture**: each edible layer gets an
  XZ-planar 256² EditableImage; cells whose surface is within
  `crust.depth` of the layer top are painted as lighter mottled skin,
  eaten-below cells repaint as flat body color (also erases cracks there —
  intended). Per-cell repaint only on crust↔body transitions (cached).
- **Cracks live**: `CrackAt` (land star / step line polylines) was dead
  code — now wired: landings in `CakeFeelSubsClient`, walking steps in the
  walk-crunch cadence (`cracks.stepChance`).
- **NEW `CakeFeelSubsClient`**: per-layer `jumpMult` (client Humanoid,
  JumpPower/JumpHeight both handled; WalkSpeed stays server-authoritative
  in BodySubs), `bounce` landing restitution (trampoline sponge, capped by
  `feel.bounceMaxUp`), ALL landing crack feedback incl. the one fresh-cake
  first-crack ceremony (moved out of CakeSubsClient — one Landed owner).
- **Degradation ladder** (R8-loud at every step): per-layer slabs → ONE
  slab + height-palette texture (`singleMode`, no per-layer materials but
  layers still colored + per-layer ooze) → visible keycap part grid.
  Retries every new cake (budget may free).
- **Config tuning**: jelly → Glass (see gotcha in cake-sim.md), middles
  3-4 (was 3-5), middleThickness 10-16, totalHeight 52-68, frosting 6-8.

## Review hardening (adversarial workflow, 17 findings → fixed)
- Squish near a band boundary could teleport a dropped vertex up to
  `band.bottom` (tens of studs spike) — writeSquish now skips bands that
  don't own the surface (`pe.y <= bottom + EPS`).
- A throw inside the yielding rebuild left `rebuilding=true` forever
  (frozen renderer, silent) — OnSnapshot pcalls the rebuild + warns.
- Snapshot arriving during the yielding pool build was later overwritten
  by the FIRST handler's stale meta — supersede guard on `cakeIndex`.
- Crater-rim normals of UNMOVED neighbor vertices went stale (lighting
  seam) — normal-only refresh ring after the ooze loop.
- Squish offsets written into meshes without touching `pe.y` could bake a
  dent across a rebuild — force-restore dented verts before clearing.
- CakeFeelSubsClient: HumanoidRootPart now wait-or-warn (was silent-dead
  feel for a life, R8) + stale-hook bailout after yields on fast respawn.
- Double first-landing crack (two Landed handlers) — consolidated.

## Studio verification (live playtest)
Boot: `slab pool: 6/6 FixedSize meshes (2371 verts each) in 442 ms`,
`bands rebuilt — 6 slabs (6 layers) in 520 ms`, zero new warns. Visual:
6 slabs with own materials (Glass jelly T=0.45 — layer below visible
through it), crust stripes on the skirt. Landing from 25 studs drew a
branching crack star in the crust texture (butter reference matched).
12 live `EatAt` bites → crater with crust→body repaint at the rim, belly
filled. Fallback columns invisible, collision matched visuals. NOT
exercised live: sponge bounce/jump mult on a real mid-layer surface
(needs eating 7+ studs down), single-mesh + keycap tiers (need real
budget exhaustion) — logic-reviewed only.

## Iteration 2 (same day, user screenshots: corners, side-eating, cracks)
Three visual defects reported and fixed, all live-verified:
1. **Accordion corners** — the discrete footprint staircase pleated the
   skirt at rounded corners. Fix: ring + partial-boundary vertices are
   projected horizontally onto the ANALYTIC rounded rect expanded by half
   a cell (straight edges land exactly on the collision boundary, arcs go
   smooth, the outer ring collapses into degenerate slivers). Render-only.
2. **Curtains through lower layers on side cuts** — eaten-through slabs
   dropped to y=0, hanging tall transition quads through the exposed
   cliff. PROBED FIRST: neither per-vertex color alpha (AddColor/
   SetFaceColors) nor EditableImage texture alpha RENDER on MeshParts —
   both display fully opaque, so alpha-hiding is impossible. Fix: the
   **drape-under-cover rule** — eaten-through sheets tuck
   `render.hideSink` (2.0 + 0.05/band) studs UNDER the local surface;
   under a TRANSLUCENT owner (jelly) they tuck below the owner's BOTTOM so
   the see-through volume stays clean. hideSink must exceed max squish
   dent (0.7×1.6) + crack sink cap (0.5) + wobble (0.18).
3. **Pixelated 2D cracks** — texture 256→384 (4 px/stud), beveled stroke
   (light rim + 2px dark core), and REAL 3D breakage: `crackSink` — a
   permanent per-vertex subsidence (land 0.16-0.3, step 0.05-0.1, falloff
   radius 1.9, cap 0.5) applied where the band owns the surface; cleared
   per cell when its crust plate is eaten through, and cleared BEFORE the
   rebuild's two-pass (stale dents must not bake into a new cake).

## Gotchas for future sessions
- NEVER keep dynamic EditableMeshes alive — build → FixedSize-clone →
  destroy. Budget failures return nil, not throws: pcall alone is NOT a
  check (this exact silent path existed in the old crust-image code).
- FixedSize enforcement is runtime-only: AddVertex on a fixed mesh does
  NOT error in Edit mode — don't "verify" it there.
- Rojo may briefly duplicate a newly created script in Studio (two
  identical instances); bootstrap is immune (name-keyed) but play-mode
  requires killing the stale twin if sources diverge.

## Files
`src/client/modules/CakeRenderer.lua` (rewrite),
`src/client/subscriptions/CakeFeelSubsClient.lua` (new),
`src/client/subscriptions/CakeSubsClient.lua` (ceremony removed, step
cracks, supersede guard), `src/shared/config/CakeConfig.lua` (feel key,
Glass, thickness), `src/server/services/CakeCycleService.lua` (comment).

## Related
- Feature: `docs/features/cake-sim.md` (rewritten Client section)
- Prior flow: `2026-07-17_cake-grounding-fixes.md`, `2026-07-16_eat-the-cake-v1.md`
- Upstream: QUEUE rows (FixedSize pattern, nil-return gotcha, feel subs)
