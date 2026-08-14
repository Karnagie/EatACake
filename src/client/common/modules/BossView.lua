--[[
	BossView — client-side visual of the CAKE MONSTER (GDD §6.2, called the
	boss everywhere in code and phase strings): a giant gummy bear built from
	primitives ONCE at Init (template, R5), cloned in when the cycle enters the
	boss phase. Purely cosmetic — hits are EatAt taps.

	⚠ It has NO health bar and NO nameplate (removed 2026-08-13, user request).
	The monster's HP is the HUD's top-centre CakeBar, which shows the same
	`payload.boss.hp` with a timer beside it (features/app-root.md) — a
	world-space bar over the model was the SAME number a second time, and it
	covered the thing the player is supposed to be looking at. Nothing here
	consumes HP any more, so there is no SetHp: `CakeCycleUpdate` feeds the bar
	directly through AppRoot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))

local BossView = {}

local template: Model?
local current: Model?
local clock = 0

function BossView.Init()
	local model = Instance.new("Model")
	model.Name = "CakeGuardian"

	local function ball(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Ball
		part.Size = size
		part.Position = offset
		part.Color = color
		part.Material = Enum.Material.Neon
		part.Transparency = 0.25
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		return part
	end

	local gummy = Color3.fromRGB(255, 90, 120)
	local body = ball("Body", Vector3.new(14, 16, 11), Vector3.new(0, 8, 0), gummy)
	ball("Head", Vector3.new(9, 9, 8), Vector3.new(0, 18, 0), gummy)
	ball("EarL", Vector3.new(3.5, 3.5, 3), Vector3.new(-3.6, 22.5, 0), gummy)
	ball("EarR", Vector3.new(3.5, 3.5, 3), Vector3.new(3.6, 22.5, 0), gummy)
	ball("PawL", Vector3.new(4, 4, 4), Vector3.new(-8, 8, 0), gummy)
	ball("PawR", Vector3.new(4, 4, 4), Vector3.new(8, 8, 0), gummy)
	model.PrimaryPart = body

	template = model
end

--API
function BossView.IsShown(): boolean
	return current ~= nil
end

--API
function BossView.Show()
	if current or not template then
		return
	end
	local origin = CakeConfig.grid.origin
	current = template:Clone()
	current:PivotTo(CFrame.new(origin.x, origin.y + 2, origin.z))
	current.Parent = workspace
end

--API
function BossView.Hide()
	if current then
		current:Destroy()
		current = nil
	end
end

--API
-- Idle wobble (a gummy bear must jiggle).
function BossView.Step(dt: number)
	clock += dt
	if current then
		local origin = CakeConfig.grid.origin
		local squish = 1 + math.sin(clock * 3) * 0.04
		current:PivotTo(
			CFrame.new(origin.x, origin.y + 2 + math.abs(math.sin(clock * 2)) * 1.2, origin.z)
				* CFrame.Angles(0, math.sin(clock * 0.7) * 0.3, 0)
				* CFrame.fromEulerAnglesXYZ(0, 0, (squish - 1) * 0.5)
		)
	end
end

return BossView
