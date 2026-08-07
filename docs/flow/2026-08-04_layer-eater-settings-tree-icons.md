# 2026-08-04: Layer Eater purchase, game Settings button, hex-tree icons

Tags: checkpoint, shop, monetization, cake-sim, upgrades, ui-kit, settings, app-root, theme, map

## Task
Three user requests in one session:
1. "I added `ReplicatedStorage.Assets.Checkpoint.LayerEater`. Add a prompt to it
   that, when activated, offers a purchase for 9 Robux. After the purchase, it
   should automatically eat one layer of the player's current cake."
2. "add settings button to game, it's only in lobby right now"
3. "add icons to upgrade tree nodes. You can find icons here
   `C:\Users\vladimir\Desktop\Sprites`"

## Context
- The checkpoint plate already carries `GymMachine` + `UpgradeStationBody`, both
  positioned at computed corners by `MapService.SetCheckpointHeight`; the user
  authored a new `LayerEater` cat contraption on the plate's −Z corner (pivot
  offset from the plate `(-4.64, 4.42, -8.42)`, with a **165° yaw**).
- `ShopSubs` owns `ProcessReceipt` in both places; grant kinds go through
  `RewardGrantSubs` (ADR-0002); `burn` was already a GAME-partition-only kind.
- `AppRoot`'s meta menu is `Visible = showLobby`, but `SettingsPanel`,
  `SettingsSubs(Client)`, `SettingsData` and `LocalSettingsService` are all
  COMMON and the panel was already rendered in the game place.
- `HexNode` was text-only (name + status).

## Plan
1. New `eatlayer` grant kind + `CakeFieldService.ClearActiveBand`, sold by a
   HIDDEN ShopData product bought from a world prompt.
2. One game-HUD Settings button in the slot the lobby menu occupies.
3. Upload the missing glyphs, map them per stat in `UpgradeTreeConfig`, re-cut
   `HexNode`'s content zones icon-first.

## Changes

**Created:**
- `src/client/common/data/ShopUiData.lua` — prompt name → product key pairs
- `tools/headless-sim/layereater_scenario.lua` — 19 assertions on the paid clear
- `docs/decisions/0018-grant-readiness-predicates.md` — ADR
- `docs/flow/2026-08-04_layer-eater-settings-tree-icons.md` — this doc

**Modified:**
- `services/CakeFieldService.lua` — `ClearActiveBand()`
- `services/MapService.lua` — resolve/ride/prompt-ensure the `LayerEater`
- `data/MapConfigData.lua` — `checkpoint.layerEater*`
- `subscriptions/CakeSubs.lua` — `eatlayer` grant + readiness predicate
- `subscriptions/RewardGrantSubs.lua` — `RegisterReady` / `IsReady`
- `subscriptions/ShopSubs.lua` — `hidden` products, `eatlayer` descriptor rule,
  readiness threaded through `grantableList` and the `RequestPurchase` prompt
- `data/ShopData.lua` — `layer-eater` product (`hidden`, `devProductId = 0`)
- `subscriptions/ShopSubsClient.lua` — `PromptTriggered` → `RequestPurchase`
- `modules/AppRoot.lua` — `GameSettingsBtn`
- `UIKit/Icons.lua` — 8 new glyphs
- `config/UpgradeTreeConfig.lua` — `icons` block
- `modules/LocalUpgradeTree.lua` — `node.icon`
- `UIKit/Components/HexNode.lua` — glyph + icon-first cut
- `UIKit/Components/HexTreeOverlay.lua` — pass `icon`; notifier placement from Theme
- `UIKit/Theme.lua` — `HexTree.Icon*` zones, `States.*.IconTransparency`,
  `Notifier.Center/Size` (were dead)
- `tools/monetization/create_monetization.py` — `layer-eater` in `PRODUCT_COPY`
- docs: MAP, checkpoint, shop, upgrades, settings, app-root, cake-sim, ui-kit,
  registries/data-keys, upstream/QUEUE

## Decisions

**The paid clear PAYS the calories it removed.** Asked the user; they chose it
over a pure time-skip. Priced through the identical bite formula (`removed ×
band.density × layer.calories × cake mult × biome mult × CaloriesMult`) so a
bought layer and an eaten one are worth the same, and because the amount is
computed from the volume ACTUALLY removed, a half-eaten band pays only for what
was left — the product cannot be farmed by buying it twice on one band. The
belly is deliberately NOT filled: a paid convenience that ends with the buyer
over capacity and walking to the gym punishes the purchase.

**`ClearActiveBand` does not advance the layer gate.** Tempting, because the
gate then lags up to a second. But `ScanStats` (1 Hz) is the single path that
drops `activeBandIndex`, and `CakeSimulationSubs` compares before/after to move
the checkpoint plate, fire the `layer-cleared` announce and the retention beat.
Advancing the gate in the service would make the indices already equal by the
time the scan ran, so a bought clear would be the ONE layer nobody celebrates.
The lag costs at most one debounced client cue.

