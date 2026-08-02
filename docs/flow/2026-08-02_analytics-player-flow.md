# 2026-08-02: Analytics — the 31-step player-flow funnel and every tap

Tags: analytics, funnel, lobby, matchmaking, tutorial, game-round, teleport,
economy, shop, ui-kit, tooling

## Task
"Implement analytics for the game… as comprehensive and high-quality as
possible… The analytics should cover the entire game, but the highest priority
right now is the initial player flow. We need a funnel that tracks absolutely
every step and action taken by the player… Literally every tap and action
should be tracked and visible, so I can clearly understand where players get
confused, what they fail to understand, and which actions they do not complete."

## Context
`AnalyticsSubs` existed as a 150-line retention stub: 7 onboarding beats, 6 loop
counters, two place-leg timers, and a hand-written event name at each call site.
Nothing client-side was instrumented at all, so the entire lobby — pad approach,
difficulty, party size, START — was invisible; so were the intro slides, SKIP,
and every button in the game.

## Plan
Research the platform first, because the naive implementation of this request is
impossible on Roblox and fails **silently**. Confirmed from the Roblox docs and
a staff answer (2026-08-02): **120 + 20×CCU events/minute per server**, **100
custom event names per experience**, **10 funnels × 100 steps**, **3 custom
fields**, server-only and published-only. A solo game server gets ~140/min.

So: one CATALOG, "every tap" as ONE event name with the control id in a custom
field, a token-bucket budget with priority tiers, coalescing to pay for density,
and a session id that survives the lobby→game teleport so the funnel does not
break in half exactly where it gets interesting.

## Changes

**Created:**
- `src/shared/config/AnalyticsConfig.lua` — the catalog: 8 funnels, 31 ordered
  flow steps, 41 event names, quota constants, priority tiers, the client trust
  allow-lists, and `Validate()` (boot-time occupancy check, R8)
- `src/shared/remotes/AnalyticsBeat.model.json`
- `src/server/common/subscriptions/Analytics/Sink.lua` — the ONLY caller of
  AnalyticsService: token bucket at the live allowance, 3 tiers with reserves,
  coalescing into `value`, drop accounting, rate-limit-vs-unpublished handling
- `src/server/common/subscriptions/Analytics/Session.lua` — per-player session,
  funnel engine, cohort, teleport continuity, stalls, abandonment
- `src/server/common/subscriptions/Analytics/Ingest.lua` — client beat
  validation, per-player budgets, the trust boundary
- `src/client/common/modules/LocalAnalyticsService.lua` — client queue
- `src/client/common/subscriptions/AnalyticsSubsClient.lua` — every client-side
  signal in one place
- `docs/decisions/0017-budgeted-analytics-catalog.md`
- `tools/headless-sim/analytics_scenario.lua` — 53 checks against the real
  modules

**Modified:**
- `AnalyticsSubs.lua` — rewritten as the API + connections + slow tick; the old
  `Onboard`/`Count` survive as shims that map onto the catalog
- `UIKit/Interaction.lua` + `UIKit/init.lua` — `SetTrackHandler`; press capture
  on the aggregate edge, id derived from the Instance Name, and a **disabled**
  button reporting `dead` through `InputBegan`
- `UIKit/Components/{Button,SettingRow,Toggle,DayCard,PetCard,PetRevealOverlay,HexTreeOverlay}.lua`
  — ids for the clickables outside `usePressable`
- `UIKit/Components/MatchmakingPanel.lua` — `onSelectDifficulty` /
  `onSelectPlayers`; `ShopPanel.lua` — `onTabChanged`
- `AppRoot.lua` — forwards those three as callbacks
- `LobbyQueue/{Protocol,Launch}.lua`, `LobbyQueueSubs.lua`,
  `LobbyQueue/Membership.lua` (effects now carry `player`/`leader`/`state`)
- `TeleportSubs.lua` (+ one shared `onRecovered`), `GameRoundSubs.lua`,
  `GameRound/Return.lua`, `CakeSubs.lua`, `CakeSimulationSubs.lua`,
  `CakeCycleSubs.lua`, `BodySubs.lua`, `UpgradeSubs.lua`, `TutorialSubs.lua`,
  `ShopSubs.lua`, `RewardGrantSubs.lua`
- `LobbySubsClient.lua`, `TutorialSubsClient.lua`, `ShopSubsClient.lua`,
  `UpgradesSubsClient.lua`, `CakeSubsClient.lua`
- `TutorialConfig.analyticsBeat` → `"tutorial-done"` (a catalog key)
- `tools/headless-sim/{build_sim.py,harness_head.lua,roblox_stub.lua}` —
  per-scenario module sets, a per-module `script` proxy, an AnalyticsService
  recorder, fake players, a `typeof` shim

## Decisions

