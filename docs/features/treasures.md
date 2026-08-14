# Treasures — buried finds you DIG OUT

## What it does
GDD §6.1, reworked 2026-07-26 (ADR-0012). At cake spawn, 8-40 finds (scaled by
edible volume) are buried inside the loaf as real **authored models** — the
place-authored `Items` library — each scaled to ~1.5-2× the player. They are
invisible until the surface nears them, fade in a few studs before their crown
would break through, sparkle + rim-glow while partly exposed, and the moment
**nothing covers them any more** they pop out of the hole, spin, and fly to the
nearest player (auto-collect, no proximity hunt).

Exposure is **MONOTONIC** — cake oozing back can never re-bury a find. Every
find pays a `gems` descriptor and nothing else (granted via RewardGrantSubs);
`progress.findsCollected += 1`. The consumed flag lives ON THE FIND (§13),
never on the player.

## What a find pays
**Gems only** since 2026-07-31 — boosts and eggs no longer drop. Rarity now
scales the SIZE of the gem payout instead of the KIND of prize, so digging deep
pays in the one currency the shop spends: you EARN gems and then CHOOSE a boost
(`features/boosts.md`) instead of being handed a random one.

Amounts ride `TreasureConfig.finds[].reward` and span 2 gems (common berry) to 70
(legendary trapped-pet).

The chosen cake may multiply every descriptor before grant. `cake-classic` is
1×; `cake-rainbow` is **1.5×**. `CakeCycleService.ScaleFindReward` combines that
variant multiplier with co-op scaling, floors once, and returns a copy so the
shared `TreasureConfig` descriptor is never mutated. Difficulty and random rare
skins do not multiply finds.

⚠ **The payout amounts, the weights and `spawn` are ONE balance set.** A solo
cake's 40 finds are worth **~496 gems ≈ exactly one boost** — the price lives in
`features/boosts.md`. (A flat roll expects ~347; `spawn.depthRarityBias` carries
the rest, which is the point.) Change one and the "one cleared cake buys one
boost" rule breaks.

### Co-op: gems pay PER HEAD
The find COUNT comes from cake volume, which is roster-independent (the footprint
and height are fixed for any population), and a find is consumed by whoever
reaches it first — so 4 players collect ~10 finds each out of the same 40.
Without a per-head term a co-op player needed FOUR cakes for one boost. Gems
therefore carry the same rule calories already had:
`CakeConfig.composition.coopFinds` (0.62) plus the selected variant's
`findRewardMultiplier` → `CakeStateData.findPayoutScale`,
applied by `CakeCycleService.ScaleFindReward` (`features/cake-cycle.md`).

Classic baseline (rainbow applies its 1.5× descriptor multiplier on top):

| party | classic gems per player per cake |
|---|---|
| solo | 496 |
| 2p | 402 |
| 3p | 371 |
| 4p | 355 |

Deliberately **NOT** multiplied by the difficulty premium the way calories are:
difficulty already pays in calories, and leaving gems out of it keeps
"one cleared cake buys one boost" true on every difficulty.

## The model library (authored contract)
| Where | What |
|---|---|
| `Workspace.Items` | where you AUTHOR them. Any number of `Model`s / `BasePart`s as direct children. |
| `ReplicatedStorage.Assets.Items` | where they LIVE at runtime — `TreasureService.Init` moves `Workspace.Items` here on boot (ADR-0007). Save the place to keep it there. |

Authored as of 2026-07-26 (5): `KK Candy Floor`, `Yoyle Berry`,
`Meshes/Peppermint`, `strawberry`, `candy`. The boot log prints every model with
its PREPARED size — that line is the only view of the library outside Studio, so
read it first when something looks wrong.

