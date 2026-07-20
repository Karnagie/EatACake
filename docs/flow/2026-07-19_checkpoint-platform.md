# 2026-07-19: Checkpoint return-to-gym platform

Tags: checkpoint, body-gym, cake-sim, map, ui-kit, net

## Task
"When on the cake, F key or a UI button returns you to a checkpoint — the place
where you extract fat. The checkpoint is a platform beside the cake on 4 legs,
its top at the height of the last layer; as a layer is eaten it drops to the
next layer's height."

## Context
"Extract fat" = the gym (`features/body-gym.md`): converts stored→banked
calories, empties the belly. It was a FLOOR zone (`MapConfigData.gym`, x=78,
y≈0). The cake is a heightfield (`features/cake-sim.md`) with bottom-up layer
bands `{id,bottom,top}`; `CakeFieldService.ScanStats` already computes
`topBandIndex` at 1 Hz. Footprint is FIXED (loaf 84×57, +X edge at 42 studs).
No keybind system existed (input was raw UserInputService). UI = the kit
(`roblox-ui-kit` skill), composed in `AppRoot`.

## Plan
User chose (AskUserQuestion): **move the gym onto the platform** (remove floor
gym) + **return-target only** (spawn stays on the cake). Build the platform in
MapService (code-built-map pattern); drive its height from CakeSubs' scan via
`topBandIndex`; teleport via a new server-authoritative `ReturnToCheckpoint`
remote fired by F (ContextActionService) and a HUD button.

## Changes

**Created:**
- `src/shared/remotes/ReturnToCheckpoint.model.json` — teleport request remote
- `docs/features/checkpoint.md` — feature doc (single source)

**Modified:**
- `data/MapConfigData.lua` — `gym` → `checkpoint` (platform geometry + prompt/range)
- `services/MapService.lua` — removed floor gym build; build the Checkpoint
  (plate/4 legs/machine+prompt); `SetCheckpointHeight` (dedup guard),
  `GetCheckpointCFrame`, `NearGym` on the moving machine; capture footprint in Init
- `subscriptions/CakeSubs.lua` — set height on new cake + from the 1 Hz scan
  `topBandIndex`; `ReturnToCheckpoint` handler (IsLoaded/char guards, 0.5 s
  debounce, PlayerRemoving cleanup)
- `subscriptions/BodySubs.lua` — prompt name from `checkpoint.promptName`
- `client/subscriptions/BodySubsClient.lua` — F key (CAS, textbox-focus guard) +
  `onReturnCheckpoint` callback
- `client/modules/AppRoot.lua` — HUD "BURN FAT" button (bottom-center, above belly)
- `shared/UIKit/Theme.lua` — `CheckpointButton` style + `AppHud.Checkpoint*`
- `client/data/LocaleData.lua` — `hud-burn-fat`
- Docs: MAP, registries/remotes, features/body-gym (gym now on checkpoint)

**Deleted:** floor gym zone (GymPad + 4 circling machines) — folded into the checkpoint.

## Decisions
- **Height = `composition[topBandIndex].top`** (stepwise per layer), not the
  live max surface — matches "drops when a layer is eaten". `topBandIndex` only
  decreases when a whole band is gone (auto-sweep cleans the tail), so steps are
  clean and infrequent.
- **Server-authoritative teleport**: the checkpoint Y is server truth; the
  client sends no destination. Debounce 0.5 s (a mashed key can't rag-doll).
- **Legs resize** (floor→plate bottom) rather than a rigid rig, so it always
  reads as "standing on the ground beside the cake" at any height.
- **Dedup guard** in `SetCheckpointHeight` — the 1 Hz re-assert would otherwise
  re-replicate 5 anchored parts every second.
- Anchored plate: a player on it when it steps down briefly falls to the new
  height (acceptable; steps are rare).

## Verification
Studio playtest (studio-verifier) — PASS. Clean R8 boot; `workspace.Map.Checkpoint`
= plate (center 51.5, top Y 68 = origin 2 + top-layer 66) + 4 legs (66 tall,
floor→plate) + machine/GymPrompt on top; `ReturnToCheckpoint` teleports the
player to the plate (6 studs from the machine, in range). Adversarial review
clean on core logic; its 3 nits fixed (promptRange→config, R8 gym-prompt log,
new-cake re-seat). ⚠ The new `ReturnToCheckpoint.model.json` **double-synced** in
the live Rojo session (2 RemoteEvents) — deduped in Edit mode; a Rojo sync
restart rebuilds it clean (see memory `rojo-new-file-double-sync`).

## Open Questions / Followups
- Polish: a short server tween on layer-step instead of a snap (players don't
  ride anchored parts, so a snap is functionally fine).
- Advertise the F shortcut on the button label on desktop only (needs a
  platform check in AppRoot).

## Related
- Feature: `docs/features/checkpoint.md`; `docs/features/body-gym.md`,
  `docs/features/cake-sim.md`
- Prior flow: `docs/flow/2026-07-18_eat-in-front-ball-roll.md`
