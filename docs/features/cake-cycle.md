# Cake cycle (zones, mini-bosses, boss, rare cakes, biomes)

## What it does
State machine per cake (GDD §9): `spawning → eating → (miniboss → eating)* →
boss → reward → spawning`. `CakeSimulationSubs` drives `CakeCycleService.Step(dt)`; returned
events are orchestrated by `CakeCycleSubs` (R3/R4). In a reserved match the
first fresh cake is finite: reward is terminal and `GameRoundSubs` returns the
roster instead of spawning another cake.
In an active game-place round, cake construction/snapshots/simulation are
deferred until the profile-ready roster start commits. The combined/unknown
development build is not active round mode and retains the endless fallback.

## Phases
- **eating** — bottom reached (`progress ≥ 0.995`, 1 Hz scan) → `BeginBoss`.
- **miniboss** — the ZONE GATE (below). No timer; the only exit is beating it.
- **boss** — the CAKE MONSTER (renamed from "Cake Guardian"/"BOSS" on
  2026-08-13; the phase string, announce keys, SFX names and analytics steps all
  still say `boss`): HP = `bossTapsPerPlayer (120) × players ×
  bossHpMultiplier` (fixed launch count in a reserved match; current population
  in endless fallback); every `EatAt` = 1 damage. Sized as a ~20-30 s frantic
  finale, with the timer always leaving ~1.5× the time a base eater needs.
  ⚠ **Keep that margin when tuning**: `HP / (players × eatRate)` must stay well
  under the timer or the match is unwinnable by construction (easy solo 90 taps
  / 67.5 s; hard solo 150 / 45 s; hard 4p 600 / 45 s).
  Defeat before the timer is a win; timer expiry is a
  loss (no reward). Boss VISUAL is
  client-side only (`BossView`), HP travels in `CakeCycleUpdate` (4 Hz).
  ⚠ **The world-space HP bar over the monster was REMOVED 2026-08-13** (user
  request). Its health has always ALSO been the HUD's top-centre `CakeBar`, so
  the billboard was the same number twice, drawn over the thing the player is
  supposed to be looking at. `BossView.SetHp` is gone with it; nothing
  client-side consumes boss HP any more — `AppRoot` feeds the bar straight from
  the payload. The same call removed the zone gate's HP bar (below).
  Defeating it now fires the food-burst celebration: `features/food-burst.md`.

## ZONES + MINI-BOSSES (2026-08-07)
A cake is a SEQUENCE of flavour ZONES — "3 chocolate layers, then 5 sponge, then
9 butter" — not a random flavour per layer. Classic keeps the default contract:
**every boundary between two zones is a MINI-BOSS that must be beaten before the
cake unlocks again**. A selectable variant may mark a boundary visual-only with
`groups.gateBoundaries`; rainbow has seven colour terraces but only the five
authored mini-boss rigs. With classic `composition.groups.count` = 5 that is 4
gates + the Cake Monster = 5 monsters per cake. ⚠ It was 4 zones until
2026-08-07: the deepest was TWELVE layers /
~15 min, longer than the first three together, so the last third of a run had no
punctuation. Classic still gets one gate per boundary; a fixed visual variant
may explicitly leave selected boundaries open with `gateBoundaries`.

| piece | where |
|---|---|
| the 40 layers + the 10 groups | `Shared/config/CakeLayersConfig` (`CakeConfig.layers` / `.layerGroups` are still the accessors) |
| how many zones, how big | default `CakeConfig.composition.groups`; variants may override `{count, minLayers, layerShares, radiusScales, gateBoundaries}` |
| the roll | `CakeCycleService.rollZones` → per-band `group` (1 = TOP) + `state.zones` (`{id, nameKey, members, layers, radiusScale, gateFromPrevious, gateIndex?, bossModel?}`) |
| HP / size / entrance tuning | `CakeConfig.cycle.miniBoss` |
| the gate firing | `CakeSimulationSubs` 1 Hz scan → `CakeCycleSubs.BeginMiniBoss(zone)` |
| the visual | client `MiniBossView` + authored rigs in `ReplicatedStorage.Assets.MiniBosses` |
| the zone you can SEE coming | the outer wall is ONE BAND PER ZONE (`CakeWrapper`, `features/cake-sim.md`) wearing the group's `sideTexture` |

