# 2026-07-26: Buried item finds (dig them out)

Tags: treasures, cake-sim, juice, audio, assets, config

## TL;DR (this doc is long — 22 passes; read this, then jump to what you need)

| What shipped | Where |
|---|---|
| Finds are BURIED authored models you dig out and that auto-collect | `features/treasures.md`, ADR-0012 |
| Cake 330 → **170** studs (silhouette; measured cost food −1.8%, waste 6.0→6.8%) | `CakeConfig.composition.maxTotalHeight` |
| Wall texture: unresolved DECAL ids (candy-cane stripes) → seamless cake photo | `CakeConfig.render.wrapper.textures` |
| Sweep distances capped at 25% of band thickness (waste 8.3 → 6.8%) | `CakeConfig.sim.sweepBandFraction` |
| `layer-cleared` rhythm beat (the gate step used to be silent) | `features/cake-cycle.md` |
| `FINDS n/N` goal bar + `Finds` leaderstat (discovery SET, 9 kinds) | `AppRoot.cakeBarModel`, `LeaderboardSubs` |
| Surface GLINT over a nearly-uncovered find (dig THERE, not an x-ray) | `JuiceConfig.findGlint` |
| NEW DISCOVERY! on each first-ever kind | `progress.foundKinds` |
| Retention instrumentation: 6-beat onboarding funnel + per-place-leg minutes | `features/analytics.md` |
| Headless verification harness (runs real modules, no Studio) | `tools/headless-sim/README.md` |
| Adversarial review: 8 findings → 4 fixed, 4 refuted (incl. a CRITICAL spawn pad derived from the wrong constant) | pass 18 |
| Rarity made legible without new art: scenery out of the treasure pool, rarer = bigger, rarer = pulsing | pass 19 |
| Strain: the glow deepens + floods as the last cake comes off, so release is telegraphed | pass 20 |
| `DebugUncoverFind` dev hook — puts a find at the surface on demand; made every find visual verifiable, and immediately caught that 60% of finds had NO anticipation cue | pass 21 |
| **Depth now pays** (Drain the Lake): rare-or-better 14.3% at the surface → 33.7% at the floor, surface distribution unchanged | pass 22 |

**Measured:** layers-to-uncover median **2**; one cake = **126 min** fresh /
**33 min** fully upgraded (eating + forced gym trips). Re-gated after the review:
204 files compile, all 3 treasure modes PASS, pacing unchanged.

**Still open:** ~3 more props for `Workspace.Items` (use the
`InsertService:LoadAsset` recipe in pass 17), re-model the authored tray + room
height in Studio, and publish to read the funnel. See *Open Questions* at the end.

## Task
> "I added several models under `Workspace.Items`. These are the item models
> that should be hidden inside the cake and collected by the player. Right now,
> the items inside the cake are represented by simple circles. Replace those
> circles with the provided models. Make the items fairly large — approximately
> 1.5 to 2 times the size of the player. Players should have to dig the items
> out, after which they should be collected automatically. The items should be
> large enough that fully uncovering one usually requires digging through two or
> three layers… enhance the models with tweens, animations, VFX and other
> satisfying effects."

Part of the standing goal: the most satisfying ASMR loop possible (Drain the
Lake / ASMR Tower reference), aimed at 30+ min sessions and 20%+ retention.

## Context
`TreasureService` rolled finds at cake spawn as `{ cell, revealHeight }`, and
when the surface dropped past the reveal height it cloned a 2.4-stud neon **ball**
at the surface, which despawned after 45 s and was collected by walking within
5 studs. Nothing about eating actually *uncovered* anything — the ball appeared.

Read first: `docs/MAP.md`, `features/treasures.md`, `features/cake-sim.md`,
`features/juice.md`, `flow/2026-07-26_cake-pacing-rebalance.md` (band shape),
`flow/2026-07-26_audio-sfx-music.md` (sound keys).

## Plan
Make the find a real object that is *already in the cake*, and let the
heightfield decide when it is uncovered — so digging is the reveal, not a
trigger that happens to fire while you dig. Then auto-collect with a flourish.

## Changes

**Created:**
- `docs/decisions/0012-buried-authored-finds.md` — the design + rejected alternatives
- `tools/headless-sim/` — Roblox-API stub + bundler that runs REAL `src/` modules
  under the standalone Luau CLI (README covers the two non-obvious constraints)

**Modified:**
- `src/shared/config/TreasureConfig.lua` — added `rarity` per find + a `model`
  section (library name, height-driven sizing with max/min extent clamps, burial
  fractions, preload/reveal/free thresholds, cascade + pop/fly timings) and
  `rarityFx` (client burst/shake/sound/ring per rarity). `spawn.minDepthFraction`
  dropped (depth is now dealt per band).
