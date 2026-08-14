# 2026-08-13: Game HUD menu — Upgrades / Shop / Squishies, with affordability cues

Tags: app-root, ui-kit, upgrades, shop, pets, tutorial, analytics, monetization, theme

## Task
User, two requests:
1. Add an **Upgrades** icon to the in-game UI that opens the same window the
   prompt does; animate the icon and badge it when an upgrade is affordable; and
   make sure the **tutorial does not break** when the window is opened through the
   UI instead of the prompt.
2. Add **Shop** and **Squishies** icons to the in-game UI, fully functional —
   equip a squishy mid-run, and a pass bought in the shop applies immediately.
   Animate + badge the Shop icon when the player can afford a boost, "so that even
   a child can understand that they should open the Shop, go to the Boosters
   section, and purchase one".

## Context
The GAME place's HUD had exactly ONE button — Settings (`GameSettingsBtn`, added
2026-08-04) — sitting in the slot the lobby's 6-8 button meta menu occupies. The
Upgrades button was removed from the HUD on 2026-07-30 with the reasoning "you
stand at the checkpoint after every belly burn, so a HUD button is a second door
into the same room"; the tree's only opener since then was the checkpoint's
authored `UpgradeStation` ProximityPrompt.

The important discovery of the reading pass: **almost none of this needed new
wiring.** `ShopSubs` (+ `ProcessReceipt`, the gem path), `PetSubs`,
`PassOwnershipSubs`, `RewardGrantSubs` and every one of their client subs are
already COMMON, and the Pets/Shop panels in `AppRoot` were never place-gated —
only the BUTTONS were missing. The game place is in fact the *stronger* half for
delivery: `burn` and `eatlayer` are registered only there, so nothing a shop cell
sells is undeliverable in a match.

Prior flow: `2026-08-09_arrow-until-purchase-safe-area-slide-entrance.md` (the
tutorial's completion-on-purchase rule, which is what made requirement 1 mostly
already true), `2026-08-04_layer-eater-settings-tree-icons.md` (the lone game
Settings button).

## Plan
1. One `menuBlock(items)` builder in `AppRoot` for BOTH menus, so the grid
   arithmetic exists once; a new `GameMenu` frame carrying four entries.
2. A `pulse` prop on `HudMenuButton` following the kit's existing attention
   recipe, driven by the SHARED affordability predicates the windows themselves
   use (`LocalUpgradeTree.AnyAffordable`, a new
   `LocalShopService.AffordableBoostCount`).
3. Tutorial: work out what actually breaks, fix that, and change nothing else.
4. Server: make a mid-session gamepass purchase reach the player through all
   three of its channels, not just the attribute one.
5. Studio playtest, adversarial review, fix the findings, re-verify.

## Changes

**Modified:**
- `src/client/common/modules/AppRoot.lua` — `menuBlock` builder; `GameMenu` frame
  (Upgrades / Shop / Squishies / Settings) replacing `GameSettingsBtn`;
  affordability view-models + place gating; `modalBusy()` and the Upgrades
  branch's own modal guard; `selectable` passed to every menu button; the eat
  hint suppressed while a panel is open; R8 line on a refused HUD press.
- `src/shared/UIKit/Components/HudMenuButton.lua` — `pulse` and `selectable`
  props.
- `src/client/common/modules/LocalShopService.lua` — `AffordableBoostCount`.
- `src/client/common/subscriptions/UpgradesSubsClient.lua` — header (two
  openers); the world-prompt sweep now RE-CHECKS for a late `workspace.Map`
  instead of warning once.
- `src/client/common/data/UpgradesUiData.lua` — `prompt-sweep-seconds` /
  `prompt-sweep-timeout-seconds` (R1: the cadence is data).
- `src/client/common/subscriptions/TutorialSubsClient.lua` — `reportTreeOpened()`
  (prompt + tick + purchase backstop); `finish()` reports which step it ended on.
- `src/client/common/subscriptions/AnalyticsSubsClient.lua` — panel re-open
  debounce.
- `src/shared/config/AnalyticsConfig.lua` — `client.panelReopenSeconds`.
- `src/server/common/subscriptions/PassOwnershipSubs.lua` — `ApplyPerkAttributes`
  re-pushes pets `slots` and the pushed/applied stats; the join fetch never
  downgrades a runtime `true`.
- `src/server/common/subscriptions/BoostSubs.lua` — header: second caller.
- `src/server/common/subscriptions/ShopSubs.lua` — header: the window opens in
  both places now.

## Decisions

