--[[ SettingsData
	Client settings definitions (R1: the setting SET + defaults live here, not
	in the view). The Settings window renders one toggle row per definition,
	ordered by `order`; labels resolve through LocaleData by `labelKey` (R1).

	Data shape:
	  definitions : { [id: kebab-case string] = { order: number, labelKey: string, default: boolean } }
	  titleKey    : locale key for the window title

	Ids MUST match the profile section keys in
	src/server/data/ProfileSchema/CoreSection.lua `defaults.settings` — the
	server validates SetSetting against that section, so an id that exists
	only here will not persist. Feature doc: docs/features/settings.md.
]]

local SettingsData = {}

SettingsData.titleKey = "title-settings"

SettingsData.definitions = {
	["music-enabled"] = { order = 1, labelKey = "label-music", default = true },
	["sfx-enabled"] = { order = 2, labelKey = "label-sound-effects", default = true },
}

return SettingsData
