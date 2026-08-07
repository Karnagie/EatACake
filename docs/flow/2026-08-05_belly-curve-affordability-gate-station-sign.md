# 2026-08-05: Belly curve, affordability gate, station sign

Tags: upgrades, body-gym, tutorial, cake-cycle, balance, config, ui, tooling, analytics

## Task

Three user requests, verbatim:

1. "In the tutorial/start flow, the player should be prompted to burn fat not when
   the meter is almost full, but when they can afford the bite radius upgrade."
2. "Rebalance the game slightly and make the progression more noticeable. For
   example, at the beginning, the player should need to burn fat every 10 seconds.
   After the first upgrade, this should increase to every 30 seconds, then to every
   1 minute 30 seconds, so the progression feels more visible."
3. "In `ReplicatedStorage.Assets.Checkpoint.UpgradeStationBody.AvailableGui.Txt`,
   display how many upgrades the player can currently purchase."

## Context

- `features/upgrades.md` (hex tier tree, RUN-scoped, ADR-0013),
  `features/body-gym.md` (belly → gym loop), `features/tutorial.md` (5-step
  onboarding, ADR-0016), `features/checkpoint.md` (the authored station).
- The belly→gym rhythm was documented as a deliberate constant (~90 s, ADR-0011)
  and `capacity` grew 4× across the tree to "lengthen the stretch as you get
  stronger".
- `AvailableGui` is authored place content with the placeholder text
  "6 Available"; nothing in `src/` referenced it.

## Plan

Measure before touching anything: instrument `tools/balance-model/pacing.py` to
report seconds-of-eating per belly bucketed by capacity tier, confirm or refute
the complaint, then solve the capacity curve against the user's three target
intervals with a fixed-point iteration, and re-price only as much as the new
curve forces. Implement the two client asks around ONE shared affordability
predicate so the sign can never promise a purchase the tree then refuses.

## Changes

**Created:**
- `src/client/common/subscriptions/UpgradeStationSubsClient.lua` — the world
  "N Available" sign (game-place gated, 2 Hz poll, explicit-chain resolve).
- `docs/decisions/0019-belly-interval-is-the-progression-curve.md`

**Modified — game:**
- `src/shared/config/UpgradeConfig.lua` — capacity base 84000 → **4400** and the
  whole tier ladder re-solved; `burnSpeed` base 0.06 → **0.20**; every stat's
  tier-1 cost ~0.55× with the per-tier ratio 3.1 → 3.4 (tree 772,250 → 755,260).
- `src/shared/config/TutorialConfig.lua` — new `burnPromptStat = "biteRadius"`;
  `bellyThreshold01` re-documented as the SAFETY NET (value unchanged, so the
  server's `belly-full` analytics beat does not move).
- `src/client/common/subscriptions/TutorialSubsClient.lua` — step 3 fires on
  affordability (`calories + floor(stored × gymEff) >= cost`), belly as fallback;
  evaluated from both the `StomachUpdate` handler and the existing throttled tick.
- `src/client/common/modules/LocalUpgradeTree.lua` — `AffordableCount` (new),
  `CanAffordNext` (new), `AnyAffordable` now a wrapper (it had no caller since
  2026-07-30; it has two now).
- `src/client/common/modules/LocalStatsService.lua` — `GymEfficiency()`.
- `src/client/common/data/UpgradesUiData.lua` — `["station"]` world contract.
- `src/client/common/data/LocaleData.lua` — `station-available` = "{n} Available".
- `src/server/game/subscriptions/BodySubs.lua` — comment only: the shared-threshold
  claim was made false by ask 1.
- `src/client/common/subscriptions/EconomySubsClient.lua`,
  `src/server/common/data/ProfileSchema/EconomySection.lua` — stale header claims
  ("calories tick on every bite", "calories never reset") corrected.

**Modified — tooling:**
- `tools/balance-model/pacing.py` — **bite-math bug fixed** (below), mirrored
  upgrade table re-synced, `fills` instrumentation + `--intervals` report.
- `tools/headless-sim/pacing_scenario.lua` + `build_sim.py` — eater stats now READ
  `UpgradeConfig` instead of being hardcoded; new section **D) ONBOARDING GATE**
  asserting the affordability margin; section B's conclusion rewritten.

