# Lobby matchmaking

## Player flow

The lobby clones `ReplicatedStorage.Assets.LobbyEnvironment` into
`workspace.LobbyMap`. Entering any direct
`Touchers/<Model>/GroupToucher` admits the player to that pad. The first
admitted player is the leader and receives the kit `MatchmakingPanel`; they
choose `easy` / `medium` / `hard` and a maximum party size from 1–4. **The
selector opens on `MatchConfig.defaults` (Easy / 1 Player)**, so a solo run is
ONE tap and START is live on the first frame; the defaults are applied per
SESSION, in the same effect that used to clear the previous party's choices, and
a default the selector is not offering (a party size above the pad's cap, a
retired difficulty) is ignored rather than forced. START **breathes**
(`Components.Button` `pulse`) exactly while it can be pressed — its
dim-when-disabled CanvasGroup clips, so `MatchmakingLayout.StartPulseHeadroom`
inflates the group and deflates the button inside it, leaving rest geometry
unchanged.
⚠ A preselection is REPORTED like a tap (`onSelectDifficulty(id, isDefault)` /
`onSelectPlayers(n, isDefault)`): the `difficulty-pick` / `party-pick` flow steps
sit between `selector-open` and `start-press`, so leaving them unreported would
show every one-tap start as a drop-off (`features/analytics.md`). Whether the
player actually CHOSE is still visible — the kit counts the `Difficulty_*` /
`Players_*` presses themselves, and those only exist when a finger lands on one.
The effect reports only for a real `sessionKey`; the panel is mounted (hidden)
for the whole lobby visit and must not beat on mount.
A valid choice starts a server-owned countdown whose length depends on PARTY SIZE
(`Core.CountdownSeconds`): **5 s solo, 15 s for 2+** — a solo player is only
waiting on themselves. Picked once, when START is pressed, so a late joiner
rides the remaining time rather than resetting it. Players standing in the same
toucher are reconciled by overlap scan, up to the selected cap; stepping out
removes them after the configured grace period.

At expiry the current admitted roster is profile-released and sent by one
`TeleportAsync` call to a reserved server in place `136881957250247`. The finite
roster/difficulty/result contract is `features/game-round.md`; profile handoff
guarantees and retries are `features/persistence.md`. The public return lobby is
place `126172008675265` (ADR-0010).

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

`Shared.config.MatchConfig` is the single contract for modes, `defaults`
(the selector's opening pick), cap, countdown,
arrival/result timings, authored names, and teleport retry limits. Difficulty
scales eating WORK, the calorie payout and boss HP/time — **not cake height**
(`cakeHeightMultiplier` is gone: a bite clears to the band floor, so height never
moved clear time). Authoritative profile/economy state never travels in teleport
data.

Server: `LobbyQueueData`, `LobbyQueueService` + `services/LobbyQueue/*`,
`LobbyQueueSubs` + `subscriptions/LobbyQueue/*`, `GameRoundService`,
`GameRoundSubs`, `CakeCycleSubs`, `TeleportSubs`, `TeleportRetrySubs`.
Client/kit: `LobbyUiData`, `LobbySubsClient`, `AppRoot`, `MatchChoice`,
`MatchmakingPanel`, `PlayerControlData`, `PlayerControlService`,
`TeleportControlSubsClient`.