**The tutorial was already safe; the thing that was not is the one nobody would
have guessed.** Completion tests the STATE (`UpgradesUpdate` carries any tier
≥ 1) from ANY live guided step — never a prompt transition — so a tier bought
through a HUD button ends onboarding exactly like one bought at the computer.
Nothing about the exit was ever prompt-shaped. What DID ride the prompt alone was
the **tutorial funnel's `upgrades` step and its dwell**, so a player who bought
through the HUD would leave a hole between `arrived` and `done` that reads as a
drop-off.
⚠ And the thing I got wrong first: I wrote a comment claiming the *player-flow*
step `upgrades-open` was at risk too. It was not — `AnalyticsSubsClient` polls
the open PANEL and fires it for any opener. Found by recording the live
`AnalyticsBeat` remote during a playtest, which is the only reason the comment is
now true instead of plausible.

**A HUD open moves NO tutorial step, deliberately.** The prompt proves the player
is AT the station (it deliberately reaches several studs back onto the cake,
which is why it has always been honoured from any live guided step); the button
is reachable from anywhere, including step `eat` with an empty balance.
Advancing there would tear down the eat popup and run the guidance beam to a
computer across the cake for a player who has not eaten yet. The beat is
therefore reported only from `step == "upgrades"`, so an early HUD open can never
assert step 5 out of order.

**The cues sequence with onboarding for free, so onboarding was left alone.**
Upgrades cost CALORIES, which are banked only at the gym, so at tutorial step
`path` the balance is provably 0 and the icon is quiet while the TO CHECKPOINT
button pulses; at step `upgrades` they have banked, so the checkpoint pulse stops
exactly as the Upgrades cue starts. A "suppress cues during onboarding" flag was
considered and rejected: it would have added an AppRoot state field for a case
that cannot occur (a new account has 0 gems, and onboarding runs once per
account).

