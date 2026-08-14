# ADR-0022 — Global leaderboards run on OrderedDataStore, beside the profile

Date: 2026-08-14
Status: accepted

## Context

The lobby hub has three authored screens (`TopGems`, `TopSpeedrunners`,
`TopCakeCount`) that must rank players **across every server and every
session**. Ranking is inherently cross-session: nothing in a running server
knows what the other servers' players have earned.

`ProfileStore` cannot answer this. A profile is session-locked to one player on
one server: reading someone else's profile to compare scores is exactly the
thing session locking exists to prevent, and there is no "sort all profiles"
operation at any price.

Roblox offers one primitive for this — `OrderedDataStore` — and using it means
calling `DataStoreService` directly, which **P5 forbids**.

## Decision

Add ONE service, `GlobalLeaderboardService`, that owns every direct
`DataStoreService` call for leaderboards, and treat its stores as a
**projection**, never as storage:

- The **profile stays the source of truth**. `progress.lifetimeGems`,
  `progress.cakesEaten` and `progress.bestCakeMillis` are written by the normal
  gameplay paths through `ProgressService`; the ordered stores are written
  *from* those values and are never read back into a profile.
- One store per board, keyed by `userId`, value = that one number.
  Name: `EatACakeTop_<board id>_v<store-version>`.
- Publishing is **idempotent**: it writes what the profile already says, so a
  repeat costs a duplicate write and nothing else. In particular a
  "best of" stat like the speedrun time can never be made worse by a late or
  out-of-order publish, because the minimum is computed in the profile.
- Losing the stores loses a board's history, not a save. Bumping
  `store-version` is the deliberate way to wipe one (an OrderedDataStore has no
  bulk delete).

P5 is amended to name this carve-out. Its rule is unchanged in substance: no
profile data is read or written outside the ProfileStore session, there is no
second copy of anything authoritative, and no other module may call
`DataStoreService`.

## Consequences

- A leaderboard number must be a **non-negative integer** and its **units are
  part of the store contract**. That is why the speedrun time is stored as
  `bestCakeMillis` in the profile too — the profile and the store must not
  disagree about what "1297000" means. Changing units means bumping
  `store-version`, otherwise old rows outrank new ones forever.
- **Zero is not a score.** Every player who has never finished a cake has a 0,
  and on the ascending speedrun board a 0 would take first place. `Publish`
  drops non-positive values instead of writing them, so "no score yet" is
  represented by the ABSENCE of a row.
- Leaderboard writes are on a **separate budget** from profile saves
  (`SetAsync`: 60 + 10/player per minute; `GetSortedAsync`: 5 + 2/player), and
  the shipped cadence (a write per changed player per 120 s, three reads per
  60 s) sits far inside both. A throttled call degrades to a stale board, never
  to a lost profile — the two systems cannot starve each other.
- Publishing deliberately does **not** happen on `PlayerRemoving`.
  `PlayerLifecycleSubs` unloads the profile there, and the order of two
  handlers on one event is not a contract. The next profile LOAD publishes
  instead, which covers the same player with no race.

## Alternatives rejected

- **MemoryStore sorted map** — the right tool for a live/hourly board, the
  wrong one for an all-time board: entries expire (45 days max) and the data is
  explicitly not durable.
- **A normal DataStore holding one big sorted table** — one key becomes a write
  hotspot for the whole universe, and `UpdateAsync` contention makes it lossy
  exactly when the game is popular.
- **Reading other players' profiles to rank them** — breaks session locking
  (P5's actual subject) and does not scale past the players on this server.

See `docs/features/leaderboards.md` for the feature, its authored GUI contract
and its tuning.
