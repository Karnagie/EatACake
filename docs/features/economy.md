# Economy (calories + gems)

## What it does
Two currencies in profile section `economy` (v2; v1 `gold` migrated → gems):
- **calories** — soft, **RUN-scoped** (ADR-0013). Earned ONLY by gym burns
  (`BodySubs` payout) and `calories` reward descriptors; spent on upgrades.
  **Wiped on every profile load** — entering the lobby AND arriving in a match —
  by `RunResetSubs` via `EconomyService.ResetCalories`. Resetting the tiers
  without the balance would be pointless (you would instantly re-buy the tree).
  A bite's contribution is `removed volume × the band's density × layer.calories
  × the cake's payoutScale` (difficulty premium × per-head co-op payout) — see
  `features/cake-cycle.md`.
- **gems** — hard, persistent. Sources: buried finds (the main faucet), daily
  rewards, codes, paid gem packs.

⚠ **`economy.calories` is NOT `progress.lifetimeCalories`.** The lifetime stat
(`ProgressService.AddStat`, written alongside every gym bank) is permanent and
feeds the leaderboard; the run reset must never touch it. Checked when the reset
landed: no live reward table grants raw calories (daily/codes/finds all pay gems,
eggs or boosts) and the shop sells calorie MULTIPLIERS, not balances — so a
per-run wipe destroys nothing earned or paid for. Adding a `calories` reward or a
calorie pack would change that; price it as run fuel or make it grant gems
instead.

`EconomyService`: Get/Add/TrySpend per currency, plus `ResetCalories` (run wipe).
Adds floor and reject ≤0; TrySpend is atomic check+deduct — `TrySpendGems` is
what the gem shop path charges with, and it must stay atomic for the reason
`features/shop.md` records.

## Gems finally have a SINK (2026-07-31)
Until the gem-priced boosts row shipped, gems were earned and never spent — a
currency with a faucet and no drain. The boosts are now the drain
(`features/shop.md` for the purchase path, `features/boosts.md` for the price and
what each boost does), and **buried finds are the faucet that price is calibrated
against** (`features/treasures.md` owns the payout table; the per-head co-op
scaling that keeps the rule true in a party is `findPayoutScale`,
`features/cake-cycle.md`). Do not restate any of those figures here: three copies
of one number is three chances to drift.

## Replication
`CurrencyUpdate` carries BOTH balances `{calories, gems}`. Pushed on join
(`EconomySubs.SendCurrency`); earn/spend flows re-push after coordinating
EconomyService (grant handlers, UpgradeSubs, BodySubs, ShopSubs' gem path).
⚠ **A SPEND pushes nothing by itself.** `RewardGrantSubs` pushes
`CurrencyUpdate` when it GRANTS; every path that DEDUCTS must call
`EconomySubs.SendCurrency` itself or the HUD pill stays stale until the next
earn. Every new spend path has to remember this.

## Multipliers
Earning multipliers live in StatsService (see `features/upgrades.md`); a live
timed boost multiplies `calories`/`gems` on top of them (`features/boosts.md`).
Reward kind `gems` applies GemsMult unless `rawAmount = true` (paid packs).

## Rules
All mutation through EconomyService — never touch `profile.economy.*`
elsewhere. Services never fire remotes (R3/R4).

## Files
`ProfileSchema/EconomySection`, `services/EconomyService`,
`subscriptions/EconomySubs`, `subscriptions/RunResetSubs` (the per-run wipe),
`remoteUpdates/CurrencyUpdate.model.json`,
client `EconomySubsClient` (HUD pills). Run scoping: ADR-0013,
`features/upgrades.md`.
