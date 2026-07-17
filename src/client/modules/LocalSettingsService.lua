--[[
	LocalSettingsService — settings view-model (R2, logic only). Builds
	UIKit.SettingsPanel rows/defaults from SettingsData; AppRoot renders the
	panel and SettingsSubsClient wires persistence (SetSetting remote).

	Setting ids are kebab-case and IDENTICAL to the profile's
	`core.settings` keys (the server validates against the section defaults).
]]

local LocalSettingsService = {}

local locale, settingsData

function LocalSettingsService.Init(data)
	locale = data.LocaleData
	settingsData = data.SettingsData
end

--API
-- Ordered { id, label, enabled } rows for UIKit.SettingsPanel.
function LocalSettingsService.Rows()
	local rows = {}
	for id, def in pairs(settingsData.definitions) do
		table.insert(rows, { id = id, label = locale.T(def.labelKey), order = def.order, enabled = true })
	end
	table.sort(rows, function(a, b)
		return a.order < b.order
	end)
	return rows
end

--API
-- Default values keyed by id (used until the server snapshot arrives).
function LocalSettingsService.Defaults()
	local values = {}
	for id, def in pairs(settingsData.definitions) do
		values[id] = def.default
	end
	return values
end

--API
function LocalSettingsService.Title(): string
	return locale.T(settingsData.titleKey)
end

return LocalSettingsService
