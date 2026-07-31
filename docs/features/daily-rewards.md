# Daily rewards

## What it does
A 1..N daily-login track: one claim per UTC day. The streak NEVER resets on a
missed day (position only advances on claim) and LOOPS to Day 1 after the
final day. Ported from Dices.

## Tuning (per game)
`src/server/lobby/data/DailyRewardsData.lua` — the single tuning point:
`daysCount` and `days[day] = reward descriptor`. Any kind works as soon as its
feature registers a handler in RewardGrantSubs.

The shipped week (7 days): **gems on 1 / 3 / 4 / 6**, a **boost on 2 and 5**,
and the untouched **day 7 = guaranteed Epic+ squishy** (`egg`, the headline
prize). Two rules the numbers encode, both worth keeping:
- **Gem amounts are a RATIO, not a feel.** They are sized against what one
  cleared cake pays (`features/treasures.md`), which is also what one boost costs
  (`features/boosts.md`) — a week of logins is deliberately a real step toward a
  boost rather than a rounding error. Retune the find table and this table is
  stale; the ratio, not the absolute, is the thing to preserve.
- **The two boost days spend the variety budget where a new player has no other
  way to try one**: bigger bites early (day 2, while the upgrade tree is still
  empty) and x2 calories later (day 5, once there is a run worth doubling).
⚠ A `boost` day's `boostId` must name a real `TreasureConfig.boosts` def —
`RewardsSubs.grantable` proves it BEFORE consuming the claim, because
`GrantBoost` answers an unknown id with `false` and the claim would be spent for
nothing. This table shipped `boostId = "golden-slice"` (a FIND id) once already.

## Flow
1. Join: `PlayerLifecycleSubs` pushes `DailyRewardUpdate`
   `{ day, claimable, nodes = ARRAY of {day, kind, amount...} }` only after
   BOTH the profile loaded AND the client fired `ClientReady` (end of
   LocalBootstrap) — otherwise the first sync is silently lost.
2. Client (`RewardsSubsClient`) re-keys the array into AppRoot state;
   `LocalRewardsService.BuildDailyCards` derives per-card state
   (claimable/tomorrow/claimed/locked; `claimable == false` marks the
   previous position "claimed today", which also handles the Day N → Day 1
   loop seam).
3. Claim: DayCard click (only "claimable" cards are Active) →
   `ClaimDailyReward` → server pre-checks the kind has a grant handler (a
   mistuned table must not eat the claim) → `DailyRewardService.Claim`
   validates + advances + returns descriptor (R3) → `RewardGrantSubs.Grant`
   credits it → fresh payload with `granted` → `PersistenceService.Save`.
4. Double-claim same UTC day: `Claim` returns nil → server resyncs the client.
5. Startup validation (deferred past all Starts): warns if `days` has gaps,
   entries outside `1..daysCount`, or kinds without registered handlers.

## State (profile section `dailyRewards`, see DailyRewardsSection.lua)
`day` (1..daysCount loop position), `lastClaimDay` (UTC day index, 0 = never).
Day index = `math.floor(os.time() / 86400)`.

## UI (kit-rendered — the old Studio-authored DailyRewardsGui path is retired)
`UIKit.RewardsPanel` (landscape grid strip) of `DayCard`s inside AppRoot; opened
from the HUD menu (`DailyRewards`); green badge on the HUD button while
claimable — since time rewards were deleted this is the **only** badge left in
the menu (`features/app-root.md`). Card states: claimable = gold accent +
clickable, claimed = green check, tomorrow/locked = dimmed.
⚠ A boost day renders per-`boostId` label + art from
`LocalRewardsService.BOOST_CARD` (one generic "x2 Boost" would advertise the
wrong perk now that there are four). **Adding a boost to `TreasureConfig.boosts`
means adding a row there too** — an unmapped id falls back to the generic card
and `Log.Once`s. The labels are short because the reward line sits in a ~96px
zone beside the art: **~9 characters** before it renders under 14px.

## Files
Server: `DailyRewardsData`, `ProfileSchema/DailyRewardsSection`,
`DailyRewardService`, `RewardsSubs`. Client: `RewardsSubsClient`,
`LocalRewardsService` (card view-model), AppRoot panel. Remotes:
`ClaimDailyReward`, `DailyRewardUpdate`.