⚠ **A Toolbox id and its name are not evidence — at LAYER level either.**
The 2026-08-08 audit rendered all 42 unique `texture`/`sideTexture` ids at
size and found 16 slots were cartoons, product photos or wrong-subject images
(a pistachio CHARACTER, a Tootsie Roll product shot, a strawberry-jam LABEL
used for blueberry); all replaced with visually verified IMAGE ids (never
decal ids — `CakeLayersConfig` header). Before shipping any new layer texture:
render it on a part and LOOK. Audit + candidate pipeline: flow
`2026-08-08_layer-texture-audit.md`.

**Zones are split by LAYER COUNT (`layerShares`), not by clear-time cost, and
that is measured.** Clear time goes as `1/scoop²`, so the deepest band costs
~16x the top one — which says "split by cost", and is true only for a FIXED
eater. The player buys tiers as they dig and the upgrade ramp nearly cancels the
scoop ramp: `tools/balance-model/pacing.py` (ramped, 5 seeds) measures a FLAT
**~1.21 min per layer** over all 29 bands. Cost-weighting put 11 layers and
13.2 min in the opening zone; counting puts 3 layers there. Shipped split at 28-29
layers: **3 / 5 / 6 / 7 / 8 layers ≈ 4.5 / 5.1 / 7.1 / 7.9 / 10.6 min** of a
35.5-min run — every zone longer than the one above it (design target: opening
zone 3-4 min, later ones longer — see the flow doc for why the opening
measures 4.5).

⚠ **`hardness` and `calories` are no longer free per layer.** They used to average
out inside a cake because identity was random; a zone is 3-12 consecutive layers
sharing one value, so the spread became a per-ZONE swing. Both were narrowed
(0.95-1.12 and 0.145-0.197, pool mean held at the old 0.174) — see the
`CakeLayersConfig` header before widening either.

**The gate rides the layer gate; it is not a second mechanism.** `ScanStats`
already advances `activeBandIndex` at 1 Hz. The subscription enumerates every
destination group between the previous and post-scan groups and queues each
configured gate in `CakeStateData.pendingMiniBossZones`; this matters when rapid
LayerEater receipts or a Studio skip flatten several zones inside one scan.
`FinishMiniBoss` immediately starts the next FIFO entry, and the Cake Monster
refuses to start until the queue is empty. Blocking the cake needs no second
field lock — `EatAt` already drops every bite when `phase ~= "eating"`, and
`ScanStats` only runs while eating, so the field freezes. The paid LayerEater's
readiness predicate refuses for the same reason. The mini-boss announce REPLACES
`layer-cleared` for that beat (two banners in one frame would stomp each other).
⚠ The CORE band carries the DEEPEST zone's index on purpose: the gate reaches
band #1 when everything edible is gone, and any other value there fires a spurious
gate one second before the Cake Monster.

**Fighting it** is the same tap as eating: `EatAt` is routed to
`CakeCycleService.DamageMiniBoss` (1 damage) in that phase, so the client sends
its own root position and there is nothing new to trust. HP =
`tapsPerPlayer (50) × players × difficulty bossHpMultiplier × tapsGrowth^(gate-1)`
— 38 / 47 / 59 / 73 on easy solo, ~8-15 s each. ⚠ `tapsGrowth` came down
1.35 → 1.25 when the cake went to 5 zones: at 1.35 the FOURTH gate would out-HP
the Cake Monster itself, and a crumb monster must never out-fight the finale. **No timer, by design**: the Cake Monster's
timeout is a loss because it is the finale; a timeout 8 minutes into a 35-minute
run would strand the run for nothing.

