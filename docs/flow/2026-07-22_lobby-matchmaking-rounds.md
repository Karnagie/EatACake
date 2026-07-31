# 2026-07-22: Lobby matchmaking and finite rounds

Tags: lobby, matchmaking, teleport, persistence, cake-cycle, ui-kit, shop, split

## Task

Entering any authored lobby GroupToucher must open easy/medium/hard + 1–4
selection, show party/countdown on its world labels, and send the standing party
to game place `136881957250247` after 30 seconds. Win/loss returns to lobby;
touching the authored chocolate opens Shop; gameplay HUD/input is hidden in lobby.

## Context

ADR-0009 had split server partitions and a preliminary single-player public
teleport, but left place-aware client UI and published flow unfinished. The
lobby asset already contained three same-named touch models and legacy scripts.
Prior flow: `2026-07-22_lobby-game-place-split.md`.

## Plan

Define one shared lobby/round protocol, build independent server-authoritative
pad queues and kit UI, replace public endless launch with reserved fixed-roster
rounds, harden the ProfileStore handoff, then verify lobby behavior live.

## Changes

**Created:**

- `Shared.config.MatchConfig`, queue remotes, `LobbyQueueData`/
  `LobbyQueueService`/`LobbyQueueSubs` and focused helper folders — independent
  touch occupancy, session-keyed leader configuration, labels/countdown, launch.
- `LobbyUiData`, `LobbySubsClient`, UIKit `MatchChoice`/
  `MatchmakingPanel` — place marker, chocolate trigger, candy selector.
- `PlayerControlData`, `PlayerControlService`, `TeleportControlSubsClient` —
  reason-keyed movement freeze throughout the profile-release handoff.
- `RoundStateData`, `GameRoundService`, `GameRoundSubs`, `GameRound/Return` —
  authenticated fixed roster, bounded arrival window, finite result and
  profile-safe lobby return.
- `TeleportData`, `TeleportRetrySubs`, `Teleport/Release`, `Teleport/Recovery`,
  `Teleport/Resync` —
  visible handoff state, bounded release/read-back, exact reserved-destination
  retry, bounded concurrent recovery, and authoritative state replay before
  input unlock.
- `CakeCycleSubs`, `CakeSimulationSubs` — lifecycle/Heartbeat split from player
  input; `GameUiData` — game client marker.
- `features/lobby-matchmaking.md`, `features/game-round.md`, ADR-0010.

**Modified:**

- `AppRoot`/locale/theme/project files and game input subscriptions — selector,
  place-aware gameplay HUD/input gates, lobby/game client partitions.
- `ShopPanel`/`ShopRow` geometry — explicit automatic-canvas cell heights keep
  the chocolate-opened catalogue rows visible instead of collapsing to zero.
- `LobbyMapService`/`LobbySubs` — sanitize legacy toucher scripts/status names,
  clone the authored container/environment/spawn, then bind every pad. The
  user's transparent spawn and position edits were preserved without runtime
  view creation.
- Cake cycle/input/state — difficulty tuning, roster authorization, boss
  win/loss terminal handling, milestone save, fixed launch count.
- Persistence/teleport — final-save nonce plus cleared-lock read-back before
  teleport, grouped release/one `TeleportAsync`, exact-destination retry, and
  concurrent token/deadline-gated profile recovery with a hard watchdog.
- Profile schema application is transactional on a deep copy; failed/missing
  migrations or failed sanitizers abort without saving a partial shape/stamp.
- Studio asset: all three queue visuals use `WaitingStatus`, initial `Waiting` /
  `0/4`, and the three legacy client scripts are disabled (runtime clone also
  destroys them); empty `LobbyMapContainer` and invisible `LobbySpawn` templates
  plus `Shared.UIKit.Templates.UpgradeTreeBlur` now make runtime views clone-only.
- Finished-round lobby retries batch only loaded profiles, so a late loading
  arrival cannot block ready finishers; fatal return setup closes admission and
  disconnects present players instead of stranding them in the ended server.

## Decisions

- Reserved server per launch, not a shared public game: a pad's difficulty,
  population, and one-match lifecycle must be isolated (ADR-0010).
- Queue membership comes from server overlap reconciliation; the client owns
  only presentation and sends session-correlated choices.
- Expected launch count remains fixed if a member fails to arrive/leaves, so
  difficulty cannot be reduced after acceptance.
- `OnSessionEnd`/generic `OnAfterSave` are not commit proof. Teleport waits for
  the exact persisted release nonce and nil stored session; async retries reuse
  Roblox's returned `TeleportOptions` to retain the reserved destination.

## Verification

- `rojo build` passed for lobby, game, and combined projects.
- Studio compiled all 195 repository Luau sources with zero failures.
- Live Lobby boot: server 13 data, 15/15 services, 18/18 subscriptions; client
  Common+Lobby 5 data, 24 modules, 15/15 subscriptions; no feature boot errors.
  ProfileSchema registered 12 sections and initial state pushed 11/11 domains.
- Three pads bound in X order. Live touch opened the Easy/Medium/Hard + 1–4
  selector; Medium + 2 started a logged 30-second countdown and labels advanced
  through `1/2 Medium - 20s` / `16s`. Chocolate touch opened the populated Shop:
  3 visible sections and 15 nonzero-size item rows with text/buttons.
- Lobby Calories/Checkpoint/gameplay input were hidden/skipped; the lobby meta
  menu remained available and is absent from the game place.
- Studio's expected teleport HTTP 403 exercised recovery: the profile was
  re-acquired, 11/11 domains replayed before movement unlocked, and the pad reset
  to `0/4 Waiting Players...`.
- Final adversarial review reported no remaining actionable CRITICAL/WARN items.

## Open Questions / Followups

- Verify the real lobby → reserved game → lobby hop and shared-lock behavior in
  published servers; Studio cannot complete/prove that cross-server contract.
- Pre-existing upgrade-station placement remains split-incomplete (ADR-0009
  Remaining); it is not part of the matchmaking/chocolate flow.

## Related

- Feature: `docs/features/lobby-matchmaking.md`, `docs/features/game-round.md`, `docs/features/persistence.md`,
  `docs/features/cake-cycle.md`, `docs/features/app-root.md`
- ADRs: ADR-0009, ADR-0010
- Prior flow: `docs/flow/2026-07-22_lobby-game-place-split.md`
