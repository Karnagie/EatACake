# Analytics — the instrumentation

Where players get confused, what they never finish, and every tap in between.
Decision + platform quotas: **ADR-0017**. Catalog: `Shared.config.AnalyticsConfig`.

## ⚠ Read this before adding a metric

Roblox analytics is quota'd, and going over produces **no error** — the event is
dropped server-side and the metric silently never appears.

| Quota | Limit |
|---|---|
| Rate limit | **120 + (20 × CCU) per minute, per SERVER** (solo game server ≈ 140) |
| Custom event names | **100 per experience**, ever |
| Funnels | **10 names × 100 steps** |
| Custom fields | **3 per event**, 8000 combined unique values |
| Where | **server only, published places only** (Studio always fails) |

So: **never write a literal event name.** Add a key to
`AnalyticsConfig.events` / `.flowSteps` / `.funnels` and pass the key.
`AnalyticsConfig.Validate()` runs at boot and logs occupancy; an unknown key
warns instead of inventing a name. Current occupancy: **41/100 events,
8/10 funnels, 31/100 steps** on the longest funnel.

## The initial player flow

One ordered list (`AnalyticsConfig.flowSteps`) drives three things at once: the
`PlayerFlow` custom funnel (per session, so it measures returning players too),
the built-in **onboarding** funnel (lifetime, first-session cohort only —
Roblox reports it against D1/D7 retention), and the `flow_step` event whose
**value is the seconds spent on the previous step**.

| # | Step | Fired from |
|---|---|---|
| 1 | Joined | `AnalyticsSubs` (PlayerAdded) |
| 2 | Character Spawned | `AnalyticsSubs` (CharacterAdded) |
| 3 | HUD Ready | client, deferred to after the bootstrap loop (AppSubsClient mounts the root) |
| 4 | Approached A Pad | client, within `padApproachStuds` of an authored pad |
| 5 | Stood On A Pad | `LobbyQueue/Protocol` (admission effect) |
| 6 | Match Selector Opened | `LobbyQueue/Protocol` (open effect) |
| 7 | Difficulty Chosen | **client** — never reaches the server unless START is pressed |
| 8 | Party Size Chosen | **client** — same |
| 9 | Start Pressed | **client**, before validation |
| 10 | Countdown Started | `LobbyQueue/Protocol` (Configure accepted) |
| 11 | Match Launched | `LobbyQueue/Launch` |
| 12 | Teleport Started | `TeleportSubs`, after `TeleportAsync` succeeds |
| 13 | Arrived In Game | `GameRoundSubs` (validated arrival) |
| 14 | Match Started | `GameRoundSubs` (cake built, input live) |
| 15 | Story Slides Shown | `TutorialSubsClient` |
| 16 | Slides Skipped | `TutorialSubsClient` |
| 17 | Eat Hint Shown | `TutorialSubsClient` (optional — first session only) |
| 18 | First Bite | `CakeSubs`, after auth + rate limit |
| 19 | Eat Hint Cleared | `TutorialSubsClient` (button **or** first bite) |
| 20 | First Find Collected | `CakeSimulationSubs`, after the grant lands |
| 21 | First Layer Cleared | `CakeSimulationSubs` (layer gate steps down) |
| 22 | Belly Full | `BodySubs.SendStomach` (same threshold as the tutorial beam) |
| 23 | Reached The Checkpoint | client plate test **or** the gym prompt, whichever first |
| 24 | Fat Burn Started | `BodySubs` (gym prompt) |
| 25 | First Fat Burned | `BodySubs` (both the drain and the instant path) |
| 26 | Upgrade Tree Opened | client (panel opened) |
| 27 | First Upgrade Bought | `UpgradeSubs`, after the spend succeeds |
| 28 | Tutorial Completed | `TutorialSubs` |
| 29 | Boss Reached | `CakeCycleSubs.BeginBoss` |
| 30 | Match Won | `GameRoundSubs.Finish("win")` |
| 31 | Returned To Lobby | `AnalyticsSubs`, from the return TeleportData |

