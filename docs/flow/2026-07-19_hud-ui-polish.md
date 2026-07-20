# 2026-07-19: HUD UI polish (icon menu, cake-bar hide, checkpoint proximity)

Tags: app-root, ui-kit, checkpoint, body-gym, ui

## Task
Four player-facing HUD tweaks:
1. Remove the UI element showing the cake completion percentage.
2. Redesign the left-side menu buttons: standalone icons with the label just
   BELOW each icon, NO background behind icon or text. Placeholder icon
   `rbxassetid://138519589128299` for all (per-panel real art later).
3. Make those buttons bigger — the old ones were too small to tap on phones.
4. The "TO CHECKPOINT" button should only appear when the player is far from
   the checkpoint; hide it when already close.

## Context
- HUD is composed in `client/modules/AppRoot.lua` (the one React root). The
  left menu was 8 rows of `Components.Button` on `Theme.MenuButton` (blue
  background). Cake % lives in the top-center `CakeBar` (`cake-progress` =
  "CAKE {pct}%"), which the same bar reuses for boss HP/timer + the "NEW CAKE
  IN Xs" countdown + the "PET TIME!" reward flash (`AppRoot.cakeBarModel`).
- The bare icon+label pattern already existed in the kit demo
  `Components/Hud.lua` (`menuButton`, `BARE_BUTTONS=true`) — formalized here
  into a real exported component.
- Checkpoint platform parts replicate under `workspace.Map.Checkpoint`
  (`CheckpointPlate`, axis-aligned); `UpgradesSubsClient` already reads them
  client-side. `features/checkpoint.md`, `features/app-root.md`.

## Plan
Kit-first. New `HudMenuButton` component + `Theme.HudMenuButton` style; drive
the menu loop from it. Gate `CakeBar` visibility on phase. Client-side
proximity check (BodySubsClient RenderStepped, throttled) → `checkpointFar`
state → hide the button. Asked the user how far the cake-bar removal should go;
they chose "hide during eating only" (keep boss + spawn + reward).

## Changes

**Created:**
- `src/shared/UIKit/Components/HudMenuButton.lua` — bare icon + label-below
  button, no background; whole rectangle is a transparent `TextButton` (big
  tap target); self-constrains via `UIAspectRatioConstraint`
  (`DominantAxis = Height`); optional notification `Badge`.

**Modified:**
- `src/shared/UIKit/Components/CakeBar.lua` — added `visible` prop
  (`Visible = props.visible ~= false`).
- `src/shared/UIKit/init.lua` — registered `HudMenuButton`.
- `src/shared/UIKit/Theme.lua` — new `Theme.HudMenuButton` section (nominal
  100×118, icon zone + label zone). `Theme.AppHud`: bigger menu geometry
  (`MenuWidth 92/1920`, `MenuButtonHeight 100/1080`, gap 12), removed the now
  dead old-menu `Badge*` keys, added `MenuIcons`/`MenuIconPlaceholder` (all the
  placeholder id) and `CheckpointHideMarginStuds = 1.5`.
- `src/client/modules/AppRoot.lua` — menu loop builds `Components.HudMenuButton`
  (icon = `hud.MenuIcons[name]`); `cakeVisible = phase ~= "eating"` passed to
  `CakeBar.visible`; `CheckpointBtn` frame `Visible = state.checkpointFar ~=
  false`; new `checkpointFar = true` state default.
- `src/client/subscriptions/BodySubsClient.lua` — throttled (~5 Hz) proximity
  check in the existing `RenderStepped` loop reads
  `workspace.Map.Checkpoint.CheckpointPlate`, pushes `checkpointFar` to AppRoot
  ONLY on change; `Log.GraceOnce` if the plate never replicates. Requires
  `UIKit.Theme` (for the margin) + `Log`.

## Decisions
- **Cake bar: hide during eating, keep for boss/spawn/reward.** The bar is
  reused for boss HP/timer and the new-cake countdown; deleting it outright
  would drop that info. `cakeVisible = (state.cake ~= nil and phase ~=
  "eating")`. Chosen by the user over "remove entirely" / "drop only the
  number".
- **Whole button is the tap target.** `HudMenuButton` root is a transparent
  `TextButton` (icon + label as inert children) so the comfortable tap area is
  the full icon+label rectangle, not just the icon.
- **Button FILLS its list cell — no aspect constraint on the button.** First
  tried a `UIAspectRatioConstraint (DominantAxis = Height)`, but that COLLAPSES
  the button on any screen narrower than ~1.64:1 (iPad 4:3, 16:10): the default
  `AspectType = FitWithinMaxSize` makes `DominantAxis` inert and fits the button
  inside the (thin `MenuWidth` × row-height) box, taking the smaller axis →
  under-filled column, smaller tap targets (the opposite of the request; caught
  in Studio + adversarial review). Fix: drop the constraint. The button fills
  its `UIListLayout` cell (`Size = fromScale(1, rowFrac)`) at full row height on
  every aspect ratio; the icon (`ScaleType.Fit`) self-fits a square and the
  label auto-scales, so the internal zones (fractions of the cell) hold at any
  cell shape.
- **Proximity by plate FOOTPRINT, not radius.** near = inside the plate's XZ
  footprint (`|dx| ≤ Size.X/2 + margin`, same for Z), read from the live
  `CheckpointPlate` (it steps down per layer). The cake and plate footprints
  don't overlap in X (an `edgeGap` sits between them), so a player anywhere on
  the cake is always "far" — a radial threshold couldn't separate them because
  the plate is only 0.5 studs off the cake's +X edge. Margin kept small (1.5)
  so the cake edge isn't swallowed.
- **Threshold in `Theme.AppHud`** (R1: no constant in the subscription) — next
  to the other checkpoint-button layout constants; BodySubsClient reads
  `Theme.AppHud.CheckpointHideMarginStuds` (0.4, kept < the loaf→plate
  `edgeGap` 0.5 so the near zone's inner edge stays outside the loaf — the cake
  never false-hides the button; caught in review).
- **Push-on-change only.** The 5 Hz check calls `AppRoot.Set` solely when the
  near/far boolean flips, so the HUD doesn't re-render every tick.
- Kept `Theme.MenuButton` (unused now) as a generic kit style; only the
  game's HUD switched to the icon variant.

## Open Questions / Followups
- Real per-panel icons: swap each `Theme.AppHud.MenuIcons[*]` entry (all point
  at the placeholder today).

## Related
- Feature: `docs/features/app-root.md`, `docs/features/checkpoint.md`
- Prior flow: `docs/flow/2026-07-19_checkpoint-platform.md`,
  `docs/flow/2026-07-19_gym-fat-drain-rework.md`