- **A catalog, not log calls (ADR-0017).** Event names are the scarcest
  resource and are spent forever on first send. Code passes keys; `Validate()`
  reports occupancy at boot (41/100, 8/10) because exceeding a quota produces
  no error at the call site — Roblox just drops the event.
- **"Every tap" is ONE event name.** `ui_press` with the control id in a custom
  field. Identity is derived from the pressed Instance's Name inside the kit's
  press primitive, so a button is counted because it EXISTS, not because it was
  instrumented. Same shape as the existing `SetSoundHandler` injection.
- **`ui_dead_press` rides `InputBegan`.** A disabled GuiButton suppresses
  `Activated`/`MouseButton1Click` but still receives `InputBegan` — and that
  difference IS the signal ("they pressed, the game said nothing"). No `Active`
  value changed, so nothing sinks differently.
- **Priority + coalescing instead of dropping.** Bulk traffic may only touch
  the top half of the minute's bucket; 40 taps on one button collapse into one
  event carrying `value = 40` (the batching trick Roblox's own docs name).
  Whatever is still refused is counted and reported via `analytics_dropped`.
- **Rate limit ≠ unavailable.** The old code disabled the module on the first
  throw. That is right for Studio (three strikes, one warn) and catastrophic for
  a busy live server, where "too many events" is routine — so the two are told
  apart by the message and a rate limit only empties the bucket for a minute.
- **The session id crosses the teleport, as an ARRAY.** Numeric table keys are
  stringified over TeleportData (the warning already in `Net.lua`), so a
  userId-keyed map would miss silently and split every funnel. The destination
  adopts the id + cohort + flow index and suppresses steps it already passed.
- **Cohort comes from ProfileStore's `SessionLoadCount`, carried not
  recomputed.** A teleport is a profile load, so it reads 2+ for a brand-new
  player arriving in the game place. It also resolves AFTER the first beats, so
  onboarding calls are HELD until the profile lands rather than guessed at.
- **The onboarding funnel fires only for the `new` cohort.** It is lifetime and
  de-duped by Roblox; firing it for veterans doubles the budget for data that is
  thrown away.
- **The client asserts only what the server cannot see.** Difficulty, party
  size, START, slides, SKIP, hint dismissal, pad proximity, HUD-ready. Bites,
  purchases, arrivals and results are refused with a warn. R6 applies to
  telemetry: a modded client gains nothing by lying, but it can poison the
  dataset the design decisions come from.
- **The client selections matter most.** Difficulty and party size never reach
  the server unless START is pressed and accepted, so "chose hard, then walked
  away" was completely invisible. It is now steps 7–9 of the funnel, and the gap
  between `start-press` (client) and `countdown` (server) is exactly the set of
  players whose START did nothing.
- **Panel state is POLLED, not taken from `onPanelChanged`.** `AudioSubsClient`
  owns that callback key, `SetCallbacks` is last-writer-wins, and Audio sorts
  after Analytics — registering it would have silently unplugged the panel
  whoosh. A panel lives for seconds; a 4 Hz poll is exact enough.
- **Confusion is measured, not inferred.** `flow_step`'s value is the dwell on
  the previous step; `flow_stall` fires once when a step's patience budget is
  blown; `flow_abandon` on leaving mid-flow — but never while teleporting, which
  would make the healthiest path in the game look like its worst leak.
- **A `visit` funnel's first step opens a new attempt.** Found while
  cross-checking the catalog: without it, the first shop visit's seen-set
  suppressed every later visit, so the shop funnel would have reported one visit
  per session forever. Fixed in the engine rather than by asking every caller to
  remember a `BeginVisit`.
- **Two funnel slots left empty.** The 11th funnel is dropped silently, so the
  margin is the safety mechanism.

## Adversarial review (2026-08-02) — 5 CRITICAL, all fixed

The review earned its keep; several of these were invisible to 53 green checks.

1. **The drop report could disable all telemetry.** `Sink.ReportDrops` handed
   `LogCustomEvent` a POSITIONAL array where every other path builds a
   `CustomField0N` dict. Roblox's reflection throws on that cast; three throws
   trip the disable rule — so two minutes into every busy server, telemetry
   would have switched itself off with a warn blaming Studio. The harness could
   not catch it because the stub recorded `fields` verbatim: **the stub now
   enforces the Dictionary cast**, which is the durable half of the fix.
2. **Client strings became `Log.Once` KEYS.** `onceFired` is never cleared, so
   an attacker-chosen `beat.k` was unbounded server memory *and* an unbounded
   warn stream from an unauthenticated remote. All refusal keys are now a fixed
   string plus the player's own id, and no client text reaches a warn.
3. **The gym drain was a firehose.** `creditResult` runs at 8 Hz and banked on
   most ticks, emitting 2 uncoalesced events per tick — 16/s for ONE player
   against a ~2.5/s server allowance. A ten-second burn would have emptied the
   budget and starved every funnel step on the server for the rest of the
   minute: the instrumentation causing the exact undercount it exists to
   prevent. Ticks now accumulate and one event is emitted per gym SESSION,
   which is also the truer number ("what this trip was worth"). Flooring once
   at the end fixed a second bug free — sub-1 deltas were logging `amount = 0`.
4. **A client could assert its own purchase.** `clientFunnels` allow-listed
   whole funnels, and `shop`/`upgrades` both END in `bought`. Now per-STEP.
5. **Length-clamping is not cardinality-clamping.** Short-but-always-new field
   values would have exhausted the experience-wide 8000-unique-value budget in
   ~30 minutes and collapsed every breakdown in the game to "Other". Added a
   per-player distinct-value cap that folds the excess into `other`.

Also fixed from the WARN list: the coalescing flush ignored the priority
reserves (defeating the core of ADR-0017); the rate-limit "backoff" did not
back off (`admit` never consulted it); `ui_hold` was coalesced despite being a
duration; the `match` funnel's last step went out under the wrong session id
(the round id lives on the other server — it is now restored from the return
TeleportData); the `queue` funnel declared a session mode nothing implemented,
so only the FIRST pad visit per player was ever counted; `LocalAnalyticsService
.Init` used `Net.Remote` (an untimed `WaitForChild` that `pcall` cannot stop),
which could have hung the entire client bootstrap — including `ClientReady`,
which the server holds all initial state behind; an inline `onTabChanged`
closure in AppRoot defeated ShopPanel's `React.memo` and reconciled ~700
elements at bite rate; analytics calls on the bite / find / layer / upgrade
paths were unwrapped, and the upgrade one sat between the calorie spend and the
milestone save; `CakeCycleSubs`' group beat `return`ed instead of `continue`d on
one player's failure; the client's urgent flush (up to 4/s) exceeded the
server's 3/s admission, costing whole messages; onboarding beats held for a
loading profile were sent out of order; and `Session.Fields` allocated a fresh
table per bite.

Then the cross-check tool — strengthened to verify client assertions too —
immediately caught a regression the per-step allow-list had *just* introduced:
three matchmaking funnel steps (`difficulty`/`party`/`start`) that
`LobbySubsClient` still sends were no longer allow-listed, so they were being
written, sent and silently refused. It is now `tools/headless-sim/catalog_xcheck.py`.

## Bugs found and fixed along the way
- **The gym's MAIN path was never instrumented.** The pre-existing beat lived
  only in `burnAll` (instant burn / auto-gym); the gradual drain — what almost
  every player actually does — banked calories through `creditResult` and logged
  nothing. Both now share one `beatBank`.
- **`upgrade_bought` referenced an undefined `level`** in the first pass of the
  rewrite (should be `newLevel`); caught by the catalog cross-check script.

## Verification
- Luau syntax gate over `src/` and `tools/`: clean.
- `AnalyticsConfig.Validate()` standalone: 41/100 events, 8/10 funnels,
  31/100 steps, no problems.
- `tools/headless-sim/catalog_xcheck.py`: every `Event`/`Flow`/`Funnel`/
  `BeginVisit` key referenced anywhere in `src/` exists in the catalog, AND
  every key a client asserts is allow-listed.
- `tools/headless-sim/analytics_scenario.lua`: **66/66** checks — budget,
  priority reserves, coalescing (40 taps → 1 event, value 40), the trust
  boundary, teleport continuity, stalls/abandonment, recurring-funnel attempts,
  economy validation, unpublished-place shutdown, plus one block per CRITICAL
  from the review.
- The existing treasure and pacing scenarios still pass (harness changes are
  additive; `pacing_scenario` is now named in `MODULE_SETS` rather than relying
  on the fallback).
- **Not yet verified live in Studio/a published place** — see below.

## Open Questions / Followups
- **Studio playtest pending**: the console contract (catalog occupancy line,
  budget line, the disable-once warn) and one end-to-end lobby→game run to see
  the flow steps land in order. Analytics itself cannot report in Studio by
  design (published places only), so the beats are read from the `[Analytics]`
  log lines.
- **`ui_dead_press` depends on `InputBegan` firing on an inactive GuiButton.**
  Reasoned from how `Active` works (it governs sinking and `Activated`, not
  pointer events) and it costs nothing if wrong — but it is the one claim here
  that a live playtest should confirm.
- Two funnel slots are free. Candidates if needed: squishy/egg progression, and
  a settings/audio funnel.
- If a backend ever appears, the catalog is the place to add a second, unquota'd
  sink (ADR-0017 "alternatives rejected").

## Related
- Feature: `docs/features/analytics.md`
- ADR: ADR-0017 (new); touches ADR-0009 (two places), ADR-0002 (grant registry)
- Prior flow: `docs/flow/2026-08-01_onboarding-tutorial.md`,
  `docs/flow/2026-07-22_lobby-matchmaking-rounds.md`
