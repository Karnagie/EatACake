# ADR-0009 — Two-place lobby/game split (one universe)

Status: **Accepted** (Decision 1 superseded by ADR-0010 reserved matchmaking).
Date: 2026-07-22. Related: ADR-0001 (persistence), ADR-0007 (place-authored
scene assets), ADR-0002 (reward grants), ADR-0010 (finite reserved rounds).

## Context

The game was one place. We split it into two (Drain-the-Lake style): a **LOBBY**
(hub + shop + meta/progression) and a **GAME** (cake + core gameplay). The hard
constraint: a player's ProfileStore profile (currency, upgrades, pets, stomach…)
must stay correct in BOTH places, spendable in the lobby and effective in the
game. DataStores are **universe-scoped**, so both places share ONE
`PlayerProfiles`/userId session lock — that shared lock is what makes cross-place
consistency emergent instead of hand-synced.

## Decision

1. **One universe, two places.** Lobby is the start place. The original
   shared-public/no-matchmaking server choice is superseded by ADR-0010: lobby
   queues now reserve one finite game server per fixed roster.

2. **Session follows the player, "Option A" handoff** (`TeleportSubs`, common):
   source freezes input → folds playtime → `Unload(userId, true)` (final save)
   → **read-backs the exact release nonce plus a cleared persisted lock** →
   `TeleportAsync`; on failure it re-acquires the lock so the player isn't
   stranded. Destination runs the **unchanged** `LoadProfile`. **Never
   `Steal=true`** (P5) — that drops the source's final save. The
   `intentionalRelease` flag (`PlayerProfileData.releasing`, consumed in
   `PersistenceService.OnSessionEnd`) suppresses the mid-teleport `session-taken`
   kick. `TeleportInitFailed` retries Roblox's returned options so reserved-party
   members retain the same destination.

3. **Repo = partitions, not copies.** `src/{server,client}/{common,lobby,game}/…`.
   `src/shared` + `common` are **mapped** (single on-disk copy) into both places,
   never duplicated — so `ProfileSchema` and remote defs are byte-identical by
   construction. Two project files (`game.project.json`, `lobby.project.json`)
   map Common+Game / Common+Lobby; `default.project.json` stays as the **combined
   full-game build** (all partitions) for single-place dev/testing.

4. **Partition-aware bootstrap.** One `collectPartitions()` loader merges each
   partition's `data`/`services|modules`/`subscriptions`; routing is decided
   purely by which partition folders a place maps. The same bootstrap file is
   byte-identical in both places. Flat (pre-split) layout still works (single
   `{root}` partition) — backward compatible.

5. **No static cross-partition sub requires.** Subs that will land in different
   partitions resolve each other through the merged `subscriptions` registry
   (passed to `Start`) instead of `require(script.Parent.X)`. Same-partition
   requires stay static. Game-only calls made from lobby subs are guarded
   (`if BodySubs then …`).

6. **Placement.** Persistence/economy/stats/progress/pets/time/**stomach** +
   lifecycle/grant/economy/settings/leaderboard/pets/**passOwnership**/**teleport**
   subs → common. Shop/codes/rewards/group/quests/rebirth/upgrade → lobby.
   Cake-sim/cycle/treasure/gym/map/round + cake/body → game. `StomachService` &
   `PlayerRuntimeData` are **common** (rebirth's belly-reset and lifecycle
   cleanup run in both places). Client partitions provide `LobbyUiData` /
   `GameUiData` markers and lobby-only touch wiring; common AppRoot/gameplay
   subscriptions gate their place-specific presentation/input from those markers.

7. **`PassOwnershipSubs` (common)** fetches gamepass ownership on join in BOTH
   places (writes `ShopData.passOwnership`, which `StatsService` reads directly),
   so game-place perks are correct even though the shop UI is lobby-only.

## Consequences

- **Data-safe by construction**: single writer at every instant; the whole
  profile round-trips the shared DataStore, so every section is consistent in
  both places with zero per-feature plumbing.
- Lean game/lobby **servers** (real benefit); the combined build stays for dev.
- Cost: the teleport handoff is the one thing to get right, and it is
  **only verifiable on PUBLISHED places** — Studio mock stores are per-VM and
  share no lock.

## Non-negotiables (carry forward)

- Never `Steal=true`; `ProfileSchema` byte-identical + **mapped**; explicit
  milestone `Save`s (short game rounds never autosave — window is 300s, first
  150s skipped, ADR-0001/persistence.md); re-read the profile on arrival, never
  trust `TeleportData` for authoritative state; verify lock behavior on published
  places.

## Remaining

- Resolve the pre-existing upgrade-station split completely: its subscription
  and overlay are lobby-gated, but `LobbyEnvironment` still has no authored
  `UpgradeStation` prompt. Move/re-author the opener off the game checkpoint and
  into the lobby before advertising it.
- Reward kinds whose handler is game-only (`burn`, registered by `BodySubs`)
  can't be granted in the lobby — keep belly-affecting products out of the lobby
  shop, or add a common handler.
- Runtime verification on two published places (lobby→reserved game→lobby: no
  `session-taken` kick, no lost/duped currency).
