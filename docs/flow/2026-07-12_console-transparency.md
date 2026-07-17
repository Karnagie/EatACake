# 2026-07-12: Console transparency (Log layer, rule R8)

## Task
User ran the empty template and the console showed almost nothing — if
something silently fails in a real project, nobody notices. Requirement:
the console must show what loaded, what subscribed, what was skipped and why.
Not only subscriptions — everything.

## Context
Silent paths existed in: bootstrap (missing folder → silent empty table,
module without Start → silently never runs), PersistenceService (no
DataStore access → game runs, nothing persists, zero output), ProfileSchema
(sections registered invisibly), feature subs (SendX early-returns),
RewardsSubsClient (missing GUI → silent return).

## Changes

**Created:**
- `src/shared/Log.lua` — `Info` (verbose-gated), `Sum` (always), `Warn`
  (always), `Once` (warn once per key); `[Server/Scope]` / `[Client/Scope]`
  greppable prefixes; `Log.verbose` toggle (true by default).

**Modified:**
- Both bootstraps — per-folder module lists, per-module Init/Start ok/FAILED,
  missing/empty folder warns, subscription without Start warns ("will NEVER
  run"), final summary with counts; client logs ClientReady send/failure.
- `ProfileSchema/init.lua` — logs every registered section (key + version),
  skipped templates, invalid/duplicate sections; summary line; warns when
  zero sections.
- `PersistenceService` — boot report of resolved `ProfileStore.DataStoreState`
  (loud warn on NO ACCESS: "profiles will NOT persist" + how to fix), mock
  mode warn, per-profile load Info (isNew, session #), migration applied
  Info, all failure paths through Log.Warn.
- `PlayerLifecycleSubs` — initial-state push Info, client-ready-before-profile
  Info.
- `EconomySubs`/`RewardsSubs` — dropped pushes warn instead of silent return.
- `RewardsSubsClient` — missing GUI / missing nodes warn ONCE with a pointer
  to the GUI contract doc; wired-buttons count Info; node without ClaimButton
  warns; ResetOnSpawn=true warns.
- `CLAUDE.md` — new rule **R8: Console Transparency — a silent failure is a
  bug** (all output through Log, every failure early-return logs why).

## Decisions
- One shared Log module instead of raw print/warn: greppable prefixes, one
  verbosity switch for release, `Once` primitive for repeated checks.
- `Log.verbose` lives as a constant in Log.lua (not a data module): Log is
  pre-bootstrap infrastructure like Net, needed before data modules load.
- Info vs Warn line: expected lifecycle = Info (can be muted); anything a
  developer must act on = Warn (never muted).

## Post-playtest fix (same day)
Live run showed a FALSE-POSITIVE warn: the first `DailyRewardUpdate` lands
before StarterGui is cloned into PlayerGui (character not spawned), so
"'DailyRewardsGui' not found" fired, then the GUI appeared 0.3s later.
Added `Log.GraceOnce(scope, key, seconds, stillBroken, message)` — a
non-blocking deferred re-check (task.delay, no yields in caller flow, calls
coalesced per key) that warns only if the dependency is still missing after
the grace period (10s for the GUI). Deliberately NOT a blocking
WaitForChild-with-timeout: on slow connections that would stall the feature.
The immediate "exists but has NO Node_<n>" warn stays — a StarterGui clone
arrives atomically with children, so that one can't false-positive.
R8 updated with the late-dependency rule.

## Open Questions / Followups
- When telemetry lands, mirror Log.Warn into an analytics event
  (persistence_error style) for prod visibility.
- Consider a `/verify-console` checklist in docs/recipes (what a healthy
  boot log looks like).

## Related
- Feature: `docs/features/persistence.md`, `docs/features/daily-rewards.md`
- Rule: CLAUDE.md R8
- Prior flow: `docs/flow/2026-07-12_daily-rewards-economy.md`
