# ADR-0008: Render only the current + next cake layer; hide the bulk behind a textured wrapper

## Status
Accepted (2026-07-20)

## Context
The cake is one 64×64 heightfield with a bottom-up `composition` of bands
(ADR-0003). `CakeRenderer` built ONE FixedSize EditableMesh slab PER band and
drew the sides via per-band ring skirts. A DYNAMIC EditableMesh reserves
worst-case budget (~8 slabs fit a desktop client, fewer on laptops —
`2026-07-18_layer-meshes-crust-feel.md`), so the band count was hard-capped: a
composition past `MAX_LAYER_MESHES` dropped to the single-palette fallback.

The cake was made ~3× taller with ~10–14 layers (2026-07-20). Building a slab per
band does not scale to that. But the **layer gate** (ADR-follow-on,
`2026-07-19_layer-gate.md`) already forbids digging below the active band's
floor — so at any moment the player can only ever SEE the active band and the
one directly below it (through holes). Every layer below that is occluded.

## Decision
Render the **active band + the one directly below it** as 2 slabs
(`assignWindowBands`/`windowFor`) — both the current AND next layer are visible
(the next shows through craters cleared to the active floor; the lower windowed
band is forced OPAQUE so a translucent one can't reveal the hollow). The window
slides DOWN each time the layer gate advances (`rewindow`, driven by
`LocalCakeField.ActiveBandIndex()` polled in `editableStep`; no mesh creation,
reuses the pooled slabs). The cake below the NEXT band is hidden by a client
module **`CakeWrapper`** — a plain textured **Part (Block)**, sized to the loaf,
standing from the base up to the next band's bottom and shrinking as layers
finish, top-capped so a crater cleared to the floor shows cake not a void. It
wears a random cake photo per cake as tiling `Texture` instances.

(Iterated 2026-07-20: initial = 2 slabs + an EditableMesh wall; then 1 slab + a
Part wall (user: "the wall covers everything except the top layer"; the mesh
wall's URI texture didn't display, so → a Part with reliable tiling `Texture`s);
then back to 2 slabs (user: "the next layer should also be visible") keeping the
Part wall. The Block trades exact rounded corners (~6-stud corner poke) for
reliability + performance.)

The **simulation is unchanged** — the heightfield keeps full data for every band;
only the render is windowed. `MAX_LAYER_MESHES` stays as a safety cap (the pool
now only ever grows to 2).

## Consequences
- **Layer count is decoupled from the mesh budget** — arbitrarily many/taller
  layers render at a fixed 2-slab cost. This is what makes the 3× cake viable.
- Image textures on layers become affordable again (only 2 slabs, a static
  `TextureContent` reference — not the per-cell `EditableImage` paint that was a
  mobile trap, `2026-07-19_cake-rebuild-mobile-spike.md`).
- Correctness rests on the layer gate: if it were disabled (`layerGate.enabled =
  false`, free-dig), a bite could cut past the next band and expose the wrapper /
  void. The window render assumes the gate is ON.
- `CakeWrapper` reads `LocalCakeField` directly (like `CakeWaxShell`) — no
  renderer↔wrapper coupling; both are driven from `CakeSubsClient`.
- Fallbacks unchanged: single-palette mode (1 slab, whole cake — occludes the
  wrapper) and the parts keycap grid still cover the full cake.

## Alternatives rejected
- **Keep a slab per band, raise `MAX_LAYER_MESHES`** — blows the EditableMesh
  budget on weak devices (the exact failure the FixedSize-pool work fought).
- **A single tall textured prism for the whole cake** — can't show the deforming
  top surface / craters the game is built on.
- **Wrapper as a 3rd "bulk" slab reusing the slab machinery** — the slabs' planar
  XZ UVs smear a texture on vertical side faces; a dedicated wall mesh with
  wall-appropriate UVs is needed.
