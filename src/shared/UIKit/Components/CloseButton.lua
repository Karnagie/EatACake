local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local STYLE = Theme.Exit

local function roundedFrame(name, position, size, corner, zIndex, gradient, color)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
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

local function arm(name, rotation, size, color, zIndex, gradient, gradientRotation)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
	}
	if gradient then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = gradientRotation,
		})
	end

	return React.createElement("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(STYLE.XCenter.X, STYLE.XCenter.Y),
		Size = size,
		Rotation = rotation,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function CloseButton(props)
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
	})

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "CloseButton",
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
	}, handlers), {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = STYLE.AspectRatio,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, {
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
			InnerRim = roundedFrame(
				"InnerRim",
				UDim2.fromScale(STYLE.InnerRimPosition.X, STYLE.InnerRimPosition.Y),
				UDim2.fromScale(STYLE.InnerRimSize.X, STYLE.InnerRimSize.Y),
				STYLE.InnerRimCorner,
				zIndex + 2,
				STYLE.InnerRimGradient
			),
			Face = roundedFrame(
				"Face",
				UDim2.fromScale(STYLE.FacePosition.X, STYLE.FacePosition.Y),
				UDim2.fromScale(STYLE.FaceSize.X, STYLE.FaceSize.Y),
				STYLE.FaceCorner,
				zIndex + 3,
				STYLE.FaceGradient
			),
			XOutlineA = arm("XOutlineA", 45, UDim2.fromScale(STYLE.XOutlineSize.X, STYLE.XOutlineSize.Y), STYLE.XOutline, zIndex + 4),
			XOutlineB = arm("XOutlineB", -45, UDim2.fromScale(STYLE.XOutlineSize.X, STYLE.XOutlineSize.Y), STYLE.XOutline, zIndex + 4),
			XFillA = arm("XFillA", 45, UDim2.fromScale(STYLE.XFillSize.X, STYLE.XFillSize.Y), Color3.new(1, 1, 1), zIndex + 5, STYLE.XGradient, 45),
			XFillB = arm("XFillB", -45, UDim2.fromScale(STYLE.XFillSize.X, STYLE.XFillSize.Y), Color3.new(1, 1, 1), zIndex + 5, STYLE.XGradient, 135),
		}),
	})
end

return CloseButton
