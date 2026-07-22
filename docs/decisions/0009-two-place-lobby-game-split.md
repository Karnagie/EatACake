# ADR-0009 — Two-place lobby/game split (one universe)

Status: **Accepted, partially implemented** (structural split done; publish-time
config + place-aware client + runtime verification pending — see "Remaining").
Date: 2026-07-22. Supersedes nothing. Related: ADR-0001 (persistence), ADR-0007
(place-authored scene assets), ADR-0002 (reward grants).

## Context

The game was one place. We split it into two (Drain-the-Lake style): a **LOBBY**
(hub + shop + meta/progression) and a **GAME** (cake + core gameplay). The hard
constraint: a player's ProfileStore profile (currency, upgrades, pets, stomach…)
must stay correct in BOTH places, spendable in the lobby and effective in the
game. DataStores are **universe-scoped**, so both places share ONE
`PlayerProfiles`/userId session lock — that shared lock is what makes cross-place
consistency emergent instead of hand-synced.

## Decision

1. **One universe, two places.** Lobby is the start place. Game servers are
   **shared public** (the cake is a collaborative social sim — biome/treasures
   are server-wide), NOT reserved; no matchmaking. Movement is
   `TeleportService:TeleportAsync` both ways.

2. **Session follows the player, "Option A" handoff** (`TeleportSubs`, common):
   source freezes input → folds playtime → `Save` → `Unload(userId, true)`
   (intentional release) → **waits for the lock to actually release** → 
   `TeleportAsync`; on failure it re-acquires the lock so the player isn't
   stranded. Destination runs the **unchanged** `LoadProfile`. **Never
   `Steal=true`** (P5) — that drops the source's final save. The
   `intentionalRelease` flag (`PlayerProfileData.releasing`, consumed in
   `PersistenceService.OnSessionEnd`) suppresses the mid-teleport `session-taken`
   kick.

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
   Cake-sim/cycle/treasure/gym/map + cake/body → game. `StomachService` &
   `PlayerRuntimeData` are **common** (rebirth's belly-reset and lifecycle
   cleanup run in both places). **Client is fully common for now** (shared
   client; place-aware UI to follow).

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

## Remaining (not yet done)

- Fill `PlaceConfig.lobbyPlaceId/gamePlaceId` after publishing; teleport is
  disabled until then.
- Author `ReplicatedStorage.Assets.LobbyEnvironment` (ADR-0007 pattern).
- **Place-aware client** (also closes a live R8 gap): the client is fully
  common, so the GAME place currently surfaces lobby-only controls with **no
  handler** — the checkpoint `UpgradeStation` prompt + HUD upgrade/rebirth
  buttons fire `BuyUpgrade`/`DoRebirth` into a server without
  `UpgradeSubs`/`RebirthSubs` (silent dead controls). Gate the cake HUD /
  8-button meta menu by place, and either hide the game-place upgrade/rebirth
  controls + station prompt OR move those subs to common. Wire the
  "Play"/"Return" buttons to the `RequestTeleport` remote.
- Move the upgrade-station opener off the game checkpoint onto a lobby hub
  station.
- Reward kinds whose handler is game-only (`burn`, registered by `BodySubs`)
  can't be granted in the lobby — keep belly-affecting products out of the lobby
  shop, or add a common handler.
- Runtime verification on two published places (fast lobby↔game round-trip: no
  `session-taken` kick, no lost/duped currency).
