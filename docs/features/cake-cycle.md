# Cake cycle (phases, boss, rare cakes, biomes)

## What it does
State machine per cake (GDD §9): `spawning → eating → boss → reward →
spawning`. Driven by `CakeCycleService.Step(dt)` from CakeSubs; transitions
return event strings the subscription acts on (R3).

## Phases
- **eating** — bottom reached (`progress ≥ 0.995`, 1 Hz scan) → `BeginBoss`.
- **boss** — Cake Guardian: HP = `bossTapsPerPlayer × players`; every `EatAt`
  = 1 damage; 30 s timer auto-defeats (never blocks the loop). Boss VISUAL is
  client-side only (`BossView`), HP travels in `CakeCycleUpdate` (4 Hz).
- **reward** — every player with a loaded profile gets ONE free server-side
  pet roll (`PetService.Roll(userId, "cycle")`; rainbow cake floors rarity to
  Epic). `progress.cakesEaten += 1`.
- **spawning** — 15 s countdown → new composition roll → `ResetCake` →
  snapshot broadcast.

## Composition roll (`RollComposition`)
frosting top + 3-5 middles (no immediate repeats) + core bottom; thickness
normalized to a rolled total height; radius scales ~√players. Rare cakes:
golden 4% (x3 calories), rainbow 1% (Epic+ pet) — плюс **hourly event**: if
no rare cake happened for 3600 s the next cake is forced golden (§12.2).

## Biomes
Server biome per cake = biome unlocked by the highest-rebirth player online
(`ProgressService.BiomeFor`). Biome = palette recolor (`MapService.ApplyBiome`)
+ calories multiplier (`MapConfigData.biomes[x].caloriesMult`).

## Update contract
`CakeCycleUpdate` (1 Hz; 4 Hz in boss): `{phase, progress, timer,
boss = {hp, maxHp}?, rareKind, biome, avalanche, announce}`.
`announce` keys: `new-cake`, `rare-cake-golden`, `rare-cake-rainbow`,
`boss-spawned`, `cake-cleared` → client `announce-*` locale keys.

## Files
`services/CakeCycleService`, `subscriptions/CakeSubs` (orchestration),
client `BossView`, `CakeSubsClient`. Pets: `features/pets.md`.
