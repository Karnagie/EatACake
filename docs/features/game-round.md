# Game round

## Authority and start

One reserved game server owns one finite match. `GameRoundService` validates
`Player:GetJoinData()` before admission: source universe/place, protocol,
non-empty round id, known difficulty, playable `cakeId`, 1–4 contiguous unique
positive user ids, matching expected count, and the arriving player in that
roster. The first valid arrival establishes the round; every later arrival must
match the round id, difficulty, cake and roster exactly or is kicked. A
no-source/no-TeleportData direct join becomes an easy solo fallback using
`CakeConfig.defaultVariantId` (`cake-classic`) in production. In Studio only,
non-empty `CakeConfig.studioVariantId` replaces that direct-join cake after the
same playable-variant validation; real TeleportData remains authoritative.

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

| Mode | Cake WORK | Calorie payout | Boss HP | Boss time | Solo clear |
|---|---:|---:|---:|---:|---:|
| `easy` | 1.08× | 1.00× | 0.75× | 1.50× | **34.9 min** (measured 2026-08-11) |
| `medium` | 1.27× | 1.25× | 1.00× | 1.20× | ~41 min (extrapolated) |
| `hard` | 1.49× | 1.55× | 1.25× | 1.00× | ~44 min (extrapolated) |

Difficulty work buys more LAYERS and smaller scoops; it never changes the chosen
variant's silhouette. Selectable variants may set their own height and duration;
the current rainbow contract and measurements live in `features/cake-cycle.md`.
Calorie payout rises faster than difficulty work, so hard mode is the efficient
farm. Party size multiplies work by `1 + 0.5(n−1)` and payout per head by
`1 + 0.62(n−1)`.
⚠ Every `workMultiplier` rose ×1.08 on 2026-07-30: the upgrade tree is RUN-scoped
and re-priced so it is fully owned by ~48% of the cake, which means the back half
of a run is played at full power — the bump buys the 40-minute target back.
Only solo easy was measured across seeds; the other rows scale from it.
Knobs + the measurement: `features/cake-cycle.md`, ADR-0011, ADR-0013.

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

All runtime state is in `RoundStateData`: active/established/direct flags,
`cake-id`, fixed roster, participants, arrival deadline, two-phase start/result
guards, and return window. `MatchConfig.protocolVersion` is **2**; v1 arrivals
have no authoritative cake and are rejected, so lobby and game places must be
published coherently.
`MatchConfig` owns protocol/timing/tuning. `GameRoundSubs` owns arrival/removal
events and cross-sub orchestration; `GameRound/Return` owns the bounded,
profile-safe lobby return loop; `CakeCycleSubs` owns terminal cake behavior;
`CakeSimulationSubs` owns the Heartbeat; `CakeSubs` owns participant-gated input.

Lobby formation/launch: `features/lobby-matchmaking.md`. Decision: ADR-0010.
