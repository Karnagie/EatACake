# 2026-07-30: Run-scoped progression, head-on eating, boss prize, game-HUD pass

Tags: upgrades, economy, cake-sim, cake-cycle, app-root, ui-kit, pets, persistence, config, balance, tooling

## Task

Four requests, verbatim:

1. *"There shouldn't be an Upgrades button in the lobby. In general, when entering
   the lobby or starting a new cake-eating run, all upgrades and core features
   should reset. Only meta-progression should carry over."*
2. *"During the boss encounter, you can't see which Squish is going to drop."*
3. *"Update the UI in the core gameplay section — the cake-eating part. I improved
   it in the lobby, but the core gameplay still uses the old version. This is
   especially noticeable with the icons. Also, for example, when the upgrade
   window is open, the screen does not become completely dark because the GUI does
   not ignore Roblox's GUI inset."*
4. *"The balance needs improvement. It took me 1 hour and 1 minute to complete the
   game, while the intended completion time was 40 minutes. I also didn't unlock
   even half of the upgrades. The progression should be balanced so that players
   can unlock every upgrade by the time they have eaten half of the cake. Eating
   the cake should also feel smoother: currently, when you run directly into a
   layer, you often get stuck and eat very slowly. By comparison, eating the cake
   while running across its surface is much faster."*

## Context

Prior: `2026-07-26_cake-pacing-rebalance.md` (ADR-0011 pacing curve, rebirth
removed, tree moved to common), `2026-07-22_lobby-game-place-split.md` (ADR-0009
handoff), `2026-07-26_squishy-retheme-shop-grid.md` (the icon registry + the shop
the user is comparing the game HUD against).

## Plan

Read the four areas first, then fix in dependency order: the aim bug (it changes
what "balanced" even means), then the run-reset, then the boss prize, then the UI,
then re-measure and re-price the tree against the new numbers.

## Changes

**Created:**
- `src/server/common/subscriptions/RunResetSubs.lua` — wipes run state on profile load
- `src/shared/UIKit/Components/BossPrizeCard.lua` — HUD card for the squishy at stake
- `tools/balance-model/pacing.py` — pacing + PROGRESSION model (numpy; the Luau CLI is absent)
- `docs/decisions/0013-run-scoped-progression.md`