`Flow()` is **idempotent per session and ordered**, so a beat can be fired from
wherever the truth actually is without any caller tracking whether it already
happened.

### Confusion signals
| Event | Means |
|---|---|
| `flow_step` (value) | seconds spent on the previous step — one event, every step |
| `flow_stall` | still on this step past its `stallSeconds` budget. Fires ONCE |
| `flow_abandon` | left mid-flow. **Never** fired while teleporting — that is the flow continuing elsewhere |
| `ui_dead_press` | pressed a DISABLED control, or one the input lock swallowed: they tried, the game said nothing |
| `queue_error` / `match_reject` / `teleport_fail` | the refusal, by reason |

## The other funnels (8 of 10 used, 2 free on purpose)

| Key | Name | Session id | Steps |
|---|---|---|---|
| `flow` | `PlayerFlow` | analytics session (spans the teleport) | the 31 above |
| `queue` | `Matchmaking` | per pad visit (`visit`) | enter → selector → difficulty → party → start → countdown → launch → sent |
| `tutorial` | `Tutorial` | analytics session | slides → skip → eat → bite → belly → path → arrived → upgrades → done |
| `match` | `Match` | round id | arrive → start → bite → layer → gym → upgrade → half → boss → win → return |
| `shop` | `Shop` | per visit | open → tab → card → prompt → bought |
| `upgrades` | `Upgrades` | per visit | open → select → attempt → bought |
| `gym` | `GymBurn` | per visit | near → start → tap → banked |
| `find` | `Finds` | per visit | glint → uncovered → collected |

Landing on a `visit` funnel's **first step opens a new attempt** automatically
(`Session.Funnel`) — otherwise the first shop visit's seen-set would suppress
every later one and the conversion rate would be nonsense.

## Architecture

| Piece | Owns |
|---|---|
| `Shared.config.AnalyticsConfig` | the catalog + quotas + `Validate()` |
| `AnalyticsSubs` | the public API, the connections, the slow tick |
| `Analytics/Sink` | **the only code that calls AnalyticsService** — token bucket, priority tiers, coalescing, drop accounting |
| `Analytics/Session` | per-player session, funnel engine, teleport continuity, stalls |
| `Analytics/Ingest` | validates + admits the client beat stream |
| `LocalAnalyticsService` | client queue: coalesce, batch, flush |
| `AnalyticsSubsClient` | every client-side signal, in one place |

Other subs push beats IN through the registry (`subscriptions.AnalyticsSubs`,
the ADR-0009 coupling pattern); this module never reaches into a domain.
**Every caller treats it as optional** (`if AnalyticsSubs then`) and warns once
if missing (R8). Telemetry must never take a gameplay path down.

### Budget
`Sink` refills a token bucket at `120 + 20×CCU` × `safety01` (0.75). Tiers:

| Tier | Reserve | Carries |
|---|---|---|
| `critical` | — | funnel steps, economy, match lifecycle, purchase results |
| `normal` | 15% | counters, tutorial, queue, panels |
| `bulk` | 50% | `ui_press`, `bite`, holds |

Bulk may only touch the top half of the bucket, so a tap storm cannot eat the
budget a funnel step needs two seconds later. The coalescing **flush obeys the
same reserves** — it did not once, and up to 240 buffered bulk entries would
drain the bucket the moment their window elapsed, defeating the whole design.

Refused events are counted and reported through `analytics_dropped` **and** a
console warn. That report **reserves** a token rather than competing for one
(drops happen precisely when the budget is empty) and keeps its counts if it
cannot send, so the honesty mechanism cannot be silenced by the condition it
exists to announce.

`coalesce = true` merges identical (event, fields, player) tuples for ~6 s and
sends the count as the event's `value`. **Counters only** — summing two dwell
times produces a number that describes nobody. `gym_banked` is not coalesced
either: the 8 Hz drain loop **accumulates** and emits one event per gym
session, because 16 events/second for one player is six times the whole
server's allowance.

