--[[
	BossView — client-side visual of the Cake Guardian (GDD §6.2): a giant
	gummy bear built from primitives ONCE at Init (template, R5), cloned in
	when the cycle enters the boss phase. Purely cosmetic — hits are EatAt
	taps, HP arrives via CakeCycleUpdate. World-space HP bar (non-kit UI is
	allowed for world-space visuals per the UI workflow).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))

local BossView = {}

local template: Model?
local current: Model?
local hpFill: Frame?
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

	local gui = Instance.new("BillboardGui")
	gui.Name = "HpBar"
	gui.Size = UDim2.fromOffset(260, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 16, 0)
	gui.AlwaysOnTop = true
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.5)
	back.Position = UDim2.fromScale(0, 0.5)
	back.BackgroundColor3 = Color3.fromRGB(40, 20, 30)
	back.BorderSizePixel = 0
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 255, 140)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Text = CakeConfig.cycle.bossName
	title.Parent = gui
	back.Parent = gui
	gui.Parent = body

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
	local body = current:FindFirstChild("Body")
	local gui = body and body:FindFirstChild("HpBar")
	local back = gui and (gui :: BillboardGui):FindFirstChildOfClass("Frame")
	hpFill = back and back:FindFirstChild("Fill") :: Frame?
end

--API
function BossView.SetHp(hp: number, maxHp: number)
	if hpFill then
		hpFill.Size = UDim2.fromScale(math.clamp(hp / math.max(1, maxHp), 0, 1), 1)
	end
end

--API
function BossView.Hide()
	if current then
		current:Destroy()
		current = nil
		hpFill = nil
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