**Docs:** `features/upgrades.md` (rewritten Progression + new sign section),
`features/body-gym.md`, `features/tutorial.md`, `features/cake-cycle.md`,
`features/game-round.md`, `decisions/0011` + `0013` (supersession notes),
`registries/data-keys.md` (locale key + a new "authored world-instance contracts
read by the client" table), `MAP.md`.

## Decisions

**The complaint was structurally right, and the curve ran backwards.** Measured on
the shipped config: 227 s per belly at tier 0 falling to 102 s at tier 5. Capacity
grew 4× while eating power grew ~20×, so every purchase made the interruption
*more* frequent. Full reasoning, the solved table and the rejected alternatives are
in ADR-0019.

**Found: the balance model had a real bite-math bug, and it had been wrong the
whole time.** `Field.apply_bite` clamped the WHOLE bite window to the band floor
(`np.maximum(floor_units, sub_h - delta)`), which raised every out-of-cake cell in
the window from 0 up to the floor and counted the rise as *negative* removed
volume. Every bite whose disc touched the loaf rim under-reported food; the opening
bites (a flat cake makes `argmax` tie-break to the lowest index — the rim) reported
tens of thousands of food units NEGATIVE. Lua has no such bug: `CakeOps.ApplyBite`
iterates only the cells it selected. Fixing it moved the live-config clear time
from a nonsense 50.4 min to **39.0 min**, which is what the published 38.9 min
always claimed — so the number was right and the model that produced it was not.

**Found: commit `1c21a15` ("123") hand-tuned `biteRadius` base 3.4 → 2.4 and
`biteDepth` 3.6 → 2.6 and pushed their top tiers up, and nothing downstream was
updated.** The python model's mirror, `pacing_scenario.lua`'s hardcoded eater, and
four doc claims ("base 3.4", "~7.6-stud spoonful", "~2.4× eating power") were all
left describing an eater the game does not ship. Both models are now config-driven
or sync-checked; the docs are repaired. **This is why the drift guards exist and
why the hardcoded copy in the Luau scenario was worth deleting.**

**The tutorial gate must test UNBANKED calories.** `RunResetSubs` wipes
`economy.calories` on every profile load, and the only thing that banks calories is
the gym trip step 3 exists to prompt — so a gate reading the banked balance can
never fire. It reads `calories + floor(stored × gymEff)`, the exact figure
`GymService` will bank.

**The belly threshold stays as a safety net rather than being replaced.** The
affordability margin is only ×1.36 (a full base belly of frosting is worth ~612
calories against a 450 cost). If a future re-price closes that, the player would
sit at a full belly that refuses to eat with no guidance at all — the worst state a
first session can reach. The net costs four lines; `pacing_scenario.lua` section D
now fails the build before it can matter.

**The sign POLLS AppRoot instead of listening to the remotes.** Both updates that
move the count are consumed by other subscriptions that write into AppRoot, and
client subs Start alphabetically — `UpgradeStationSubsClient` connects *before*
`UpgradesSubsClient`, so a handler on the same remote would render one push behind
forever. A 2 Hz read has no ordering hazard and is needed anyway for the instance
(place content replicates late).

**The sign counts STATS the player can PAY for, not a greedy spending sequence** —
a sign promising "7" over a tree you can only buy 3 things from is a lie the player
can see. It shares `LocalUpgradeTree.AffordableCount` with the tree's Buy button
and category badge, so the sign can never over-promise. ⚠ It is deliberately NOT
the gold-hex count: a hex is gold when it is the next UNLOCKED tier, which has to
show its price before you can afford it, so gold hexes ≥ the sign's N. (Caught by
review — the first draft of these comments asserted the two could never differ.)

**Clear time moved 38.7 → 35.3 min and MatchConfig was deliberately left alone.**
The delta is EAT time (33.4 → 29.6 min), not the gym — total gym time actually rose
0.4 min, since there are two more trips and each is much shorter. Halving the
tier-1 prices is what did it: the eating stats reach the player minutes earlier and
clear cake faster for the rest of the run. A `workMultiplier` bump to claw the 3.4
minutes back would have re-shifted the interval curve that had just been solved and
compressed the easy/medium spacing.

## Review

Closed with a four-lens adversarial review (correctness / balance / project rules /
tooling), every finding independently refuted before being reported: **17 confirmed,
10 refuted**. All 17 fixed. The three that were real defects rather than stale prose:

