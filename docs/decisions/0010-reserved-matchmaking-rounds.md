# ADR-0010 — Reserved matchmaking and finite game rounds

Status: **Accepted**. Date: 2026-07-22. Supersedes ADR-0009 Decision 1's
shared-public/no-matchmaking game-server choice; retains ADR-0009's partition and
ProfileStore handoff decisions.

## Context

Lobby pads must form parties of 1–4, choose a difficulty, launch together after
30 seconds, play one win/loss cake, and return together. A public endless game
server cannot guarantee roster isolation, fixed difficulty/population, or a
terminal return.

## Decision

1. Each lobby pad is an independent server-authoritative queue. The first
   admitted player owns a rotating session key and may configure mode/cap;
   overlap reconciliation, not client claims, owns membership.
2. Countdown expiry snapshots the current roster and makes one
   `TeleportAsync` call with `ShouldReserveServer=true`. Teleport data contains
   only protocol/round/difficulty/fixed-roster metadata, never profile or reward
   authority.
3. The reserved server accepts exactly one validated roster. It starts when all
   members arrive or after a bounded arrival window, while retaining the launch
   count for cake/boss scaling if members are missing or leave.
4. The cake cycle is finite in match mode: boss defeat = win/reward; boss timeout
   = loss/no reward. Either terminal state sends present roster members to the
   public lobby with bounded recovery/retry.
5. ADR-0009's single-session handoff remains mandatory. Safe release means a
   read-back sees both the exact per-handoff nonce and a cleared persisted
   ProfileStore session. Async teleport retries reuse Roblox's returned
   `TeleportOptions` so a partially failed party retains its reserved target.

## Consequences

- Parties cannot mix with other pads/rounds; difficulty and scale are stable.
- Departures do not make the boss cheaper after launch.
- Queue remotes are leader/session/rate validated; destination and roster remain
  server-owned.
- Cross-place teleport and shared-lock behavior still require published-place
  verification; Studio can verify queue/UI/round logic but cannot complete the
  live hop reliably.

Feature contracts: `docs/features/lobby-matchmaking.md`,
`docs/features/game-round.md`. Persistence contract:
`docs/features/persistence.md`.