Each entry is prepared ONCE at Init: uniform-scaled so its LONGEST side is
`model.targetSizeStuds` (10.5 studs = 1.83× the 5.73-stud R15 rig, measured
live), anchored,
`CanCollide/CanQuery/CanTouch/CastShadow = false`, original transparency stamped
as a `BaseTransparency` attribute, and any child Script destroyed. Clones inherit
all of it. A find def may name its model (`finds[].model = "<child name>"`);
unnamed defs are assigned round-robin, so **dropping new models in needs no
config edit**. ⚠ Round-robin is a FALLBACK, not a design — unpinned, a common
berry can get the strawberry while a legendary gets whatever is next in the
rotation, and the reward reads as random rather than earned. Four finds are
pinned to matching art (`berry`→strawberry, `candy-gem`→candy,
`charm`→Meshes/Peppermint, `capsule`→Yoyle Berry); the rest round-robin because
the library has 5 treasure models for 9 finds. **The single best art investment
is ~4 more props**, after which every find can be pinned. The boot log prints the
resolved mapping (`find art (* = pinned): …`), and a pin that does not resolve
warns rather than silently falling back. No library → plain neon orbs + a warn
(R8 graceful degradation).

`model.sceneryModels` lists library entries that are **scenery, not treasure**.
They stay resolvable BY NAME (an explicit `model =` pin still works) but are
removed from the round-robin pool — without it a legendary could dig up as the
candy FLOOR TILE, which reads as a bug rather than a reward. Boot logs
`scenery (pin-only, out of the round-robin): …`, and if scenery is ALL the
library holds, the empty-pool warn says so instead of claiming the folder is
empty.

## Depth pays
`spawn.depthRarityBias` skews the rarity roll by how deep the find was dealt:
each tier's weight is multiplied by `(1 + bias * depth)^tier` (common = 0 …
legendary = 4), depth 0 at the surface → 1 at the deepest edible band.

| tier | surface | bottom |
|---|---|---|
| common | 61.2% | 40.4% |
| rare | 8.2% | 13.8% |
| epic | 4.1% | 11.0% |
| legendary | 2.0% | 8.8% |

Rare-or-better: **14.3% → 33.7%**. Depth 0 leaves the distribution exactly as a
flat roll, so the opening minutes are untouched — only the deep end skews, and
nothing is ever guaranteed. Composes with `rarityScale`: deeper ⇒ rarer ⇒
bigger ⇒ a longer dig, so the best rewards are the deepest. ⚠ The band a find
is dealt to is fixed by its index alone, which is why it can be resolved
BEFORE the rarity roll — keep that ordering if you touch `SpawnForCake`.

## Rarity has to be readable BEFORE the reward
Colour rides the rim glow and the glow does not exist until the crown breaks
through — so while a find is still being dug, two cues carry rarity:

| Cue | Where | Notes |
|---|---|---|
| **Size** (`model.rarityScale`) | multiplies `targetSizeStuds` per tier | ⚠ **Never set a tier below 1.0.** Measured: scaling commons to 0.85 moved one-layer finds from 13/40 to 15/40 — it broke the "usually two or three layers" requirement to serve a cue. Scaling only the rare tiers UP costs nothing there (mean 2.05 / median 2, unchanged) and makes the best rewards the deepest digs. Top of the band (legendary 1.28 → 2.35× the rig) deliberately exceeds the "1.5-2×" spec for the 6% of rolls that are epic+. |
| **Pulse** (`rarityFx[].glowPulse`) | rim-glow pulse depth once revealed, at `model.highlightPulseHz` | `0` for common ON PURPOSE: with up to 40 finds a pulse on everything is wallpaper. Only what is worth crossing the cake for breathes, so the pulse itself reads as "this one matters" before you can tell what it is. |
| **Strain** (`model.strain`) | from `startFraction` of the footprint cleared, the pulse DEEPENS (`pulseGain`) and the glow FILL floods in (`fillGain`) toward release | The window between "crown showing" and "free" is where the payoff is closest, and it used to be the flattest part of the dig — the find just sat there. |

**Seeing any of this in Studio — use the dev hook, not a config edit.** At
production scale a find takes minutes of eating to surface. In a playtest, switch
the command bar to SERVER context (`Test > Toggle Client View`) and:

```lua
workspace:SetAttribute("DebugUncoverFind", 0.5)  -- nearest find: revealed, mid-strain
workspace:SetAttribute("DebugUncoverFind", 0)    -- nearest find: uncovered, frees next tick
```

`TreasureService.DebugUncoverNearest` carves the field over the nearest buried
find and lets the NORMAL tick walk it through `loaded → revealed → strain →
freed` — it never sets states directly, so what you watch is the real path.
Studio-gated **twice** — at the hook in `CakeSimulationSubs` AND inside the
function itself. The second gate is not redundant: it protects every future call
site, and a debug function that hands out rewards is exactly what gets wired to a
remote by accident later. Re-firing with a smaller value carves
further, which is how the escalation gets measured rather than eyeballed.

