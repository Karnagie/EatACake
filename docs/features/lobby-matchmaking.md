# Lobby matchmaking

## Player flow

The lobby clones `ReplicatedStorage.Assets.LobbyEnvironment` into
`workspace.LobbyMap`. Entering any direct
`Touchers/<Model>/GroupToucher` admits the player to that pad. The first
admitted player is the leader and receives the kit `MatchmakingPanel`; they
choose `easy` / `medium` / `hard` and a maximum party size from 1–4. A valid
choice starts a server-owned 30-second countdown. Players standing in the same
toucher are reconciled by overlap scan, up to the selected cap; stepping out
removes them after the configured grace period.

At expiry the current admitted roster is profile-released and sent by one
`TeleportAsync` call to a reserved server in place `91726662453442`. The finite
roster/difficulty/result contract is `features/game-round.md`; profile handoff
guarantees and retries are `features/persistence.md`. The public return lobby is
place `80059832045175` (ADR-0010).

## Authored lobby contract

Under `ReplicatedStorage.Assets.LobbyEnvironment`:

- `Touchers` contains one or more direct Models. Each has direct
  `GroupToucher` (`BasePart`) and `GroupToucherVisual`.
- `GroupToucherVisual.PlayerCount.Txt` shows `present/max`.
- `GroupToucherVisual.WaitingStatus.Txt` shows waiting/configuration,
  `<Mode> - <seconds>s`, teleporting, or failure state. Legacy `ChestStatus` is
  normalized to `WaitingStatus`; legacy scripts under each toucher clone are
  removed before it enters Workspace.
- `Forest.Chocolate["Meshes/chocolate"]` is a `BasePart`; touching its runtime
  clone opens the existing Shop panel.
- `LobbySpawn` is the invisible authored `SpawnLocation` at `(0, 0.5, 90.5)`.

`ReplicatedStorage.Assets.LobbyMapContainer` is an empty authored Folder cloned
as `workspace.LobbyMap`; the environment clone is parented beneath it. If the
container/environment is missing, the existing Workspace is preserved and the
map/queue bind warns instead of creating runtime fallback view objects.

Missing authored dependencies warn and degrade without stalling (R8). Pads are
ordered left-to-right by model pivot X and keep independent sessions.

## Network and authority

| Direction | Remote | Contract |
|---|---|---|
| client → server | `LobbyQueueRequest` | `(action, sessionKey, difficulty?, maxPlayers?)`; `action` is `configure` or `leave`. Rate-limited, session-correlated, leader-only. |
| server → client | `LobbyQueueUpdate` | `(kind, payload?)`; `open`, `close`, `error`, or `busy`. `open` carries `{sessionKey,currentPlayers,maxPlayers}`. |

The client never chooses a destination, roster, countdown, or reward. Game join
data must match protocol version, universe/lobby source, round id, difficulty,
contiguous unique roster, count, and arriving user.

## Place/UI contract

`LobbyUiData` and `GameUiData` are project-mapped partition markers. In the
lobby, AppRoot hides the cake HUD, belly, checkpoint button, eat control, game
overlays, and gameplay input subscriptions; the lobby meta menu, matchmaking,
and chocolate Shop flows remain active. During any verified-release handoff,
the server `Teleporting` attribute holds a reason-keyed client movement lock;
recovery releases it without racing other modals. In the game, lobby/meta UI
and touch wiring are absent. The combined
development build maps both markers but intentionally does not build the lobby
map while `MapService` is present.

## Tuning and files

`Shared.config.MatchConfig` is the single contract for modes, cap, countdown,
arrival/result timings, authored names, and teleport retry limits. Difficulty
currently scales cake height and boss HP/time; authoritative profile/economy
state never travels in teleport data.

Server: `LobbyQueueData`, `LobbyQueueService` + `services/LobbyQueue/*`,
`LobbyQueueSubs` + `subscriptions/LobbyQueue/*`, `GameRoundService`,
`GameRoundSubs`, `CakeCycleSubs`, `TeleportSubs`, `TeleportRetrySubs`.
Client/kit: `LobbyUiData`, `LobbySubsClient`, `AppRoot`, `MatchChoice`,
`MatchmakingPanel`, `PlayerControlData`, `PlayerControlService`,
`TeleportControlSubsClient`.
