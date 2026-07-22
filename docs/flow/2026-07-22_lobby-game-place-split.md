# 2026-07-22: Lobby/game place split (phases 1–3)

Tags: persistence, bootstrap, teleport, shop, rebirth, map, architecture, split

## Task
Split the single place into two — a LOBBY (shop + meta) and a GAME (cake + core
gameplay), Drain-the-Lake style — keeping the player profile correct in both.
Ordered: fix data-safety bugs → bootstrap groundwork → do the split. Lobby scene
lives at `ReplicatedStorage.Assets.LobbyEnvironment`.

## Context
Single-place game on the RobloxTemplate skeleton (data/services/subscriptions,
ProfileStore persistence, partition-unaware bootstrap). Design produced by a
multi-agent workflow (understand → research → 3 competing architectures → judge +
adversarial data-safety pass); winner = "session follows the player, Option A
handoff". Central risk: the ProfileStore session lock across two places.

## Plan
Phase 1 fix latent data-loss bugs (they get worse under short game rounds).
Phase 2 make the bootstrap/persistence split-ready while still single-place
(backward-compatible, verifiable). Phase 3 partition the tree, add project files,
and the teleport handoff. Done on branch `feat/lobby-game-split` off a clean
checkpoint of prior WIP.

## Changes

**Created:**
- `src/server/common/subscriptions/PassOwnershipSubs.lua` — gamepass ownership
  fetch on join in BOTH places (game needs perks; shop UI is lobby-only).
- `src/server/common/subscriptions/TeleportSubs.lua` — Option A lobby↔game
  handoff (Save → intentional Unload → wait for release → TeleportAsync; reload
  on failure; never Steal).
- `src/shared/config/PlaceConfig.lua` — the two PlaceIds + `current()`/
  `otherPlaceId()` (unset until published → teleport disabled + warns).
- `src/shared/remotes/RequestTeleport.model.json` — HUD "Play"/"Return" trigger.
- `src/server/lobby/services/LobbyMapService.lua` + `.../subscriptions/LobbySubs.lua`
  — clone `Assets.LobbyEnvironment` into the hub (skipped in the combined build).
- `game.project.json`, `lobby.project.json` — the two places.
- `docs/decisions/0009-two-place-lobby-game-split.md`.

**Modified:**
- Phase 1: milestone `PersistenceService.Save` in UpgradeSubs / CakeSubs (reward
  + treasure) / BodySubs (instant-burn + drain-complete); `~30s`→`~300s (first
  ~150s skipped)` autosave doc drift in CLAUDE.md, persistence.md,
  PersistenceService, RewardsSubs, PlayerLifecycleSubs.
- Phase 2: `PlayerProfileData.releasing` + `PersistenceService.Unload(userId,
  intentional?)` + OnSessionEnd kick suppression; partition-aware `loadFolder`
  in ServerBootstrap/LocalBootstrap (+ `subscriptions` as Start's 3rd arg);
  `PushInitialState` hook on 11 subs; `PlayerLifecycleSubs` discovers hooks from
  the registry (dropped 11 static requires).
- Phase 3: registry-lookup coupling in 9 subs; `git mv` the whole server tree
  into common/lobby/game and client into common; `ShopSubs` lost
  `RefreshPassOwnership` (→ PassOwnershipSubs). `default.project.json` unchanged
  = combined build.

**Moved to COMMON (notable):** `StomachService` (rebirth belly-reset runs in the
lobby), `PlayerRuntimeData` (lifecycle cleanup in both places).

## Decisions
- **Client fully common (for now).** Server split is where the benefit is (lean
  servers, authority separation). Client shared avoids the invasive place-aware
  `AppRoot` refactor on top of heavy WIP; UI differentiates by data + a place
  flag later. See ADR-0009 "Remaining".
- **`default.project.json` = combined build.** The partition loader loads all
  three partitions, so the user's existing `rojo serve` keeps working as the full
  game; lobby/game project files are the two places.
- **Cross-partition coupling via the `subscriptions` registry**, not static
  requires — makes subs partition-location-independent; guarded for game-only
  calls from lobby. Same rationale extends R3/R4 "coordinate via subscriptions".
- **Option A handoff, `intentionalRelease` flag, milestone saves** — all from the
  design's adversarial data-safety pass; verified against the vendored ProfileStore
  (`AUTO_SAVE_PERIOD=300`, first 150s skipped; OnSessionEnd kick at :260).

## Open Questions / Followups
- Fill `PlaceConfig` PlaceIds post-publish; author `Assets.LobbyEnvironment`.
- Place-aware `AppRoot` (hide cake HUD in lobby / meta menu in game) + wire the
  "Play"/"Return" buttons to `RequestTeleport`.
- Move the upgrade-station opener from the game checkpoint to a lobby hub station.
- `burn` reward kind is game-only (BodySubs handler) — no lobby handler; keep
  belly products out of the lobby shop or add a common handler.
- **Runtime verification on two PUBLISHED places** (Studio mock stores share no
  lock — cross-place bugs are invisible in Studio).

## Related
- ADRs: ADR-0009 (this split), ADR-0001 (persistence), ADR-0007 (scene assets).
- Feature: `docs/features/persistence.md` (handoff + milestone saves).
