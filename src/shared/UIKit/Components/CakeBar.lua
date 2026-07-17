--[[ CakeBar
	Cake progress bar (HUD top-center). Dark outer pill (gold
	RareOuterGradient for rare cakes) > light groove > pink fill whose
	width = progress01 of the groove (red BossFillGradient in boss mode),
	centered OutlinedText on top. All geometry/gradients from Theme.CakeBar
	(nominal 560x56).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function CakeBar(props)
	local style = props.style or Theme.CakeBar
	local zIndex = props.zIndex or 1
	local progress01 = math.clamp(props.progress01 or 0, 0, 1)

	local outerGradient = props.rare and style.RareOuterGradient or style.OuterGradient
	local fillGradient = props.mode == "boss" and style.BossFillGradient or style.FillGradient

	return React.createElement("Frame", {
		Name = props.name or "CakeBar",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.OuterCorner, 0) }),
		Gradient = React.createElement("UIGradient", {
			Color = outerGradient,
			Rotation = 90,
		}),
		Groove = React.createElement("Frame", {
			Name = "Groove",
			Position = UDim2.fromScale(style.GroovePosition.X, style.GroovePosition.Y),
			Size = UDim2.fromScale(style.GrooveSize.X, style.GrooveSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.GrooveCorner, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.GrooveGradient,
				Rotation = 90,
			}),
			Fill = React.createElement("Frame", {
				Name = "Fill",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(progress01, 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 2,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.FillCorner, 0) }),
				Gradient = React.createElement("UIGradient", {
					Color = fillGradient,
					Rotation = 90,
				}),
			}),
		}),
		Label = React.createElement(OutlinedText, {
			text = props.text or "",
			position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
			size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	})
end

return CakeBar
