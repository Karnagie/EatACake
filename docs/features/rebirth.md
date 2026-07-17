# Rebirth ("Food Coma") & biomes

## What it does
GDD §9: spend `RebirthCost` calories → reset the six upgrades + empty the
belly + wipe calories → `rebirths += 1`. Permanent +25% calories per level
(StatsService). Gems, pets, quests, streaks survive. Rebirth level unlocks
biomes (`factory → donut → candy`): the SERVER cake takes the biome of the
highest-rebirth player online at spawn (shared-cake compromise, see
cake-cycle.md) — palette recolor + richer calories.

## Flow
`DoRebirth` remote → RebirthSubs: cost gate → TrySpendCalories →
`UpgradeService.ResetForRebirth` → `StomachService.Burn(0,0)` →
`EconomyService.ResetCalories` → `ProgressService.ApplyRebirth` → resync
pushes (rebirth/upgrades/currency/stomach). Failed spend just resyncs.
`RebirthUpdate` = `ProgressService.Summary`: `{rebirths, lifetimeCalories,
cakesEaten, findsCollected, biggestBelly, nextCost, biome}`.

## Config
`UpgradeConfig.rebirth`: `resets`, `multPerLevel`, `baseCost × growth^n`,
`biomes` order. Biome palettes/mults: `MapConfigData.biomes`.

## Files
`ProfileSchema/ProgressSection`, `services/ProgressService`,
`subscriptions/RebirthSubs`; client `RebirthSubsClient`, kit `RebirthPanel`.
