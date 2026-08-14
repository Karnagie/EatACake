# 2026-08-11: Playable rainbow cake

Tags: cake-select, cake-cycle, cake-sim, treasures, game-round, lobby-matchmaking, map, balance, localization, tooling

## Task
Add a rainbow pyramid cake with grouped colour layers, 1.5× size/duration,
soft or jelly material, no wax/crust, `Assets.Environment1`, first-clear unlock,
and 1.5× gem finds.

## Context
The lobby catalogue, persistence, first-clear unlock and cake UI already existed,
but the selected id stopped at the lobby and every game round built classic. The
heightfield and wrapper assumed one full footprint for every band.

## Plan
Carry the leader's authoritative selection through the match handoff, introduce
data-driven playable variants, add per-band terrace masks to the existing field,
and calibrate total duration with the ramped progression model before live QA.

## Changes

**Created:**
- `tools/headless-sim/cake_variant_scenario.lua` — variant, terrace, coating and reward invariants.
- `tools/headless-sim/round_cake_scenario.lua` — lobby selection/teleport/round validation contract.
- `docs/decisions/0020-bounded-selectable-cake-variants.md` — size, duration and protocol decision.

**Modified:**
- `CakeConfig` / `CakeLayersConfig` — classic/rainbow runtime variants and six fixed soft colour groups.
- Lobby launch + `GameRoundService` / `RoundStateData` — protocol-v2 `cakeId`, leader ownership and validation.
- `CakeCycleService` / `CakeFieldService` / `TreasureService` — height/duration/reward multipliers and per-band footprints.
- `MapService` — stable map container and authored environment swap.
- `CakeRenderer`, `CakeWaxShell`, `CakeWrapper`, `CakeFeelSubsClient` — variant-gated squish multiplier, optional coating/crust and terrace rendering.
- Headless/balance tooling — fixed-mask simulations and classic-vs-rainbow duration report.

## Decisions
The 1.5× physical scale is height (170→255), not diameter: the classic already
nearly fills the 64-cell field and both authored rooms use the same 100×88 plate.
Rainbow keeps the classic base but grows through six radius masks. A measured
1.79× bite-work factor produces 1.4980× total time because gym time is fixed.
The opaque, heavily squishing material option was chosen over translucent jelly.
See ADR-0020.

## Verification
- Every source module compiled; `default`, `game` and `lobby` Rojo builds passed.
- Headless contracts passed: selectable variant 67/67, round handoff 14/14,
  paid LayerEater 19/19, and treasure easy/hard/fallback all collected 40/40.
- Five-seed ramped balance model stayed config-synchronised and measured
  52.21 vs 34.86 minutes = 1.4980×.
- Whole-feature adversarial review found no critical issue. Its classic-feel
  warning produced the variant-level squish opt-in; the established grouped
  classic wrapper was confirmed to create no equal-footprint terrace caps.
- Studio Edit-mode preflight confirmed the authored `Environment1` has 436
  BaseParts and no collider intersecting the cake at Y=152..260. Play mode
  itself could not start (`Start play hasn't finished yet`), so live render,
  deformation, transition and R8-console checks remain blocked rather than failed.

## Open Questions / Followups
- Push the six new `zone-rainbow-*` rows to the cloud localization table as part
  of release operations; English fallback is already safe locally.
- Protocol v2 requires a coordinated lobby/game publish rather than a rolling
  v1-lobby→v2-game deployment.
- Retry the live Studio checklist when the connected session can enter Play mode.

## Related
- Features: `docs/features/cake-select.md`, `cake-cycle.md`, `cake-sim.md`, `treasures.md`, `game-round.md`, `lobby-matchmaking.md`
- ADRs touched: ADR-0007, ADR-0011, ADR-0020
- Prior flow: `docs/flow/2026-08-11_cake-selection-ui.md`