**Boosts only for the Shop cue.** Gem packs are bought with Robux and every Robux
card is always "affordable", so a badge over those would be lit for the whole
session and mean nothing. Boosts are the only cards whose state flips with a
balance the player earns by playing — which is also exactly what the user asked
the badge to teach. `AffordableBoostCount` is a strict subset of the set the
cells resolve to `buy`, so the icon can never advertise a purchase the panel then
refuses (the same one-way guarantee the upgrade station's world sign has).

**Settings moved from the first cell to the last.** It was the game HUD's only
button, so this costs some muscle memory — but it is the one entry a player never
needs mid-run, and the three above it are what the pacing depends on. The lobby's
established order was NOT touched (that roster's stability is a documented rule).

**A perk reaches the player three ways and only one of them is an attribute.**
`ApplyPerkAttributes` was named for the channel it happened to use. READ-per-use
stats (`CaloriesMult`, `GemsMult`, `EatRate`, `Capacity`) need nothing; PUSHED
snapshots (`slots` on PetsUpdate, `capacity` on StomachUpdate) and APPLIED values
(Humanoid WalkSpeed) do — so a VIP buyer saw "3 / 3" squishy slots and an
un-doubled belly bar until the next place transition. Reused `BoostSubs.Apply`
rather than growing a second copy: it exists to re-derive exactly that set for a
timed boost, is documented idempotent, and a pass moves the same three values.
The same routine now runs on JOIN, where the ordering hazard is identical
(`PassOwnershipSubs.PushInitialState` yields on its first
`UserOwnsGamePassAsync`, so every other hook has already run against an empty
ownership cache — the note that fixed `slots` in 2026-07-30 described the bug and
fixed only half of it).

**The combined dev build stacks the two menus instead of overlapping them.**
Published places map exactly one partition marker, so the offset is always 0
live; it is computed from the lobby block's own measured height rather than added
to `Theme` as a second position constant. (They already collided before this —
the lone Settings button sat on the lobby's first cell.)

## From the adversarial review (10 findings, 9 fixed, 1 accepted)

- **The R8 message I wrote was false.** "the tree can still be opened from the
  checkpoint prompt" — but every early return in `UpgradesSubsClient.Start`
  happens BEFORE both the `SetCallbacks` and the `PromptTriggered` connect, so a
  missing `onToggleUpgrades` means the prompt is dead for the same reason. A
  misleading diagnostic is worse than none.
- **A modal is TWO boundaries and the scrim only closes one.** `HudMenuButton`
  was the single kit pressable that never set `Selectable`, so its TextButton
  defaulted to true: a D-pad could reach a *breathing* HUD icon through an open
  panel's own scrim and swap `openPanel` out from under it, arming the camera
  freeze and movement lock behind a shop the player never closed. Fixed at both
  ends — `selectable = <no panel open>`, and the Upgrades branch got its own copy
  of the modal guard (it TOGGLES, so it cannot simply borrow `togglePanel`'s).
- **The HUD button can open the tree before `workspace.Map` replicates.** Until
  now the only opener lived *inside* that map, so the "no map" branch was
  unreachable; it warned once with `Log.Once` and gave up. Leaving the world
  prompts enabled means the E-to-close press ALSO fires whatever prompt is in
  range — and `LayerEaterPrompt` turns that into a Robux dialog. Now a bounded
  re-check (R8's late-dependency rule) with the warn deferred to the timeout.
- **The tree became a mashable, *breathing* toggle, and each toggle costs beats
  that do not coalesce** (`panel` open + `panel` close + a non-deduped funnel
  step). ~2 toggles/s passes the server's 240 beats/min admission and takes that
  player's REAL beats down with it for the rest of the minute. Added a 5 s
  per-panel re-open debounce measured from the last REPORTED open (so a mash
  cannot walk the deadline forward), with closes emitted only when their open
  was. Verified live: three cycles in ~2.4 s → exactly one open, one funnel step,
  one close.
- **The join ownership fetch could clobber a mid-session purchase.** It yields up
  to ~4.5 s per throttled pass and then writes every key; `UserOwnsGamePassAsync`
  is eventually consistent right after a purchase, so a blind write turned the
  paid perk OFF for the session. It never downgrades a runtime `true` now. This
  was latent before; buying a pass mid-run is what makes it routine.
- **Both menus mount in both places** (only the parent frame's `Visible`
  differs), and `Theme.Feel.Pulse` repeats forever — so an ungated cue left
  TweenService driving UIScales on invisible buttons for the session. Cues are
  gated by place.
- Accepted as-is: in the combined DEV build the game block's Y offset moves when
  the lobby roster gains a row from a late social push. Correct, and dev-only.

## Verification
- Luau syntax gate over all of `src/` (0 failures); three Rojo builds (default /
  game / lobby).
- `analytics_scenario.lua` 76/76; `catalog_xcheck.py` clean.
- Studio playtest in the GAME place (`EatACake-Game`, 136881957250247), twice —
  once for the feature, once after the review fixes. Both boots: 18/18
  subscriptions started, no `require FAILED`, no new warnings.
  - Four buttons render at 65x50 in a 2x2 block, y 172..450 nominal.
  - Shop opens with live products and all four tabs; Squishies opens and renders
    a collection; the tree opens with the FULL modal wiring (blur 18, camera
    `Scriptable`, 3/3 world prompts disabled) and restores all of it on close.
  - Badge + pulse: with 5,000 calories / 5,000 gems both icons carry a badge and
    read `PulseScale = 1.0722` mid-breath while Pets/Settings sit at exactly
    1.0000; dropped to 0 / 87 both return to `1.0000` with no badge and no stuck
    tween. The Boosts tab's four cells were green `buy` at the same moment — the
    predicate and the cells agree.
  - Tutorial: opening the tree from the HUD at step `eat` left the step at `eat`
    and hid the eat hint; the machine then ran `eat → belly → path → upgrades`
    normally with the beam retargeting plate → computer, and the beat recorder on
    the live `AnalyticsBeat` remote showed `tutorial|arrived` → `flow|checkpoint`
    → `funnel|upgrades|open` → `tutorial|upgrades` in order.
  - `selectable` flips to false on all four buttons while the Shop is open.

## Open Questions / Followups
- **Not exercised live:** the Upgrades modal guard's refusal branch (reachable
  only by controller — pointer presses are contained by the scrim, which the
  playtest confirmed by closing the shop instead), the prompt-sweep retry (needs
  a genuinely late `workspace.Map`), and the `PassOwnershipSubs` no-downgrade
  path (needs a real Robux gamepass purchase mid-fetch). All three are reasoned
  and reviewed, not measured.
- The equip round-trip was verified as far as the panel rendering a collection;
  the click on a card did not land because the Studio MCP's mouse tool wedged
  mid-session (a known failure mode). `EquipPet` → `PetSubs` is COMMON and
  unconditional, so the wiring is not in doubt, but a live equip in a match is
  worth one minute of the next playtest.
- ⚠ The Studio MCP's `user_mouse_input` `instance_path` mode silently failed on
  `UpgradesOverlay.Close.CloseButton` (a control in the top ~60 px band) while
  working everywhere else; raw abs coordinates worked. Cost several turns.

## Related
- Features: `docs/features/app-root.md`, `docs/features/upgrades.md`,
  `docs/features/tutorial.md`, `docs/features/shop.md`, `docs/features/pets.md`,
  `docs/features/settings.md`, `docs/features/ui-kit.md`,
  `docs/features/analytics.md`
- ADRs touched: ADR-0006 (ref-owned tweens), ADR-0013 (run-scoped tree),
  ADR-0014 (money path), ADR-0016 (a marker owning its own render step)
- Prior flow: `docs/flow/2026-08-09_arrow-until-purchase-safe-area-slide-entrance.md`,
  `docs/flow/2026-08-04_layer-eater-settings-tree-icons.md`
