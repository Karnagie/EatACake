--[[ Selector
	One-line switch between demo apps for quick visual verification in Studio.
]]

-- "Hud", "PetsInspect", "Pets" or "Settings"
local SHOW = "Hud"

if SHOW == "Hud" then
	return require(script.Parent.HudDemo)
end

if SHOW == "PetsInspect" then
	return require(script.Parent.PetsInspectDemo)
end

if SHOW == "Pets" then
	return require(script.Parent.PetsDemo)
end

return require(script.Parent.SettingsDemo)
