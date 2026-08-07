# Upgrades (hexagon tier tree)

## What it does
Nine calorie-bought stats bought as discrete **TIERS** in a **hexagon
honeycomb** UI (GDD §10), grouped in three categories:
- **eating** — biteRadius / biteDepth / eatSpeed
- **body** — capacity / runSpeed
- **gym** — gymEff (calories per burn) + the fat-burn stats **burnSpeed**
  (passive drain rate), **burnPerTap** (fat per tap), **instantBurn** (fat
  removed on press; final tier = whole belly). See `features/body-gym.md`.

`upgrades.levels[id]` = tiers OWNED (0 = none, `#tiers` = maxed). Tier values +
costs ONLY in `Shared/config/UpgradeConfig`; ALL derived numbers come from
`StatsService` (server) / `LocalStatsService` (client mirror).
⚠ The tier is no longer the whole story: `StatsService` also multiplies
biteRadius / walkSpeed / capacity by any live timed BOOST, and the client mirror
only learns about the bite one through a player attribute
(`features/boosts.md`).

## RUN-SCOPED (2026-07-30, ADR-0013) — the tree is not permanent meta
Every profile load wipes `upgrades.levels` (all tiers → 0), `economy.calories`
and the belly — which covers both halves of the rule "reset on entering the lobby
AND on starting a new run", because the lobby↔game handoff reloads the profile on
each teleport (ADR-0009). A run starts as a base eater and buys the WHOLE tree
back inside one cake. Owner: common `RunResetSubs`, fired from
`PlayerLifecycleSubs`'s `OnProfileLoaded` hook (BEFORE any state is replicated —
see `features/persistence.md`); flags in `UpgradeConfig.run`
(`resetOnLoad`/`resetBelly`). Meta that survives: gems, squishies, daily rewards,
shop purchases + gamepasses, timed boosts (`features/boosts.md` — the whole
reason a lobby purchase is worth anything), `progress.lifetime*`.
⚠ `progress.lifetimeCalories` is a DIFFERENT field from `economy.calories` (only
the leaderboard reads it) and is never reset.

