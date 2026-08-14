# 2026-08-12: Studio rainbow launch override

Tags: cake-select, cake-cycle, game-round, studio, tooling

## Task
Make Studio Play launch the rainbow cake immediately instead of the classic
cake so the new variant can be tested before going through lobby progression.

## Context
Production correctly defaults a direct join to `cake-classic`, and the combined
development build had no established round `cake-id`, so both Play paths selected
`CakeConfig.defaultVariantId`. The real lobby handoff already carries an explicit,
authoritative protocol-v2 `cakeId` and must remain unchanged.

## Plan
Add one Studio-only config switch, consume it only when no explicit round cake
exists or the join has no teleport source, and cover both Play paths headlessly.

## Changes

**Created:**
- `docs/flow/2026-08-12_studio-rainbow-launch.md` — this task record.

**Modified:**
- `CakeConfig` — `studioVariantId = "cake-rainbow"`; nil restores normal testing.
- `CakeCycleService` — combined/fallback Studio launches use the validated override.
- `GameRoundService` — Studio direct joins use the same override; production and
  explicit lobby arrivals retain their existing contracts.
- Headless harness/scenarios — an `IsStudio` stub plus assertions for both paths.
- Cake selection, cycle and round docs — test-switch contract and reset instruction.

## Decisions
The production default remains `cake-classic`. The override is not a profile
write and is never inserted into real lobby TeleportData. An invalid Studio id
warns and falls back to the production default, keeping Play usable and visible
under R8.

## Verification
- `luau-compile`: all 233 source files pass.
- `rojo build`: default, GAME and LOBBY projects pass.
- Selectable-cake scenario: 71/71, including valid, invalid, nil-reset and
  malformed combined-Studio fallback paths.
- Round handoff scenario: 18/18, including Studio direct join, explicit lobby
  precedence and invalid-override fallback.
- Adversarial review: clean, with no CRITICAL or WARN findings.
- Live GAME-place Play was blocked by a stale Rojo session: Studio's synced
  `CakeConfig` did not yet contain `studioVariantId`, so it correctly exercised
  the older classic path. Bootstrap/persistence remained healthy with no errors.
  Reconnect Rojo and Sync All before the visual rainbow pass.

## Open Questions / Followups
- Set `CakeConfig.studioVariantId = nil` after rainbow-focused QA when ordinary
  classic direct/fallback Play should be the default again.

## Related
- Features: `docs/features/cake-select.md`, `cake-cycle.md`, `game-round.md`
- ADR touched: ADR-0020
- Prior flow: `docs/flow/2026-08-11_rainbow-cake.md`
