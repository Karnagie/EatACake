--[[
	StatRow — label-left / value-right stat pill (Theme.StatRow recipe,
	extracted from PetsInspectPanel's inline helper so other windows
	(inspectors, stat cards) can place it freely via position/size).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function roundedFrame(name, position, size, corner, zIndex, gradient)
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(corner, 0) }),
		Gradient = React.createElement("UIGradient", { Color = gradient, Rotation = 90 }),
	})
end

local function StatRow(props)
	local style = props.style or Theme.StatRow
	local zIndex = props.zIndex or 1
	return React.createElement("Frame", {
		Name = props.name or "StatRow",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 1,
			style.FaceGradient
		),
		Label = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			zIndex = zIndex + 2,
		}),
		Value = React.createElement(OutlinedText, {
			text = props.value or "",
			position = UDim2.fromScale(style.ValuePosition.X, style.ValuePosition.Y),
			size = UDim2.fromScale(style.ValueSize.X, style.ValueSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Right,
			zIndex = zIndex + 2,
		}),
	})
end

return StatRow
