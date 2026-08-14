--[[
	UpgradesSubsClient — upgrade levels consumer + hex-tree open/close (R4):
	  * UpgradesUpdate feeds LocalStatsService (bite prediction) + AppRoot's
	    hex-tree; node buys flow back through the BuyUpgrade remote.
	  * The tree is a full-screen MODAL overlay with TWO openers (2026-08-13):
	    the authored `UpgradeStation` ProximityPrompt on the game checkpoint's
	    computer (built by MapService, enabled, HoldDuration 0), and the GAME
	    HUD's Upgrades button, which routes through `onToggleUpgrades` so it
	    cannot bypass the modal wiring (features/app-root.md). Opening a menu is
	    local UI, so it needs no server round-trip. E (or the Close button) closes
	    it; a BlurEffect dims the world while open.
	    ⚠ The HUD button is live on the first rendered frame, while `workspace.Map`
	    is a server-side CLONE that replicates late (ADR-0007) — so
	    `setCheckpointPromptsEnabled` can now genuinely run before there is a map
	    to sweep. That used to be unreachable (the only opener lived inside the
	    map), which is why it degrades with a bounded RE-CHECK rather than one
	    warn: leaving the world prompts on means the E-to-close press also fires
	    whatever prompt is in range — and one of them (`LayerEater`) opens a Robux
	    dialog.
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

local UpgradesSubsClient = {}

function UpgradesSubsClient.Start(data, modules)
	local upgradesData = data.UpgradesUiData
	if upgradesData == nil then
		Log.Warn(SCOPE, "UpgradesUiData missing -- the upgrade tree cannot be opened in this place")
		return
	end
	local upgradesConfig = upgradesData["config"]
	local upgradesState = upgradesData["state"]
	if type(upgradesConfig) ~= "table" or type(upgradesState) ~= "table" then
		Log.Warn(SCOPE, "UpgradesUiData config/state missing -- upgrade UI wiring skipped")
		return
	end
	local promptName = upgradesConfig["prompt-name"]
	local closeActionName = upgradesConfig["close-action-name"]
	local blurSize = upgradesConfig["blur-size"]
	local blurTemplateName = upgradesConfig["blur-template-name"]
	-- Tuning lives in the data module (R1). Defaulted rather than validated: a
	-- missing cadence must not disable the whole tree, and both values only
	-- affect how patiently the prompt sweep waits for a late map.
	local PROMPT_SWEEP_INTERVAL = math.max(0.1, tonumber(upgradesConfig["prompt-sweep-seconds"]) or 0.5)
	local PROMPT_SWEEP_TIMEOUT = math.max(PROMPT_SWEEP_INTERVAL, tonumber(upgradesConfig["prompt-sweep-timeout-seconds"]) or 15)
	if type(promptName) ~= "string" or promptName == ""
		or type(closeActionName) ~= "string" or closeActionName == ""
		or type(blurSize) ~= "number"
		or blurSize ~= blurSize or blurSize < 0
		or type(blurTemplateName) ~= "string" or blurTemplateName == ""
		or type(upgradesState["disabled-prompts"]) ~= "table"
	then
		Log.Warn(SCOPE, "UpgradesUiData config invalid -- upgrade UI wiring skipped")
		return
	end
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local LocalStatsService = modules.LocalStatsService
	local PlayerControlService = modules.PlayerControlService
	local controlData = data.PlayerControlData
	if PlayerControlService == nil or controlData == nil or type(PlayerControlService.SetLocked) ~= "function" then
		Log.Warn(SCOPE, "PlayerControlData/PlayerControlService missing -- upgrade modal control gate unavailable")
		return
	end
	local controlReason = controlData.reasons and controlData.reasons.upgrades
	if type(controlReason) ~= "string" or controlReason == "" then
		Log.Warn(SCOPE, "PlayerControlData upgrade reason invalid -- upgrade modal control gate unavailable")
		return
	end
	local rBuy = Net.Remote("BuyUpgrade")

	local player = Players.LocalPlayer
	local setOpen -- forward decl
	local function resolveBlurTemplate(): BlurEffect?
		local uiKit = Shared:FindFirstChild("UIKit")
		local templates = uiKit and uiKit:FindFirstChild("Templates")
		local template = templates and templates:FindFirstChild(blurTemplateName)
		return if template and template:IsA("BlurEffect") then template else nil
	end
	local function ensureBlur(): BlurEffect?
		local current = upgradesState["blur"]
		if typeof(current) == "Instance" and current:IsA("BlurEffect") and current.Parent ~= nil then
			return current
		end
		local template = resolveBlurTemplate()
		if template == nil then
			Log.GraceOnce(SCOPE, "upgrade-blur-template-missing", 10, function()
				return resolveBlurTemplate() == nil
			end, `Shared.UIKit.Templates.{blurTemplateName} never replicated -- upgrade overlay continues without world blur`)
			return nil
		end
		local blur = template:Clone()
		blur.Enabled = upgradesState["open"] == true
		blur.Size = if blur.Enabled then blurSize else 0
		blur.Parent = Lighting
		upgradesState["blur"] = blur
		return blur
	end
	ensureBlur()
	Shared.DescendantAdded:Connect(function(descendant)
		if descendant.Name == blurTemplateName and descendant:IsA("BlurEffect") then
			ensureBlur()
		end
	end)

	-- Modal while open: freeze the camera (no zoom/rotate/pan) and stop character
	-- movement, so the tree stays put — convenient on PC and phone (the user's #2).
	local function setModal(active: boolean)
		local camera = Workspace.CurrentCamera
		if active then
			if camera then
				upgradesState["saved-camera-type"] = camera.CameraType
				camera.CameraType = Enum.CameraType.Scriptable
			end
			PlayerControlService.SetLocked(controlReason, true)
		else
			local savedCameraType = upgradesState["saved-camera-type"]
			if camera and savedCameraType ~= nil then
				camera.CameraType = savedCameraType
			end
			upgradesState["saved-camera-type"] = nil
			PlayerControlService.SetLocked(controlReason, false)
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

	-- Disable EVERY world prompt under this place's active map while the tree is
	-- open. The station and nearby prompts may share E — leaving one on lets the
	-- E-to-close press trigger behind the overlay, and `LayerEaterPrompt` turns
	-- that press into a Robux dialog (features/shop.md, hidden products).
	-- Re-enabled on close. Returns whether a map was found, so the caller can
	-- re-try while the tree is still open (the map replicates late — header).
	local function setCheckpointPromptsEnabled(enabled: boolean): boolean
		local disabledPrompts = upgradesState["disabled-prompts"]
		if enabled then
			for _, prompt in ipairs(disabledPrompts) do
				prompt.Enabled = true
			end
			table.clear(disabledPrompts)
			return true
		end
		local map = Workspace:FindFirstChild("LobbyMap") or Workspace:FindFirstChild("Map")
		if map == nil then
			return false
		end
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then
				d.Enabled = false
				table.insert(disabledPrompts, d)
			end
		end
		return true
	end

	-- The map can legitimately arrive AFTER the tree opens now that a HUD button
	-- can open it on the first frame. Re-check on a slow tick for as long as the
	-- tree is open, and only warn if it never shows up — R8's late-dependency
	-- rule, non-blocking. A one-shot `Log.Once` here would both false-positive on
	-- a normal late clone AND latch the key, permanently swallowing the real
	-- failure later in the session.
	local promptSweepGeneration = 0
	local function armPromptSweep()
		promptSweepGeneration += 1
		local generation = promptSweepGeneration
		task.spawn(function()
			local waited = 0
			while upgradesState["open"] == true and promptSweepGeneration == generation do
				if setCheckpointPromptsEnabled(false) then
					Log.Info(SCOPE, `world prompts disabled after the map replicated ({string.format("%.1f", waited)}s late)`)
					return
				end
				if waited >= PROMPT_SWEEP_TIMEOUT then
					Log.Once(
						SCOPE,
						"no-active-map",
						"workspace.LobbyMap/Map never appeared — world prompts are NOT disabled while the "
							.. "upgrade tree is open, so the E-to-close press also fires whatever prompt is in range"
					)
					return
				end
				waited += PROMPT_SWEEP_INTERVAL
				task.wait(PROMPT_SWEEP_INTERVAL)
			end
		end)
	end

	setOpen = function(open: boolean)
		if open == upgradesState["open"] then
			return
		end
		upgradesState["open"] = open
		AppRoot.Open(if open then "Upgrades" else nil)
		local blur = ensureBlur()
		if blur then
			blur.Enabled = open
			blur.Size = if open then blurSize else 0
		end
		local swept = setCheckpointPromptsEnabled(not open)
		if open and not swept then
			-- No map yet (it replicates late, and the HUD button can beat it).
			-- Keep trying while the tree is open — leaving the prompts live is
			-- what turns the E-to-close press into a Robux dialog.
			armPromptSweep()
		end
		setModal(open)
		if open then
			ContextActionService:BindAction(closeActionName, onCloseKey, false, Enum.KeyCode.E)
		else
			ContextActionService:UnbindAction(closeActionName)
		end
	end

	-- nil until the first push: the join snapshot is the player's existing tree,
	-- not a purchase. The cue follows a level actually going UP in the update,
	-- never the button — a refused buy (unaffordable, maxed) stays silent
	-- (docs/features/audio.md).
	local lastLevels: { [string]: number }? = nil

	Net.Update("UpgradesUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.levels) ~= "table" then
			return
		end
		LocalStatsService.SetLevels(payload.levels)
		AppRoot.Set({ upgrades = payload.levels })
		local snapshot, bought = {}, false
		for id, level in pairs(payload.levels) do
			if type(id) == "string" and type(level) == "number" then
				snapshot[id] = level
				if lastLevels ~= nil and level > (lastLevels[id] or 0) then
					bought = true
				end
			end
		end
		lastLevels = snapshot
		if bought and SoundPool then
			SoundPool.Play("upgradeBuy")
		end
	end)

	local Analytics = modules.LocalAnalyticsService

	AppRoot.SetCallbacks({
		onBuyUpgrade = function(id: string)
			-- The tap on a node's BUY. The server logs the attempt and the
			-- result; this exists so a buy the client itself never sends (a
			-- dropped remote, a stale panel) still shows up as a click.
			if Analytics then
				Analytics.Funnel("upgrades", "select")
			end
			rBuy:FireServer(id)
		end,
		-- Routed from the overlay Close button so blur + E-binding stay in sync.
		onCloseUpgrades = function()
			setOpen(false)
		end,
		-- HUD menu button: the tree is MODAL (blur, frozen camera, movement lock,
		-- world prompts off), so opening it must come through here, never through
		-- AppRoot.Open directly.
		onToggleUpgrades = function()
			setOpen(not upgradesState["open"])
		end,
	})

	-- Open on the station prompt (fires client-side for the local player).
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == promptName then
			setOpen(true)
		end
	end)

	-- Respawn while open would strand the modal (frozen camera + disabled
	-- controls on the new character) — force-close so setModal restores them.
	player.CharacterAdded:Connect(function()
		if upgradesState["open"] then
			setOpen(false)
		end
	end)
end

return UpgradesSubsClient
