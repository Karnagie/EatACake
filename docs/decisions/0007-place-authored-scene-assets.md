# ADR-0007: Static scene = place-authored editable `ReplicatedStorage.Assets`, cloned at runtime

## Status
Accepted (2026-07-20)

## Context
The whole static scene (candy room: floor, studded walls + candy props, cake
tray, ceiling, candle landmarks) and the **checkpoint platform** (gym machine +
upgrade "computer" station) were procedurally `Instance.new()`-built in
`MapService.Build` (~500 lines). The models look poor and could not be
hand-edited. The user wants every static asset stored in `ReplicatedStorage` as
an editable model that code **clones** (R5), so they can replace/improve each one
in Studio.

The cake heightfield and its collision columns are live simulation (not art) and
stay procedural — this ADR covers only the STATIC scene.

## Decision
The static scene lives as two **place-authored** models under
`ReplicatedStorage.Assets`:
- `Environment` — the whole static room, parts at world positions (relative to
  `grid.origin`).
- `Checkpoint` — the checkpoint parts, resolved by NAME.

`MapService.Build` **clones** these into `workspace.Map` / `Map.Checkpoint` and
resolves the named parts; it never builds geometry procedurally at the runtime
path. `SetCheckpointHeight` still positions the NAMED checkpoint parts (the
platform is dynamic — it tracks the top cake layer), so authored checkpoint parts
must keep the names.

**Place-authored, not Rojo-synced.** The assets live in the `.rbxl` place, edited
in Studio; the user SAVES the place to keep changes. (Chosen over an
`Assets.rbxmx` synced into the Rojo tree — the user preferred editing directly in
Studio.) Code is Rojo-synced and resolves the assets by name.

**Self-heal generator.** `MapService.GenerateAssets()` GENERATES the default look
(the old geometry, kept ONLY as a seed) into `ReplicatedStorage.Assets` for any
missing template. `Build` calls it, so a fresh repo clone with no authored assets
still boots a working scene — but a runtime-generated model does NOT persist;
author + save to keep edits. Every missing/failed resolve warns (R8) + degrades.

**Biome recolor is opt-in.** `ApplyBiome` recolours only parts carrying a
`BiomeRole` attribute (floor/conveyor/platform/ceiling/wall/accentWall/beam — the
generated defaults set it). A part the user re-authored without the attribute
keeps its own colour. So the per-biome room skin (gameplay) survives while the
user keeps full colour control.

## Consequences
- The user can replace any static model in Studio; the clone reflects it
  (geometry, material, non-recoloured properties). The checkpoint is dynamic:
  edit part LOOKS, keep the NAMES (single BaseParts resolved + positioned by
  code).
- Assets are not in git (place-authored) — a fresh clone self-heals to the
  default look until the user authors + saves.
- The named/attribute contract is the interface (checkpoint part names; the
  `BiomeRole` attribute). Documented in the `MapService` header +
  `features/checkpoint.md`.

## Alternatives rejected
- **`Assets.rbxmx` synced by Rojo** (like `ReactLua-Packages.rbxmx`) — in git,
  but the user preferred editing in Studio directly (place-authored) over the
  export-rbxmx round-trip.
- **Keep procedural build** — the whole point was to make the models editable.
- **Hard-fail if Assets missing** — the self-heal generator is more robust
  (graceful degradation, R8).
