--[[
	UiInputSubsClient -- global pointer continuation for reusable UIKit gestures.

	Owns UserInputService InputChanged/InputEnded connections (R4) and forwards
	them into UIKit.InputBridge. Components still own gesture interpretation;
	this subscription owns only the engine event wiring.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))

local UiInputSubsClient = {}
local SCOPE = "UiInputSubsClient"

function UiInputSubsClient.Start()
	local uiKit = Shared:FindFirstChild("UIKit")
	local bridgeModule = uiKit and uiKit:FindFirstChild("InputBridge")
	if bridgeModule == nil or not bridgeModule:IsA("ModuleScript") then
		Log.Warn(SCOPE, "UIKit.InputBridge missing — global drag release/move continuation is disabled")
		return
	end
	local ok, bridge = pcall(require, bridgeModule)
	if
		not ok
		or type(bridge) ~= "table"
		or type(bridge.DispatchChanged) ~= "function"
		or type(bridge.DispatchEnded) ~= "function"
	then
		Log.Warn(SCOPE, `UIKit.InputBridge failed to load — global gestures disabled: {tostring(bridge)}`)
		return
	end
	UserInputService.InputChanged:Connect(bridge.DispatchChanged)
	UserInputService.InputEnded:Connect(bridge.DispatchEnded)
	Log.Info(SCOPE, "UIKit global pointer continuation wired")
end

return UiInputSubsClient
