# 2026-08-07: Cake zones, zone-gate mini-bosses, per-zone wall

Tags: cake-cycle, cake-sim, balance, config, render, app-root, ui-kit, pets, analytics, localization, tooling

## Task
Six user requests, verbatim in intent:
1. Group the layers into flavour families (jelly, butter, chocolate, cheese, jam — plus new
   groups for whatever does not fit), several layers each, laid down one after another.
   Chocolate must gain Nutella / white / Dubai variants.
2. When a player finishes one group and reaches the next, a BOSS appears and must be beaten
   before continuing. Bosses stand still, rotate to face players, start 4× player size and
   shrink to half a player at 0 HP, then vanish with a Toolbox VFX. They burst up through the
   top of the cake — unexpected and fun.
3. Remove the preview showing which squishy the cake will award.
4. Keep the final boss; the mini-bosses use the models in `Workspace.MiniBosses`, moved to
   `ReplicatedStorage`.
5. The side of the cake must show what is coming. (First asked as "each layer gets its own
   exterior texture"; corrected mid-task to **one wall per GROUP of layers**.)
6. Groups may differ in size. The FIRST group should take ~3-4 minutes, later ones longer.
   3-4 bosses in the whole cake.

## Context
`RollComposition` (ADR-0011) rolled each layer's identity independently out of a flat
7-entry `middlePool`, so depth meant nothing: eating was a random flavour every ~1.4 min.
The only boss was the Cake Guardian at the bottom (`features/cake-cycle.md`), and it
advertised its prize through `CakeStateData.pendingPetRolls` → `UIKit/BossPrizeCard`.
`CakeWrapper` hid everything below the two rendered slabs behind ONE ring of 32 block
segments wearing ONE tiled cake photo. Prior flow: `2026-08-03_round-cake.md` (why the wall
is flat block segments), `2026-08-05_belly-curve-affordability-gate-station-sign.md` (the
ramped-run model this task leans on).

## Plan
Keep the PACING CURVE untouched — band count, `scoop`, `density` and thickness are ADR-0011's
and are measured. Change only layer IDENTITY (zones), add a phase, and rebuild the wall.
Then measure, because requirement 6 is a timing claim.

## Changes

**Created:**
- `src/shared/config/CakeLayersConfig.lua` — the layer LIBRARY (40 layers) + the 10 flavour
  GROUPS, built from a per-group physics base plus per-variant overrides. Owns the new
  `sideTexture`/`sideColor` fields (per LAYER for the wall cap, per GROUP for the wall band).
- `src/client/common/modules/MiniBossView.lua` — the zone-gate boss visual: prepare an
  authored rig into a static prop, burst it up through the crust, yaw it at the local player,
  scale it with HP, poof it on death.
- `docs/features/cake-zones.md` — n/a (folded into `features/cake-cycle.md`, one doc per feature).

**Modified:**
- `src/shared/config/CakeConfig.lua` — layers/groups moved out (two accessors kept);
  `composition.middlePool` → `composition.groups {count, minLayers, layerShares}`;
  `cycle.miniBoss` tuning; `render.wrapper` band knobs.
- `src/server/game/services/CakeCycleService.lua` — `rollZones` + zone-aware identity + per-band
  `group` + the mini-boss rig roster; `BeginMiniBoss` / `DamageMiniBoss` / `FinishMiniBoss`;
  `Step` learns `miniboss-defeated`.
- `src/server/game/data/CakeStateData.lua` — `zones`, `miniBoss`, `miniBossesDefeated`;
  `pendingPetRolls` removed.
- `src/server/game/subscriptions/CakeCycleSubs.lua` — mini-boss orchestration + broadcast field;
  prize pre-roll deleted, `fireCycle` back to a plain broadcast.
- `src/server/game/subscriptions/CakeSimulationSubs.lua` — zone-boundary detection in the 1 Hz
  scan; `miniboss-defeated` handling; the `DebugClearLayer` Studio hook.
- `src/server/game/subscriptions/CakeSubs.lua` — `EatAt` routes to the mini-boss in that phase.
- `src/client/common/modules/CakeWrapper.lua` — one pooled textured ring PER FLAVOUR ZONE.
- `src/client/common/subscriptions/CakeSubsClient.lua` — mini-boss show/hit/hide + breach FX.
- `src/client/common/modules/AppRoot.lua`, `src/shared/UIKit/init.lua`,
  `src/shared/UIKit/Theme.lua`, `src/client/common/modules/LocalPetsService.lua`,
  `src/client/common/data/LocaleData.lua` — prize preview removed; mini-boss HUD + 13 new keys.
- `src/shared/config/AnalyticsConfig.lua` — `miniboss-start` / `miniboss-end`.
- `tools/balance-model/pacing.py` — PARSES `CakeLayersConfig` instead of mirroring 40 layers;
  mirrors the zone split; `report()` prints the per-zone minutes.
- `tools/headless-sim/pacing_scenario.lua` + `build_sim.py` — section E asserts the zone split.
- `tools/robloxloc/robloxloc.py` — UTF-8 stdout (a cp1252 console killed `pull` after it had
  already written the CSV).

**Deleted:**
- `src/shared/UIKit/Components/BossPrizeCard.lua` — the prize preview (req 3).

**Studio (place-authored, saved by the user):**
- `Workspace.MiniBosses` → `ReplicatedStorage.Assets.MiniBosses` (5 rigs).
- `ReplicatedStorage.Assets.Vfx.MiniBossPoof` — built from the free "NEXT PARTICLES KIT"
  (`EnemyDeathFX` + `Glow` + `Rays` + a flash light), emitters disabled so the client `:Emit`s.

## Decisions

**Zones split by LAYER COUNT, not by clear-time cost — and that is a measurement.**
The obvious model says the deepest band costs ~16× the top one (clear time goes as `1/scoop²`),
so zones "should" be cost-weighted. That is true for a FIXED eater and false for the run people
play: the player buys tiers as they dig and the upgrade ramp very nearly cancels the scoop ramp.
`tools/balance-model/pacing.py` (ramped, 5 seeds) measures a FLAT **~1.21 min per layer** across
all 29 bands — 1.89 min for the first (no upgrades yet), 1.84 for the last. The cost-weighted
split I built first put **11 layers and 13.2 minutes** in the opening zone, the exact opposite of
requirement 6. By count it is 3 / 5 / 9 / 12 layers ≈ **4.5 / 5.1 / 10.3 / 15.4 min** of a 35.5-min
run. Mean clear time moved 35.3 → 35.5 min and the tree still completes at ~50% of the cake, so
ADR-0013's target survives. ⚠ The opening zone measures 4.5 min against a 3-4 min ask: it carries
the un-upgraded first ~90 seconds (bands 1-2 alone are 3.5 min), and 3 layers is the smallest zone
`minLayers` allows. Two layers would land at 3.5 min if the 3-4 window ever matters more than the
"3-4 chocolate layers" example the same request gave.

**The pacing curve was not touched.** Band count, `scoop`, `density`, thickness and the
renormalisation are byte-identical; zones only decide `ids[k]` and stamp `band.group`. That is
what makes the timing claim above a measurement of ONE change rather than of a rebalance.

**`hardness` and `calories` had to be NARROWED.** They were free per layer while identity was
random — a hard or rich layer averaged out inside every cake. A zone does not average: 6-12
consecutive layers now share one value. Ranges pulled in from 0.85-1.25 → 0.95-1.12 and
0.122-0.237 → 0.145-0.197, holding the pool mean at the old 0.174 so income per bite is unchanged.
Same reasoning for `walkSpeedMult`/`jumpMult`: caramel at 0.6 speed was fun as one layer in twenty
and would be miserable as a nine-layer zone.

**A mini-boss is a GATE, not a race — no timer.** The Cake Guardian's timeout is a loss because it
is the finale. A timeout 8 minutes into a 35-minute run would strand the run for nothing, so
`Step` never ticks the mini-boss phase down; the only exit is beating it. HP is
`50 × players × difficulty × 1.35^(gate-1)` (38 / 51 / 69 on easy solo) — ~8-15 s of tapping.

**The gate rides the layer gate, not a new mechanism.** `ScanStats` already advances
`activeBandIndex` once per second and is already the single path that moves the checkpoint plate
and announces a cleared layer. The boundary test is `composition[previous].group <
composition[active].group`, and the mini-boss announce REPLACES "LAYER CLEARED!" for that beat so
two banners cannot stomp each other. Blocking the cake needs no new code at all: `EatAt` already
drops every bite when `phase ~= "eating"`, and `ScanStats` only runs while eating, so the field
freezes for the duration. The paid LayerEater's readiness predicate refuses during a gate for the
same reason.

**The core band carries the DEEPEST zone's index on purpose.** The gate reaches band #1 when
everything edible is gone; any other value there would fire a fourth mini-boss one second before
the Cake Guardian.

**`Model.PrimaryPart` silently beats `Model.WorldPivot`.** Found in the playtest, not by reading:
the boss stood **6.4 studs sunk into the cake**. `prepare()` re-seats the pivot at the rig's FEET so
`PivotTo(groundY)` means "stand here", but a Model with a PrimaryPart takes its pivot from that part
and ignores `WorldPivot` — on an R6 rig that is the HumanoidRootPart, i.e. the hip. `ScaleTo` grew
it about the hip too, so the error scaled with HP. Fix: clear `PrimaryPart` during prepare (these
are static props; the Humanoid is stripped anyway).

**The boss faces the LOCAL player, client-side.** "Rotate to face the players" has no single
correct answer for a shared entity, so every client sees it staring at them. The rig's authored
facing is measured once off its HumanoidRootPart LookVector and cancelled out, so a rig authored
facing any direction still looks at you.

**`Model:ScaleTo` is throttled.** It walks every descendant and these rigs carry ~490, so the HP
size is smoothed per frame but only APPLIED at ≤12 Hz and past a 0.004 threshold.

**The wall is one pooled ring per ZONE.** `Texture` tiling only works on flat block faces — a part
carrying a mesh maps textures through the MESH's UVs and silently ignores `StudsPerTile` (measured
2026-08-03), so this forces the segment ring either way. 20 segments × 4 zones = ~80 anchored,
non-colliding, non-query parts, created ONCE and re-placed thereafter; a finished zone PARKS its ring
rather than destroying it. The TOPMOST ring is clamped to the wall top, so it shrinks layer by layer
and only vanishes once its whole zone is eaten; `StudsPerTileV` is the zone height over a ROUNDED row
count, so a whole number of rows always fits (a fractional row slices the image at the top edge).