## The ONLY entry point is the checkpoint prompt
There is **no Upgrades button in the HUD, in either place** (removed 2026-07-30).
The tree opens from the authored `UpgradeStation` **ProximityPrompt** on the
checkpoint's computer — built by `MapService.buildCheckpoint` (`ActionText
"Upgrades"`, `HoldDuration 0`, range `MapConfigData.checkpoint.upgradePromptRange`,
enabled from creation) and handled by `UpgradesSubsClient`'s
`ProximityPromptService.PromptTriggered`. You stand at the checkpoint after every
belly burn, so that is already where the purchase decision happens; a HUD button
is a second door into the same room.
⚠ Do not re-read the pre-2026-07-30 claim that the tree "was reachable from
NOWHERE" and needed a HUD button — the game checkpoint's prompt was live the whole
time. `AppRoot`'s meta menu is `Visible = showLobby`, so that button only ever
existed in the LOBBY, where a run-scoped tree has nothing to spend.
Service + subs + `UpgradesUiData` stay COMMON.

## The world sign: "N Available" (2026-08-05)
The authored `UpgradeStationBody.AvailableGui.Txt` billboard shows the local
player how many upgrades they can buy RIGHT NOW, so the walk to the station is a
decision made from across the cake instead of after arriving. Owner:
`UpgradeStationSubsClient` (client, COMMON, game-place gated on `GameUiData`);
authored contract + tuning in `UpgradesUiData["station"]`; string
`LocaleData["station-available"]` (`"{n} Available"`); count from
`LocalUpgradeTree.AffordableCount` — the same predicate the tree's Buy button and
category badge use, so the sign can never promise a purchase the tree refuses.
- **Count = distinct STATS whose next tier the player can PAY for.** Deliberately
  not a greedy spending sequence: a sign promising "7" over a tree you can only
  buy 3 things from is a lie the player can see.
  ⚠ It is NOT the gold-hex count. A hex is gold when it is the next UNLOCKED tier
  (`owned == tier - 1`, no reference to the balance) — a tier must show its price
  before you can afford it — so gold hexes >= the sign's N at all times.
- **0 affordable hides the whole BillboardGui** (`hide-when-zero`) — "0 Available"
  reads as a broken station.
- **It POLLS `AppRoot` at 2 Hz, it does not listen to the remotes.** The two
  updates that move the count (`UpgradesUpdate`, `CurrencyUpdate`) are consumed by
  other subscriptions that write into AppRoot, and client subs Start
  alphabetically — `UpgradeStation…` connects BEFORE `Upgrades…`, so a handler
  here would render one push behind forever. The tick is needed anyway for the
  INSTANCE (place content, replicates late).
- ⚠ **Resolve by explicit chain, never `FindFirstChild("Txt", true)`.**
  `UpgradeStationBody` carries TWO BillboardGuis and both their labels are named
  `Txt`; a recursive search silently relabels the static "Upgrades" nameplate.
- The generated fallback checkpoint (`MapService.GenerateAssets`) has no
  BillboardGui at all — a missing sign warns once via `Log.GraceOnce` and the
  prompt still opens the tree.

`LocalUpgradeTree.AnyAffordable` (the old badge feed) is now a thin wrapper over
`AffordableCount`, which the sign uses — it is wired again.

## Progression (re-priced 2026-07-30 ADR-0013; belly curve re-shaped 2026-08-05 ADR-0019)
Each stat is ~5 tiers (`instantBurn` 4). `StatsService.upgradeValue` returns
`tier==0 and def.base or def.tiers[min(tier,#tiers)].value`.
- **`capacity` base 4400 is THE PACING STAT** — the belly is in FOOD units
  (`removed × the band's density`), and how OFTEN it fills is the rhythm the
  player feels. Measured seconds of eating per belly (`pacing.py --intervals`,
  solo easy, 5 seeds, first belly filled at each tier):

  | tier | value | seconds per belly |
  |---|---|---|
  | base | 4,400 | **10.0** |
  | I | 13,000 | **30.6** |
  | II | 58,000 | **89.1** |
  | III | 120,000 | 122.3 |
  | IV | 235,000 | 148.5 |
  | V | 645,000 | 183.8 |

  ⚠ Before 2026-08-05 this curve ran BACKWARDS — 227 s per belly at tier 0 down to
  63 s at tier 5 — because capacity grew 4× while eating power grew ~20×, so every
  purchase made the interruption *more* frequent. Growing 147× is not extravagance,
  it is what winning that race costs.
- **`biteRadius` base 2.4 is the strongest eating stat**: a bite clears to the
  layer floor, so clear time scales with bite AREA. It is multiplied by the
  band's `scoop` (2.23 icing → 0.558 core), so a base eater takes a ~5.4-stud
  spoonful of frosting and a ~1.3-stud chip of the core.
  ⚠ Its **tier-1 cost (450) is load-bearing for onboarding** — see
  `features/tutorial.md`. A full base belly of frosting is worth ~612 calories;
  past ~600 the tutorial's step 3 can no longer fire from affordability.
  `pacing_scenario.lua` section D asserts that margin (≥ ×1.2).
- **`biteDepth` base 2.6 is bite STRENGTH** against `sim.biteClearRefDepth` (3.6):
  it widens the fully-cleared core of the scoop (and lets you take a dense band in
  one bite instead of three).
- **`runSpeed` base 20 matters more than it looks**: on the wide top layers the
  scoop clears cake faster than you can walk over it.
- **`burnSpeed` base 0.20** — burn time is a FRACTION of the belly, so it is a
  constant ~1/value SECONDS at any belly size. At the old 0.06 a hands-free burn
  took 16.7 s against a 10 s opening belly, i.e. longer than the eating it
  interrupted.

**Costs — the whole tree is 755,260 calories** (was 772,250). Target unchanged:
every tier owned by the time HALF the cake is eaten. The 2026-08-05 pass halved
the tier-1 prices and steepened the per-tier ratio 3.1 → 3.4 to hold that total —
so the first purchases arrive within the first minute (they are what teaches the
loop) without the tree finishing any earlier.
Measured (`tools/balance-model/pacing.py`, 5 seeds, solo easy): clear **35.3 min**
= eat 29.6 + gym 5.7 over **22 trips** (84% of the session spent eating), tree
complete at **48% of the cake** (5/5 seeds), ~6% forfeited to the sweeps.
Before: 38.7 = eat 33.4 + gym 5.3 over 20 trips. ⚠ The gym is slightly LONGER in
total (two more trips, each far shorter); the whole 3.4-minute win is EAT time,
bought by the halved tier-1 prices putting the eating stats in the player's hands
minutes sooner.
⚠ Total eating power grows **~20×** end to end, NOT the ~2.4× this doc claimed
until 2026-08-05 — a hand-tune (commit `1c21a15`) moved `biteRadius` base 3.4→2.4
and `biteDepth` 3.6→2.6 while pushing their top tiers up, and neither the doc nor
the models were re-measured. Re-measure, never extrapolate.
⚠ `instantBurn` is priced at ~0.35× the others' scale: at a flat scale its 4 tiers
were 48% of the whole tree, so one gym-convenience stat crowded out every stat
that touches the cake.
⚠ **Cost changes are coupled to the 50%-of-cake target, and capacity values are
coupled to the interval curve** — re-measure with the model, don't eyeball. The
old numbers were calibrated against a simulation that never bought tiers mid-run,
which is how a documented "40 min" shipped as a real 1 h 01 m.

Tier COUNT and the remote contract are unchanged → **no profile migration** (a
returning save's `levels[id]` still means tier count; the run reset only changes
values, not shape — P2). The `UpgradeConfig.rebirth` block is GONE with the
rebirth system; what resets tiers now is the run reset above.

## Honeycomb (UpgradeTreeConfig + LocalUpgradeTree)
- **root** tree: centre LOGO hex + one CATEGORY hex per group (eating / body /
  gym) at alternating neighbours so they TOUCH the logo. A category shows a
  notifier BADGE when it holds an affordable next-tier. Tapping drills in.
- **sub-tree** per category: centre BACK hex, then the category's stats PACKED
  into a dense honeycomb blob — each stat gets an angular SECTOR (its tiers form
  one connected wedge-clump, tier 1 nearest the centre), so hexes touch
  edge-to-edge with NO connectors (`packSectors(counts)`). Tier k unlocks when
  k-1 owned. Only tiers 1..**min(owned+2, #tiers)** are shown per stat (owned +
  available + the next preview); deeper tiers appear as you buy.
- Hexes are edge-to-edge (`UpgradeTreeConfig.hex.nodeFill = 1`, dark Outer
  layers meet like a comb). `LocalUpgradeTree.BuildTree(treeId, levels,
  calories)` lays nodes on a unit hex grid then AUTO-FITS the bounding box into
  the square canvas (uniform scale) so every tree fills the view. Returns
  `{ nodes, nodeWidth, nodeHeight }` (Scale); each node carries `detail`
  (name/desc/status/buyText/affordable) for the tap panel, categories a `badge`.
- Node states: `locked` (gray) / `available` (gold, the next buy) /
  `owned` (blue) / `category` (purple) / `back` (teal) / `logo`.
- **Anything buyable RIGHT NOW BREATHES** (2026-08-05). `node.pulse` runs a
  looping scale tween on the hex (`HexNode`, its own centre-anchored UIScale —
  ADR-0006: React never writes that `Scale`), tuned in `Theme.HexTree.Pulse`.
  It fires for an AFFORDABLE tier and for any category holding one, and the
  category's "!" badge pulses on the same clock (it lives in the overlay's top
  layer, so it cannot inherit the node's scale and needs its own).
  ⚠ It is NOT the gold `available` state — gold means UNLOCKED and priced, which
  a tier must be before you can afford it. Same predicate as the Buy button and
  the world sign, so a breathing hex can never refuse the purchase it advertises.
  1.06, not `Theme.Feel.Pulse`'s 1.10: `nodeFill = 1` packs the comb
  edge-to-edge, so a node grows straight into its neighbours.
- **Every node carries a GLYPH** (2026-08-04). `UpgradeTreeConfig.icons` maps
  each stat / category / back to a `Theme.Icons` registry NAME;
  `LocalUpgradeTree` attaches it as `node.icon` and `HexNode` switches to the
  icon-first cut in `Theme.HexTree` (`Icon*` zones: glyph 144 / name 60 / status
  52 on the sprite's 512x444 grid). All five tiers of one stat share one glyph —
  the roman numeral separates them; a per-tier glyph would make a stat's wedge
  read as five unrelated upgrades. A LOCKED node fades its glyph
  (`States.locked.IconTransparency`) instead of tinting it, so the SHAPE — the
  only thing telling a non-reader which stat a wedge is — survives. A node with
  no mapping renders the original text-only cut unchanged.
  ⚠ Judge a glyph at NODE size: `biteRadius` shipped as `UiAim` for one
  screenshot and read as an X (cancel) on the hex the player is asked to buy.
  Icon:text is 2.4:1 by measurement — both text zones are HEIGHT-bound at node
  size, so height moved out of them goes straight into the glyph.

## Flow
`BuyUpgrade` remote (statId) → UpgradeSubs: `IsLoaded` gate → `NextCost` gate
(nil = maxed → resync) → `EconomyService.TrySpendCalories` → `ApplyLevel` (tier
+1) → pushes `UpgradesUpdate {levels}` + `CurrencyUpdate` + `BodySubs.RefreshBody`.
Clicking the gold `available` hex fires `BuyUpgrade(statId)` (advances that stat
one tier). Costs recomputed client-side — only levels travel. **Remote contract
UNCHANGED** by the tier rework (still `BuyUpgrade(statId)`).

## Open/close + modal (UpgradesSubsClient — R4)
The station `ProximityPrompt` ("UpgradeStation") — the sole opener — fires client-side →
`ProximityPromptService.PromptTriggered` → `AppRoot.Open("Upgrades")`. Opening a
menu is LOCAL UI — no server round-trip. On open it becomes MODAL: the cloned
`Shared.UIKit.Templates.UpgradeTreeBlur` dims the world, the camera is frozen
(`CameraType = Scriptable`) and character
movement is locked through `PlayerControlService`'s `upgrade-overlay` reason so
nothing shifts behind
the tree, and ALL prompts under the active `LobbyMap`/`Map` are disabled (station + nearby prompts may share E — an
enabled one would re-fire on the E-to-close press and hide behind the overlay).
**E** (ContextAction, suppressed while a TextBox is focused) or the red **X**
top-right closes (restores camera/prompts and releases only its own movement
lock; an active teleport lock remains). Reopening resets the
nav-stack to root (AppRoot effect on `openPanel=="Upgrades"`).

**Place status:** subscription, overlay and server handler are COMMON, so the
overlay would *work* in either place, but only the GAME place authors an
`UpgradeStation` prompt (the checkpoint computer), so in practice the tree is
match-only — which matches the run-scoped design. Authoring a prompt in
`LobbyEnvironment` would add a lobby entry point; don't, unless the tree stops
being run-scoped.

## GUI contract
`HexTreeOverlay` (zIndex 60, above panels): dim scrim + a clipped square
`Viewport` holding a `World` frame whose Position/Size are ZOOM/PAN bindings +
calories `StatPill` top-left + red X `CloseButton` top-right + +/-/1x zoom buttons
bottom-right + a **Detail card** shown NEXT TO a tapped tier. `HexNode` is a pure
VISUAL (no input): flat-top hex SPRITE (`Theme.HexTree.HexImage`, 512/444) stacked
Outer/Rim/Face tinted per state by UIGradient + OutlinedText name/status +
optional red "!" `Notifier`.
- **Pan/zoom**: hexes live in a `World` frame (Position/Size = zoom/pan bindings)
  inside a SQUARE `Viewport` (coordinate ref) inside a FULL-SCREEN `Clip` — so the
  tree pans across the whole screen and only clips at the screen edges, not a
  small window.
- **Single input surface**: a transparent full-screen Active `InputSurface`
  (zIndex z+7, ABOVE hexes z+2..z+5 and the "!" badge layer z+6, BELOW controls
  z+8 / card z+10). Press-start is detected here; DRAG/pinch/END run on
  `UserInputService` (global) so a release over a control doesn't leak. DRAG to
  pan, scroll / 2-touch pinch / +-/1x buttons to zoom, TAP to act. A press that
  moves > threshold is a pan (not a tap). A tap is **hit-tested** to the nearest
  hex; tier → focus + Detail card next to it (Active, so it's inert to the pan
  surface), category → drill in, back → up. Zoom keeps the cursor point fixed;
  pan clamped; zoom/pan/focus reset on tree change. The card DISMISSES on drag,
  empty-space tap, or tapping the open tier again.
- Interaction is identical on PC + touch. AppRoot holds `treeStack`; overlay
  `onNodeActivated(action)`: `open`→push, `back`→pop, `buy`→`onBuyUpgrade`
  (from the card's green Buy, dimmed when unaffordable); tier focus + pan/zoom
  are overlay-local.

## Persistence (P2)
`UpgradesSection` v2. `migrations[1]` rescales v1 linear levels → v2 tiers
(`round(oldLevel/oldCap * 5)`, clamped) so returning saves keep ~their power.
The gym fat-burn stats (`burnSpeed`/`burnPerTap`/`instantBurn`) are NEW `levels`
ids added later, defaulting to 0 — reconcile fills them for existing profiles,
so NO version bump/migration is needed (every consumer reads a missing id as
tier 0).
Idempotent: only a stored-v1 profile runs it. StatsService clamps reads
(`min(tier,#tiers)`) so an over-cap value can't inflate a stat; NextCost/ApplyLevel
return nil past the last tier (no further buy). ⚠ **Deploy caveat**: `levels[id]`
changed MEANING (linear level → tier) without changing the KEY, so during a
rolling deploy an old v1 server reads a migrated profile's tier count as a linear
level and lets it be re-bought at old per-level prices (a transient cheap-max
exploit, not corruption). **Drain/shut down v1 servers before the v2 push.** The
bulletproof alternative (if ever needed) is to store tiers under a NEW key so old
servers see it absent.

## Files
Server (all COMMON): `ProfileSchema/UpgradesSection` (v2),
`services/UpgradeService` (+`ResetTiers`), `StatsService`,
`subscriptions/UpgradeSubs`, `subscriptions/RunResetSubs` (the run wipe);
`data/MapConfigData` (station),
`services/MapService` (builds/rides the computer). Shared:
`config/UpgradeConfig` (tiers), `config/UpgradeTreeConfig` (honeycomb + `icons`),
`HexUtil`
(axial math), `UIKit/Theme` (`HexTree`, incl. the `Icon*` zones + `Notifier`
placement), `UIKit/Icons` (`UiPunch`/`UiHammer`/`UiShoe`/`UiBoom`/`UiHand`/
`UiCake`/`UiDumbbell` were added for this), `UIKit/Components/HexNode` +
`HexTreeOverlay`. Client: `LocalStatsService` (+`GymEfficiency`),
`LocalUpgradeTree` (view-model + the shared affordability predicates
`AffordableCount`/`AnyAffordable`/`CanAffordNext`),
`AppRoot` (overlay + nav-stack; NO HUD button), `subscriptions/UpgradesSubsClient`
(prompt open/close + buys), `subscriptions/UpgradeStationSubsClient` (the world
"N Available" sign), common `data/UpgradesUiData` (modal config/state +
`["station"]` world contract),
`PlayerControlData`/`PlayerControlService`, `UIKit/Templates/UpgradeTreeBlur`,
`data/LocaleData` (`hex-*`, `cat-*`, `upgrade-*-desc`, `station-available`).
The old flat `UIKit/UpgradesPanel`/`UpgradeRow` are now UNUSED (kept, not wired).
