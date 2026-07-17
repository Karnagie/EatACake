# 2026-07-15: Settings window + React health check

Tags: settings, ui-kit, react, packages, bootstrap, r8

## Task
"Check whether React works in the project" — playtest logs showed
`Infinite yield possible on ReplicatedStorage.Packages:WaitForChild("node_modules")`
from `ReactRoblox`. To verify, show a Settings window at startup with "Music"
and "Sound Effects" buttons.

## Context
UI kit (`Shared.UIKit`) + `UiRoot` existed but NOTHING rendered through it yet
(only reference demos). React resolves from `ReplicatedStorage.Packages`.
Symptom: `node_modules` under `Packages` was absent, so `ReactRoblox`'s
`WaitForChild("node_modules")` yielded forever — and because that require runs
during client bootstrap, the WHOLE client bootstrap parked (the log stopped at
`LocalRewardsService.Init`, never reached `UiRoot.Init` or the summary).

## Plan (final)
React packages are **vendored** as a single committed model
`ReactLua-Packages.rbxmx` (a `Packages` folder holding `React`, `ReactRoblox`,
and `node_modules`), rojo-mapped to `ReplicatedStorage.Packages`. No npm, no
build step — every copy gets React out of the box. Then build the Settings
window as the first real kit feature, rendered at start.

(First attempted the npm/npmluau route — `npm install` restoring an optional
`node_modules` path — then replaced it with the vendored `.rbxmx` at the user's
request: simpler, self-contained, nothing to run per copy.)

## Changes

**Created:**
- `src/client/data/SettingsData.lua` — settings definitions (R1: the row set +
  defaults live here). `music`, `sound-effects`, both default on.
- `src/client/modules/LocalSettingsService.lua` — Settings VIEW: builds the kit
  `SettingsPanel` (Settings archetype) from SettingsData; owns React-internal
  UI state; `Element(props)` for the caller.
- `src/client/subscriptions/SettingsSubsClient.lua` — mounts the window via
  `UiRoot.Render` at start; `onToggle` side-effect hook (logs today).
- `docs/features/settings.md`.

**Modified:**
- `default.project.json` — `ReplicatedStorage.Packages` now `$path`
  `ReactLua-Packages.rbxmx` (was `Packages/` dir + optional `node_modules`).
- `src/client/modules/UiRoot.lua` — `Render` returns boolean (honest logging).
- `src/client/data/LocaleData.lua` — `title-settings`, `label-music`,
  `label-sound-effects`.
- `docs/MAP.md`, `docs/features/ui-kit.md`, `docs/registries/data-keys.md`,
  `TEMPLATE_CHANGELOG.md`.

**Deleted:**
- `node_modules/`, `package.json`, `package-lock.json`, the (now empty)
  `Packages/` dir + its `React.lua`/`ReactRoblox.lua` loaders — the npm route,
  superseded by the vendored `.rbxmx`.

## Decisions
- **Vendor React as a committed `.rbxmx`, not npm.** The npm/optional-path setup
  infinite-yielded (and parked all of client bootstrap) whenever `npm install`
  was skipped in a copy. A single rojo-mapped model bundles `node_modules`
  inseparably, so the packages are always present — no per-copy step, no
  missing-dependency failure mode. Rojo maps a model file's single root
  instance; the file's root IS a `Packages` folder, so key `Packages` → file
  gives a clean `ReplicatedStorage.Packages` (verified via `rojo build`: one
  `Packages` folder, React/ReactRoblox/node_modules inside, no double-nesting).
- **Settings set lives in a data module (SettingsData), not the view.** R1;
  also makes rows extensible without touching React. Labels via LocaleData.
- **Window owns its own toggle/open state** (React `useState`), like the kit
  demos — R4-exempt per `features/ui-kit.md`. Domain side-effects stay in the
  subscription's `onToggle` (R4).
- **Reused `SettingsPanel`** — the Settings archetype is "(exists: SettingsPanel)"
  per the skill's window-archetypes table; no new components warranted.

## Open Questions / Followups
- No persistence/audio yet: `onToggle` only logs. Persist to profile `core`
  (reserved in registry) + apply SoundService group volume when a settings
  feature lands. Move the `default = true` seeds to originate from `core` then.
- Updating React = replace `ReactLua-Packages.rbxmx` (re-export jsdotlua under a
  `Packages` folder).
- After changing `default.project.json`, `rojo serve` must be restarted and the
  Studio Rojo plugin reconnected to pick up the new `Packages` mapping.

## Related
- Feature: `docs/features/settings.md`, `docs/features/ui-kit.md`
- Prior flow: `docs/flow/2026-07-15_ui-kit-port.md`
