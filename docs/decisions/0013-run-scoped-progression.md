# ADR-0013 — Upgrades and calories are RUN-scoped, not permanent meta

Date: 2026-07-30
Status: Accepted
Changes the progression half of ADR-0011 (the cake-side pacing curve stands).

## Context

By request: *"when entering the lobby or starting a new cake-eating run, all
upgrades and core features should reset. Only meta-progression should carry
over"*, and *"the progression should be balanced so that players can unlock every
upgrade by the time they have eaten half of the cake."*

The shipped design was the opposite: the 44 upgrade tiers were permanent, priced
at **16,019,500** calories in total, against a run that earns ~1.6 M. Measured
consequences (`tools/balance-model/pacing.py`, 3 seeds, solo easy):

- a run ended owning **21 of 44 tiers** — the tree paid out over ~20 runs;
- eat + gym time was **54.6 min**, and a real playtest reported **1 h 01 m**
  against a documented target of 40;
- the deepest half of every cake was therefore played at roughly the power the
  player started with.

The "40 min" in the docs came from a model that never simulated a player *buying
tiers mid-run*; the two published endpoint measurements (126 min fresh, 33 min
maxed) cannot be interpolated to it. Nothing had actually measured the run people
play.

## Decision

**The upgrade tree and the spendable calorie balance are RUN state.** Both are
wiped on every profile load — which is both halves of the request, because the
lobby↔game handoff releases and reloads the profile on each teleport (ADR-0009).

| Resets each run | Carries over (META) |
|---|---|
| `upgrades.levels` (all 44 tiers → 0) | `economy.gems` |
| `economy.calories` | `pets.owned` / `.equipped` (squishies) |
| `stomach.fill` / `.stored` + any open gym session | quests, daily/time rewards |
| | shop purchases + gamepass ownership |
| | timed boosts (`progress.activeBoosts`) |
| | every `progress.lifetime*` stat |

⚠ `progress.lifetimeCalories` is a **different field** from `economy.calories`.
The leaderboard and the `burn-calories` quest read the lifetime stat, so the run
reset must never touch it. No live reward grants raw calories (checked: daily,
time, codes and finds pay gems / eggs / boosts), so resetting the balance
destroys nothing earned or purchased.

Mechanics:

- `UpgradeService.ResetTiers` / `EconomyService.ResetCalories` /
  `StomachService.SetBelly(0, 0)`, orchestrated by the new common
  `RunResetSubs`, flagged by `UpgradeConfig.run`.
- It runs from a **new `OnProfileLoaded(player)` lifecycle hook**, discovered by
  `PlayerLifecycleSubs` exactly like `PushInitialState` but fired earlier —
  after the profile loads, before anything is replicated. Resetting from a
  `PushInitialState` hook would have raced `EconomySubs`/`UpgradeSubs`, which
  sort earlier alphabetically and would have pushed the pre-reset values with no
  later correction.
- No profile migration: the section SHAPES are unchanged, only the values (P2).

**Re-priced to the new target.** The whole tree costs **772,250** (a ~20×
cut); tier VALUES are untouched, because the power curve was never the problem —
the price of reaching it was. `instantBurn` is scaled a further ×0.35 because at
a flat scale its 4 tiers were 48% of the entire tree, so one gym-convenience
stat crowded out everything that touches the cake. Difficulty
`workMultiplier`s rose ×1.08 (easy 1 → 1.08) to absorb the speed-up from
finishing the tree early.

Measured (`--candidate`, since RETIRED — it froze this proposal's costs while
reading every other value live, so after ADR-0019 it measured a config that never
existed; 5 seeds, solo easy): **clear 38.9 min**, whole tree
owned at **46% of the cake** (5/5 seeds) around the 27-minute mark.
⚠ SUPERSEDED 2026-08-05 by ADR-0019 (the belly-fill curve): the tree total is now
755,260, tier-1 prices are ~0.55× with a steeper 3.4 per-tier ratio, and the
re-measured run is **35.3 min / 48% of the cake**. The 50%-of-cake target itself is
unchanged.

## Consequences

- The run is a roguelite arc: start as a base eater, be maxed by half the cake,
  spend the back half strong. That is what pulls the clear time down without
  making the cake smaller.
- The upgrade tree has **no HUD button in either place**. `AppRoot`'s meta menu is
  `Visible = showLobby`, so the button only ever existed in the LOBBY — where a
  run-scoped tree has nothing to spend — while the tree's real opener, the
  checkpoint computer's `UpgradeStation` ProximityPrompt, was live in the game
  place the whole time. You are stood at the checkpoint after every belly burn, so
  that is already where the purchase decision happens.
  (The first cut of this change added a game-place button on the strength of a
  stale doc line — "re-enabling the game checkpoint computer's prompt" — which
  reads as if that prompt were disabled. `MapService.buildCheckpoint` constructs it
  enabled with `HoldDuration = 0`. Two greps would have settled it; the doc was
  believed instead of the code. `LocalUpgradeTree.AnyAffordable` is the leftover:
  kept, not wired.)
- **Long-term progression is carried entirely by gems, squishies and
  gamepasses.** Equipped squishies (calories / eatSpeed / gems bonuses) are the
  only permanent power. That is a deliberate consequence, and the thing to watch:
  if runs start feeling identical, the answer is more meta depth on that side,
  not re-persisting the tree.
- A player who buys tiers and then leaves loses them. Acceptable and intended —
  a run is the unit of progress — but it means the tree must stay cheap enough to
  rebuild, so **cost changes are now coupled to the 50%-of-cake target** and
  should be re-measured, not eyeballed.
- `UpgradeConfig.run.resetOnLoad = false` restores permanent-meta behaviour in
  one line if this proves wrong.

## Alternatives rejected

- **Reset the tiers but keep the calories.** Pointless: the player instantly
  re-buys the same tree, so nothing resets in practice.
- **Reset only on lobby entry, not on match start.** Same thing in this
  architecture (every match arrival is a fresh profile load), and it would have
  needed a second, place-aware code path to express it.
- **Keep the tree permanent and just cut the costs** to hit "all upgrades by half
  a cake". Then the tree is maxed forever after the first run and every later run
  starts with nothing left to buy — the calorie sink the loop is built around
  disappears, which is the failure the 2026-07-26 pass had already fixed once.
- **A separate per-run currency alongside permanent calories.** Two currencies
  for one sink, a second UI to explain, and the profile field would still need
  resetting. No benefit over resetting the one that exists.