**The visual** (`MiniBossView`, client-only — HP travels on `CakeCycleUpdate`;
player-facing name CRUMB MONSTER since 2026-08-13, code name unchanged):
one of 5 authored rigs, drawn per GATED boundary so none repeats inside a cake. It
starts `emergeDepthStuds` under the freshly-cleared floor, pitched back, and
punches up through it in `emergeSeconds` with an overshoot — "bursting out of the
cake". It then STANDS STILL and only yaws toward the LOCAL player (so every player
is the one being stared at). Size IS the health bar: 4x a player at full HP down
to half a player at 0, then it pops in `Assets.Vfx.MiniBossPoof`.
⚠ Its billboard is a ZONE NAMEPLATE only — the HP fill was removed 2026-08-13
with the Cake Monster's, because health already had two better readouts (the
HUD bar, and the rig's own size). `SetHp` still runs: it is what drives
`targetScale`, so deleting the call would freeze the rig at full size and
delete the only feedback the fight has left in the world.
Beating one takes the SAME celebration as the finale — splash, rolled cheer and
a food burst, at the middle of the three sizes (`features/food-burst.md`). Every
change made for the Cake Monster was applied here too, by design: the two are
one fight at two scales, and only the SPAWN beats stay plain announcements.
⚠ `prepare()` must clear `Model.PrimaryPart` before setting `WorldPivot` — a Model
with a PrimaryPart takes its pivot from THAT PART and ignores `WorldPivot`, which
on an R6 rig is the hip, and `ScaleTo` grows about the pivot too, so the boss stood
6.4 studs INSIDE the cake with the error scaling with HP.

⚠ **The squishy PRIZE PREVIEW was removed 2026-08-07** (user request): the fight no
longer advertises what it pays. `pendingPetRolls`, `prepareBossPrizes`, the
per-recipient `fireCycle` clone, `UIKit/BossPrizeCard`, `Theme.BossPrize`,
`LocalPetsService.BuildPrize` and `boss-prize-caption` are all gone;
`CakeCycleUpdate` is a plain broadcast again outside a reserved match.
`PetService.Preview`/`Grant` stay split — `Roll` is still built from them.

- **reward** — on a match win, every present validated participant with a loaded
  profile receives the squishy the boss HUD has been ADVERTISING (see below);
  `progress.cakesEaten += 1`.
- **spawning** — 15 s countdown → new composition roll → `ResetCake` →
  snapshot broadcast.

## Composition roll (`RollComposition`) — THE PACING CURVE (ADR-0011, ADR-0020)
`CakeConfig.variants[cakeId]` selects the composition contract. Difficulty and
party size never change that chosen silhouette; they still change layer count
and scoop work through the existing ADR-0011 curve.

| variant | zones / silhouette | coating + room | finds |
|---|---|---|---:|
| `cake-classic` | frosting cap + 5 random flavour zones; 170 edible studs; one ~93.3-stud disc footprint | wax + brittle crust; `Assets.Environment`; rare rolls enabled | 1× |
| `cake-rainbow` | 7 fixed ROYGBIV runs; 29 solo-easy bands split 7/5/4/4/3/3/3; 204 edible studs; terrace radii .72/.76/.81/.87/.94/.97/1 from top→base | opaque soft SmoothPlastic, heavy `squishMult=2.6`; no frosting/wax/crust; `Assets.Environment1`; rare rolls disabled | 1.5× |

The 2026-08-12 visual correction supersedes ADR-0020's 255-stud interpretation
of physical size: rainbow is shorter (204 edible studs) and every upper terrace
is wider, while the maximum base remains the classic footprint. A 1.5× diameter
cannot fit the 64×64 field (classic radius is already 31.1 cells against the
31.5-cell boundary), would require a 96×96 grid/2.25× cells, and would overrun
the authored 100×88 cake plate. The explicit 1.5× requirements that remain are
measured clear duration and find-gem payout. `CakeFieldService`, cleanup sweeps,
find placement, the renderer and `CakeWrapper` consume each band's footprint.

Classic keeps frosting on top, core at the bottom, and the rest drawn from the
ZONES above (no immediate repeat inside a zone). Selectable variants may supply
fixed groups, height, footprints and coating flags. Pacing lives on each BAND:

