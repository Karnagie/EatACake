# 2026-08-12: Rainbow cake visual correction

Tags: cake-cycle, cake-sim, checkpoint, render, balance, localization, tooling

## Task
Correct screenshot-reported rainbow defects: smooth the jagged top perimeter,
remove upper-layer triangles bleeding into lower terraces, include every rainbow
colour, make the silhouette shorter/wider, and keep the checkpoint reachable
beside every active layer.

## Context
The first playable rainbow implementation (see
`2026-08-11_rainbow-cake.md`) already owned selection, Environment1, soft
material, coating suppression and 1.5× find payout/duration. Its field and
wrapper had per-band footprints, but `CakeRenderer` still sampled/projected one
maximum footprint. The checkpoint likewise stayed beside that maximum edge.

## Plan
Fix the renderer contract rather than hiding the spikes with tuning, rebalance
the silhouette as seven ROYGBIV terraces, preserve measured progression and five
available mini-boss rigs, and connect the fixed supported checkpoint to the
active terrace with a dynamically sized cloned bridge.

## Changes

**Created:**
- `docs/decisions/0021-footprint-aware-rainbow-terraces.md` — superseding
  silhouette, renderer, gate and checkpoint-reach decisions.

**Modified:**
- `CakeRenderer` — per-footprint vertex masks, analytic rims and isolated
  target/display/ooze states; XZ rewrites on pooled radius changes; honest
  visible-column fallback when one slab cannot represent several terraces.
- `CakeLayersConfig`, `CakeConfig`, `LocaleData` — seven ROYGBIV materials;
  204-stud height; wider `.72→1` masks; balanced `7/5/4/4/3/3/3` run; indigo
  and violet keys; calibrated work 1.75.
- `CakeCycleService`, `CakeSimulationSubs`, `CakeStateData` — visual boundaries
  decoupled from five sequential boss gates; every same-scan crossed gate queues
  FIFO before the Guardian; authoritative post-scan band drives checkpoint top
  + footprint; Studio layer skips suppress find/profile writes.
- `MapService`, `MapConfigData`, `CakeCycleSubs` — pooled `CheckpointBridge`
  cloned from authored checkpoint geometry; fixed main supports; active-edge
  span based on the actual authored plate size.
- `cake_variant_scenario.lua`, `pacing.py` — seven-zone/gate/shape assertions and
  exact live-config pacing mirror.
- Routed feature docs, MAP and locale registry — revised contracts.

## Decisions
- The newer “shorter and wider” correction supersedes the earlier 255-stud
  physical-size interpretation. Within the fixed 64-cell field, a shorter
  stepped cake cannot honestly remain 1.5× classic physical size. Duration and
  find gems remain independently and measurably 1.5×.
- The checkpoint platform does not move inward: its legs would become hidden
  colliders inside wider lower terraces. Only a narrow bridge follows the edge.
- Indigo→violet is visual-only. Five authored rigs remain five gates, and gate
  HP growth uses a sequential gate index rather than the seven-colour index.

## Verification
- 233/233 Luau source files compile.
- Default, GAME and LOBBY Rojo builds pass.
- Real-module headless checks pass: cake variant 143/143, round handoff 18/18,
  paid LayerEater 19/19; analytics catalogue cross-check passes.
- Five-seed progression model is config-synchronised and measures 52.09 vs
  34.86 minutes = 1.4943× (acceptance 1.45–1.55×).
- Renderer geometry audit checked 3,064 mask-crossing topology edges across all
  seven radii; no large-height edge retained an unprojected endpoint.
- Live Studio exact-sync/R8 verification passed: seven clean terraces, no wax or
  cross-colour spikes, stable soft deformation, and a red→orange clear moved the
  bridge from X `34.088` to `35.954` on the same scan while gate #1 spawned.
- Adversarial review found and closed five WARNs: multi-zone gate skipping,
  authored plate-size drift, off-centre authored pivots, low-budget squish
  mismatch, and stale fallback dents surviving a full snapshot rebuild. Focused
  re-review is recorded in the final task handoff.

## Open Questions / Followups
- Push the seven `zone-rainbow-*` locale rows during release operations; English
  fallback is safe locally. The prior six rows were never published.
- The first live `DebugClearLayer` run predated its new reward-suppression latch
  and visibly changed the Studio test profile by +87 gems; audit that account
  through the normal profile-session path rather than a direct DataStore edit.
- Coordinated protocol-v2 lobby/game publication remains an ADR-0020 release
  constraint unrelated to this visual correction.

## Related
- Features: `docs/features/cake-cycle.md`, `cake-sim.md`, `checkpoint.md`
- ADRs: ADR-0020, ADR-0021
- Prior flow: `docs/flow/2026-08-11_rainbow-cake.md`
