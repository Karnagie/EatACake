# Time rewards (playtime-today track)

## What it does
Milestones claimed as the player accumulates playtime DURING the current UTC
day; accrued seconds + claimed set reset at the day boundary (lazy rollover on
every service entry point; mid-session boundary re-anchors the live session).

## Tuning
`src/server/data/TimeRewardsData.lua`: `milestones[index] = {seconds, reward}`,
`count`, `flushInterval`. Rewards = descriptors (ADR-0002).

## State
Profile section `timeRewards` (`TimeRewardsSection.lua`): `day`, `today`,
`claimed` (int-keyed, in `intKeySets`; sanitize strips non-int keys). The live
session anchor is RUNTIME-only in `TimeRewardsData.sessionStarts` — persisting
it would corrupt `today` after a crash (schema persistence saves everything in
the profile).

## Flow
Join: `PlayerLifecycleSubs` → `TimeRewardService.BeginSession` +
`RewardsSubs.SendTime` (ClientReady-gated). Every `flushInterval`s a loop in
`RewardsSubs` folds live time into the profile (ProfileStore autosave then
snapshots it). Leave: `EndSession` before `Unload`.
Claim: card click → `ClaimTimeReward(index)` → HasHandler pre-check →
`TimeRewardService.Claim` (reached + unclaimed) → `RewardGrantSubs.Grant` →
fresh `TimeRewardUpdate` with `granted` → `PersistenceService.Save`.
Invalid claim → resync.

## Payloads
`TimeRewardUpdate` = `{ secondsToday, claimed = ARRAY, nodes = ARRAY of
{index, seconds, kind, amount...}, granted? }` (arrays: RemoteEvent int-key
stringification). Client re-keys and runs a LIVE clock:
`secondsToday + (os.clock() - receivedClock)`; a 1s ticker re-renders while
the panel is open (AppRoot), countdowns land on 0:00 and flip to Claim.

## UI
Kit panel `UIKit.RewardsPanel` (shared with daily) of `DayCard`s; card title =
threshold clock, sub = countdown/state; HUD badge when any milestone is
reached & unclaimed (`LocalRewardsService.AnyTimeClaimable`).

## Files
Server: `TimeRewardsData`, `TimeRewardsSection`, `TimeRewardService`,
`RewardsSubs` (shared with daily). Client: `RewardsSubsClient`,
`LocalRewardsService`, AppRoot panel. Remotes: `ClaimTimeReward`,
`TimeRewardUpdate`.
