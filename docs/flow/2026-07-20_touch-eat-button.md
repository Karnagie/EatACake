# 2026-07-20: Dedicated touch EAT button (no more "touch anywhere = eat")

Tags: cake-sim, app-root, ui-kit, input, mobile

## Task
User (mobile): "any touch input, including simply using the movement joystick,
causes the player to eat the cake. Eating should only be triggered by a separate
tap or by pressing and holding in a dedicated input area." (Task 3 of a 4-part
mobile/asset overhaul — see plan.)

## Context
`CakeSubsClient` started eating on ANY `UserInputService.InputBegan` of type
`Touch` (tracking the first finger). On mobile the movement joystick / camera
drag are raw touches, so they ate the cake. PC held the mouse anywhere. The kit
already had a round HOLD-style button (`GymOverlay` TAP) built on the shared
`Interaction.usePressable` press primitive.

## Plan
Add a dedicated on-screen **EAT** hold-button (touch only) and drive touch eating
ONLY from it; leave PC mouse-hold and the AutoEat attribute path untouched.

## Changes

**Created:**
- `src/shared/UIKit/Components/EatButton.lua` — round candy-pink (Rarity.Epic)
  hold-to-eat button, bottom-right thumb zone, built from the same Outer/Rim/Face
  + OutlinedText recipe as the gym TAP button; wired for HOLD via the extended
  `usePressable`.
- `docs/flow/2026-07-20_touch-eat-button.md` (this).

**Modified:**
- `src/shared/UIKit/Interaction.lua` — `usePressable` gains optional
  `onPressStart(input)` / `onPressEnd(input)` HOLD callbacks, and its press state
  became **finger-aware**: instead of one boolean it refcounts the Touch
  `InputObject`s that began on the button plus a `mouseDown` flag
  (`pressed = mouseDown or #touches > 0`). `onPressStart` fires on the FIRST
  press-in, `onPressEnd` on the LAST release; the disabled/hidden reset fires
  `onPressEnd` if it was held. Backwards-compatible (existing buttons pass only
  `onActivated`).
- `src/shared/UIKit/Theme.lua` — `Theme.EatButton` (round-button geometry, Epic
  palette, HUD placement) + freeze.
- `src/shared/UIKit/init.lua` — registers `EatButton`.
- `src/client/data/LocaleData.lua` — `eat-button` = "EAT".
- `src/client/modules/AppRoot.lua` — `IS_TOUCH` gate
  (`TouchEnabled and not KeyboardEnabled`), `eatButtonVisible` (eating/boss phase,
  not gymActive, no panel open), renders `EatButton`, wires `onEatDown`/`onEatUp`.
- `src/client/subscriptions/CakeSubsClient.lua` — removed the raw-Touch branch
  from `InputBegan`/`InputEnded`; touch eating now comes only from the button via
  `AppRoot.SetCallbacks({onEatDown, onEatUp})`. `onEatDown` fires ONE immediate
  `doBite()` (a tap can begin+end in a frame) then the Heartbeat auto-repeats
  while `eating`. PC mouse-hold path unchanged.
- Docs: `features/app-root.md`, `features/cake-sim.md`.

## Decisions
- **Touch-only button, PC unchanged.** `IS_TOUCH = TouchEnabled and not
  KeyboardEnabled` — a hybrid laptop reads as PC (mouse-hold). The button is
  hidden when a panel or the gym overlay is up, and outside the eating/boss
  phases.
- **Finger-aware press (from adversarial review).** A single press boolean let a
  second finger tapping the same button cancel the first finger's hold, and had a
  latent event-order dependency. Refcounting the touch `InputObject`s fixes both
  and makes drag-off release reliable, so the earlier single-finger global
  `InputEnded` safety was dropped (redundant + multi-touch-buggy).
- **Immediate bite on press-down** (not just `lastBiteAt = 0`) so a sub-frame tap
  still lands ≥1 bite.

## Verification (Studio, live)
- Clean boot, no errors. EAT button matches the kit style (thick dark-magenta
  outline heavier at the bottom, top rim flash, face lip, outlined "EAT").
- Forced `IS_TOUCH = true` (temp, reverted): hold → belly climbed; release →
  belly frozen (no stuck-on); tap on fresh cake → one bite; press-scale hit 0.93
  on press and sprang back on release.
- Backward-compat: the Shop menu button still opens its panel (onActivated); the
  EAT button correctly hides while a panel is open.
- PC mouse-hold-anywhere still eats (belly climbed); the raw-touch eat path is
  gone (structural — the Touch branch was removed).

## Open Questions / Followups
- Button placement (0.86, 0.66) was tuned on a desktop capture; confirm it clears
  the default mobile jump button on a real device / device-emulation pass.
- `IS_TOUCH` is computed once at module load (a keyboard connected after boot
  won't re-evaluate) — accepted per the documented "hybrid reads as PC" choice.

## Related
- Feature: `docs/features/cake-sim.md` (input), `docs/features/app-root.md`
- Primitive: `Interaction.usePressable` (ADR-0006, kit juice)
- Upstream: `docs/upstream/QUEUE.md` (2026-07-20 dedicated touch action button)
