# ADR-0017: Analytics is a budgeted catalog, not a set of log calls

## Status
Accepted (2026-08-02)

## Context
The ask was to instrument the whole game and, above all, the initial player
flow: "literally every tap and action should be tracked and visible, so I can
clearly understand where players get confused, what they fail to understand,
and which actions they do not complete."

The obvious implementation — call `AnalyticsService:LogCustomEvent` wherever
something happens, with a descriptive event name — cannot work here, and it
fails **silently**, which is the dangerous part. Verified 2026-08-02 against
`create.roblox.com/docs/production/analytics` (event-types, custom-events,
funnel-events) and the Roblox staff answer in devforum thread 3084051:

| Quota | Limit |
|---|---|
| Rate limit | **120 + (20 × CCU) events per minute, per server** |
| Custom event names | **100** per experience (cardinality; resets daily) |
| Funnels | **10 names × 100 steps** |
| Custom fields | **3 per event**; 8000 combined unique VALUES before "Other" |
| Economy | 10 currencies, 20 transaction types, 100 SKUs |
| Retention | 90 days from last data received |
| Where | **Server only, published places only** |

Three consequences drive everything below.

1. **A solo game server is allowed ~140 events/minute**, a bit over two per
   second. A player mashing the EAT button and walking a HUD full of buttons
   generates ten times that. Sending anyway does not raise the limit: Roblox
   drops the overflow and the dashboard shows an undercount indistinguishable
   from a real one.
2. **Event names are the scarcest resource, field values are cheap** — Roblox's
   own guidance is "use custom fields whenever possible instead of event names,
   since there is a much tighter cardinality limit on event names". One name
   per button would exhaust the budget for the whole experience, forever, on
   one screen.
3. **The client cannot log at all**, yet every tap happens there — and the game
   is two places (ADR-0009), so a player's first session is split across two
   servers by a teleport that lands in the middle of the funnel.

## Decision

**One catalog.** `Shared.config.AnalyticsConfig` declares every funnel, every
step, every event name and every rate constant. Code passes catalog KEYS, never
literals, and `Validate()` runs at boot and reports the catalog's occupancy
against the quotas (R8) — because a catalog over quota produces no error at the
call site, just a metric that never appears.

**"Every tap" is one event name.** `ui_press` carries the control id in a
custom field. Identity is DERIVED from the pressed Instance's own Name inside
the kit's press primitive, so a button is counted because it exists, not
because someone instrumented it. `ui_dead_press` is the same for a press on a
DISABLED control — the player tried and the game did not answer.

**The budget is spent deliberately.** `Analytics/Sink` holds a token bucket
refilled at the live allowance (recomputed from the player count, since the
allowance grows with CCU), with three priority tiers and reserves. A funnel
step happens once and cannot be reconstructed; the ten-thousandth bite can. So
bulk traffic may only touch the top half of the bucket, and whatever is refused
is COUNTED and reported through `analytics_dropped`.

**Density is paid for by coalescing, not by dropping.** Identical
(event, fields, player) tuples inside a short window collapse into one call
carrying the count as the event's `value` — the batching trick Roblox's own
docs name. Forty taps on one button cost one event, which is what makes "track
every tap" affordable at all.

**The funnel spans the teleport.** The analytics session id is minted in the
lobby and carried in the launch `TeleportData` (and in the return payload), so
`PlayerFlow` is ONE funnel from "joined" to "returned to lobby" across two
servers. It is an ARRAY of per-player entries, not a userId-keyed map, because
teleport data stringifies numeric keys.

**The client is trusted only with what the server cannot see.** It may assert
that a popup rendered, a difficulty was selected or SKIP was pressed
(`clientFlowSteps`); it may not assert a bite, a purchase, an arrival or a
match result. The funnel allow-list is per STEP, not per funnel — `shop` and
`upgrades` both end in a conversion step, so a funnel-wide list would have let
a client assert its own purchase. Its beats are batched, bounded and
rate-limited like any other remote (R6) — a modded client gains nothing by
lying to analytics, but it can poison the dataset the game's design decisions
are made from.

Two bounds that are easy to miss because they are not about volume:
**cardinality** (a short but always-new field value exhausts the
experience-wide 8000-value budget and collapses every breakdown to "Other", so
distinct values are capped per player), and **log keys** (`Log.onceFired` is
never cleared, so no client-supplied string may ever become one).

**Confusion gets its own signals.** Every flow step carries a patience budget;
blowing it emits `flow_stall` once. Every step's `flow_step` value is the
seconds spent on the PREVIOUS step. Leaving mid-flow emits `flow_abandon` —
but never while teleporting, which is the flow continuing elsewhere.

## Consequences

- Adding a metric means adding a catalog entry, not a call with a new name.
  Slightly more ceremony, and the quota can no longer be exceeded by accident.
- Bulk metrics (taps, bites) are explicitly best-effort on a saturated server,
  and say so in-band. Funnels, economy and match lifecycle are not.
- Two funnel slots are left deliberately empty: exceeding ten drops the excess
  silently, so the margin is the safety mechanism.
- The instrumentation is verifiable without Studio:
  `tools/headless-sim/analytics_scenario.lua` runs the real Sink/Session/Ingest
  modules against a stubbed AnalyticsService and asserts the budget, the
  priority reserves, the coalescing, the trust boundary and the teleport
  continuity (66 checks), and `catalog_xcheck.py` statically proves every call
  site's keys exist and every client assertion is allow-listed. The stub
  enforces the custom-fields Dictionary cast — a stub that records arguments
  verbatim lets a malformed field table pass 53 green checks and throw live.
- **A hot loop must accumulate, not log.** The gym drain runs at 8 Hz; logging
  per tick spent six times the whole server's allowance on one player. Any
  future per-tick metric follows the same shape: accumulate, emit once per
  bounded episode.
- The pre-catalog API (`Onboard`/`Count`) survives as a deprecated shim that
  maps onto the catalog, so a missed call site degrades into the right metric
  rather than a warning.

## Alternatives rejected

- **One event name per action.** Exhausts the 100-name experience-wide budget
  and cannot express "which button" without exhausting it faster.
- **Send everything and let Roblox sort it out.** The platform drops the
  overflow with no signal at the call site; the result is a confident
  undercount, which is worse than a known gap.
- **A second, self-hosted pipeline over HttpService.** Full fidelity, but it
  needs a backend the project does not have, and the data would live somewhere
  the Creator Dashboard cannot join it to retention. Revisit if a backend
  appears; the catalog is the natural place to add a second sink.
- **`session_minutes` as one number.** A teleport ends the player's server
  session, so a per-server timer measures one LEG. The legs stay separate
  (`place_minutes_lobby` / `place_minutes_game`) and Roblox's own engagement
  metric already reports true cross-place session length.