The separate cake-cycle hook `DebugClearLayer` can uncover many finds at once.
It arms `CakeStateData.debugSuppressFindRewards` before changing the field, so
those finds retain their shared pop/collect visuals but skip gems, discovery,
progress, analytics and persistence until a new cake resets the latch.

Measured this way (2026-07-29, a common `candy-gem`, template baseline
`Fill=0.850`): keep 50% → `0.814`, keep 15% → `0.502`, keep 6% → `0.410`;
`Outline` held at `0.100` throughout, correct for common.

⚠ **Strain is a PROPERTY animation and must stay one.** The first cut wobbled the
model's pose each tick and stranded 6 finds. `Model:GetPivot()` on a model with
**no PrimaryPart** returns the recomputed bounding-box centre with **identity
rotation**, so every `PivotTo` derives the parts' relative offsets from a frame
that has already lost the previous rotation — the transform COMPOUNDS, and the
find walks away from its hole. Animate a find's pose only in `playCollect`, which
runs once and then destroys the model. (Reveal/free themselves are safe either
way: both read cached spawn values — `radiusCells`, `x`, `z`, `topUnits` — and
never the model's live geometry.)

## Life of a find
| State | Trigger | What happens |
|---|---|---|
| `buried` | spawn | cloned into `workspace.CakeFinds`, alpha 1 (invisible) |
| `loaded` | cover ≤ top + `preloadLeadStuds` | fades in over `fadeInSeconds` — still under cake, so the fade is masked, never a pop-in |
| `revealed` | cover ≤ top + `revealEpsilonStuds` | sparkle on (rate ∝ exposure), rim `Highlight` (Occluded — never an x-ray radar), `revealed` broadcast |
| `collected` | cover ≤ bottom + `freedEpsilonStuds` | pop out + spin + magnet flight to the nearest loaded player, then destroyed |

One pass over the model's own XZ footprint yields both tests (`coverStats`):
**reveal** on the MIN surface (the crown shows the moment the lowest point
drops past the find's top — what the player actually sees), **freed** on the
FRACTION of footprint cells eaten to the bottom (`freedCoverFraction`, 0.88).
A cheap centre-cell early-out skips the scan for every still-deep find.

⚠ Both were once a single MAX and both were wrong at the ends: reveal waited
for the WHOLE footprint to drop, and a wide/tilted prop never freed at all —
its bounding footprint is far bigger than its silhouette, so one un-eaten
corner cell stranded a find the player could see was completely dug out.

## Digging depth (why it takes 1-3 layers)
Finds are dealt **round-robin over the shuffled edible bands**, so ~1 sits in
every layer — a 40-minute cake never has a dry stretch. Each find's TOP is sunk
`burialFraction` of its band's thickness below the band top, and the model is
~8.5 studs tall against 3.5-25 stud bands: a find usually spans a band boundary,
so you see its crown in one layer and only free it in the next (the layer gate
decides *when*, which is the point). `SpawnForCake` clamps every find's BOTTOM
above the inedible core, so no find is ever unreachable. XZ placement is sampled
inside the assigned band's own footprint (with the model margin inset), and the
later coverage scan uses that same footprint. This keeps finds inside narrow
rainbow terraces instead of burying them in empty air beyond that colour group.

## Config / state
`Shared/config/TreasureConfig` — `finds` (weights, rarity, rewards, colors,
optional `model`), `spawn` density, `model` (library name, sizing, burial,
reveal/free thresholds, cascade + pop/fly timings), `rarityFx` (client FX
loudness). The `boosts` defs also live in that file but belong to another
feature now — `features/boosts.md`, never duplicated here.
Runtime state: `CakeStateData.treasures` (shape documented in that file's header).

## Signals the player actually reads
- **`FINDS n/N` on the HUD bar while eating.** The cake-% bar is hidden during
  eating (it barely moves), which left the core loop with no progress signal at
  all; the same bar now carries the per-cake find goal instead
  (`TreasureService.FindCounts` → `CakeCycleUpdate.finds` → `AppRoot.cakeBarModel`).
  A countable set is what gives a long run something to aim at.
- **`Finds` on the LEADERBOARD** — distinct KINDS discovered out of 9, not
  pickups collected (`ProgressService.CountFindKinds`). A small number that
  visibly stalls pulls harder than a big one that only ticks up; it replaced
  "biggest belly", a joke stat with nothing actionable behind it.
- **A NEW DISCOVERY! banner the first time you ever dig up each of the 9 kinds.**
  `progress.foundKinds` (a `{ [findId] = true }` set — a NEW profile field with a
  default, so no version bump, P2) is checked on every collect;
  `ProgressService.MarkFindDiscovered` returns true only once per kind and rides
  the payload as `firstEver`. A first discovery is celebrated at RARE loudness
  whatever the find actually is, and its banner outranks the rarity banner — so
  the first berry lands and the fortieth does not. Nine one-off moments spread
  across a player's early sessions.
- **A GLINT on the cake surface above a nearly-uncovered find.** Fired once per
  find when it reaches `loaded`; the client shimmers pooled particles at that XZ
  until the crown breaks through (`JuiceConfig.findGlint`). It marks the SPOT,
  never the item — that is the difference between "dig here" and an x-ray that
  deletes the dig.

## Replication
`TreasureUpdate` FireAllClients:
- `{event="near", findId, rarity, color, position}` — start the surface glint.
- `{event="revealed", findId, rarity, color, position}` — crumb puff + chime at
  the crown, for everyone; clears the glint.
- `{event="collected", findId, nameKey, rarity, color, reward, byUserId,
  position}` — burst (+ a crumb ring for rare+); the collector also gets the
  camera shake, the rarity sound, a floating reward label and — rare+ only — an
  `announce-find-<rarity>` banner. 40 finds a cake, so common finds get no banner.
  ⚠ `reward` is the descriptor `RewardGrantSubs.Grant` **returned**, never the
  config one: TWO multipliers sit between `finds[n].reward.amount` and the
  balance — the per-head co-op scale, and `GemsMult` (x2-gems pass / VIP / gems
  pets) inside the handler. Sending the input floated "+70" over a find that
  banked 140, for exactly the players who had paid for the perk.

The pop/spin/flight itself is **server-side** (`playCollect`, a timed
`task.spawn` loop, never an event subscription) so every player sees the same
flourish. Currency updates ride the grant handlers.

## Cadence
`TreasureService.Tick(loadedUserIds, dt)` at 2 Hz inside `CakeSimulationSubs`.
Freed finds are dealt out one per `cascadeSeconds` beat, so an auto-swept layer
pops its finds out one after another (a cascade) instead of all in one frame.

## Gotchas
- The rim `Highlight` is `Occluded` on purpose. `AlwaysOnTop` would let players
  see every buried find through solid cake and delete the whole dig. It only
  switches to `AlwaysOnTop` during the collect flight. Live Highlights are
  capped (`MAX_GLOWS`) — the engine only renders ~31.
- Finds are visible **through a translucent layer** (jelly is Transparency 0.45
  Glass). That's a feature, not a bug: the toy in the marmalade.
- The "Eat the top layer first!" cue and `layer-cleared` fire at the SAME moment
  (you are mowing the floor when a layer finishes), so the nag is suppressed for
  `LAYER_CLEAR_PRIORITY_SECONDS` after a clear — otherwise it stomps the
  celebration within a frame (found by playing, not by review).
- Scale is measured on each model's OWN (local) extents, never the world AABB —
a prop authored at an angle has a world box far bigger than itself, so scaling
against that makes it come out visibly smaller than its neighbours. The world
AABB is used for burial depth and footprint, which genuinely are world spans.
- `prepareTemplate` runs on an unparented CLONE of each library entry, never on
  the authored model. It rescales, anchors, strips collision and DESTROYS child
  Scripts — doing that in place would permanently damage your source art the
  moment you saved the place (which the migration log tells you to do). Your
  `Items` models stay exactly as authored.

## Files
`services/TreasureService`, `subscriptions/CakeSimulationSubs`
(participant-gated grants + FX fanout), shared `config/TreasureConfig`;
client FX in `CakeSubsClient`. Design: ADR-0012.
