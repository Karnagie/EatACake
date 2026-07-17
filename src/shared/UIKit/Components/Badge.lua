--[[ Badge — green notification dot (ring + gradient fill). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function Badge(props)
	local style = props.style or Theme.Badge
	local zIndex = props.zIndex or 60

	if props.visible == false then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "Badge",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Ring = React.createElement("Frame", {
			Name = "Ring",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = style.RingColor,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
		Fill = React.createElement("Frame", {
			Name = "Fill",
			Position = UDim2.fromScale(style.FillPosition.X, style.FillPosition.Y),
			Size = UDim2.fromScale(style.FillSize.X, style.FillSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.FillGradient,
				Rotation = 90,
			}),
		}),
	})
end

return Badge
