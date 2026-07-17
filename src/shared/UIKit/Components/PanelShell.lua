local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function roundedFrame(name, position, size, color, cornerRadius, zIndex, gradient)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(cornerRadius, 0),
		}),
	}
	if gradient then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		})
	end

	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function PanelShell(props)
	local style = props.style or Theme.Panel
	local children = {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		BodyShadow = roundedFrame(
			"BodyShadow",
			UDim2.fromScale(style.ShadowPosition.X, style.ShadowPosition.Y),
			UDim2.fromScale(style.ShadowSize.X, style.ShadowSize.Y),
			Color3.new(1, 1, 1),
			style.ShadowCorner,
			1,
			style.ShadowGradient
		),
		BodyBorder = roundedFrame(
			"BodyBorder",
			UDim2.fromScale(style.BorderPosition.X, style.BorderPosition.Y),
			UDim2.fromScale(style.BorderSize.X, style.BorderSize.Y),
			Color3.new(1, 1, 1),
			style.BorderCorner,
			2,
			style.BorderGradient
		),
		BodyFill = roundedFrame(
			"BodyFill",
			UDim2.fromScale(style.FillPosition.X, style.FillPosition.Y),
			UDim2.fromScale(style.FillSize.X, style.FillSize.Y),
			Color3.new(1, 1, 1),
			style.FillCorner,
			3,
			style.FillGradient
		),
	}

	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	return React.createElement("Frame", {
		Name = props.name or "PanelWithHeader",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = props.visible ~= false,
		ZIndex = props.zIndex or 1,
	}, children)
end

return PanelShell