⚠ **I built a ring per LAYER first, and that was wrong.** It satisfied the literal request ("each
layer should have its own exterior texture") and missed the intent: ~28 near-identical stripes up the
side read as noise rather than information, and cost ~560 parts to say less than four chunky bands
do. Corrected to one wall per GROUP, which is also the honest match for the feature — zones are what
the mini-boss gates are drawn on. The per-LAYER `sideTexture` survives for the top CAP only, which
really is one layer seen face-on down a crater; `CakeLayersConfig.groupOfLayer` resolves a band's
layer id to its zone, so the wall needed no protocol change.

**Four of the ten zone textures were unusable, and only a screenshot could tell.** Toolbox search
returns DECAL ids whose names say nothing about whether the image is a flat material or a product
shot. Rendered 20 studs wide on a probe wall in Studio: jam was a photo of jam JARS, cheese a clipart
slice on white, candy a collage WITH TEXT baked in, crumb a few crumbs on an empty white field.
Replaced off a 3-round probe with full-bleed material photos (deep glossy preserve, whipped
cheesecake cream, pink spun sugar, dense brown crumb). ⚠ Judge a wall texture at WALL SIZE on the
real geometry — an asset id and its name are not evidence.

**The prize preview came out whole, including its Theme section.** With `pendingPet` gone,
`fireCycle` stopped needing a per-recipient clone and is a plain broadcast again (outside a reserved
match) — the reason `docs/registries/remotes.md` carried a ⚠ on `CakeCycleUpdate`. `PetService`'s
`Preview`/`Grant` split stays: `Roll` is still built from it, it just has no second caller.

**`pacing.py` now PARSES the layer library.** Mirroring 40 (hardness, calories) pairs by hand is
the exact drift the file's `check_config_sync()` exists to prevent, and the Lua builds them from a
base + overrides, so a regex-per-layer mirror was never going to hold. It reads
`CakeLayersConfig.lua` with a brace matcher instead and raises loudly if the parse loses
frosting/core or finds no groups. What is still mirrored — `composition.groups` — is checked.

**A `DebugClearLayer` Studio hook was needed to test this at all.** Clearing a layer honestly takes
MINUTES at production scale (clear time is area-driven), which made the zone gate — the one thing
that only happens at a layer boundary — untestable without shrinking the cake in config, i.e.
testing a cake the game does not ship. I tried that first and it was worse than useless: on a
21-stud disc the wax shell never built and the wall never built, both artifacts of the test config.
The hook goes through `ClearActiveBand`, the same call the paid LayerEater uses, so the 1 Hz scan
fires the gate exactly as a real clear would.

## What the adversarial review caught
Two CRITICALs, both found by the 5-lens review + refutation pass, neither reachable by the
playtest I had already run:

**1. The breach juice was latched on the VIEW, not on the TRANSITION.** The entrance
(`bossAppear` + a 0.55 camera punch + 100 particles) sat inside `if not MiniBossView.IsShown()`.
That is "once" only while the view WORKS: `Show` deliberately no-ops when the rig cannot be
resolved (no `Assets.MiniBosses` — and that tree is place-authored, so a fresh clone or a template
harvest has none), `IsShown()` then stays false forever, and the block re-ran on every
`CakeCycleUpdate` — 1 Hz, for a phase that is UNTIMED by design. `CameraShake.Impulse` is additive,
so trauma never decayed. The path documented as "no visual, the fight still runs" was actually a
sting and a camera punch every second for the whole gate. Now latched on `mini.index` (the gate),
cleared on every exit, and the win sting keys off the announce so a gate fought without a rig still
resolves audibly. Verified in Studio with the folder renamed away: exactly one warning, no rig,
gate still fightable, camera drift **0.000 studs** over a second.

**2. `pacing.py`'s new zone-split guard could never match.** Its regex wanted two tabs of indent for
a `groups = {` block that sits at one, so `check_config_sync()` appended "composition.groups: not
found" on EVERY run — the banner was permanently red (hiding every other check) and the comparison
it exists to perform never executed; real drift and the standing false positive were
indistinguishable. The dead branch would also have crashed, handing two tuples to an
`abs(got - want)` comparator. ⚠ I had reported "config sync clean" off a `| head` that cut the
banner. Fixed, made elementwise, and then PROVEN live by deliberately drifting `layerShares[1]`
0.11 → 0.20 and watching it complain before restoring.

## Verification
- `luau-compile` over all 205 `src/` files: clean.
- `tools/headless-sim/pacing_scenario.lua` §E (new): zones contiguous top-down, layer counts match
  `layerShares`, every boundary gets a distinct rig. Sections A-D unchanged and passing.
- `treasure_scenario`, `layereater_scenario` (19/19), `analytics_scenario`: passing.
- `tools/balance-model/pacing.py`: config sync clean AND proven to fire on drift (see above),
  clear 35.5 min, tree at ~50%, zone split 4.5 / 5.1 / 10.3 / 15.4 min.
- Live Studio playtest on the SHIPPED config: clean boot; `chocolate×3 → sponge×5[MrsCCustom] →
  butter×9[SammyCustom] → cream×12[SweetyCarolCustom]`; `DebugClearLayer 3` → gate → `mini-boss #1
  'MrsCCustom' guards the 'sponge' zone, hp=38`; 60 taps → defeated → phase back to eating; rig
  19.3 studs at 100% HP → 10.9 at 50% → 2.4 at 0%, feet on the surface at every scale; HP billboard
  titled with the zone name; HUD bar "MINI-BOSS! EAT IT!"; wall 561 parts → 501 after three layers.
- Localization: 13 keys pushed to universe 10593425705, `boss-prize-caption` pruned, `status` clean.

## Open Questions / Followups
- The opening zone measures **4.5 min** against the 3-4 min ask (see the first decision). Drop
  `minLayers` to 2 and `layerShares[1]` to ~0.08 if the window matters more than the layer count.
- Zone ORDER is a free draw, so a cake can open on caramel (slow feet) or candy (fast). Nothing
  weights it; if the opening zone should always be an easy one, that is a one-line filter in
  `drawDistinct`.
- 21 of the 40 layers share a `sideTexture` with a sibling and differ by `sideColor` — a distinct
  Toolbox image per variant would read better on the rim.
- ⚠ Pre-existing, found in passing and NOT touched: `PetConfig.assetsFolder = "Squishes"` but the
  place has `ReplicatedStorage.Assets.Bosses` holding the 50 `Squishy N` models, and there is no
  `Assets.Items` for treasures either. Both features fall back to primitives today.

## Related
- Feature: `docs/features/cake-cycle.md` (zones + both bosses), `docs/features/cake-sim.md` (wall)
- ADRs touched: ADR-0011 (pacing curve — unchanged, deliberately), ADR-0013, ADR-0019
- Prior flow: `docs/flow/2026-08-03_round-cake.md`,
  `docs/flow/2026-08-05_belly-curve-affordability-gate-station-sign.md`
