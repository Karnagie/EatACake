# Cake cycle (phases, boss, rare cakes, biomes)

## What it does
State machine per cake (GDD §9): `spawning → eating → boss → reward →
spawning`. `CakeSimulationSubs` drives `CakeCycleService.Step(dt)`; returned
events are orchestrated by `CakeCycleSubs` (R3/R4). In a reserved match the
first fresh cake is finite: reward is terminal and `GameRoundSubs` returns the
roster instead of spawning another cake.
In an active game-place round, cake construction/snapshots/simulation are
deferred until the profile-ready roster start commits. The combined/unknown
development build is not active round mode and retains the endless fallback.

## Phases
- **eating** — bottom reached (`progress ≥ 0.995`, 1 Hz scan) → `BeginBoss`.
- **boss** — Cake Guardian: HP = `bossTapsPerPlayer × players` (fixed launch
  count in a reserved match; current population in endless fallback);
  every `EatAt` = 1 damage. Defeat before the timer is a win; timer expiry is a
  loss (no reward). Boss VISUAL is
  client-side only (`BossView`), HP travels in `CakeCycleUpdate` (4 Hz).
- **reward** — on a match win, every present validated participant with a loaded
  profile gets ONE free server-side
  pet roll (`PetService.Roll(userId, "cycle")`; rainbow cake floors rarity to
  Epic). `progress.cakesEaten += 1`.
- **spawning** — 15 s countdown → new composition roll → `ResetCake` →
  snapshot broadcast.

## Composition roll (`RollComposition`)
frosting top + 3-4 middles (no immediate repeats) + core bottom; thickness
normalized to a rolled total height. The loaf FOOTPRINT is a FIXED landmark
(~90×78 studs) regardless of population. **Easy-mode co-op scaling**: the rolled
`totalHeight` is multiplied by `1 + composition.perPlayerScale·(players−1)` (0.15;
players present at spawn), clamped to `grid.maxHeight` (270) — a TALLER (== longer
to eat) shared loaf for a crowd, SUBLINEAR so more mouths still clear it faster
(solo ~40 min, 4 players ~18 min, not ~10; see `2026-07-19_easy-mode-balance.md`).
Height is the only population lever because the 64-cell grid caps the footprint.
Boss HP also scales with players. Reserved-round difficulty comes from
`MatchConfig`: easy shortens the loaf/lower boss HP/longer boss timer, medium is
neutral, and hard lengthens the loaf/raises boss HP/shortens the timer.
Rare cakes:
golden 4% (x3 calories), rainbow 1% (Epic+ pet) — плюс **hourly event**: if
no rare cake happened for 3600 s the next cake is forced golden (§12.2).

## Biomes
Server biome per match cake = biome unlocked by the highest-rebirth validated,
present participant with a loaded profile
(`ProgressService.BiomeFor`). Biome = palette recolor (`MapService.ApplyBiome`)
+ calories multiplier (`MapConfigData.biomes[x].caloriesMult`).

## Update contract
`CakeCycleUpdate` (1 Hz; 4 Hz in boss): `{phase, progress, timer,
boss = {hp, maxHp}?, rareKind, biome, activeBandIndex, announce}`.
(`activeBandIndex` = the layer-gate top edible band, so the client's bite
prediction/lock tracks the server between snapshots — see
`features/cake-sim.md`. Avalanche/slump energy is a client-local value in
`LocalCakeField`, never networked.)
`announce` keys: `new-cake`, `rare-cake-golden`, `rare-cake-rainbow`,
`boss-spawned`, `cake-cleared`, `match-lost` → client `announce-*` locale keys.

## Files
`services/CakeCycleService`; `subscriptions/CakeSubs` (player input),
`CakeCycleSubs` (lifecycle/reward), `CakeSimulationSubs` (Heartbeat),
`GameRoundSubs` (finite result); client `BossView`, `CakeSubsClient`. Match
contract: `features/game-round.md`. Pets: `features/pets.md`.
