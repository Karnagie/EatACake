# 2026-07-22: Eat beneath the player + cleaner eaten crater (no wax flaps)

Tags: cake-sim, config, rendering, gameplay

## Task
Follow-up to `2026-07-22_wax-holes-remnant-sweep-treadmill.md` (user screenshot):
1. Eating should affect the area in front of the player AND directly BENEATH them
   (the front-only bite left a pillar under their feet).
2. Small pieces still remain in the eaten middle — it should be COMPLETELY eaten.

## Context
- The old thin-remnant sweep only caught isolated spikes / 1-cell walls; it left
  the ragged partially-eaten RIM around a crater.
- Studio diagnosis (toggling `workspace.CakeWaxShell.Transparency`): the ragged
  white bits at the crater rim were the WAX SHELL draping over the edge, not field
  remnants — the field/frosting-slab crater was already clean.

## Changes
- **(1) Eat beneath** — `CakeSubs` EatAt handler applies a SECOND `ApplyBite` at the
  player's own XZ (`root.Position`) in addition to the sent front point (both share
  `biteRadius`/`biteDepth`). The beneath bite is GEOMETRY ONLY, not paid as
  calories (adversarial-reviewer: avoids a double-income exploit — the token bucket
  assumes one token = one paid bite). Server-chosen point,
  so no reach/surface anti-cheat. When moving forward the beneath bite usually hits
  already-cleared cake (removed 0), so it only adds volume when stationary.
- **(2a) Eaten-zone cleanup sweep** — `CakeConfig.sim.remnantSweep` reworked
  (`clearedMarginStuds`, `eatenEpsilonStuds`, `minClearedNeighbors`) +
  `CakeFieldService.ScanStats`: snaps any active-band cell TOUCHING a crater (a
  neighbour near the active floor) to the floor when it is EATEN-INTO (bitten >
  eatenEpsilon below its band top) OR an isolated pillar/1-cell wall. Full cells
  with a crater on only ONE side are LEFT (clean cut edge preserved); the loaf
  perimeter is SUPPORT. Cleans the ragged rim + interior crumbs.
- **(2b) Wax recedes from craters** — `CakeWaxShell`: a piece now hides when its
  AREA straddles a crater, tested by sampling the surface at each fan-TRIANGLE
  centre (precomputed `c.tc` = (centroid + two adjacent boundary verts)/3). The
  earlier vertex-only min missed pieces whose VERTS sit on the rim while the piece
  spans the hole (a flat wax SHELF / flap). Now the wax recedes cleanly.

## Decisions
- **Sample the piece AREA, not its vertices.** A draping triangle needs a low
  vertex (caught by vertex-min), but a FLAT wax shelf over a crater has all verts on
  the rim — only an interior/triangle-centre sample catches it. Fan-triangle centres
  are precomputed once (cheap per-frame reads; mesh writes still dirty-skip when
  resting, so the perf guard holds).
- **Eat-beneath is self-limiting**: forward motion hits already-cleared cake, so it
  rarely doubles volume; it mainly matters when standing still (clears under you).

## Verification (Studio, live)
Synced via the local-HTTP push (Rojo plugin still disconnected). Boot clean (0
errors). Ate a cluster: belly rose; the player SANK into the crater (beneath bite
works); top-down capture shows the middle eaten to the next layer with the wax
receding into a clean funnel — the draping flaps are gone (vs. the vertex-only
version, which still showed shelves). Toggling the wax off confirmed the field
crater itself is clean.

## Open Questions / Followups
- A thin ring of wax funnel-wall remains at the very rim (the natural frosting→hole
  transition) — clean, not a "small piece". Tune `hideDepth` if more recession is
  wanted.
- Eat-beneath volume/pace is a feel value (usually near-zero extra when moving).
- The eaten-zone sweep forfeits volume (documented in cake-sim.md gotcha).

## Related
- Feature: `docs/features/cake-sim.md`
- Prior flow: `2026-07-22_wax-holes-remnant-sweep-treadmill.md`
