# ADR-0004: Shared game config lives in src/shared/config/

## Status
Accepted (2026-07-16)

## Context
Cake layers, upgrades, pets, treasures, body morph and juice tuning are
needed by BOTH sides: the server simulates/validates with them, the client
predicts/renders/displays with them (colors, odds text, formulas for
predicted bites). R1 says config lives in data modules; duplicating tables
per side would drift, and replicating them over remotes is wasteful.

## Decision
Pure-data config modules live in `src/shared/config/*.lua` (CakeConfig,
UpgradeConfig, BodyConfig, PetConfig, TreasureConfig, JuiceConfig — no
logic, no Instances beyond Color3/ColorSequence values). Rules:
- **Server**: services still receive config through data modules —
  `CakeConfigData` re-exports the shared configs (R1/R2 intact) and owns
  server-only tuning (anti-cheat caps).
- **Client**: modules require `Shared/config/*` directly — same precedent
  as `UIKit.Theme` (shared style infra).
- Formulas are interpreted in exactly TWO places: `StatsService` (server,
  authoritative) and `LocalStatsService` (client mirror, prediction only,
  never trusted).

## Consequences
One tuning point per number (GDD requirement "all numbers in config
modules"); client and server can never disagree on geometry/odds/formulas;
the server data-module discipline stays enforceable in reviews.
