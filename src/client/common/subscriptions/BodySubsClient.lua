--[[
	BodySubsClient — stomach/gym/body domain on the client (R4, GDD §8):
	  * StomachUpdate -> HUD state + floating calorie numbers (§7.3)
	  * GymUpdate -> fat-burn overlay state (started/progress/result/stopped) +
	    deflate celebration (coins, whoosh)
	  * drives BallRollController (full-belly tumble) per frame (the equipped
	    squishies are stepped by PetsSubsClient instead — COMMON, so they also
	    fly in the lobby, where this Start returns early)
	  * gym taps: AppRoot's onGymTap callback -> GymTap remote (+ per-tap sound)
	  * return to checkpoint: F key (ContextActionService) + AppRoot's
	    onReturnCheckpoint callback -> ReturnToCheckpoint remote (server teleports
	    onto the checkpoint platform — features/checkpoint.md)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local Theme = require(Shared:WaitForChild("UIKit"):WaitForChild("Theme"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))
local BodyConfig = require(Shared:WaitForChild("config"):WaitForChild("BodyConfig"))

local SCOPE = "Body"

local BodySubsClient = {}

function BodySubsClient.Start(data, modules)
	if data.GameUiData == nil then
		Log.Info(SCOPE, "game client partition absent -- body/gym/checkpoint input skipped in lobby")
		return
	end
	local AppRoot = modules.AppRoot
	local FloatingNumbers = modules.FloatingNumbers
	local ComboMeter = modules.ComboMeter
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local BallRollController = modules.BallRollController
	local PlayerControlService = modules.PlayerControlService

	local player = Players.LocalPlayer
	local rGymTap = Net.Remote("GymTap")
	local rReturn = Net.Remote("ReturnToCheckpoint")
	local controlGateReady = PlayerControlService ~= nil and type(PlayerControlService.IsLocked) == "function"
	if not controlGateReady then
		Log.Warn(SCOPE, "PlayerControlService.IsLocked missing -- body/checkpoint input disabled")
	end
	local function inputLocked(): boolean
		if not controlGateReady then
			return true
		end
		local ok, lockedOrError = pcall(PlayerControlService.IsLocked)
		if not ok then
			Log.Once(SCOPE, "control-gate-failed", `PlayerControlService.IsLocked FAILED -- body/checkpoint input disabled: {lockedOrError}`)
			return true
		end
		return lockedOrError == true
	end

	-- Return to the checkpoint platform to burn fat. Fired by the HUD button
	-- (onReturnCheckpoint) and the F key; the server owns the destination.
	local function returnToCheckpoint()
		if inputLocked() then
			Log.Info(SCOPE, "ReturnToCheckpoint ignored while client input is locked")
			return
		end
		rReturn:FireServer()
	end

	local function headPosition(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root and root.Position + Vector3.new(0, 3.5, 0) or nil
	end

	-- Hide the gym "Burn it off!" prompt for THIS player while the belly is empty
	-- (mirrors the server's `fill < minStartFill` no-op guard, features/body-gym.md):
	-- setting Enabled locally on the shared world prompt affects only this client.
	-- Re-checked from StomachUpdate AND the ~5 Hz loop so a late-replicating prompt
	-- (or a rebuilt one, which defaults Enabled=true) converges either way.
	local gymMinStartFill = BodyConfig.gym.minStartFill
	local lastFill = 0
	-- GymMachine carries exactly one ProximityPrompt (the gym prompt) — resolve by
	-- class so the client doesn't depend on the server-only prompt name.
	local function resolveGymPrompt(): ProximityPrompt?
		local map = Workspace:FindFirstChild("Map")
		local checkpoint = map and map:FindFirstChild("Checkpoint")
		local machine = checkpoint and checkpoint:FindFirstChild("GymMachine")
		return machine and machine:FindFirstChildWhichIsA("ProximityPrompt") :: ProximityPrompt?
	end
	local function updateGymPrompt()
		-- The upgrade-tree modal OWNS every checkpoint prompt while open (it disables
		-- them so the E-to-close press can't also start a gym session behind the
		-- overlay — UpgradesSubsClient). Don't fight it: skip while it's open; it
		-- restores prompts on close and this gate re-applies on the next tick.
		if AppRoot.GetOpenPanel() == "Upgrades" then
			return
		end
		local prompt = resolveGymPrompt()
		if prompt == nil then
			-- R8: warn once (deferred, non-blocking) only if it truly never resolves.
			-- A missing checkpoint/plate is already GraceOnce'd in the proximity check.
			Log.GraceOnce(SCOPE, "no-gym-prompt", 10, function()
				return resolveGymPrompt() == nil
			end, "workspace.Map.Checkpoint.GymMachine ProximityPrompt missing — gym prompt can't empty-hide (stays shown)")
			return
		end
		local shouldEnable = not inputLocked() and lastFill >= gymMinStartFill
		if prompt.Enabled ~= shouldEnable then
			prompt.Enabled = shouldEnable
		end
	end

	Net.Update("StomachUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		AppRoot.Set({ stomach = payload })
		lastFill = tonumber(payload.fill) or lastFill
		updateGymPrompt()
		local gained = tonumber(payload.gained) or 0
		if gained >= 1 then
			local pos = headPosition()
			if pos then
				local color = if payload.glutton
					then Color3.fromRGB(255, 140, 90) -- glutton x2: hotter numbers
					else Color3.fromRGB(255, 235, 130)
				FloatingNumbers.Show(pos, `+{math.floor(gained)}`, ComboMeter.Intensity(), color)
			end
		end
	end)

	-- Fat-burn session events (features/body-gym.md): "started" opens the tap
	-- overlay, "progress" streams the remaining-fat fraction (~stepHz) into it,
	-- and "result"/"stopped"/"auto"/"instant" close it. Only the burns that
	-- actually banked calories ("stopped" is a walk-away, no payout) play the FX.
	Net.Update("GymUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local event = payload.event
		if event == "started" then
			AppRoot.Set({ gym = { active = true, remain01 = 1 } })
			SoundPool.Play("gymStart")
		elseif event == "progress" then
			AppRoot.Set({ gym = { active = true, remain01 = tonumber(payload.remain01) or 0 } })
		elseif event == "result" or event == "stopped" or event == "auto" or event == "instant" then
			AppRoot.Set({ gym = { active = false } })
			local banked = tonumber(payload.banked) or 0
			if banked > 0 and event ~= "stopped" then
				SoundPool.Play("gymWhoosh")
				SoundPool.Play("gymPayout") -- the calories actually banking
				local pos = headPosition()
				if pos then
					ParticlePool.Burst(pos, Color3.fromRGB(255, 220, 90), JuiceConfig.particles.coinsPerGymBurn)
					FloatingNumbers.Show(pos, `+{banked} cal`, 1, Color3.fromRGB(150, 255, 150))
				end
			end
		end
	end)

	-- Gym mash taps + the return-to-checkpoint button flow from the kit UI
	-- through AppRoot's callbacks.
	AppRoot.SetCallbacks({
		onGymTap = function()
			if inputLocked() then
				Log.Info(SCOPE, "GymTap ignored while client input is locked")
				return
			end
			rGymTap:FireServer()
			-- No sound here: the tap button is a kit pressable, so the shared
			-- press primitive already clicks it (Interaction SOUND contract) —
			-- a second cue per tap would just double up.
		end,
		onReturnCheckpoint = returnToCheckpoint,
	})

	-- F key shortcut (desktop). ContextActionService actions can fire while a
	-- kit TextBox (e.g. the codes input) is focused — skip those so typing "f"
	-- never teleports the player.
	ContextActionService:BindAction("ReturnToCheckpoint", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		returnToCheckpoint()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F)

	-- TO CHECKPOINT button visibility: hide it once the player is on/at the
	-- checkpoint platform (no point teleporting where you already are). The plate
	-- replicates under workspace.Map.Checkpoint; "near" = inside its XZ footprint
	-- expanded by a small margin (Theme.AppHud.CheckpointHideMarginStuds, kept <
	-- the loaf→plate edgeGap so the near zone's inner edge stays outside the loaf
	-- — a player anywhere on the cake reads "far"). Throttled; pushes on change.
	local margin = Theme.AppHud.CheckpointHideMarginStuds
	local checkAccum = math.huge -- force a check on the first frame
	local wasFar: boolean? = nil

	local function setFar(far: boolean)
		if wasFar ~= far then
			wasFar = far
			AppRoot.Set({ checkpointFar = far })
		end
	end

	local function updateCheckpointProximity()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			return -- no character yet; hold the last state
		end
		local map = Workspace:FindFirstChild("Map")
		local checkpoint = map and map:FindFirstChild("Checkpoint")
		local plate = checkpoint and checkpoint:FindFirstChild("CheckpointPlate") :: BasePart?
		if plate == nil then
			-- Not replicated yet: keep the button visible (the server no-ops
			-- ReturnToCheckpoint until the plate exists anyway). Warn once, deferred
			-- and non-blocking (R8), only if it truly never arrives.
			Log.GraceOnce(SCOPE, "no-checkpoint-plate", 10, function()
				local m = Workspace:FindFirstChild("Map")
				local c = m and m:FindFirstChild("Checkpoint")
				return c == nil or c:FindFirstChild("CheckpointPlate") == nil
			end, "workspace.Map.Checkpoint.CheckpointPlate missing — TO CHECKPOINT button can't proximity-hide (stays visible)")
			setFar(true)
			return
		end
		-- Plate is axis-aligned (built with an unrotated CFrame): Size.X = plate
		-- depth (world X), Size.Z = plate width (world Z).
		local delta = root.Position - plate.Position
		local near = math.abs(delta.X) <= plate.Size.X / 2 + margin
			and math.abs(delta.Z) <= plate.Size.Z / 2 + margin
		setFar(not near)
	end

	RunService.RenderStepped:Connect(function(dt)
		BallRollController.Step(dt) -- full-belly -> tumble roll (every character)
		checkAccum += dt
		if checkAccum >= 0.2 then -- ~5 Hz poll (checkpoint button + gym prompt show/hide)
			checkAccum = 0
			updateCheckpointProximity()
			updateGymPrompt()
		end
	end)
end

return BodySubsClient
