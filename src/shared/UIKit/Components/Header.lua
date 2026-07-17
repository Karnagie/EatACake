local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local CloseButton = require(script.Parent.CloseButton)

local function roundedFrame(name, position, size, corner, zIndex, gradient)
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

local function Header(props)
	local zIndex = props.zIndex or 1
	local style = props.style or Theme.Header

	return React.createElement("Frame", {
		Name = props.name or "Header",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, Theme.Layout.HeaderHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			style.RimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			style.FaceGradient
		),
		Title = props.showTitle ~= false and React.createElement(OutlinedText, {
			text = props.title or "Settings",
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TitleGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}) or nil,
		Close = props.showClose ~= false and React.createElement(CloseButton, {
			name = "Close",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.CloseCenter.X, style.CloseCenter.Y),
			size = UDim2.fromScale(style.CloseSize.X, style.CloseSize.Y),
			zIndex = zIndex + 10,
			enabled = props.closeEnabled ~= false,
			onActivated = props.onClose,
		}) or nil,
	})
end

return Header