**New: grant READINESS (`RewardGrantSubs.RegisterReady`).** The hole this
closes is specific and was already latent for `burn`: `HasHandler` answers "is
this kind deliverable in this place", never "can it be delivered to this player
right now". A handler that answers the second question by returning nil is too
late — `ShopSubs.grantProduct` has already committed the receipt, logs a warn,
and returns true, so the player pays and gets nothing. The predicate runs inside
`grantableList`, i.e. before the first grant and before the gem path spends, so
"not yet" becomes NotProcessedYet (Roblox re-delivers) or a refusal that never
charges. `RequestPurchase` now consults it too, so the Roblox dialog never opens
for a purchase that would have to be deferred — "you were charged, come back
later" is a support ticket.

**`ClearActiveBand` resolves its target band from the FIELD, not from
`activeBandIndex`.** Readiness (above) cannot see another player's receipt
arriving 10 ms earlier, and `activeBandIndex` only refreshes at 1 Hz — so two
purchases inside one tick would both target the same band and the second buyer
would pay for one that is already flat (removed = 0 → nil → the very
paid-for-nothing outcome the readiness hook exists to prevent). Recomputing the
top band from `maxH` with the same rule `ScanStats` uses makes the second
purchase clear the NEXT layer instead, and outside the race the two always agree
— including immediately after an auto-sweep, where both resolve to the band
below.

**HIDDEN products.** `layer-eater` needs a ShopData entry (both purchase paths
resolve keys there) but must not draw a cell: the shop window opens in the
LOBBY, where `eatlayer` has no handler, so a lobby cell would take Robux and
appear to do nothing until the next match. `hidden = true` skips it in
`shopPayload`; `ShopUiData["prompt-products"]` is the buy surface instead.

**The LayerEater keeps its AUTHORED pose; everything else on the plate is
placed by formula.** Its authored pivot carries a 165° yaw, and
`PivotTo(CFrame.new(pos))` silently discards rotation — a modelled contraption
would snap to face north on the first height update. MapService captures the
pivot offset from the plate (and the rotation) at resolve time, before the first
`SetCheckpointHeight`, and re-applies `CFrame.new(plate + offset) * rotation`.
This is also the friendlier contract: the author positions the prop in Studio and
it stays where they put it.

**The prompt is ensured in code AND authored in the place.** Added to
`ReplicatedStorage.Assets.Checkpoint.LayerEater` in Studio (needs a place SAVE to
persist) *and* self-healed by `MapService.ensureLayerEaterPrompt`, which adopts
an existing prompt or creates one on the model's **biggest** BasePart. Biggest,
not first: an authored prop is a pile of same-named `Part`s in arbitrary order,
so `FindFirstChildWhichIsA` lands on a whisker and the anchor moves whenever the
author re-orders anything.

**Settings button is NOT added to the meta-menu frame.** That frame is
`Visible = showLobby` because its *other* handlers are lobby subs; settings are
COMMON end to end. A separate `GameSettingsBtn` takes the same slot
(`Theme.AppHud.MenuPosition`, one menu cell) with `Visible = showGame` — free
space in the game HUD, since the cake bar is top-centre and the boss prize
top-right.

**Hex glyphs: judge at NODE size, not in the sprite folder.** `biteRadius`
shipped as `UiAim` for exactly one screenshot — a reticle of two crossed red
bars, which at 70×60 px reads as an **X**, i.e. CANCEL, on the very hex the
player is being asked to buy. Final map is fist / hammer / bolt (eating), box /
sneaker (body), chart / hand / flame / burst (gym), cake / arm / dumbbell
(categories), arrow (back); the logo stays glyph-less because it touches the
eating category and a second cake there reads as a duplicate node.

**Icon:text = 2.4:1, measured off live instances, not chosen.** First cut
(icon 116 / name 68) rendered 15px of glyph against 8px of text — 1.9:1, a
picture beside a label. Second (150/56) hit 2.7:1 but dropped the COST on gold
`available` hexes to ~6px, and the cost is the whole decision on exactly those
nodes. 144/60/52 keeps the name at its original rendered size and costs the cost
~12%. Both text zones turned out to be HEIGHT-bound at node size, which is why
height moved into the glyph at all.

**A locked node FADES its glyph rather than tinting it.** Full-colour art on a
gray hex makes the un-buyable nodes the brightest thing in the tree; tinting to
gray destroys the shape, which is the only thing telling a non-reader which stat
a wedge belongs to. `IconTransparency = 0.45`.

**Found in passing: `Theme.HexTree.Notifier.Center/Size` were dead** —
`HexTreeOverlay` carried its own `0.28 / 0.30 / 0.46` literals (kit iron rule 2),
which is why the two disagreed. Now read from Theme, and pushed out to 0.83 so
the "!" badge overlaps ~11% of the new glyph instead of ~33%.

## Adversarial review (post-implementation)
`adversarial-reviewer` returned 1 CRITICAL, 7 WARN, 5 NIT. Fixed in this task:

- **CRITICAL — a declined grant consumed the receipt anyway.** `grantProduct`
  logged the decline and still returned `true`. Tolerable while every grant was
  unconditional; `eatlayer` is the first whose success depends on live world
  state. Fixed two ways: `ClearActiveBand` resolves its band from the field
  (kills the concurrent-buy and stale-gate cases outright), and a SINGLE-grant
  product whose only grant declines now returns false → NotProcessedYet. Multi-
  grant products keep the old behaviour deliberately (ADR-0014 re-mint risk).
- **WARN — no minimum-value guard**: full price for the last 10% of a layer, at a
  price that can never be lowered. New `CakeFieldService.TopBandFill()` +
  `layerEaterMinRemainingFraction` (0.25); the readiness predicate refuses below
  it, so the dialog never opens.
- **WARN — `RequestPurchase` had no rate limit** while the gem remote did, and
  this change gave it a mashable world surface plus a fourth always-reachable
  refusal branch (each answering with a full catalogue re-push). Both remotes now
  share one `overBurst` helper with separate per-remote buckets; the
  unconfigured-id warn became `Log.Once` (a `Log.Warn` on a HoldDuration-0 prompt
  is a one-key console flood).
- **WARN — R8 silent failure**: a *nil* `ShopUiData` fell through both branches,
  leaving every world prompt a silent no-op. Now warns.
- **WARN — doc drift onto the publish checklist**: `publish-readiness.md`
  certified "ALL 11 ARE LIVE" while `layer-eater` sits at id 0 — and because it
  is world-sold, the "wall of SOON buttons" symptom does not surface it. Counts
  and the create command are now in that recipe, MAP and `shop.md`.
- NITs: shared config table no longer mutated by `LocalUpgradeTree`; the
  LayerEater prompt is now ensured even when the PLATE fails to resolve (those
  are independent failures); the stale `HexNode` "logo" comment corrected.

Documented rather than fixed, in `features/checkpoint.md` "Known consequences":
the SHARED-CAKE effect (one purchase deletes three players' layer income and
frees their finds — flagged to the user as an open design question), the absence
of a server-side distance check (deliberate), the invisible deferred receipt, and
the dead-end prompt while the id is 0. Not done: splitting `CakeSubs` (338 lines,
over the ~300 R7 guidance — `CakeLayerEaterSubs` is the clean seam).

## Verification
- **Luau syntax gate** over all of `src/` after every edit round.
- **Studio playtest** (game place): clean boot (20/20 subs, 15/15 services), the
  only new warn is the expected `NOT ON SALE` for the unconfigured id; the
  LayerEater rides the plate at its authored offset AND its authored 165° yaw;
  the prompt fires → `RequestPurchase` → the correct server refusal; 8 rapid
  fires produce ONE refusal line + ONE throttle line (was 8 unthrottled warns);
  the Settings button renders in the game HUD and opens the panel; the hex tree
  opens from the station prompt with glyphs at real client resolution.
- **Measured, not reviewed**: `layereater_scenario.lua`, 19/19 — the paid clear
  cannot be reached in Studio without a live dev product, so the honesty
  properties (paid volume == removed volume, exactly; two purchases in one tick
  clear two different bands) are asserted against the real service instead.
  `analytics_scenario` still 66/66; `pacing_scenario` still builds.
- **Prompt range is MEASURED**: the F-teleport lands 10.1 studs from the eater,
  so the shipped 10 would have hidden it exactly on arrival → 14.
- ⚠ Not verified end-to-end: the actual receipt → grant → calories path. That
  needs the dev product.

## Open Questions / Followups
- **`ShopData.layer-eater.devProductId` is 0** until the Creator Dashboard
  product exists. The user opted to have it created with
  `tools/monetization/create_monetization.py --apply --write-shopdata --only
  layer-eater`; the run needs the `.ROBLOSECURITY` cookie file path. Until then
  boot warns `NOT ON SALE` and the prompt refuses (loudly, R8) — nothing is
  charged. ⚠ A dev product is CREATE-ONCE: name/description/price are permanent.
- The Studio-authored `LayerEaterPrompt` only persists if the user **saves the
  place**; the runtime self-heal covers them if they don't.
- Squint test: at 1x zoom a 10-node sub-tree renders ~70px hexes, so under heavy
  blur the STATE hierarchy (gold = affordable) survives but individual glyph
  identity does not. That is a property of the node size, not of the glyphs — the
  tree is pan/zoomable and the detail card carries the text.
- `UiAim` is uploaded and registered but no longer used by the tree.

## Related
- Features: `docs/features/checkpoint.md`, `shop.md`, `upgrades.md`,
  `settings.md`, `app-root.md`, `cake-sim.md`
- **New: ADR-0018** (grant readiness predicates)
- ADRs touched: ADR-0002 (reward descriptors), ADR-0007 (authored assets),
  ADR-0014 (receipt safety), ADR-0015 (gem purchase path)
- Prior flow: `docs/flow/2026-08-03_round-cake.md`