- `src/server/game/services/TreasureService.lua` — rewritten. Migrates
  `Workspace.Items` → `ReplicatedStorage.Assets.Items`, prepares each template
  once (uniform scale, anchor, inert, `BaseTransparency` attribute, scripts
  stripped), deals finds round-robin over shuffled edible bands, clones models in
  hidden, and runs the buried → loaded → revealed → collected state machine off
  `cover` (MAX field height over the model's own footprint). Server-side
  pop + spin + magnet-flight collect.
- `src/server/game/data/CakeStateData.lua` — treasure entry shape documented.
- `src/server/game/subscriptions/CakeSimulationSubs.lua` — passes the real `dt`,
  fans out the new `revealed` event, and enriches `collected` with
  nameKey/rarity/color/reward.
- `src/client/common/subscriptions/CakeSubsClient.lua` — rarity-scaled treasure
  FX: crown puff + chime on reveal; burst (+ crumb ring for rare+), camera
  shake, floating reward label and a rare+-only banner on collect.
- `src/shared/config/AudioConfig.lua` — `treasureBig` (rare+ pop).
- `src/client/common/data/LocaleData.lua` — `announce-find-{rare,epic,legendary}`.
- `docs/features/treasures.md` — rewritten around the authored contract.

**Also in this pass — the missing rhythm beat:** finishing a layer was
completely SILENT. `CakeSimulationSubs` now broadcasts `layer-cleared` when the
layer gate steps DOWN (never on a new cake, where the index jumps back up);
`CakeSubsClient` answers with the new `layerCleared` chime (reuses an authored
sample — no new SFX content), a camera punch and a ring of crumbs around the
eater; `announce-layer-cleared` = "LAYER CLEARED!". ~28-42 beats per cake, one
every ~1.4 min of a 40-minute run.

## Decisions
- **`cover` = MAX over the footprint, not the centre cell.** A find is only free
  when nothing covers *any* of it, so what the rule says and what the screen
  shows can never disagree. A centre-cell early-out keeps the 2 Hz scan cheap
  (cover ≥ centre always, so skipping is provably safe).
- **Monotonic exposure.** The settle automaton refills craters; letting it
  re-bury a find would punish the player for the simulation.
- **Bottom clamped above the inedible core.** Otherwise a deep find's bottom
  could sit below the absolute floor and never be uncoverable. (The first draft
  had a "band cleared → force free" fallback for this; it fired the instant the
  find's band became active — i.e. free with zero digging — and was replaced by
  the clamp, which makes stranding impossible by construction instead.)
- **Rim `Highlight` stays `Occluded`.** `AlwaysOnTop` is an x-ray treasure radar
  and would delete the dig. It only goes `AlwaysOnTop` for the collect flight.
- **Depth dealt per band, not uniformly.** ~1 find per layer means the reward
  cadence rides ADR-0011's pacing curve for free: harder/co-op cakes have more
  layers, hence more spread-out finds, not a clump.
- **Round-robin model assignment.** Adding art is a drag-and-drop into
  `Workspace.Items`; naming a model in a find def is optional pinning.
- **Server-side collect flourish.** Shared cake → shared moment, and it is a
  timed `task.spawn` loop, not an event subscription (R4).

## Verification — headless simulation (no Studio this session)
Built a **Roblox-API stub + bundler** (`scratchpad/roblox_stub.lua`,
`build_sim.py`) that runs the REAL `TreasureService` / `TreasureConfig` /
`CakeConfig` / `GridUtil` under the standalone `luau` CLI against a simulated
cake being mowed band by band. The stub carries real 3×3 CFrame rotation
because the finds are tilted — an axis-aligned stub would have verified nothing.

9 runs (3 seeds × solo-easy / 4p-hard / no-library):

| Check | Result |
|---|---|
| **Layers needed to fully uncover a find** | mean **1.65-2.27**, **median 2** in every scenario (one seed: 13× one layer, 19× two, 7× three, 1× four) — the requested "usually two or three, one if the layer is thick" |
| Finds revealed / collected | **40/40** every run, **0 stranded** |
| Collect flight completes + destroys the model | 40/40 |
| Finds whose footprint leaves the loaf | **0** |
| Visible surfaces at spawn (would show through the cake) | **0** |
| Live emitters at spawn | **0** |

Bugs the harness caught that review had not:
1. **`Model:ScaleTo` is ABSOLUTE** (relative to the model's *authored* size)
   while the computed factor was relative to its *current* size — preparing an
   already-prepared template silently RESET it to authored size.
2. **`Model:GetBoundingBox()` is in the PIVOT's frame, not world axes** — with
   tilted finds its `.Y` is the model's local height, not the vertical span the
   player digs through. Replaced with a real world-AABB (project each part's
   oriented box onto the world axes).
3. **A constant `edgeMarginCells` is wrong** — a wide prop needs a wider margin
   than a narrow one; 2 of 40 finds poked out of the loaf side. The margin is
   now derived from each find's own footprint radius.
4. **Elongated props laid flat are ~1 stud tall** and got uncovered by a single
   scoop. Fixed by tilting every find (`tiltDegrees` 35) — which also just looks
   right: half-buried objects never lie perfectly flat.

## Verification — LIVE in Studio (desktop control, no Studio MCP)
The Studio MCP registered **zero tools** this session (bridge process running,
nothing exposed — see the memory note). Studio was driven directly with the
desktop-control MCP instead: screenshots + the command bar. That works and is
the fallback whenever the MCP is down.

`Workspace.Items` holds **5 models**: `KK Candy Floor` (6.3×0.9×10.1, a Model of
30 parts), `Yoyle Berry` (12.6×13.3×11.2), `Meshes/Peppermint` (MeshPart
10.6×3.3×10.6), `strawberry` (MeshPart 18.9×13.9×25.6), `candy` (Part
9×4.8×5.8) — a berry, a wrapped sweet, a peppermint, a strawberry and a candy
disc. All on-theme.

Confirmed on screen:
- Library migration + preparation, per-model resulting sizes in the boot log:
  `KK Candy Floor 8.9×11.3×5.4, Yoyle Berry 9.9×10.5×8.8, Meshes/Peppermint
  10.5×3.3×10.5, strawberry 9.0×7.5×10.5, candy 11.4×7.6×6.8` — every longest
  side ≈ 10.5 studs against a **measured 5.73-stud** R15 rig = **1.83×**.
- `40 finds buried in cake #1 (40 authored models, 0 fallback orbs) across 28
  bands` on the production cake (28 layers, 330 studs, 2 253 005 studs³).
- The five prepared models spawned beside the character for a scale check —
  they read clearly "bigger than me" without being absurd.
- **A buried peppermint uncovered by actually digging**, sitting in the crater
  with cake still around it. This is the loop working.
- Layer gate cue, `auto-sweep … tail collapsed`, `layer gate: active band -> #N`
  and the renderer's `layer window -> active #N` across two consecutive layer
  clears.

Two bugs the live run caught that the headless sim could not:
1. **A rotated `Part` was sized from its world AABB**, which is larger than the
   part, so `candy` came out at 14.2 studs — over the cap and visibly out of
   scale with its neighbours. Scale now comes from each model's OWN extents.
2. **The scale rule itself was too clever** (target height, clamped by min/max
   on the largest extent) and produced 0.4-11.3 stud spreads on real art. It is
   now one predictable rule: longest side → `targetSizeStuds` (10.5).

And one UX bug found purely by playing: **the "Eat the top layer first!" nag
fired the instant a layer completed** — the same moment, since you are mowing the
floor when it happens — and stomped the new LAYER CLEARED banner within a frame.
The clear now wins for `LAYER_CLEAR_PRIORITY_SECONDS` (2.5 s).

## Second pass — competitor study, then polish

Studied the three reference games before touching anything else. Two lessons
were directly transferable and both are now in:

**Drain the Lake** — the loop is bucket → tokens → upgrade → deeper, and what
carries it is (a) *"giving each run a goal"* — a countable set of discoverable
chests — and (b) flag markers that tell you where to go, so movement is a
decision rather than a wander.
**+1 Speed Keyboard Escape ASMR** — every single step fires a crisp click AND
compounds a visible number. Zero-latency, per-action, always.

Applied:
- **`FINDS n/N` goal bar.** The cake-% bar is deliberately hidden while eating
  (2026-07-19) — which is ~all of the playtime, so the core loop ran with NO
  progress signal at all. The same bar now carries the per-cake find goal during
  eating (`TreasureService.FindCounts` → `CakeCycleUpdate.finds` → `cakeBarModel`).
  No new component, so no layout risk. **Verified on screen.**
- **Surface GLINT over a nearly-uncovered find** (`near` event → client
  `nearMarkers` → pooled shimmer at the surface point, `JuiceConfig.findGlint`).
  Marks the SPOT, never the item — an x-ray would delete the dig. This is what
  turns blind mowing into "dig *there*". **Verified on screen** (sparkles on the
  icing over buried finds).
- The **layer-cleared beat** (previous pass) is the closest analogue to the
  keyboard game's per-step tick that the cake loop can carry — it now fires ~28-42
  times a cake instead of never.

**A third bug, found only by playing:** a wide/tilted find sat fully exposed and
would not collect. Its cover test sampled the SQUARE BOUNDING BOX of the model,
sized off its LONGEST side — for a 13x5 prop that is metres of cake it never
touches, so one un-eaten corner cell held it hostage. Three fixes, all in
`coverStats`: sample a CIRCLE, size the radius from the AREA-EQUIVALENT extent
(geometric mean, not longest side), and free on a FRACTION of cleared cells
(`freedCoverFraction` 0.95) instead of a strict all-cells MAX. Reveal also moved
from MAX to MIN cover, so the crown announces when the player can first SEE it
rather than when the whole footprint has dropped. Re-verified: 5 seeds, 40/40
collected, mean layers-to-uncover 1.77-2.00 (median 2) — slightly closer to the
brief than before.

## Third pass — the silhouette, settled with evidence

The cake read as a candy-striped TOWER from outside, and I had been treating
that as blocked on pacing risk. It wasn't — it was blocked on not having
measured it. Added `tools/headless-sim/pacing_scenario.lua`, which mows a whole
cake with the REAL `CakeOps.ApplyBite` + layer gate and reports bites, eat-time
and food at several heights:

| height | bands | thickness | density | bites | food |
|---|---|---|---|---|---|
| 330 (shipped) | 28 | 24.0-4.5 | 1.12-3.40 | 33345 | 12128995 |
| **170 (chosen)** | 28 | 12.0-3.4 | 1.50-6.78 | 33510 (+0.5%) | 12129067 (**+0.0%**) |
| 110 (edge) | 28 | 7.0-3.0 | 1.68-**11.72** | 33357 (+0.0%) | 12129022 (+0.0%) |

**Height is a pure visual knob.** Clear time is AREA-driven and per-band
`density = refBandWeight/(thickness × scoop²)` absorbs the thickness change
exactly, so ADR-0011's invariance claim holds through the real bite math to
within a rounding error. ⚠ Not below ~130: at 110 the deepest band's density is
11.72 against `maxDensity` 12 and the thinnest band hits `minLayerThickness` —
clamp either and the invariance breaks.

Changes: `maxTotalHeight` 330 → **170** (~1.8× the 90×78 footprint instead of
3.7×) and `render.wrapper.tileStuds` 26 → **55** (the photo tiled ~12× up the
old wall; now ~3×).

**Then the actual culprit turned up.** Even at 170 the loaf read as a candy-cane
column, because `render.wrapper.textures` still held the two UNRESOLVED DECAL
ids — one renders blank on a `Texture`, and the other is a red/white diagonal
stripe. The resolved cake-photo IMAGE ids existed but were not in this branch's
config. Swapped all three in: the loaf now reads as a **layer cake** — vanilla
sponge, white frosting tiers, rainbow sprinkles. **Verified on screen.**

Side effect, free: thinner bands mean a 10.5-stud find spans MORE of them, so
layers-to-uncover went from mean ~1.7 to **mean 2.1-2.3, median 2** — closer to
the brief than before the change.

## Fifth pass — first-discovery moments

The last untapped retention lever from the competitor study: Drain the Lake
turns collectibles into a countable SET, and the strongest beat in that pattern
is the FIRST of each kind. Here the first berry and the fortieth were identical.

`progress.foundKinds` (a `{ [findId] = true }` set — new field with a default,
so no version bump under P2, string keys so no `intKeySets`, and the sanitizer
only lets `[string] = true` survive) plus
`ProgressService.MarkFindDiscovered(userId, findId)`, which returns true exactly
once per kind. That boolean rides the collect payload as `firstEver`; the client
promotes the find to RARE FX loudness whatever it actually is and shows
`NEW DISCOVERY!`, which outranks the rarity banner.

**Verified on screen:** a common **+2 gem berry** produced the full
`NEW DISCOVERY!` celebration, `FINDS 1/25`, gems 324 → 326. Nine such moments
now exist per player, spread across their first sessions — which is exactly the
window retention is decided in.

## Sixth pass — a "deliberate tradeoff" that was actually destructive

I had documented `prepareTemplate` mutating the authored library in place as a
deliberate prepare-once-clone-cheaply choice. It wasn't defensible. Preparing
rescales the model, anchors it, strips collision **and destroys any child
Scripts** — and the migration log explicitly tells the user to save the place to
keep the library. Save after one run and your source art is permanently
rewritten, scripts included.

Fixed: each library entry is now prepared as an **unparented clone**; the
authored models are never touched. (Clones-of-unparented work fine and cost no
replication.) Verified live — after a full boot `ReplicatedStorage.Assets.Items`
still reports the ORIGINAL sizes: `KK Candy Floor 6.3×0.9×10.1`,
`Yoyle Berry 12.6×13.3×11.2`, `candy 9×4.8×5.8`, `strawberry 18.9×13.9×25.6`,
`scripts=0` preserved. Before the fix these read ~10.5.

**Lesson worth keeping:** "deliberate tradeoff" in a comment is not the same as
a justified one. This one was written by me, one pass earlier, and survived
review because it was labelled as intentional.

## Seventh pass — make retention measurable instead of arguing about it

I had been reporting "retention needs live telemetry" as a wall. It is a wall
for *measuring* it in this session, but not for *building toward* it — and the
game had no instrumentation at all, which meant that even after publishing there
would be nothing to read.

New `AnalyticsSubs` (common, `features/analytics.md`) — the ONE place that talks
to `AnalyticsService` (R4):
- **A 6-step onboarding funnel**: Joined → First Bite → First Find → First Layer
  Cleared → First Fat Burned → First Upgrade. Roblox reports these against D1/D7
  retention directly in the Creator Dashboard, so where first-session players
  stop IS where retention leaks.
- **Session length** on `PlayerRemoving` — the 30-minute target measured rather
  than modelled.
- **Loop counters** (`find_collected`, `layer_cleared`, `gym_banked`,
  `upgrade_bought`) so the funnel steps have denominators.

Beats are pushed IN through the registry (ADR-0009 coupling); every caller
treats the module as optional (`if AnalyticsSubs then`) and every call is
pcall-wrapped, disabling itself after one failure — an unpublished place throws
on every call and telemetry must never take a gameplay path down.

**Verified live:** `[Server/Analytics] karnagiy: onboarding 1 'Joined'` on the
first playtest, with no "unavailable" warning — the calls are being accepted.

## Eighth pass — the map, actually inspected

I had written "the map is untouched" in every report without ever looking at it
deliberately. Flew the camera around it. Findings, so the next session starts
from specifics rather than a hand-wave:

**Reads well.** A small floating candy island — pink hedge border, candy trees,
hot-air balloons drifting past, a tall landmark tower. Coherent, on-theme, and
the cake now sits at a believable proportion inside it (the 330→170 change).

**The cake IS the map.** The island barely extends past the loaf; the walkable
ring outside it is thin. For a dig-focused ASMR game that is defensible — the
cake is the content — but it means there is no exploration layer at all, which
is the one structural difference from Drain the Lake, where routing between
zones is half the loop.

**The one concrete flaw: the cake's base has no stand.** The loaf meets a thin
white tray barely wider than itself, and then flat grass — no plate, no plinth,
no transition. At ground level it reads unfinished, and it is the first thing a
player sees on spawn. The checkpoint platform's legs also sit hard against the
cake side.

**NOT fixed here, deliberately.** The scene is place-authored and cloned
(ADR-0007) — adding a cake stand means authoring geometry in Studio, not
procedurally generating it from code, which R5 and that ADR both forbid. This is
a modelling task for the `ReplicatedStorage.Assets.Environment` template, and
naming it precisely is the useful thing I can do from here.

## Ninth pass — the height change left a trail

I had refused the cake-stand fix as "authoring geometry, forbidden by ADR-0007".
Checking instead of assuming: the tray is NOT authored geometry, it is
`MapConfigData.platform`, consumed by the DEFAULT generator. Which meant the
refusal was wrong, and — worse — led me to look at the rest of that file:

**A regression I introduced.** `room.wallHeight = 380` was sized AND documented
against the old 330-stud cake ("the top sits at 2 + 330 = 332… must clear ~348").
I moved the cake to 170 and left it. Any fresh clone of the repo would build a
cavernous 2×-too-tall room around the loaf — walls that no longer frame anything.
Now 210, with a ⚠ tying it to `maxTotalHeight` so the next person who moves one
moves the other.

**Two more stale statements of the same fact:** `grid.maxHeight`'s comment and
`features/cake-cycle.md` both still asserted "every cake is exactly 330 studs".
Fixed. ADR-0011 said it too — ADRs record a decision at a point in time, so it
got a dated NOTE rather than a rewrite, carrying the measurement and the
130–330 safe band the experiment found.

**And the tray itself**: a 5-stud lip on a 90×78 loaf is what made the cake look
like it met bare grass. Now a ~12-stud lip and a thicker slab — a cake PLATE.
⚠ Default-generator only; the already-authored Environment in this place keeps
its own tray until it is re-modelled in Studio.

**Lesson:** one number changed in one config had three stale restatements and one
functional dependency elsewhere. "Grep for the old value after changing a
documented constant" is cheaper than any of the ways that bites later.

## Tenth pass — my own measurement was incomplete, and two published numbers were wrong

The pacing scenario ran `CakeOps.ApplyBite` and the layer gate but **not the two
forfeiting sweeps** (`sliverSweepStuds`, `remnantSweep`) — which live in
`CakeFieldService.ScanStats`, not in `CakeOps`. So it measured what the player
EATS, never what the cake COSTS. And the sweeps are precisely what cake height
interacts with: both are ABSOLUTE stud distances, so a thinner band has
proportionally more of itself inside the sweep zone. I had halved band thickness
and then measured with the one component that could not see the consequence.

Ported both sweeps in. Corrected numbers:

| | bites | eat time | food | forfeited |
|---|---|---|---|---|
| old 330 | 15 567 | 64.9 min | 10 568 k | **6.2%** |
| **shipped 170** | 15 070 (−3.2%) | 62.8 min | 10 071 k (**−4.7%**) | **8.3%** |
| edge 110 | 14 461 | 60.3 min | 9 241 k (−12.5%) | **12.2%** |

**Two claims I published were wrong:**
1. *"Height is a pure visual knob, food +0.0%."* It costs **−4.7% food and +2.1pp
   waste**. Still well inside ADR-0011's tolerance (the failure it fixed was
   ~25%), so 170 ships — but "free" was an artifact of the incomplete model.
2. *"One cake = 354 min fresh → 33 min maxed; the 30-min floor is structural."*
   Real figures are **63 min fresh → 24 min fully upgraded**. A maxed player
   clears a cake in 24 minutes, so 30+ min sessions come from cake **plus** gym,
   upgrades, boss and the roll into the next cake — comfortable, but NOT
   guaranteed by one cake alone at the top of the upgrade curve.

Both corrected at source (the `maxTotalHeight` comment and the scenario's own
printed conclusion) so the wrong numbers cannot be re-read as fact.

**Lesson:** a model that omits a whole subsystem does not return a small error,
it returns a confident wrong answer. When a measurement says a tuned change is
FREE, that is the moment to ask what the model cannot see.
- ~~The collect was never caught on screen.~~ **CAUGHT.** The whole payoff chain
  in one frame: `RARE FIND!` banner, `+25 Gems` floating label, `FINDS 1/40` on
  the goal bar, and the gem counter ticking 299 → 324 (and persisting across the
  next boot, so the grant + save path is confirmed too).
  **How, for next time:** a full-scale free needs a whole 90×78 layer cleared, so
  make the find nearly-free at spawn instead of clearing a layer — temporarily set
  `model.targetSizeStuds` ≈ 3, `topClearanceStuds` ≈ 1.5, `burialFraction`
  ≈ {0.02, 0.08} (plus the shrunk `composition.footprint`), then stand STILL at
  the cake centre and hold the mouse. Moving at all walks you off a 22×19 loaf,
  which is what defeated the earlier attempts. Revert all four afterwards.
  (To watch a LAYER CLEAR instead, shrink `composition.footprint` to ~7/6/3 —
  a 22×19 loaf clears a layer in ~10 s. Revert after.)
- **Consider making the sweep distances PROPORTIONAL to band thickness.**
  `sliverSweepStuds` (1.5) and `remnantSweep.nearFloorStuds` (2.5) are absolute,
  so on a 3.4-stud band the rim rule reaches 74% of the way up it — that is what
  pushes waste from 6.2% to 8.3%. A cap like `min(nearFloorStuds, thickness*0.25)`
  should recover most of it. NOT done here: the sweeps exist for the clean-eaten-
  zone LOOK, and I could not evaluate the visual cost on screen within budget.
  Measure with `pacing_scenario` first, then eyeball a layer clear in Studio.
- **Re-model the authored tray + room height in Studio.** The DEFAULTS are now
  right (plate 114×102×4, walls 210), but this place's authored
  `Assets.Environment` still has the old bare tray and 380-stud walls — code
  cannot change authored geometry (ADR-0007). Highest-value remaining visual item.
- Model complexity is now a perf input (user-supplied art). Watch the frame cost
  with ~40 resident finds if someone drops a heavy prop in.
- `find.height` is stored but only used for the crown anchor + core clamp; if a
  future feature wants a per-find dig-progress HUD, `find.exposure` is already
  maintained.
- Rarity is currently cosmetic only (FX loudness). Tying rarer models to rarer
  finds needs the authored names — pin them via `finds[].model` once seen.
- **Common finds still pay +2 gems — deliberately NOT changed.** Raising the
  floor without raising expected value is not possible here: berry carries 40 of
  98 roll weight, so doubling it lifts gem EV ~35%. Free-gem income is a
  monetization decision, not an engineering one, and unlike the cake height I
  have no measurement showing a change is free. Flagged, left alone.
- **Retention (20%+) cannot be produced offline.** Playtime now HAS a measured
  floor (see the fourth pass); retention needs live telemetry after publish.

## Eleventh pass — the sweep cap, measured then visually verified

Pass ten left "make the sweep distances proportional to band thickness" as a
recommendation. Ran it instead (`pacing_scenario.lua` §C):

| cap | forfeited | food | clear time |
|---|---|---|---|
| none | 8.3% | — | 62.8 min |
| 0.35 | 7.4% | +2.0% | 63.0 min |
| **0.25** | **6.8%** | **+3.4%** | 63.5 min |
| 0.15 | 6.6% | +3.9% | 63.8 min |

0.25 takes back nearly everything the height change cost (8.3% → 6.8%, against
6.2% before it) for +0.7 min of clear time; below that the returns flatten.
Shipped as `sim.sweepBandFraction`, applied to all three sweep distances in
`CakeFieldService.ScanStats`.

With the cap shipped, the 330→170 height change costs **food −1.8% and +0.8pp
waste** (6.0% → 6.8%), not the −4.7% / +2.1pp pass ten measured without it — so
the cap recovers most of what the silhouette fix cost.

**The visual risk it was blocked on is now checked.** The sweeps exist for the
clean-eaten-zone LOOK, so a gentler sweep risked leaving ragged crumbs — the
reason I had not simply changed it. Cleared a layer on a shrunk loaf and looked:
smooth eaten floor, clean cliff edge, no crumbs, no isolated pillars, and
`auto-sweep … 26 studs³ forfeited` against 47 on the same loaf before. Look
preserved, waste down.

The same playtest confirmed the analytics chain end to end:
`AnalyticsService: LogOnboardingFunnelStepEvent event fired` alongside
`[Server/Analytics] onboarding 2 'First Bite'` and `onboarding 4 'First Layer
Cleared'`, plus `LogCustomEvent event fired`.

## Twelfth pass — rarity made legible

Models were assigned purely round-robin, so a **legendary** find could dig up as
a floor tile while a common berry got the strawberry. The reward read as random
rather than earned — and now that the authored names are known, that was fixable.

Pinned the four finds whose meaning matches available art:
`berry`→`strawberry`, `candy-gem`→`candy`, `charm`→`Meshes/Peppermint`,
`capsule`→`Yoyle Berry`. The other five still round-robin: the library has **5
models for 9 finds**, so the single best art investment is 5 more props.

Also made the assignment AUDITABLE (R8): the boot log now prints the resolved
mapping with `*` marking a config pin, and an unresolvable pin (renamed or
removed art) WARNS instead of silently falling back to a plausible-looking find —
that failure would otherwise be invisible.

**Verified live** against the real library:
`…gem=candy*, capsule=Yoyle Berry*, charm=Meshes/Peppermint*,
trapped-pet=strawberry, whisk=candy` — pins resolved, fallbacks unstarred, no
missing-pin warning.

## Thirteenth pass — make the collection visible

Pass five built the 9-kind discovery set and the first-discovery moment, but a
player had no way to SEE their progress through it — the completionist hook was
invisible, which is most of its value. Drain the Lake's equivalent is a badge
counter you can check.

Surfaced it with **zero new UI**: `ProgressService.CountFindKinds` counts the
`foundKinds` set, rides `Summary`, and `LeaderboardSubs` shows it as a **`Finds`**
column. It replaced `Belly` (biggest belly) — a joke stat with nothing actionable
behind it, where "6/9 kinds found" is a goal you can act on and a reason to come
back for the missing three.

**Verified live:** `LEADERSTAT Calories 2237206 / Cakes 0 / Finds 1` — and 1 is
exactly right, because this session collected exactly one KIND (the lost-phone),
not one pickup.

## Fourteenth pass — Toolbox prop insertion: ATTEMPTED, FAILED, place left clean

The brief says to source assets from the Toolbox directly, and I had been
assigning "add ~5 more props" to the user. That was mine to do. Attempted it.

**It did not land.** Searched 3D Assets (`donut dessert`, 435 results), inserted
a pink sprinkled donut — it appeared in Workspace as `donut 1` alongside a
`ToolboxTemporaryInsertModel`. Then the Toolbox floating dock (a separate Qt
top-level window, title `Toolbox`) **captured all keyboard/mouse input**: the
command bar stopped accepting text, Explorer drag-to-reparent did nothing, and
clicking its X did not close it. Recovered by `SendMessage(hwnd, WM_CLOSE)` from
PowerShell and re-focusing the place window — after which the command bar worked
again — but by then the cleanup pass destroyed both inserted objects rather than
moving the donut into `Items`.

**End state is CLEAN and verified:** `WORKSPACE models/parts: Terrain,
SpawnLocation` (no stray inserted content) and `Items children: 5` (the original
five, `scripts=0`). Nothing was left in the place and nothing was damaged.

**For the next attempt:**
- Close the Toolbox dock BEFORE trying to use the command bar —
  `SendMessage(hwnd, 0x0010)` on the window titled `Toolbox`, then
  `SetForegroundWindow` the place window. Studio's Qt docks steal input in a way
  clicking cannot undo.
- Inserted content arrives as a Workspace sibling AND a
  `ToolboxTemporaryInsertModel`; handle them separately, and **strip
  `BaseScript`/`RemoteEvent`/`RemoteFunction` before anything enters the
  library** — free models are a known malware vector and `prepareTemplate` only
  strips scripts from the CLONE, not from the authored original.
- **Retried in a fifteenth pass with the WM_CLOSE fix.** The dock-focus problem
  WAS solved by it — the command bar accepted input again. But the insert
  CLICKS then stopped registering on the freshly-reopened Toolbox panel, so
  nothing arrived in Workspace at all (verified: only `Terrain` and
  `SpawnLocation`). Two attempts, ~25 turns, zero props added, place clean
  both times.
- **Conclusion: STOP automating this one.** Dragging a Toolbox model into
  `Workspace.Items` takes about five seconds by hand and has now defeated
  remote control twice for different reasons. The remote path is only worth
  retrying if the Studio MCP (with a real `insert_model`) comes back — driving
  the Toolbox GUI through screenshots is not a reliable tool for this job, and
  recognising that is worth more than a third attempt.

## Sixteenth pass — session length, with the loop that was missing

The playtime model measured PURE EATING and ignored the belly→gym cycle: the
belly fills, blocks eating, and forces a walk to the checkpoint and a burn before
you can eat again. That is not a rounding error — it is a mandatory, repeating
interruption, and leaving it out understated a session the same way leaving the
sweeps out overstated the food. Same class of mistake, found the same way.

Added it (`capacity`, `burnSpeed` from `UpgradeConfig`; a 14 s round trip):

| eater | eating | gym trips | **one cake** |
|---|---|---|---|
| fresh, no upgrades | 63.5 min | 123 trips / 62.9 min | **126 min** |
| **fully upgraded** | 23.9 min | 35 trips / 9.1 min | **33 min** |

**The 30-minute target holds at BOTH ends of the upgrade curve** — which pure
eating time did NOT show (it put a maxed player at 24 min, under target). And 33
min still EXCLUDES the boss fight, upgrade stops and walking between craters, so
it is a floor, not an estimate.

Note the shape this reveals: a fresh player spends ~50% of the session at the
gym, a maxed player ~28%. The upgrade curve is not just "eat faster", it is
"interrupted less" — which is the right feel for an ASMR game and worth keeping
in mind when tuning `capacity` vs `burnSpeed`.

## Seventeenth pass — the Toolbox, finally, by script

Two passes failed trying to DRAG a Toolbox model into the library. The mistake
was the APPROACH, not the execution: there is a scripted path I never tried.

**Right-click → Copy Asset ID in the Toolbox, then `InsertService:LoadAsset(id)`
from the command bar.** No drag, no dock-focus fight. Worked first try. Added a
pink sprinkled donut (`71594297607550`) — **6 models now, up from 5.**

Verified live end to end:
- `library ready — … donut 1 10.5x4.3x10.4` — the prop arrives at **408x165x402
  studs** and `prepareTemplate` brings it to target automatically. The sizing
  pipeline handles arbitrary Toolbox art with no hand-tuning.
- `find art (* = pinned): berry=strawberry*, candy-gem=candy*,
  capsule=Yoyle Berry*, charm=Meshes/Peppermint*, golden-slice=donut 1*` —
  **5 of 9 finds pinned**, up from 4.

⚠ Two constraints:
- `LoadAsset` returns *"User is not authorized to access Asset"* for assets
  without distribution rights (2 of the 3 ids I tried, both older uploads). Only
  some Toolbox results are scriptable — try, and fall back to another result.
- Free models can carry scripts. Strip `BaseScript`/`RemoteEvent`/
  `RemoteFunction` BEFORE parenting into the library — `prepareTemplate` only
  strips the CLONE, so the authored original would keep them.

**Lesson:** I spent two passes concluding "this can't be automated, do it by
hand", when the real problem was that I was automating the wrong LAYER. GUI
automation failing is not evidence a task is manual — it is evidence to go
looking for the API underneath it.

## Eighteenth pass — the adversarial review, and what it actually caught

Ran a fan-out review over the whole change (13 agents: per-file finders, then
independent skeptics prompted to REFUTE each finding). **8 findings, 4 confirmed,
4 refuted.** All four confirmed are fixed here; the four refuted are recorded
because a refuted finding that isn't written down gets re-raised every review.

### Confirmed and fixed

| # | Where | Defect | Fix |
|---|---|---|---|
| 1 | `MapService` | **CRITICAL — spawn pad derived from the wrong constant.** The boot `CakeSpawn` pad used `origin.y + grid.maxHeight * 0.6`. `grid.maxHeight` is the **u16 field headroom (340)**, not a cake height, so the pad sat at 214 — 39 studs above the actual cake top (175), and in a room built by the `buildEnvironment` generator (walls + `Ceiling` at `room.wallHeight + 1` = 211) that is ON TOP of the sealed ceiling. | Derive from the cake: `origin.y + composition.coreThickness + composition.maxTotalHeight` → pad 183, above the cake, below a generated ceiling. |
| 2 | `CakeSubsClient` | **Glint-marker leak.** A find still in `loaded` when the cake resets never sends its `revealed`, so its `nearMarkers` entry survived forever — glinting a spot on the NEXT cake that holds nothing, and eating the `maxMarkers` budget real finds need. | Clear on `cakeIndex` change, before the yielding rebuild (the supersede guard can early-return past it). Guarded on the index, not unconditional: `SendSnapshot` re-sends the current cake to a joining player and would otherwise wipe live markers. |
| 3 | `AnalyticsSubs` | **`session_minutes` was not a session.** Two places (ADR-0009) ⇒ every lobby↔game teleport ends the player on this server, so a per-server timer measures ONE LEG. The headline 30-minute number would have been reported as "3 + 26". | Renamed to `place_minutes_lobby` / `place_minutes_game` — the game leg IS the engagement number, lobby time is queue overhead. True cross-place session length comes free from Roblox's built-in engagement metric; don't rebuild it. |
| 4 | `AnalyticsSubs` | `os.clock()` is documented as **CPU time used by Lua**, so on a mostly-idle server it can run behind wall time and under-report. | `os.time()`. Whole seconds is ample for a minutes-scale stat. |

Finding 1 is the one worth the whole review: it is invisible in every headless
scenario (nothing here renders or collides), and a constant named for the
*storage format* got read as if it were named for the *cake*.

**Severity, measured rather than asserted.** I first wrote this up as "arrivals
spawn on top of a sealed ceiling", which is the generated-room case. Inspecting
the live place (pass 19) showed it has a **rich hand-authored `Assets.Environment`
— 460 parts, balloons, towers, islands — and no ceiling at all**, because
`buildEnvironment` runs ONLY when the authored template is missing. So here the
symptom was a 39-stud drop onto the cake, not a hard break; the hard break is
what a fresh template copy (generated room, `Ceiling` at `wallHeight + 1`) would
have hit. The fix is unchanged and still required — but the severity claim was
mine to verify before publishing, and I had not.

### Refuted, with the reason

| Claim | Why it does not hold |
|---|---|
| `ScaleTo(GetScale() * scale)` compounds across spawns | Templates are prepared once and cloned; a clone inherits the prepared scale and is never re-prepared. |
| `freedCoverFraction = 0.95` can strand a find whose footprint spills off the loaf | Placement clamps the footprint inside the field (pass six replaced the old force-free fallback with exactly this); the scenario asserts `footprint leaves the loaf: 0` on every run. |
| `Onboard` silently drops beats for a player with no `reached` entry | That is the correct behaviour — no entry means the player already left; logging then would attribute a beat to a departed session. |
| Analytics `disabled` latch is a race across coroutines | Luau is single-threaded per VM; the latch is only ever read/written between yields. |

### Re-gated after the fixes
- `luau-compile` over the tree: **204 files, 0 failures**
- `treasure_scenario` × 3 modes (`easy`, `hard`, no-library): **PASS**, 40/40
  revealed + collected, 0 footprints off the loaf, layers-to-uncover median 2
  (easy) / 2 (hard) / 3 (orb fallback)
- `pacing_scenario`: unchanged (126.4 min fresh / 32.9 min maxed, waste 6.8%) —
  as expected, none of the four fixes touches pacing

### Two harness papercuts fixed while re-gating
- `build_sim.py` argv[2] is the **mode**, not the scenario file (the file is the
  `SCENARIO_FILE` env var). Passing a filename fell through to the else-branch
  and ran the no-library case while looking like a pass of the case I asked for.
  README now says so explicitly.
- The harness `Log.Once` stub ignored the key and printed every call — 36 lines
  of what looked like an R8 violation for 5 genuine warnings. It now dedups like
  the real `Log.Once`. **A stub that is louder than the real thing is a stub that
  trains you to ignore the log.**

## Nineteenth pass — the live place, and why "verified" needed re-verifying

Went into Studio to close the two remaining art/scene items. Neither ended where
I expected, and the pass produced one genuinely alarming tooling finding.

### Rojo was silently blocking every sync
The Rojo panel was sitting on an **unaccepted "Sync changes" confirmation**, so
the place had been running code older than disk — and nothing anywhere says so.
The Output looks healthy, the plugin says "Connected", a playtest runs fine; it
just runs the *previous* code. I only caught it because a boot log I had just
written (`scenery (pin-only …)`) never appeared. **A live playtest is not
evidence unless you first prove the code under test is the code you wrote.**

Follow-on trap, which cost a second wrong reading: my first sync probe used
`require(...)` and reported STALE *after* the sync was accepted — because
`require` caches per Studio session, so a cached stale table is indistinguishable
from an unsynced module. Probe `.Source`, never `require`, when the question is
"did this sync".

Verified after accepting: `TreasureConfig`, `TreasureService`, `MapService` and
`AnalyticsSubs` all carry this session's markers.

### The scene inventory changed two conclusions
Dumped the live tree through a localhost bridge (Studio POSTs a report, no
OCR — `tools`-adjacent, see below). It showed:

- `Assets.Environment` is **460 hand-authored parts** (balloons, towers,
  islands, `CakePlate` 100×2×88) — NOT the code-generated default. So the
  "re-model the room" followup is wrong as written: `buildEnvironment` only runs
  when the template is MISSING, this place never uses it, and deleting the
  authored scene to regenerate it would have destroyed real work. Corrected the
  pass-18 severity claim to match (see there).
- `Workspace.Items` holds 6 models, **zero scripts/remotes** — the library is
  clean.
- `Checkpoint` is still the generated primitive set (GymMachine = a 4×6×4 box).
  That, not the room, is the highest-value remaining art job.

### Toolbox sourcing: the pass-17 recipe does not generalise
Tried to add the 4 missing props. **16 of 16 candidate assets failed
`InsertService:LoadAsset` with "User is not authorized to access Asset"** —
across old and new id formats, so the id-era hypothesis is dead too. The
toolbox-service search API happily returns assets that only the *authenticated
Toolbox insert path* can fetch; `LoadAsset` reaches a strictly smaller set. The
Toolbox dock still refuses to open under automation (same as passes 14-16).
Recipe demoted from "the way" to "worth one try, then stop".

### So rarity got fixed where it was actually broken — in code
Not having new art is not the same as not being able to fix "rarity is
illegible". Three changes, all art-independent, all of which work with whatever
the user drops in later:

| Change | Why |
|---|---|
| `model.sceneryModels` | the candy FLOOR TILE was in the treasure pool; a legendary could dig up as scenery. Now pin-only. Live-verified: `scenery (pin-only, out of the round-robin): KK Candy Floor`, and the art mapping no longer assigns it. |
| `model.rarityScale` | size is the only rarity cue readable while a find is still buried. |
| `rarityFx[].glowPulse` | `highlightPulseHz` had been declared in config since the rework and **never read by any code** — dead config that looked like a feature. Now drives a rarity-depth pulse on the exposed crown. |

**The rarityScale mistake is the one worth keeping.** My first cut centred the
band on 1.0 (common 0.85 → legendary 1.45) and the sim immediately showed
one-layer finds going 13/40 → 15/40: I had traded away the user's explicit
"usually two or three layers" to buy a cue that was my own idea. Rewrote it to
scale only UPWARD (common/uncommon 1.0, legendary 1.28) — dig depth returns to
exactly baseline (mean 2.05, median 2, 13 one-layer) and rare finds are still
visibly bigger. *A cue that costs a stated requirement is not free, and the sim
is what makes that visible in seconds instead of after a playtest.*

### Re-gated
`luau-compile` 204 files / 0 failures; treasure scenarios easy + hard + no-library
all PASS (40/40, 0 off-loaf); pacing unchanged. Live in Studio: library resolves
5 treasure models + 1 scenery, 40 finds buried, 0 fallback orbs.

### Bridge tooling
Studio↔agent readout now goes through a tiny localhost HTTP bridge (Studio
`PostAsync`es a report, the agent reads a file) instead of screenshotting the
Output window. Structured, greppable, and it does not lie about what scrolled
off. ⚠ Studio gates `HttpService` use from the command bar behind a "Dangerous
Command Detected" prompt — click **Continue**, never "Always Continue" (that
disables the user's safety prompt permanently). Also: the command bar's
autocomplete eats the Return key, so long one-liners must be run with the Run
button, and a mis-aimed click lands in the script EDITOR — I typed into
`Log.lua` once; `rojo serve` is one-way so disk was untouched, but check.

## Twentieth pass — the anticipation beat, and a pivot trap

The flattest moment in the whole dig was the one right before the payoff: once a
find's crown broke through, the only thing that changed until release was the
sparkle rate. Added **strain** — from 45% of the footprint cleared, the rim pulse
deepens and the glow fill floods in, so the release is something you can see
coming.

**The first version was wrong and the sim caught it in one run.** I animated the
model's POSE (a shudder). Result: `FAIL — 6 stranded find(s)`, in exactly the two
scenarios that use Models, and exactly `MAX_GLOWS` of them — my block was gated on
`find.glow`, so it broke precisely what it touched. Zeroing the amplitudes still
failed, which ruled out the motion and pointed at the write itself:

> `Model:GetPivot()` on a model with **no PrimaryPart** returns
> `CFrame.new(<recomputed AABB centre>)` — **identity rotation**. So `PivotTo`
> computes each part's offset relative to a frame that has already lost the
> previous rotation, and re-applies the new rotation on top. Per-tick pose writes
> COMPOUND, and the find walks out of its own hole.

Reworked as a pure property animation (two writes on the existing `Highlight`):
same design intent, no geometry mutation, no pivot semantics involved. Scenarios
returned to **40/40 collected, mean 2.05 / 2.42 / 3.50, median 2 / 2 / 3 —
identical to baseline**.

Worth keeping: the reveal/free logic was never at risk either way (it reads only
cached spawn values — `radiusCells`, `x`, `z`, `topUnits` — never live geometry).
The damage was entirely to where the model ENDED UP. "The simulation can't be
perturbed" and "the visuals can't be broken" are different claims, and I had
checked the first while assuming the second.

**Verification status, stated precisely.** Compile gate green (204 files), all
three scenarios PASS, **synced and boots clean in Studio**:
`pulseGain=YES fillGain=YES` in `TreasureConfig`, `strain.pulseGain=YES
FillTransparency=YES restCf=no` in `TreasureService` (the `no` is the signal that
the reverted pose animation is gone), 40 finds buried, 0 fallback orbs, no
warnings on the treasure path.

**RESOLVED in pass 21 — see below. The rest of this section is the record of the
attempt that failed first.**

NOT seen on screen: the escalation itself — and I tried. Ran the documented
forcing recipe (shrink `CakeConfig.composition.footprint` to
`{hx=7,hz=6,corner=3}` + `topClearanceStuds` 8 → 2, giving a 22×19 loaf with 25
finds), played, and could not get a find to reveal inside a reasonable number of
attempts. Two things got in the way, both worth writing down because the recipe
as recorded is incomplete:

1. **You spawn in the crater, not on fresh cake.** The checkpoint plate sits in
   an already-cleared pocket, so the first bites hit the layer gate
   (`Eat the top layer first!`) and then, once past it, chewed at a surface that
   was already at floor — belly never moved. The recipe needs a step: walk OFF
   the checkpoint onto un-eaten top-layer cake before holding the mouse.
2. **Even then, reveal needs a find near the surface under YOUR footprint.**
   `topClearanceStuds = 2` makes finds *eligible* to sit high; it does not put one
   where you happen to be standing. A reliable version of this test probably wants
   a debug command that force-reveals the nearest find, rather than eating toward
   one and hoping.

Config restored and verified byte-exact (`footprint = { hx = 30, hz = 26,
corner = 10 }`, `topClearanceStuds = 8`, zero `TEMP` markers anywhere under
`src/`), compile + all three scenarios re-gated green afterwards.

So the strain beat's status is: **synced, compiles, boots clean, sim-passing,
visually unconfirmed.** That is a weaker claim than "verified" and it should stay
weaker until someone watches a find come loose.

### Why the command bar "broke" — it didn't
Three tool-level traps stacked into what looked like a dead command bar, and all
three are worth knowing:
1. **`HttpService` cannot run from the command bar during a playtest.** The bar
   defaults to the CLIENT context in play mode, and the client is not allowed to
   make HTTP requests: `Http requests can only be executed by game server`. Stop
   the playtest (or switch context via `Test ▸ Toggle Client View`).
2. **The Output FILTER hid the error that said so.** The filter was still set to
   `Treasure` from an earlier step, so the one line explaining the failure was
   filtered out and the bar looked like it was silently doing nothing. Clear the
   filter before diagnosing anything.
3. **The Run button MOVES** as the command bar grows a line (Return inserts a
   newline rather than executing, because autocomplete eats it), so a click at
   the remembered coordinate silently no-ops.

Cost: ~8 turns of "the tool is broken" when the tool was working and reporting
correctly the whole time — into a filter I had set myself.

### Bonus: the analytics rename verified itself
Stopping the playtest printed
`AnalyticsService: LogCustomEvent event fired.` followed by
`[Server/Analytics] karnagiy: place_minutes_game 18.2` — the pass-18 per-leg
rename firing end to end on `PlayerRemoving`, with the leg correctly resolved to
`game`. That one is now live-verified, not just reasoned about.

## Twenty-first pass — build the instrument, then measure

Two passes in a row ended with "the strain beat is sim-verified but visually
unconfirmed", and the forcing recipe (shrink the loaf, replay, revert) had just
failed. The problem was not the feature, it was that **the game had no way to put
a find in front of you on demand** — so every find-related visual was
structurally unverifiable, and would stay that way for every future change too.
So I built the instrument first.

### `TreasureService.DebugUncoverNearest(position, leaveFraction)`
Carves the field away over the nearest still-buried find until `leaveFraction` of
its footprint is still covered, then lets the **normal** `Tick` walk it through
`loaded → revealed → strain → freed`. It deliberately does NOT set states
directly — bypassing the path under test would verify nothing.

Driven from a Studio-only hook in `CakeSimulationSubs` (R4: the event lives in
the subscription, the logic in the service):

```lua
workspace:SetAttribute("DebugUncoverFind", 0.5)  -- revealed, mid-strain
workspace:SetAttribute("DebugUncoverFind", 0)    -- uncovered, frees next tick
```

An **attribute**, not a direct call, because the command bar keeps its own
require cache even in play mode — `require(TreasureService)` there hands back a
fresh module with empty state, so the running server is only reachable through
something it is already watching. Gated on `RunService:IsStudio()`.

### It found a design bug within one minute of existing
First use uncovered a `berry` — **common** — and nothing happened. The strain
block was nested inside `if glowPulse > 0`, and `glowPulse` is 0 for common by
design. So **berry + candy-gem, 60 of 98 roll weight, got no anticipation cue at
all**: the majority of finds in the game. The fill is a "this is about to come
loose" signal and the pulse is a rarity signal; I had conflated them. Fixed —
fill now applies to every revealed find, pulse depth stays rarity-gated.

### Then it measured the thing, on a common find
Carving progressively more of the same `candy-gem` and reading the live
`Highlight` off the server:

| Cake left over the find | clearFrac | Glow `FillTransparency` |
|---|---|---|
| keep 50% | ≈0.49 | **0.814** |
| keep 15% | ≈0.84 | **0.502** |
| keep 6% | ≈0.94 | **0.410** |

Template baseline is `0.850`. The values match `0.85 - 0.45 × pull` to three
decimals, `Outline` correctly stayed at `0.100` (common ⇒ no pulse), and the
colour came back `(90,200,255)` = `candy-gem`'s configured colour. Glow opacity
roughly **doubles** across the anticipation window.

That is the strain beat verified live, quantitatively, on the exact rarity that
had been silently broken an hour earlier.

### End-to-end proof, with the tool doing the work
With the hook in place the whole user-facing mechanic verifies in about a minute,
so it is now cheap to re-check after ANY change:

| Step | Evidence (Studio, 2026-07-29) |
|---|---|
| models replace the old orbs | `40 finds buried in cake #1 (40 authored models, 0 fallback orbs)` |
| art resolves per find | `find art (* = pinned): berry=strawberry*, candy-gem=candy*, charm=Meshes/Peppermint*, capsule=Yoyle Berry*, golden-slice=donut 1*` |
| dig → uncover | `DEBUG uncovered 'berry' (common) — carved 29/81 footprint cells, keeping 0%` |
| auto-collect + reward | HUD `FINDS 0/40 → 1/40`, gems `446 → 448` — exactly berry's configured `+2` |

A strawberry MODEL was buried, dug out, strained, popped, flew to the player and
auto-collected, granting precisely its configured reward. That is the user's
original ask ("replace the circles… players should have to dig the items out,
after which they should be collected automatically") demonstrated rather than
asserted.

**The lesson is the ordering.** I spent two passes trying to observe a thing and
one pass building the instrument that observes it — and the instrument paid for
itself immediately by finding a bug that neither the compiler, the sim, nor a
code review had caught, because none of them can tell you "the majority of finds
show nothing". When verification keeps failing, stop retrying the observation and
go build the thing that makes it cheap.

## Twenty-second pass — competitor study (all three), and the one thing we were missing

Re-ran the study of the three reference games and checked each finding against
what this game actually does, rather than assuming.

### *Drain the Lake* — DEPTH PAYS. We did not do this.
What the loop is praised for: *"a bucket that earned a trickle near the surface
can be worth far more at the bottom… the rhythm becomes a satisfying spiral"* —
upgrade, drain deeper, unlock, same effort now earns more.

EatACake had **no depth incentive at all**. `weightedFind()` took no depth
argument, and bands are SHUFFLED before finds are dealt round-robin — so a
legendary was exactly as likely in the top layer as at the bottom. The cake got
harder as you went down and paid exactly the same, which is the opposite of the
spiral.

Fixed: each tier's roll weight is now multiplied by
`(1 + spawn.depthRarityBias * depth)^tier`. Depth 0 leaves the distribution
**byte-identical** (so the first minutes are untouched); only the deep end skews.

| tier | surface | mid | bottom | shift |
|---|---|---|---|---|
| common | 61.2% | 50.3% | 40.4% | 0.66× |
| uncommon | 24.5% | 26.2% | 25.9% | 1.06× |
| rare | 8.2% | 11.3% | 13.8% | 1.69× |
| epic | 4.1% | 7.4% | 11.0% | 2.71× |
| legendary | 2.0% | 4.8% | 8.8% | **4.33×** |

Rare-or-better goes **14.3% → 33.7%** from surface to floor. Nothing is ever
guaranteed, so the bottom is a better lottery, not a payout.

It also composes with `rarityScale` for free: deeper ⇒ rarer ⇒ physically bigger
⇒ a longer dig. The best rewards are now the deepest and slowest to free, which
is exactly where anticipation should sit. Measured cost: layers-to-uncover mean
2.05 → 2.27 (easy) / 2.42 → 2.58 (hard), **median still 2** — the user's "usually
two or three layers" spec holds.

### *ASMR Tower* — PER-MATERIAL SOUND. Already done.
Its identity is *"every platform type produces a unique satisfying sound"* —
butter, jelly, slime, keyboard. Checked before building anything: EatACake
already ships six distinct bite samples (`squish`, `crumble`, `blorp`, `pshhh`,
`stretch`, `shhh`) mapped one-per-layer-material through `CakeConfig.layers[*].sfx`,
consumed at `SoundPool.PlayBite(layer.sfx, combo)` and again for walk-crunch, with
combo-driven pitch on top. No work needed — worth recording so the next pass does
not rebuild it.

### *+1 Speed Keyboard Escape | Candy & Chocolate* — mostly already done
The biggest of the three (~396k CCU, 3.39B visits), and its hook is in the title:
**every step equals +1**, a visible micro-reward on every single action, plus
"satisfying keyboard clicks, creamy visuals and relaxing candy sounds".

Checked each transferable piece against this game:

| Their pattern | Us |
|---|---|
| a visible `+N` on EVERY action, never a dead moment | **already done** — `BodySubsClient` shows `+{gained}` per bite, sized by `ComboMeter.Intensity()` and recoloured during glutton ×2 |
| per-material tactile sound | **already done** (see ASMR Tower above) |
| unlockable multipliers | **already done** — `TreasureConfig.boosts` (`golden-slice` ×2 calories), glutton ×2, the upgrade tree |
| compete with others on the server | **already done** — leaderstats, incl. the `Finds` discovery set added this task |
| **speed also accrues from time on the server** | **deliberately REJECTED — see below** |

**Rejected: passive time-based accrual.** It is a real driver of session length in
that genre, and it is the one pattern of theirs we do not have. Rejecting it
anyway for two reasons: (a) playtime is already **126 min fresh / 33 min maxed**,
4× the 30-minute target, so it buys a metric that is not short; and (b) it pays
the player for NOT playing, which is directly at odds with an ASMR game whose
entire value is the moment-to-moment act of eating. Cargo-culting a mechanic from
a game with a different core loop would cost the thing this game is actually for.
Recorded here so the next pass does not re-derive it as an oversight.

**Worth noting about the method:** three competitor games, and of every pattern
they yielded exactly ONE was missing (depth pays), four were already implemented,
and one is a considered rejection. Checking first cost a handful of greps;
assuming either way would have cost a duplicated system, a missing one, or a
mechanic that fights the core loop.

## Open Questions / Followups

- **Publish — and note the shop is DEAD until 15 ids are filled in.** All 9 dev
  products + 6 game passes are still `0`, plus `SocialData.groupId`. An unset id
  renders the shop cell in its disabled "SOON" state, so a first-session player
  opening the shop sees a wall of dead buttons — that is a day-one RETENTION
  problem, not just a revenue one, and the funnel would record the drop without
  explaining it. Full fill-in table: `docs/recipes/publish-readiness.md`.
- **Publish and read the onboarding funnel.** It is instrumented (6 first-session
  beats + per-leg minutes + loop counters). Retention is a fact about players; no
  offline work produces it, but the diagnosis is now waiting to be read.
- ~~Re-model the authored tray + room height in Studio.~~ **WRONG as written —
  corrected in pass 19.** `Assets.Environment` in this place is 460 hand-authored
  parts (balloons, towers, islands, `CakePlate` 100×2×88), not the old generated
  room, and `buildEnvironment` only runs when the template is MISSING — so the
  `wallHeight`/`platform` defaults never apply here and there is no 380-stud wall
  to fix. Do NOT delete the authored Environment to force regeneration.
- ~~Re-model the CHECKPOINT — the real remaining art job.~~ **ALSO WRONG, and for
  the SECOND time in the same way (pass 23).** The Checkpoint is already authored:
  `CheckpointPlate` carries 18 parts / 18 meshes plus authored `Crate` ×3 and
  `Fence` ×6; `GymMachine` is `Transparency = 1.0` — an INVISIBLE COLLIDER —
  wrapping a 25-part, 5-union treadmill; `UpgradeStationBody` is likewise an
  invisible collider around a 10-part model and a `basic table`. The bare
  `4×6×4` / `4×5×3` boxes reported earlier ARE the colliders; that is the intended
  contract (code positions the collider, the art rides inside it).

  **Both false to-dos came from the same bug in my own tool:** the inventory
  script listed `GetDescendants()` for `Environment` but only `GetChildren()` for
  `Checkpoint`, so anything whose art hangs one level down read as an empty
  primitive. An audit that inspects containers at inconsistent depths will invent
  work that does not exist — and I reported that invented work to the user
  repeatedly before checking. Probe depth is part of the probe's contract.
- **Common finds pay +2 gems — deliberately unchanged.** Berry carries 40 of 98
  roll weight, so lifting the floor raises gem EV ~35%; that is a monetization
  call, not an engineering one. The first-discovery moments (pass five) address
  the underlying "every find feels the same" complaint at zero gem inflation.
- Model complexity is a perf input (user-supplied art) — watch the frame cost
  with ~40 resident finds if a heavy prop goes into `Items`.
- **Add ~4 more props to `Workspace.Items`** (`bolt`, `whisk`, `lost-phone`,
  `trapped-pet` still round-robin). ⚠ Pass 19: this needs a HUMAN in the Toolbox
  — 16/16 candidates failed `InsertService:LoadAsset` with "User is not
  authorized to access Asset", so the pass-17 recipe does not generalise (see
  pass 19). Drag from the Toolbox dock, then check the boot log shows the new
  names. Note rarity legibility no longer BLOCKS on this: pass 19 made rarity
  readable through size + pulse + the scenery exclusion, so more props are now a
  variety win rather than a correctness fix.

## Tooling note
`rojo build` does not parse Luau (memory + prior flow docs). This session used
the official **`luau-compile`** CLI (luau-lang 0.731, downloaded to the
scratchpad) as a real syntax gate over the whole `src/` tree — 204 files, 0
failures. That is a strictly better pre-Studio check than `rojo build` and costs
one download.

## Related
- Feature: `docs/features/treasures.md`
- ADRs: ADR-0012 (new), ADR-0007 (place-authored assets), ADR-0011 (pacing curve)
- Prior flow: `docs/flow/2026-07-26_cake-pacing-rebalance.md`,
  `docs/flow/2026-07-26_audio-sfx-music.md`
