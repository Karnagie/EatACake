--[[ BellyBar
	Stomach meter (HUD bottom-center). Dark outer pill > light groove >
	warm fill whose width = fill01 of the groove, centered OutlinedText on
	top. When glutton (belly full) the fill and text heat up
	(FullFillGradient / GluttonTextGradient). All geometry/gradients from
	Theme.BellyBar (nominal 420x64).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

local function BellyBar(props)
	local style = props.style or Theme.BellyBar
	local zIndex = props.zIndex or 1
	local fill01 = math.clamp(props.fill01 or 0, 0, 1)
	local glutton = props.glutton == true
	-- Fill width glides to fill01 (see useFillGlide) so the belly meter fills
	-- smoothly as you eat instead of jumping each bite tick.
	local fillRef = Interaction.useFillGlide(fill01)

	local fillGradient = glutton and style.FullFillGradient or style.FillGradient
	local textGradient = glutton and style.GluttonTextGradient or style.TextGradient

	return React.createElement("Frame", {
		Name = props.name or "BellyBar",
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
			Color = style.OuterGradient,
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
				Size = Interaction.ZeroFill, -- glided to fill01 via fillRef
				ref = fillRef,
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
			textGradient = textGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	})
end

return BellyBar
