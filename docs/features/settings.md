# Settings (persisted player toggles)

## What it does
Toggle settings (music/sfx) persisted in the profile and replicated on join.
The window is the kit `SettingsPanel` rendered inside AppRoot (single-root
contract — nothing here calls `UiRoot.Render`).

## The set
`src/client/data/SettingsData.lua` `definitions[id] = { order, labelKey,
default }`. Ids are kebab-case and MUST equal the profile keys in
`ProfileSchema/CoreSection.lua` `defaults.settings` (`music-enabled`,
`sfx-enabled`) — the server validates `SetSetting` against the section
defaults (the section IS the whitelist), so a mismatched id silently won't
persist.

## Flow
Join: `SettingsSubs.SendSettings` → `SettingsUpdate { settings = map }` →
client applies effects + feeds AppRoot. Toggle: optimistic local update
(values seeded from defaults so an early toggle can't wipe the other rows) +
effect hook + `SetSetting(id, value)` fire-and-forget (server coerces
`value == true`).

## Effects hook
`SettingsSubsClient.applySetting(id, value)` — apply SoundService group
volumes etc. per game. Currently logs only.

## Files
Server: `CoreSection` (storage), `SettingsSubs`. Client: `SettingsData`,
`LocalSettingsService` (rows/defaults/title view-model), `SettingsSubsClient`,
AppRoot panel. Remotes: `SetSetting`, `SettingsUpdate`.
