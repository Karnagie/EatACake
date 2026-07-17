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
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

local function Button(props)
	local STYLE = props.style or Theme.Button
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false

	return React.createElement("TextButton", {
		Name = props.name or "Button",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		ZIndex = zIndex,
		[React.Event.MouseButton1Click] = function()
			if enabled and props.onActivated then
				props.onActivated()
			end
		end,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = STYLE.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			STYLE.OuterCorner,
			zIndex,
			STYLE.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(STYLE.RimPosition.X, STYLE.RimPosition.Y),
			UDim2.fromScale(STYLE.RimSize.X, STYLE.RimSize.Y),
			STYLE.RimCorner,
			zIndex + 1,
			STYLE.RimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(STYLE.FacePosition.X, STYLE.FacePosition.Y),
			UDim2.fromScale(STYLE.FaceSize.X, STYLE.FaceSize.Y),
			STYLE.FaceCorner,
			zIndex + 2,
			STYLE.FaceGradient
		),
		Label = React.createElement(OutlinedText, {
			text = props.text or "Button",
			position = UDim2.fromScale(STYLE.TextPosition.X, STYLE.TextPosition.Y),
			size = UDim2.fromScale(STYLE.TextSize.X, STYLE.TextSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = STYLE.TextGradient,
			outlineColor = STYLE.OutlineColor,
			textXAlignment = props.textXAlignment,
			zIndex = zIndex + 3,
		}),
	})
end

return Button
