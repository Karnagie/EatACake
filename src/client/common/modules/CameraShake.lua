--[[
	CameraShake — impulse-driven camera shake (GDD §7.3): bites push small
	impulses (scaled by bite size), the spring decays them. Applied as a
	rotation-free CFrame offset in the render step of CakeSubsClient.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JuiceConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("JuiceConfig")
)

local CameraShake = {}

local trauma = 0 -- 0..1, squared into amplitude

--API
function CameraShake.Impulse(strength: number)
	trauma = math.min(1, trauma + strength)
end

--API
-- Returns this frame's camera offset CFrame (identity when calm).
function CameraShake.Step(dt: number): CFrame
	if trauma <= 0.001 then
		trauma = 0
		return CFrame.identity
	end
	trauma = math.max(0, trauma - dt * JuiceConfig.camera.traumaDecayPerSecond)
	local amp = math.min(JuiceConfig.camera.maxAmp, trauma * trauma * JuiceConfig.camera.maxAmp)
	return CFrame.new(
		(math.random() * 2 - 1) * amp,
		(math.random() * 2 - 1) * amp,
		0
	)
end

return CameraShake
