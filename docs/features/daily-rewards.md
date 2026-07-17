# Daily rewards

## What it does
A 1..N daily-login track: one claim per UTC day. The streak NEVER resets on a
missed day (position only advances on claim) and LOOPS to Day 1 after the
final day. Ported from Dices.

## Tuning (per game)
`src/server/data/DailyRewardsData.lua` — the single tuning point: `daysCount`
and `days[day] = reward descriptor`. Template ships gold-only; game-specific
kinds work as soon as their features register handlers in RewardGrantSubs.

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
`UIKit.RewardsPanel` (landscape grid strip, shared with time rewards) of
`DayCard`s inside AppRoot; opened from the HUD menu; green badge on the HUD
button while claimable. Card states: claimable = gold accent + clickable,
claimed = green check, tomorrow/locked = dimmed.

## Files
Server: `DailyRewardsData`, `ProfileSchema/DailyRewardsSection`,
`DailyRewardService`, `RewardsSubs`. Client: `RewardsSubsClient`,
`LocalRewardsService` (card view-model), AppRoot panel. Remotes:
`ClaimDailyReward`, `DailyRewardUpdate`.
