# ADR-0003: Granular heightfield for the destructible cake

## Status
Accepted (2026-07-16)

## Context
"Eat the Cake" needs a giant destructible cake that slumps like sand, runs
at 30+ FPS on mid-range mobile with 20 players, and syncs one shared state
per server (GDD §4). Candidates: voxels + marching cubes, Roblox Terrain,
thousands of Parts, or a 2D heightfield.

## Decision
A 64×64 u16 heightfield (`buffer`, 1 unit = 0.01 studs) with an
angle-of-repose cellular automaton (budget 1500 cells/tick @ 20 Hz).
Because the cake ALWAYS slumps, overhangs/caves cannot exist, so h(x,z)
fully describes the surface — voxels are strictly redundant. Volume is
transferred between cells, never created: the calorie economy stays honest.

Supporting choices:
- **Rendering**: one EditableMesh (65×65 verts, 1 draw call), per-vertex
  palette colors, client display-height lerp; part-grid fallback behind the
  same renderer interface (EditableMesh availability is device-dependent).
  MeshPart is created at max height so fixed render bounds cover every
  future height.
- **Networking**: server-authoritative; 12 Hz cell deltas over an
  UnreliableRemoteEvent (4 B/cell, ≤2 KB) + a rotating 64-cell repair
  cursor that self-heals packet loss; full buffer snapshot on join/new cake.
  Client predicts its own bite with the SAME shared math (`CakeOps`), so
  reconcile is a plain overwrite.
- **Collision**: 8×8 invisible parts @ 5 Hz (surface is near-flat by
  construction) — never generated from the mesh.

## Consequences
- Shaft-digging impossible; avalanches propagate as budget-bounded waves.
- Chocolate "solid" layers don't flow (repose = huge) — the GDD's
  shatter-to-crumb conversion is approximated by hardness + client FX.
- Grid resolution is fixed; cake size scales via footprint radius, not grid.
- All tuning in `Shared/config/CakeConfig`; sim/net budgets are config, per
  GDD §14 the budget (not the grid) is what gets cut under load.