| per-band field | what it does |
|---|---|
| `scoop` | multiplies the eater's `biteRadius` on that band. Ramps 2.23 (icing, ~5.4-stud spoonful at base `biteRadius` 2.4) → 0.558 (core, ~1.3-stud chip). A bite clears to the band FLOOR, so clear time scales with bite AREA — **this is the difficulty ramp**, and it reads on screen. |
| `density` | how rich/filling that band is per stud³ (calories AND belly fill) = `refBandWeight / (thickness × scoop²)` — exactly the value that keeps one bite worth the same FOOD as the scoop shrinks, so the belly→gym rhythm is set by `capacity` ALONE (features/upgrades.md: ~10 s per belly at tier 0 stretching to ~180 s at tier 5) and the income stays flat at every depth. |
| thickness | follows the same ramp (deeper == chunkier), renormalised to `maxTotalHeight`. Thickness does NOT drive clear time (a bite clears to the floor). |

`work` = `MatchConfig` `workMultiplier` × `(1 + coopWork·(players−1))` (0.5; players
at spawn). It buys MORE LAYERS first (`layerExponent`), and whatever the
`maxLayers` cap cannot absorb becomes smaller scoops — so a harder/crowded cake
has more thin layers and denser cake, i.e. more "layer cleared!" moments.
Calorie payout scales separately: `caloriesMultiplier` × per-head `coopCalories`
(0.62), fixed at roll time into `state.payoutScale` so it cannot drift as players
leave. Boss HP scales with players × difficulty.

**`findPayoutScale`** is its sibling for the GEMS buried finds pay, fixed at the
same moment and applied by `CakeCycleService.ScaleFindReward` (which returns a
COPY — the caller is handed the shared config descriptor). It carries the
per-head term multiplied by the chosen variant's `findRewardMultiplier`:
`(1 + coopFinds·(players−1)) × variant multiplier`. It has no difficulty or
random-rare-cake premium. Why finds need the per-head term, and why difficulty
is deliberately excluded: `features/treasures.md`.

**Measured clear time** (2026-08-11, `tools/balance-model/pacing.py`, 5 seeds —
the FIRST model that simulates a player buying tiers mid-run, which is the run
people actually play):

| solo easy | classic | rainbow |
|---|---:|---:|
| clear (eat + gym) | **34.86 min** | **52.09 min** |
| ratio to classic | 1× | **1.4943×** (target 1.5×; acceptance 1.45–1.55×) |

`durationScale=1.5` is the player-facing target. A literal 1.5× bite-work factor
only reaches ~1.36× wall time because gym/UI time is fixed, so the revised
rainbow uses the separately named, measured `durationWorkScale=1.75`. Scoop and density are
co-adjusted: the extra work stretches eating time while food/belly milestones
remain at roughly the same cake depth.

⚠ The old row "easy solo **40 min**" was never measured this way: the model behind
it ran a fixed stat line, so the ramp was invisible. Re-measured, the shipped
tuning was **54.6 min** owning 21/44 tiers — and a real playtest reported
**1 h 01 m** (that plus boss, reveal, walking and time in the upgrade UI).
ADR-0013 re-priced the tree and raised work ×1.08 to land the 40-minute target.
⚠ medium/hard and the co-op matrix were scaled by the same ×1.08 but only solo
easy was measured across seeds — the party numbers are extrapolated. Party size
still multiplies work by `1 + 0.5(n−1)` and payout per head by `1 + 0.62(n−1)`.
Random rare skins still apply only to `cake-classic`: golden 4% (x3 calories),
rainbow 1% (Epic+ pet), plus the hourly forced-golden event after 3600 s. This
`rareKind="rainbow"` is a skin of the current classic composition and is
deliberately distinct from selectable `cakeId="cake-rainbow"`.

## Biomes
Biomes used to be unlocked by rebirth level; **rebirth was removed 2026-07-26**,
so every cake takes `CakeConfig.biomeOrder[1]` (`ProgressService.BiomeFor`, which
keeps its signature so an unlock rule is a one-liner away). Biome = palette
recolor (`MapService.ApplyBiome`) + calories multiplier
(`MapConfigData.biomes[x].caloriesMult`).

