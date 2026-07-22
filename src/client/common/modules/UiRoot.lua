--[[ UiRoot
	Owns the single React root ScreenGui for all UIKit-based UI (R7: one responsibility).
	Feature code renders into it via UiRoot.Render(element); UI callbacks are wired
	in subscriptions by passing handlers into component props (R4-compatible: React
	manages its own internal events, domain wiring stays in subscriptions).
	UI kit: ReplicatedStorage.Shared.UIKit — see docs/features/ui-kit.md and
	.claude/skills/roblox-ui-kit/SKILL.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Log = require(ReplicatedStorage.Shared.Log)

local UiRoot = {}

local root
local screenGui

function UiRoot.Init()
	local ok, err = pcall(function()
		local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

		local player = Players.LocalPlayer
		local playerGui = player:WaitForChild("PlayerGui")

		local previous = playerGui:FindFirstChild("UiRoot")
		if previous then
			previous:Destroy()
		end

		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "UiRoot"
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = false
		screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		screenGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
		screenGui.ClipToDeviceSafeArea = true
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.DisplayOrder = 100
		screenGui.Parent = playerGui

		root = ReactRoblox.createRoot(screenGui)
	end)
	if not ok then
		Log.Warn("UiRoot", `React packages unavailable — kit UI disabled ({err}). Check ReactLua-Packages.rbxmx / Packages mapping (docs/features/ui-kit.md).`)
	else
		Log.Info("UiRoot", "React root mounted into PlayerGui.UiRoot")
	end
end

--API
function UiRoot.Render(element): boolean
	if not root then
		Log.Once("UiRoot", "no-root", "Render skipped: React root not initialized (missing npm packages?)")
		return false
	end
	root:render(element)
	return true
end

--API
function UiRoot.Unmount()
	if root then
		root:unmount()
		root = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
end

return UiRoot
