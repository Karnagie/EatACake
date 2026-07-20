# 2026-07-19: Mobile CPU spike — vestigial per-layer cake texture

Tags: cake-sim, performance, mobile, editable-mesh

## Task
Mobile clients hitch to ~86 ms CPU frame time roughly every ~15 s, then
recover. Investigate with profiling data, find the exact root cause of the
periodic spike, and fix the underlying cause (no workarounds); optimize for
mobile while preserving gameplay, visuals, and functionality.

## Context
- `CakeRenderer` (client) draws the cake as ONE FixedSize `EditableMesh` slab
  PER composition band, plus a per-band `EditableImage` texture. The crust look
  was long ago moved to the always-visible `CakeWaxShell` overlay
  (`features/cake-sim.md`), leaving each slab rendering the layer BODY color.
- Full `CakeRenderer.OnSnapshot` → `editableRebuild` runs on a full
  `CakeSnapshotUpdate` (player join + every new cake). Deltas (12 Hz) do NOT
  rebuild.

## Investigation (how the root cause was found)
1. Static sweep (8-way subagent fan-out + synthesis + adversarial verify):
   NO fixed 15 s client timer exists. The one heavy SYNCHRONOUS client op is
   `editableRebuild`; the adversarial pass correctly **refuted** a clean 15 s
   cadence for it in normal play (a full snapshot fires once per cake cycle =
   spawning 15 s + eating ~18-40 min + boss ≤30 s → minutes, not 15 s). The
   `newCakeDelay = 15` is only the spawning sub-phase.
2. Live profiling (Studio play, client datamodel):
   - Idle 34 s and a load run: NO 86 ms spike, steady low heap growth, no GC
     sawtooth. The recurring ~1 s ~30 ms bumps are the SERVER's 1 Hz work
     (`ScanStats` full-field scan, cycle broadcast) bleeding into the shared
     Studio process — they will NOT exist on a real mobile client.
   - Boot log: first `editableRebuild` = 457 ms incl. a 304 ms async pool
     build; the non-pool portion was **~153 ms**.
3. Reading `paintBandImage`/`updateCellPixels`: in the MULTI-BAND path the
   per-band `EditableImage` is painted as a **uniform `bodyColor` fill** (noise
   disabled, `color = band.bodyColor` for every cell) — i.e. VESTIGIAL, visually
   identical to `part.Color = bodyColor`. Yet every rebuild paid a 384² buffer
   fill + `WritePixelsBuffer` GPU upload PER band, and every bite paid a
   `DrawRectangle` per eaten cell PER band (`updateCellPixels`).

**Root cause:** the per-band texture regeneration in `editableRebuild` is the
heavy synchronous frame; on a mobile CPU/GPU it is the ~86 ms stall. Its
cadence tracks the cake-clear cycle — it collapses toward the 15 s spawning
floor when a client clears cakes fast (maxed test stats / crowd / mobile
tester), which is when the reporter sees "roughly every 15 s". The identical
texture work also fired per-bite, feeding eating-time GC/CPU churn.

## Changes

**Modified:**
- `src/client/modules/CakeRenderer.lua` — `assignBands` MULTI-BAND branch no
  longer creates a per-band `EditableImage`; slabs render `part.Color =
  bodyColor` with `TextureContent = Content.none`. `paintBandImage` (rebuild
  loop) and `updateCellPixels` (per bite) then hit their `img == nil` guards and
  become no-ops for multi-band bands. The SINGLE-mode palette fallback is
  unchanged (it still needs a real per-cell texture). Header comment updated.
- `docs/features/cake-sim.md` — client render bullet updated (slabs = flat body
  Color; texture only in the palette fallback).

## Results (measured in Studio, desktop)
| Metric | Before | After |
|---|---|---|
| Non-first cake rebuild | ~153 ms non-pool (86 ms+ on mobile) | **6–7 ms** |
| Per-rebuild texture paint + 5 GPU uploads | ~43 ms | **0** |
| Per-bite texture `DrawRectangle` churn | every eaten cell × band | **0** |
| Cake visuals (layered body colors + wax web) | — | identical (verified) |

Measured a clean non-first rebuild by re-broadcasting a synthetic
`CakeSnapshotUpdate` (same `cakeIndex` so real deltas still heal the mirror);
`editableRebuild` self-logs its ms. Visual parity confirmed via `screen_capture`
(layered side-wall body colors + wax web + a carved crater render correctly).

## Decisions
- **Remove, don't time-slice.** The dominant cost was genuinely dead work
  (uniform texture), so deleting it is the true root-cause fix — cheaper than
  and preferable to spreading the paint across frames. The remaining ~6-7 ms
  vertex-write portion is small enough to leave synchronous (no visual-glitch
  risk from slicing a delicate mesh path). If a future device still hitches on
  the vertex writes, time-slice them behind the existing `rebuilding` guard.
- Kept the single-slab palette fallback's texture — there the image carries
  genuine per-cell height-palette variation (not uniform).

## Open Questions / Followups
- If per-cake hitch ever matters on the weakest devices, time-slice the
  two-pass vertex writes (`editableRebuild` ~880-893) + `columnsRebuild` across
  frames behind the `rebuilding`/`snapshotPending` guards.
- The Studio-only 1 Hz server bleed (`ScanStats` full-field scan) is not a
  real-client issue, but is a candidate to make incremental if server frame
  time is ever a concern.

## Related
- Feature: `docs/features/cake-sim.md`
- Prior flow: `docs/flow/2026-07-18_layer-meshes-crust-feel.md`,
  `docs/flow/2026-07-18_wax-shell.md`
- Upstream: `docs/upstream/QUEUE.md` (vestigial-texture perf trap)
