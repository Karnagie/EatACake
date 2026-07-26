# Game round

## Authority and start

One reserved game server owns one finite match. `GameRoundService` validates
`Player:GetJoinData()` before admission: source universe/place, protocol,
non-empty round id, known difficulty, 1–4 contiguous unique positive user ids,
matching expected count, and the arriving player in that roster. The first valid
arrival establishes the round; every later arrival must match it exactly or is
kicked. A no-source/no-TeleportData direct join becomes an easy solo fallback.

The match starts when all expected members arrive **and every present profile is
loaded**, or after 10 seconds with at least one loaded participant. At that
deadline, still-unloaded arrivals are removed/kicked; `expectedCount` stays fixed
for cake and boss scaling if members fail to load/arrive or later leave. No live
cake, client snapshot, or simulation exists during the roster/profile wait.
`BeginMatch` constructs the first real cake and only then commits the start;
missing/throwing/declining dependencies fail closed once as a loss and use the
bounded lobby return. `EatAt`, checkpoint return, and treasure collection
require a started match and a present roster participant.

## Difficulty and result

| Mode | Cake height | Boss HP | Boss time |
|---|---:|---:|---:|
| `easy` | 0.80× | 0.75× | 1.50× |
| `medium` | 1.00× | 1.00× | 1.00× |
| `hard` | 1.08× | 1.50× | 0.75× |

Boss defeat is a win; only present validated participants receive the cake-clear
reward and milestone save. Boss timeout is a loss with no reward. Either result
is terminal: after 5 seconds, present participants are group-returned to the
public lobby. Return attempts repeat every 10 seconds for up to 180 seconds;
profile/teleport safety is defined in `features/persistence.md`.

Each return batch includes only participants whose profile is currently loaded
and who are not already teleporting. A late arrival still loading its profile
cannot block ready finishers; it joins a later retry once loaded.
If a required return dependency is unavailable, the return window closes and
present players are safely disconnected instead of being admitted indefinitely
to an ended server.

An expected arrival after terminal result is admitted only while the bounded
return window remains, solely to join the next lobby send; after its deadline the
player is rejected instead of being stranded in an ended server.

Return TeleportData is transient/diagnostic (the lobby currently does not
display it): `{version, kind = "match-result", result = "win"|"loss", roundId}`.

## State and files

All runtime state is in `RoundStateData`: active/established/direct flags, fixed
roster, participants, arrival deadline, two-phase start/result guards, and return
window.
`MatchConfig` owns protocol/timing/tuning. `GameRoundSubs` owns arrival/removal
events and cross-sub orchestration; `GameRound/Return` owns the bounded,
profile-safe lobby return loop; `CakeCycleSubs` owns terminal cake behavior;
`CakeSimulationSubs` owns the Heartbeat; `CakeSubs` owns participant-gated input.

Lobby formation/launch: `features/lobby-matchmaking.md`. Decision: ADR-0010.
