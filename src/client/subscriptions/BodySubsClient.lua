--[[
	BodySubsClient — stomach/gym/body domain on the client (R4, GDD §8):
	  * StomachUpdate -> HUD state + floating calorie numbers (§7.3)
	  * GymUpdate -> gym minigame state + deflate celebration (coins, whoosh)
	  * drives BallRollController (full-belly tumble) + PetFollowers per frame
	  * gym taps: AppRoot's onGymTap callback -> GymTap remote
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local BodySubsClient = {}

function BodySubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local FloatingNumbers = modules.FloatingNumbers
	local ComboMeter = modules.ComboMeter
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local BallRollController = modules.BallRollController
	local PetFollowers = modules.PetFollowers

	local player = Players.LocalPlayer
	local rGymTap = Net.Remote("GymTap")

	local function headPosition(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root and root.Position + Vector3.new(0, 3.5, 0) or nil
	end

	Net.Update("StomachUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		AppRoot.Set({ stomach = payload })
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

	Net.Update("GymUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.event == "started" then
			AppRoot.Set({ gym = { active = true, duration = payload.duration, startedAt = os.clock() } })
			SoundPool.Play("uiClick")
		elseif payload.event == "result" or payload.event == "auto" or payload.event == "instant" then
			AppRoot.Set({ gym = { active = false, banked = payload.banked, bonus = payload.bonus } })
			if (tonumber(payload.banked) or 0) > 0 then
				SoundPool.Play("gymWhoosh")
				SoundPool.Play("coinBurst")
				local pos = headPosition()
				if pos then
					ParticlePool.Burst(pos, Color3.fromRGB(255, 220, 90), JuiceConfig.particles.coinsPerGymBurn)
					FloatingNumbers.Show(pos, `+{payload.banked} cal`, 1, Color3.fromRGB(150, 255, 150))
				end
			end
		end
	end)

	-- Gym mash taps flow from the kit UI through AppRoot's callback.
	AppRoot.SetCallbacks({
		onGymTap = function()
			rGymTap:FireServer()
		end,
	})

	RunService.RenderStepped:Connect(function(dt)
		BallRollController.Step(dt) -- full-belly -> tumble roll (every character)
		PetFollowers.Step(dt)
	end)
end

return BodySubsClient
