--[[
	UiData — client registry + resolver of ScreenGuis by exact name (R1).

	UI is authored in Studio (see CLAUDE.md "UI Workflow"); code resolves it
	by the NAMED INSTANCE TREE contract. Lookups are nil-tolerant so the
	template runs before the UI is authored — feature code must handle nil.

	guiNames — every ScreenGui the code expects (registry; keep updated).
]]

local Players = game:GetService("Players")

local UiData = {}

-- No Studio-authored ScreenGuis expected right now: all template UI is
-- kit-rendered (AppRoot -> PlayerGui.UiRoot). Register bespoke non-kit
-- ScreenGuis here when a game adds them.
UiData.guiNames = {}

--API
function UiData.Gui(name: string): ScreenGui?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild(name)
	return gui
end

--API
-- Recursive find of a named descendant inside a registered ScreenGui.
function UiData.Find(guiName: string, childName: string): Instance?
	local gui = UiData.Gui(guiName)
	if not gui then
		return nil
	end
	return gui:FindFirstChild(childName, true)
end

return UiData
