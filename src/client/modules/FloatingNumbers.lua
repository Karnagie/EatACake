--[[
	FloatingNumbers — pooled world-space calorie popups (GDD §7.3): a fixed
	pool of BillboardGui+TextLabel built ONCE at Init; Show() recycles the
	oldest. Size scales with combo. Zero Instance.new at runtime.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local FloatingNumbers = {}

local pool: { { anchor: BasePart, gui: BillboardGui, label: TextLabel, rise: Tween, fade: Tween } } = {}
local cursor = 1

function FloatingNumbers.Init()
	local cfg = JuiceConfig.floatingNumbers
	local folder = Instance.new("Folder")
	folder.Name = "FloatingNumbers"

	for k = 1, cfg.poolSize do
		local anchor = Instance.new("Part")
		anchor.Name = `Num_{k}`
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(200, 60)
		gui.AlwaysOnTop = true
		gui.Enabled = false
		gui.MaxDistance = 220

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 235, 130)
		label.TextStrokeTransparency = 0.2
		label.TextStrokeColor3 = Color3.fromRGB(60, 30, 10)
		label.Parent = gui

		gui.Parent = anchor
		anchor.Parent = folder
		-- Tweens PRE-BUILT per entry (zero Instance.new in the Show path).
		local rise = TweenService:Create(
			gui,
			TweenInfo.new(cfg.lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ StudsOffsetWorldSpace = Vector3.new(0, cfg.riseStuds, 0) }
		)
		local fade = TweenService:Create(
			label,
			TweenInfo.new(cfg.lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		)
		fade.Completed:Connect(function()
			gui.Enabled = false
		end)
		table.insert(pool, { anchor = anchor, gui = gui, label = label, rise = rise, fade = fade })
	end
	folder.Parent = workspace
end

--API
-- Pops a number at a world position. scale01: 0..1 (combo intensity).
function FloatingNumbers.Show(position: Vector3, text: string, scale01: number, color: Color3?)
	local cfg = JuiceConfig.floatingNumbers
	local entry = pool[cursor]
	cursor = cursor % #pool + 1

	entry.rise:Cancel()
	entry.fade:Cancel()
	entry.anchor.Position = position
	entry.label.Text = text
	entry.label.TextSize = cfg.baseTextSize + (cfg.maxTextSize - cfg.baseTextSize) * math.clamp(scale01, 0, 1)
	entry.label.TextColor3 = color or Color3.fromRGB(255, 235, 130)
	entry.label.TextTransparency = 0
	entry.gui.StudsOffsetWorldSpace = Vector3.zero
	entry.gui.Enabled = true
	entry.rise:Play()
	entry.fade:Play()
end

return FloatingNumbers