## Update contract
`CakeCycleUpdate` (1 Hz; 4 Hz in boss): `{phase, progress, timer,
boss = {hp, maxHp}?, miniBoss = {hp, maxHp, index, model, zoneKey}?, rareKind,
cakeId, biome, activeBandIndex, finds?, announce}`. ONE broadcast for everyone outside a
reserved match (it was per-recipient only while the boss prize existed).
`miniBoss.model` is the authored rig NAME the client clones; `zoneKey` is the
locale key of the zone it guards, shown on its billboard.
(`activeBandIndex` = the layer-gate top edible band, so the client's bite
prediction/lock tracks the server between snapshots — see
`features/cake-sim.md`. Avalanche/slump energy is a client-local value in
`LocalCakeField`, never networked.)
`announce` keys: `new-cake`, `rare-cake-golden`, `rare-cake-rainbow`,
`boss-spawned`, `miniboss-spawned`, `miniboss-defeated`, `cake-cleared`,
`layer-cleared`, `match-lost` → client `announce-*` locale keys.

**Session length — endpoints.** ⚠ The figures previously quoted here (126 min
fresh / 33 min maxed, from `tools/headless-sim/pacing_scenario.lua` §B) were
inflated by a units bug found 2026-07-30: the scenario multiplied
`CakeOps.ApplyBite`'s return — already a VOLUME — by `cellArea` a second time, so
food read 2.25× high, belly→gym TRIPS 2.25× high, and the forfeited fraction
2.25× low (6.8% shown vs ~17% actual). Fixed in that file. The Python model
measures the endpoints at **478 min at tier 0 / 18 min maxed** on the current
config. ⚠ Since the 2026-08-05 belly curve the tier-0 endpoint is not even a
hypothetical session: `capacity` base is sized for the first ~10 SECONDS of a run,
so that row is a player who eats a whole cake without ever buying a tier and its
time is dominated by hundreds of gym trips nobody makes.
Neither endpoint is the run people play — that is the 35.3-min ramped
figure above.

**`layer-cleared`** is the session's RHYTHM beat: fired by `CakeSimulationSubs`
whenever the layer gate steps DOWN a band (never on a new cake, where the index
jumps back up), so ~28-42 times per cake — one every ~1.4 min of a 40-min solo
run. The client answers with the `layerCleared` chime, a camera punch, a ring
of crumbs kicked up around the eater, and — since 2026-08-13 — a burst of food
sprites plus a random-cheer splash instead of the fixed "LAYER CLEARED!" line
(`features/food-burst.md`). Finishing a layer used to be SILENT.
It is also the game's DEPTH metric: the same gate move feeds the `CakeLayers`
funnel (step N = N layers cleared on this cake) and the `layer_cleared` counter
— how far a run actually gets, and how many stop at a zone gate
(`features/analytics.md`).

## Files
`services/CakeCycleService`; `subscriptions/CakeSubs` (player input),
`CakeCycleSubs` (lifecycle/gates/reward), `CakeSimulationSubs` (Heartbeat +
boundary detection), `GameRoundSubs` (finite result); shared
`config/CakeLayersConfig` (layers + groups), `config/CakeConfig`
(`composition.groups`, `cycle.miniBoss`); client `BossView` (Guardian),
`MiniBossView` (zone gates), `CakeSubsClient`. Match contract:
`features/game-round.md`. Pets: `features/pets.md`. Wall: `features/cake-sim.md`.

## Dev hooks (Studio only)
`CakeConfig.studioVariantId = "cake-rainbow"` makes Play start directly on the
rainbow cake in both the combined project and a direct GAME-place test. Set the
field to nil to test normal classic fallback. It is checked only when no round
`cake-id` exists (or for a no-source direct join), so it cannot replace a real
lobby match's protocol-v2 selection; the server logs when the override is used.

`workspace:SetAttribute("DebugClearLayer", n)` (SERVER context, in play) flattens
the next `n` layers through `ClearActiveBand` — the same call the paid LayerEater
uses — so the gate fires exactly as a real clear would. Clearing a layer honestly
takes MINUTES at production scale, which otherwise makes the zone gate testable
only on a cake the game does not ship. The first use arms the cake-scoped
`debugSuppressFindRewards` latch: finds may still pop visually, but reward,
discovery/progress, analytics and save writes are suppressed until the next cake.
Without that latch, skipping buried layers silently credits the tester's real
Studio profile.