### Failure modes, told apart
- **"unpublished place"** — throws on every call. Three strikes → the sink
  disables itself for the server with ONE warn. This is Studio.
- **"too many events"** — a rate limit, not a fault. The bucket is emptied for
  the rest of the minute and the sink keeps running. Disabling here would
  silence a *popular* server.

### The teleport
The analytics session id is minted in the lobby and rides the launch
`TeleportData` as `analytics = { {u=userId, s=sessionId, c=cohort, i=flowIndex, p=platform}, … }`
(also on the return). The destination adopts it and suppresses steps at or below
the carried index. **It is an ARRAY, not a userId-keyed map** — teleport data
stringifies numeric keys (`Net.lua`), and a keyed lookup would miss silently and
split every funnel in the game.

`GameRoundService` validates only the fields it knows, so the extra key is inert
to admission (`features/game-round.md`).

## Client → server

| Remote | Payload |
|---|---|
| `AnalyticsBeat` (c→s) | ARRAY of `{ k = kind, a = string?, b = string?, v = number? }` |

Kinds: `press`, `dead-press`, `panel`, `hold`, `flow`, `funnel`, `tutorial`,
`shop`, `platform`, `error`.

**The client may only assert what the server cannot see.** `clientFlowSteps`
allows `hud-ready`, `pad-approach`, `difficulty-pick`, `party-pick`,
`start-press`, `slides`, `slides-skip`, `eat-hint`, `eat-hint-clear`,
`checkpoint`, `upgrades-open`. `clientFunnels` is **per STEP, not per funnel** —
`shop` and `upgrades` both end in a conversion step, so a funnel-wide list would
have let a client assert its own purchase. Allowed: `queue` {difficulty, party,
start}, `tutorial` {slides…upgrades}, `shop` {open, tab, card}, `upgrades`
{open, select}, `find` {glint}. Everything else is refused with a warn.

Bounds: ≤24 beats/message, 3 messages/s, 240 beats/min per player, every string
sanitized and clamped to 40 chars, **and at most
`maxDistinctValuesPerPlayer` (80) distinct field values per player** — the rest
fold into `other`. Length-clamping is not cardinality-clamping: one modded
client sending a fresh short id per beat at the legal rate would exhaust the
experience-wide 8000-unique-value budget in about half an hour and collapse
every honest breakdown in the game to "Other" for the retention window.

⚠ No client-supplied string ever becomes a `Log.Once` KEY. `Log.onceFired` is
never cleared, so an attacker-chosen key is unbounded server memory *and* an
unbounded warn stream. Refusal keys are a fixed string plus the player's own id.

`tools/headless-sim/catalog_xcheck.py` verifies both halves statically: every
key referenced in `src/` exists in the catalog, and every key a client asserts
is allow-listed. Run it after touching the catalog — it has already caught a
tightened allow-list silently refusing three matchmaking steps the client was
still sending.

### Every tap, with no per-button wiring
`UIKit.SetTrackHandler` is injected once by `AnalyticsSubsClient` — the same
shape as the audio layer's `SetSoundHandler`. `Interaction.usePressable` reports
on the aggregate press edge (so multi-touch and drag-off are one tap), and
identifies the control by `config.analyticsId` or, failing that, by the pressed
Instance's own **Name** (with the parent prefixed when the name is generic).
Components outside `usePressable` (Toggle, PetCard, DayCard, the hex tree, the
reveal overlay) pass an id to `Interaction.Cue("press", id)`.

A **disabled** button reports too, via `InputBegan` — which fires regardless of
`Active`, unlike `Activated`/`MouseButton1Click`, and that difference IS the
signal being recorded. No `Active` value is changed, so nothing sinks
differently.

## ⚠ A leg is not a session
Every lobby↔game teleport ends the player on this server and starts a fresh one
on the next, so a per-server timer measures one LEG. A single `session_minutes`
would report a 30-minute session as "3 + 26".

