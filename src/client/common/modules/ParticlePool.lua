--[[
	ParticlePool — pooled burst emitters (GDD §7.3/§14): a fixed set of
	invisible anchored emitter-parts created ONCE at Init; bursts move a
	part to the position, tint it and :Emit(). Zero Instance.new at runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local ParticlePool = {}

local emitters: { { part: BasePart, emitter: ParticleEmitter } } = {}
local cursor = 1
local budget = 0 -- active-particle budget window

function ParticlePool.Init()
	local folder = Instance.new("Folder")
	folder.Name = "FxEmitters"

	for k = 1, JuiceConfig.particles.emitterPoolSize do
		local part = Instance.new("Part")
		part.Name = `Fx_{k}`
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false

		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Lifetime = NumberRange.new(0.35, 0.7)
		emitter.Speed = NumberRange.new(6, 14)
		emitter.SpreadAngle = Vector2.new(60, 60)
		emitter.Acceleration = Vector3.new(0, -40, 0)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = part

		part.Parent = folder
		table.insert(emitters, { part = part, emitter = emitter })
	end
	folder.Parent = workspace
end

--API
-- Burst `count` particles of `color` at `position`. Respects the global
-- active-particle budget (GDD §14: ≤ 200) via a decaying window.
function ParticlePool.Burst(position: Vector3, color: Color3, count: number)
	if budget + count > JuiceConfig.particles.maxActive then
		count = math.max(0, JuiceConfig.particles.maxActive - budget)
		if count == 0 then
			return
		end
	end
	budget += count
	local entry = emitters[cursor]
	cursor = cursor % #emitters + 1
	entry.part.Position = position
	entry.emitter.Color = ColorSequence.new(color)
	entry.emitter:Emit(count)
end

--API
-- Decays the budget window (called per frame).
function ParticlePool.Step(dt: number)
	budget = math.max(0, budget - dt * 200) -- particles live well under 1 s
end

return ParticlePool
