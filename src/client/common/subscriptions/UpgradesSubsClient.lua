--[[
	UpgradesSubsClient — upgrade levels consumer + hex-tree open/close (R4):
	  * UpgradesUpdate feeds LocalStatsService (bite prediction) + AppRoot's
	    hex-tree; node buys flow back through the BuyUpgrade remote.
	  * The tree is a full-screen overlay opened from the checkpoint COMPUTER's
	    ProximityPrompt (features/upgrades.md). Opening a menu is local UI, so it
	    is handled entirely client-side — no server round-trip. E (or the Close
	    button) closes it; a BlurEffect dims the world while open.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "UpgradesSubsClient"
-- Must match MapConfigData.checkpoint.upgradePromptName (server-built prompt).
local UPGRADE_PROMPT = "UpgradeStation"
local CLOSE_ACTION = "CloseUpgradeTree"
local BLUR_SIZE = 18

local UpgradesSubsClient = {}

function UpgradesSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local LocalStatsService = modules.LocalStatsService
	local rBuy = Net.Remote("BuyUpgrade")

	local blur = Instance.new("BlurEffect")
	blur.Name = "UpgradeTreeBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	local player = Players.LocalPlayer
	local isOpen = false
	-- Checkpoint prompts we disabled on open (to re-enable on close).
	local disabledPrompts: { ProximityPrompt } = {}
	local savedCameraType: Enum.CameraType? = nil
	local controls -- default PlayerModule controls (lazy)
	local setOpen -- forward decl

	local function getControls()
		if controls == nil then
			local ok, playerModule = pcall(function()
				return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
			end)
			if ok and playerModule then
				controls = playerModule:GetControls()
			end
		end
		return controls
	end

	-- Modal while open: freeze the camera (no zoom/rotate/pan) and stop character
	-- movement, so the tree stays put — convenient on PC and phone (the user's #2).
	local function setModal(active: boolean)
		local camera = Workspace.CurrentCamera
		if active then
			if camera then
				savedCameraType = camera.CameraType
				camera.CameraType = Enum.CameraType.Scriptable
			end
			local c = getControls()
			if c then
				c:Disable()
			else
				-- R8: don't silently skip the movement freeze.
				Log.Once(SCOPE, "no-controls", "PlayerModule controls unavailable — movement not frozen while the tree is open")
			end
		else
			if camera and savedCameraType ~= nil then
				camera.CameraType = savedCameraType
			end
			savedCameraType = nil
			local c = getControls()
			if c then
				c:Enable()
			end
		end
	end

	-- E closes while open (desktop). Suppressed while a kit TextBox is focused.
	local function onCloseKey(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		setOpen(false)
		return Enum.ContextActionResult.Sink
	end

	-- Disable EVERY checkpoint ProximityPrompt while the tree is open. The station
	-- AND gym prompts both use E with overlapping range — leaving either on lets
	-- the E-to-close press ALSO re-open the station / start a gym session behind
	-- the overlay; it also hides the overlapping prompt UI. Re-enabled on close.
	local function setCheckpointPromptsEnabled(enabled: boolean)
		if enabled then
			for _, prompt in ipairs(disabledPrompts) do
				prompt.Enabled = true
			end
			table.clear(disabledPrompts)
			return
		end
		local map = Workspace:FindFirstChild("Map")
		local checkpoint = map and map:FindFirstChild("Checkpoint")
		if checkpoint == nil then
			-- R8: the E-to-close guard depends on these prompts being off.
			Log.Once(SCOPE, "no-checkpoint", "workspace.Map.Checkpoint missing — checkpoint prompts not toggled while the tree is open")
			return
		end
		for _, d in ipairs(checkpoint:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then
				d.Enabled = false
				table.insert(disabledPrompts, d)
			end
		end
	end

	setOpen = function(open: boolean)
		if open == isOpen then
			return
		end
		isOpen = open
		AppRoot.Open(if open then "Upgrades" else nil)
		blur.Enabled = open
		blur.Size = if open then BLUR_SIZE else 0
		setCheckpointPromptsEnabled(not open)
		setModal(open)
		if open then
			ContextActionService:BindAction(CLOSE_ACTION, onCloseKey, false, Enum.KeyCode.E)
		else
			ContextActionService:UnbindAction(CLOSE_ACTION)
		end
	end

	Net.Update("UpgradesUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.levels) ~= "table" then
			return
		end
		LocalStatsService.SetLevels(payload.levels)
		AppRoot.Set({ upgrades = payload.levels })
	end)

	AppRoot.SetCallbacks({
		onBuyUpgrade = function(id: string)
			rBuy:FireServer(id)
		end,
		-- Routed from the overlay Close button so blur + E-binding stay in sync.
		onCloseUpgrades = function()
			setOpen(false)
		end,
	})

	-- Open on the station prompt (fires client-side for the local player).
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == UPGRADE_PROMPT then
			setOpen(true)
		end
	end)

	-- Respawn while open would strand the modal (frozen camera + disabled
	-- controls on the new character) — force-close so setModal restores them.
	player.CharacterAdded:Connect(function()
		if isOpen then
			setOpen(false)
		end
	end)
end

return UpgradesSubsClient
