# Economy (calories + gems)

## What it does
Two currencies in profile section `economy` (v2; v1 `gold` migrated → gems):
- **calories** — soft. Earned ONLY by gym burns (`BodySubs` payout) and
  `calories` reward descriptors; spent on upgrades/rebirth; WIPED on rebirth.
- **gems** — hard, persistent. Finds, quests, codes, gem packs.

`EconomyService`: Get/Add/TrySpend per currency + `ResetCalories` (rebirth).
Adds floor and reject ≤0; TrySpend is atomic check+deduct.

## Replication
`CurrencyUpdate` carries BOTH balances `{calories, gems}`. Pushed on join
(`EconomySubs.SendCurrency`); earn/spend flows re-push after coordinating
EconomyService (grant handlers, UpgradeSubs, BodySubs, RebirthSubs).

## Multipliers
Earning multipliers live in StatsService (see `features/upgrades.md`).
Reward kind `gems` applies GemsMult unless `rawAmount = true` (paid packs).

## Rules
All mutation through EconomyService — never touch `profile.economy.*`
elsewhere. Services never fire remotes (R3/R4).

## Files
`ProfileSchema/EconomySection`, `services/EconomyService`,
`subscriptions/EconomySubs`, `remoteUpdates/CurrencyUpdate.model.json`,
client `EconomySubsClient` (HUD pills).
