# Analytics — the retention instrumentation

## What it does
Retention is a fact about players, not about the build, so it cannot be measured
offline. It CAN be made visible. `AnalyticsSubs` is the ONE place that talks to
`AnalyticsService` (R4) and owns three things:

| Signal | Call | Why |
|---|---|---|
| **Onboarding funnel** | `LogOnboardingFunnelStepEvent` | Roblox reports these against D1/D7 retention in the Creator Dashboard. Where first-session players stop is where retention leaks. |
| **Time per place leg** | `LogCustomEvent "place_minutes_<lobby\|game>"` on `PlayerRemoving` | The 30-minute target, measured instead of modelled — but per LEG, see below. |
| **Loop counters** | `LogCustomEvent` | Denominators. "Reached step 3" means little without "how many finds does a retained player dig in session one". |

## The funnel
The first-session beats, in the order a healthy player hits them. Logged **once
per player per step**; anything a player never reaches is where onboarding leaks.

| Step | Name | Fired from |
|---|---|---|
| 1 | Joined | `AnalyticsSubs` (`PlayerAdded`) |
| 2 | First Bite | `CakeSubs` — after the bite passes auth + the rate limit (the honest "is playing" moment) |
| 3 | First Find Collected | `CakeSimulationSubs` — after the reward actually grants |
| 4 | First Layer Cleared | `CakeSimulationSubs` — on the layer-gate step down |
| 5 | First Fat Burned | `BodySubs` — when a burn banks > 0 calories |
| 6 | First Upgrade Bought | `UpgradeSubs` — after the spend succeeds |

Counters alongside: `find_collected`, `layer_cleared`, `gym_banked` (value =
calories), `upgrade_bought`, `place_minutes_lobby`, `place_minutes_game`.

## ⚠ A leg is not a session
The game is two places (ADR-0009), and **every lobby↔game teleport ends the
player on this server and starts a fresh one on the next** — so a per-server
timer can only ever measure one LEG. A single `session_minutes` would report a
30-minute session as "3 + 26" and quietly halve the headline number.

So the legs are logged separately and named for what they are:

| Event | Read it as |
|---|---|
| `place_minutes_game` | **The engagement number.** Time actually playing one round. This is what the 30-minute target is measured against. |
| `place_minutes_lobby` | Queue/menu overhead. Rising here without `place_minutes_game` rising = matchmaking is the leak. |

For true cross-place session length use **Roblox's own built-in engagement
metric** — it already aggregates over the universe. Do not rebuild it here; a
hand-rolled total would need the join anchor carried through `TeleportData` and
would still be less accurate than the one Roblox gives away.

Timing uses `os.time()`, not `os.clock()` — Roblox documents `os.clock()` as CPU
time used by Lua, which on a mostly-idle server runs behind wall time and would
under-report. Whole seconds is ample for a minutes-scale stat.

## Contract
- Other subscriptions push beats IN through the registry
  (`subscriptions.AnalyticsSubs`, the ADR-0009 coupling pattern). This module
  never reaches into a domain itself.
- Every caller treats it as **optional** — `if AnalyticsSubs then` — and warns
  once if it is missing (R8). Telemetry must never take a gameplay path down.
- Every call is `pcall`-wrapped. `AnalyticsService` throws on an unpublished
  place; the first failure disables the module for that server and warns ONCE,
  so Studio does not spam.

## Gotcha
`LogOnboardingFunnelStepEvent` has no session id — it is per PLAYER, lifetime,
and Roblox de-dupes server-side. The local `reached` set only avoids the wasted
call; it resets per server, which is correct (a returning player has already
passed those steps and Roblox ignores the repeat).

## Files
`src/server/common/subscriptions/AnalyticsSubs.lua`; beats pushed from
`CakeSubs`, `CakeSimulationSubs`, `BodySubs`, `UpgradeSubs`.