**Modified (behaviour):**
- `CakeSubsClient.computeBitePoint` — searches FORWARD for standing cake (task 4's feel bug)
- `CakeConfig` — new `aim` block; `UpgradeConfig` — `run` block + all 44 costs; `MatchConfig` — work ×1.08
- `EconomyService.ResetCalories`, `UpgradeService.ResetTiers` (re-added / new)
- `PlayerLifecycleSubs` — new discovered `OnProfileLoaded` hook; existing-player sweep `task.spawn` → `task.defer`
- `PetService` — `Roll` split into pure `Preview` + `Grant`; undefined `SCOPE` fixed
- `CakeCycleSubs` — `BeginBoss` wrapper pre-rolls prizes, per-recipient `pendingPet`, commits the advertised prize on a win
- `CakeStateData.pendingPetRolls`; `CakeSimulationSubs` routes the boss transition through the sub
- `UiRoot` — root ScreenGui is FULL-BLEED; `AppRoot` — `Hud` inset layer, place-split menu, registry pill icons, prize card
- `ScrollPane` — track click is inset-agnostic (`InputBegan`, not `GetMouseLocation`)
- `Theme` — `BossPrize` section, `AppHud.PillIcons` + its registry check, prize-card placement
- `LocalPetsService.BuildPrize`; `LocaleData` `boss-prize-caption`
- `tools/headless-sim/pacing_scenario.lua` — **units bug fixed** (double `cellArea`)

## Decisions

**Task 4's two halves were one bug and one mis-measurement, not one problem.**

*Head-on eating.* `computeBitePoint` sampled the surface at a fixed reach ahead.
Standing in the crater you just made, facing the wall of the layer, that point is
crater FLOOR — so (a) the layer-gate pre-check read it as "already eaten to the
floor here" and **skipped the bite entirely** while nagging "eat the top layer
first", and (b) any bite that did fire centred on a floor cell, where
`ApplyBite`'s `h > floorUnits` test fails, so only the falloff RIM reached the
wall. Running across the top surface centres the scoop on full cake and clears its
whole footprint to the floor — hence "much faster". It got worse with depth,
because reach scales with the shrinking scoop. Fix: march forward in
`CakeConfig.aim.stepStuds` increments to the nearest cake above the active floor.
The fast surface-mowing path returns on the first sample, so it is unchanged; the
probe is capped short (`scooped + probeStuds`) so the front crater cannot detach
from the beneath crater and leave an un-eaten ring.

*The 61 vs 40 minutes.* The 40 was never measured against a player who buys tiers
mid-run. A new model that does says the shipped tuning is **54.6 min** owning
**21/44 tiers** — which is the playtest, once you add the boss, the reveal, walking
and time spent in the upgrade UI. Re-priced the tree to 772,250 (~20× cut, values
untouched) and raised work ×1.08: **38.9 min, whole tree owned at 46% of the
cake, 5/5 seeds**. Both of the user's numbers, measured.

**Why a Python model when `tools/headless-sim/` runs the real modules.** The Luau
CLI is not installed and I did not download an executable unasked. The port paid
for itself immediately: it found that `pacing_scenario.lua` multiplied
`CakeOps.ApplyBite`'s return (already a volume) by `cellArea` **again**, inflating
food 2.25× — which inflated belly→gym trips by the same factor and understated the
forfeited fraction (6.8% published vs ~17% actual). That bug is why the published
"126 min fresh" disagreed with everything. Fixed in the Luau scenario; the Python
model carries a `check_config_sync()` that re-reads both Lua configs and fails
loudly on drift, plus a `validate()` against the published endpoints.

**The reset hook had to be a new lifecycle stage.** `PushInitialState` hooks fire
in ALPHABETICAL order, so a `RunResetSubs.PushInitialState` would have raced
`EconomySubs` and `UpgradeSubs` (both sort earlier) and the client would have been
told the pre-reset values with no correction. `OnProfileLoaded` fires after the
profile loads and before `profileLoaded` opens the push gate, so every domain's
own push then sends already-reset state — no extra re-push code anywhere. Also
changed the existing-player sweep to `task.defer` so a fast server start cannot
reach the hook before the sub that owns it has armed.

**Boss prize: `PetService.Roll` had to be split.** Roll mutates the profile, so it
cannot be used to *show* a prize. Now `Preview` (pure) + `Grant` (commit), with
`Roll = Preview + Grant` so existing callers are untouched. The preview is stored
per-user in `CakeStateData.pendingPetRolls` (runtime, not the profile — it is not
owned yet), rides `CakeCycleUpdate` **per recipient** (each fighter has their own),
and the win path grants exactly that id, falling back to a fresh roll for someone
who arrived mid-fight. The rainbow-cake Epic floor is applied at preview time so
the advertised prize and the granted one cannot disagree.

**The inset fix is a root-gui change, so it had to be paid for in two places.**
`UiRoot`'s ScreenGui was `CoreUISafeInsets`, which shrank the WHOLE tree below the
topbar — so every modal scrim stopped short of the top of the screen. Made it
full-bleed (`DeviceSafeInsets` keeps notch safety) and gave the HUD its own `Hud`
layer offset by `GuiService:GetGuiInset()`, which reproduces the old coordinate
space exactly — no HUD element moved. The non-obvious consequence: `ScrollPane`'s
track click did `GetMouseLocation() - GetGuiInset()`, a subtraction that silently
assumed an inset root and would now be wrong by the topbar height. Rewrote it to
read `input.Position` off an `InputBegan` event (same space as `AbsolutePosition`
in either mode — the convention `HexTreeOverlay` already documents), which also
picks up touch that `MouseButton1Down` never fired for.

**The Upgrades button is gone entirely — and getting there took a correction.**
`AppRoot`'s meta menu is `Visible = showLobby` and contained Upgrades, so the
button only ever existed in the lobby, where a run-scoped tree has nothing to
spend. I removed it from the lobby list and added a game-place button in its
place. **That second half was wrong**: the user pointed out the tree already opens
from the checkpoint's `UpgradeStation` ProximityPrompt, and it does —
`MapService.buildCheckpoint` constructs that prompt enabled, `HoldDuration = 0`,
and `UpgradesSubsClient` has always listened for it. You are stood at the
checkpoint after every belly burn, so the button was a second door into the same
room. Both buttons removed; `LocalUpgradeTree.AnyAffordable` (the badge feed) is
now caller-less and kept-not-wired.

What caused the mistake is worth recording, because it is a repeat: the 2026-07-26
feature doc said the HUD button was "the guaranteed entry point" and added
parenthetically "(and re-enabling the game checkpoint computer's prompt)", which
reads as if that prompt were disabled. I took the doc as the state of the world
instead of grepping `MapService` — two greps, and I had already written an upstream
row in this same session about verifying each entry point's own place gate rather
than trusting a claim about the module. I checked *which place* the button was in
and never asked whether a button was needed at all.

**Icons:** the game HUD was the last caller of `StatPill`'s legacy hand-vectored
`bolt`/`coin` shapes — so the GEMS pill wore a COIN while the shop showed the same
balance beside a gem. Both pills now resolve through `Theme.AppHud.PillIcons`
(names, registry-checked at load), shared with the shop's balance row so one
currency cannot show two glyphs at once.

## Open Questions / Followups

- **Not Studio-verified.** No Studio MCP connection was available. Everything
  below needs a live pass: the full-bleed root gui + HUD inset at several window
  sizes (the one change that could visibly move UI), the boss prize card, the
  game Upgrades button, the pill icons, and head-on eating actually feeling fast.
- **No Luau syntax gate was run** (`luau-compile` is not installed; downloading an
  executable was out of scope for an unattended session). A structural checker
  (blocks/brackets, calibrated to report zero on the shipped tree) passes on all
  209 files, which catches dropped `end`s but not every syntax error.
- Re-run `SCENARIO_FILE=pacing_scenario.lua` once the Luau CLI is available and
  reconcile it against `tools/balance-model/pacing.py` now that the units bug is
  fixed — they should agree closely, and the docs' "126 min fresh" needs updating
  to whatever they agree on.
- Meta progression now rests entirely on gems/squishies/gamepasses (ADR-0013
  consequences). Worth a design pass if runs start feeling samey.
- Co-op and medium/hard were re-scaled by the same ×1.08 but only solo easy was
  measured across seeds; the party matrix in `features/cake-cycle.md` is now
  extrapolated, not measured.

## Related
- Feature: `features/upgrades.md`, `features/economy.md`, `features/cake-sim.md`,
  `features/cake-cycle.md`, `features/app-root.md`, `features/pets.md`,
  `features/persistence.md`, `features/ui-kit.md`
- ADRs touched: **ADR-0013** (new), ADR-0011 (pacing curve stands), ADR-0009, ADR-0006
- Prior flow: `2026-07-26_cake-pacing-rebalance.md`, `2026-07-26_squishy-retheme-shop-grid.md`
