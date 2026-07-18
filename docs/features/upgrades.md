# Upgrades (six calorie-bought stats)

## What it does
GDD §10: capacity / biteRadius / biteDepth / eatSpeed / gymEff / runSpeed.
Levels live in profile section `upgrades`; formulas/costs/caps ONLY in
`Shared/config/UpgradeConfig`; ALL derived numbers come from
`StatsService` (server) / `LocalStatsService` (client mirror for bite
prediction + panel costs — same formulas, never trusted).

## Flow
`BuyUpgrade` remote (id) → UpgradeSubs: `NextCost` gate (nil = capped) →
`EconomyService.TrySpendCalories` → `ApplyLevel` → pushes
`UpgradesUpdate {levels}` + `CurrencyUpdate` + `BodySubs.RefreshBody`.
Failed spend just resyncs the client (stale balance). Costs are recomputed
client-side from config — only levels travel.

## StatsService (R3-legal derived stats)
Reads ONLY data modules: profile (upgrades/pets/progress),
`ShopData.passOwnership`, shared configs. Provides BiteRadius/BiteDepth/
EatRate/Capacity/GymEfficiency/WalkSpeed/CaloriesMult/GemsMult/PetSlots/
HasAutoEat/HasAutoGym/GrantBoost. Multiplier order (calories):
rebirth (+25%/lvl) × pets × x2-pass/VIP × timed boosts; glutton ×2 applies
in StomachService; rare-cake & biome mults apply in CakeSubs.

## Files
`ProfileSchema/UpgradesSection`, `services/UpgradeService`, `StatsService`,
`subscriptions/UpgradeSubs`; shared `config/UpgradeConfig`; client
`LocalStatsService`, `UpgradesSubsClient`, kit `UpgradesPanel`/`UpgradeRow`.