1. **The clear-time win was attributed to the wrong half of the loop.** The config
   header, the ADR and this doc all said "the whole delta is the faster gym". It is
   the opposite: gym time went UP 0.4 min (two more trips, each much shorter) and
   the entire 3.4-minute win is EAT time, bought by the halved tier-1 prices putting
   the eating stats in the player's hands minutes earlier. Corrected in all four
   places — an inverted causal claim in a tuning header is how the next rebalance
   pulls the wrong lever.
2. **"The sign and the tree can never disagree" was false.** A hex is gold when it
   is the next UNLOCKED tier (`owned == tier - 1`) — `LocalUpgradeTree.BuildTree`
   never reads the balance — so at 300 calories the tree paints nine gold hexes
   while the sign says 2. The predicate IS shared with the Buy button and the
   category badge, which buys the one-way guarantee that actually matters (the sign
   can never over-promise); the comments now say that instead.
3. **The station-name guard could not catch a missing key.** It iterated a table
   built from the locals, and a nil value creates no key, so `pairs` skipped exactly
   the drift it existed for. Now iterates key NAMES and indexes the config.

Plus, in the tooling: `--intervals` reported means while every doc quoted the
first-belly-after-purchase figure (it now prints both, labelled); the end-of-run
PARTIAL belly was being counted as a fill, dragging the top tier's mean down ~9%;
`check_config_sync` did not cover `caloriesMultiplier` or `middlePool`; the
`--candidate` flag had become a proposal to REVERT this rebalance (retired); and
`validate()`'s new banner crashed the whole report on a stock Windows console
because `⚠` is not in cp1252.

⚠ **One WARN is NOT mine and is deliberately untouched**: `ShopData.products
["layer-eater"].devProductId = 3613094133` (uncommitted, from the 2026-08-04 task)
is a LIVE id on a money path, while `tools/monetization/id_map.json`,
`docs/recipes/publish-readiness.md` and `features/checkpoint.md` all still say the
product is PENDING/0. `ShopSubs` will happily
`PromptProductPurchase(player, 3613094133)`. Either the id is real and three docs
plus the ledger are stale, or it is a placeholder pointing at somebody else's
product — the answer is outside the repo. Flagged, not guessed at.

## Open Questions / Followups

- **Studio playtest still pending.** Specifically: (a) does the body morph
  inflate/deflate every ~10 s early on read as feedback or as thrash; (b) the sign
  updates and hides at 0; (c) `trip_seconds = 14` in the model is a playtest
  observation from when bellies were 3 minutes apart — at a 10 s belly it dominates
  the early loop, so the real F-teleport round trip is worth re-timing; (d) the
  early game now takes ~6 gym trips in the first two minutes, each firing a
  milestone `PersistenceService.Save` — watch for DataStore throttle warnings.
- **4-player co-op measured** (`work ×2.70`, `calories ×2.86`): the curve still
  stretches — first belly per tier **9 / 23 / 61 / 112 / 124 / 188 s** — so the
  progression reads the same way with a party. The onboarding gate only gets
  easier (co-op multiplies calories per food, never divides).
  ⚠ Noticed while measuring, **pre-existing and NOT introduced here**: in a
  4-player match the tree completes at **12%** of the cake (old tuning: 10%),
  because `coopCalories` (×2.86 at 4 players) outruns `coopWork` (×2.70) *and*
  every player earns it. The ≤50% target is a solo number and co-op has never come
  close to it. Worth a decision — it is a balance question, not a bug in this
  change-set.
- `tools/balance-model/README.md` still says the Luau CLI "was not installed" — it
  is now (`luau`, `luau-compile` on PATH), so the two tools can finally be
  cross-checked properly.

## Related
- Feature: `docs/features/upgrades.md`, `docs/features/body-gym.md`,
  `docs/features/tutorial.md`
- ADRs: **ADR-0019** (new), supersedes in part ADR-0011 and ADR-0013's numbers
- Prior flow: `docs/flow/2026-07-30_run-scoped-progression-pacing-ui.md`,
  `docs/flow/2026-08-01_onboarding-tutorial.md`,
  `docs/flow/2026-07-26_cake-pacing-rebalance.md`
