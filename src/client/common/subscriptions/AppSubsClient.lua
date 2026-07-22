--[[
	AppSubsClient — mounts the ONE composed React root (R4).

	Alphabetically FIRST among client subscriptions, so the tree is mounted
	before feature subs start feeding state — though AppRoot.Set works
	pre-mount too (patches land in the mount snapshot).

	Feature subs NEVER call UiRoot.Render themselves: a second Render would
	REPLACE the whole tree (single-root contract, docs/features/ui-kit.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "AppSubsClient"

local AppSubsClient = {}

function AppSubsClient.Start(data, modules)
	local UiRoot = modules.UiRoot
	local AppRoot = modules.AppRoot
	if not UiRoot or not AppRoot then
		Log.Warn(SCOPE, "UiRoot/AppRoot module missing — kit UI disabled")
		return
	end
	if UiRoot.Render(AppRoot.Element()) then
		Log.Info(SCOPE, "app root rendered (HUD + 5 panels)")
	else
		Log.Warn(SCOPE, "app root NOT rendered — React root unavailable; check ReactLua-Packages.rbxmx / Packages mapping")
	end
end

return AppSubsClient