| Event | Read it as |
|---|---|
| `place_minutes_game` | **the engagement number** — time actually playing a round |
| `place_minutes_lobby` | queue/menu overhead. Rising alone = matchmaking is the leak |

For true cross-place session length use **Roblox's own engagement metric**; a
hand-rolled total would be less accurate than the one Roblox gives away. The
leg uses `os.time()` — a wall-clock duration meant to be read as minutes;
everything else here (step dwell, stall budgets, the coalescing window) is a
short interval on `os.clock()`, matching every other timer in the codebase.

## Verification without Studio
```bash
SCENARIO_FILE=analytics_scenario.lua python tools/headless-sim/build_sim.py && luau tools/headless-sim/sim.luau
python tools/headless-sim/catalog_xcheck.py
```
The scenario runs the REAL Sink/Session/Ingest against a stubbed
AnalyticsService: **66 checks** covering the budget, priority reserves,
coalescing, the trust boundary, teleport continuity, stalls/abandonment,
recurring-funnel attempts, economy validation, the unpublished-place shutdown,
and every defect adversarial review found on 2026-08-02. The stub **validates
the custom-fields dictionary shape**, because handing `LogCustomEvent` a
positional array throws — and three throws disable the sink. See
`tools/headless-sim/README.md`.

## Gotchas
- **The onboarding funnel is lifetime and de-duped by Roblox**, so it only fires
  for the `new` cohort — a veteran's steps would be thrown away at full budget
  cost. Cohort comes from ProfileStore's `SessionLoadCount`, which resolves
  AFTER the first beats, so those onboarding calls are HELD until the profile
  lands (`Session.OnProfileLoaded`, discovered by `PlayerLifecycleSubs`).
- **`SessionLoadCount` counts profile LOADS, and a teleport is a load** — it
  reads 2+ for a brand-new player arriving in the game place. That is why the
  cohort is carried across the handoff rather than recomputed there.
- **`AnalyticsSubsClient` polls the open panel** instead of registering
  `onPanelChanged`: `AudioSubsClient` already owns that key, `SetCallbacks`
  merges by key with last-writer-wins, and Audio sorts AFTER Analytics — taking
  it would silently unplug the panel whoosh.
- **Never coalesce a measurement.** `flow_step`, `ui_hold`, `gym_banked` and the
  place-minutes events carry a real value; merging them sums nonsense (two 6 s
  holds would report one impossible 12 s press).
- **A per-visit funnel opens a new attempt on its FIRST step.** Keying the
  seen-set per player instead meant the first shop visit suppressed every later
  one, so the funnel reported one visit per session.
- **A rate limit is not "unavailable".** The two AnalyticsService failure modes
  are told apart by the message; conflating them would disable telemetry
  permanently on the *busiest* servers, the ones whose data matters most.
- **Field values must be a bounded vocabulary.** 8000 unique values across all
  three fields become "Other" — never put a player name, a guid or free text in
  one.

## Files
`src/shared/config/AnalyticsConfig.lua`, `src/shared/remotes/AnalyticsBeat.model.json`,
`src/server/common/subscriptions/AnalyticsSubs.lua` + `Analytics/{Sink,Session,Ingest}.lua`,
`src/client/common/modules/LocalAnalyticsService.lua`,
`src/client/common/subscriptions/AnalyticsSubsClient.lua`,
`src/shared/UIKit/Interaction.lua` (press capture) + `UIKit/init.lua` (`SetTrackHandler`).
Beats pushed from `LobbyQueue/{Protocol,Launch}`, `TeleportSubs`, `GameRoundSubs`,
`GameRound/Return`, `CakeSubs`, `CakeSimulationSubs`, `CakeCycleSubs`, `BodySubs`,
`UpgradeSubs`, `TutorialSubs`, `ShopSubs`, `RewardGrantSubs` /
`LobbySubsClient`, `TutorialSubsClient`, `ShopSubsClient`, `UpgradesSubsClient`,
`CakeSubsClient`.
