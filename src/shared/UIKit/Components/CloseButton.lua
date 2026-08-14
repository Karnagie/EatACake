--[[
	CloseButton -- shared pressable X control for panel headers.

	Renders the standard layered Exit recipe and accepts an optional compatible
	`style`; interaction behavior and geometry stay shared across color variants.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)

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

local function arm(name, rotation, size, color, zIndex, gradient, gradientRotation, style)
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
		Position = UDim2.fromScale(style.XCenter.X, style.XCenter.Y),
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
	local style = props.style or Theme.Exit

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
		analyticsId = props.analyticsId or props.name,
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
			AspectRatio = style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, {
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
			InnerRim = roundedFrame(
				"InnerRim",
				UDim2.fromScale(style.InnerRimPosition.X, style.InnerRimPosition.Y),
				UDim2.fromScale(style.InnerRimSize.X, style.InnerRimSize.Y),
				style.InnerRimCorner,
				zIndex + 2,
				style.InnerRimGradient
			),
			Face = roundedFrame(
				"Face",
				UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
				UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
				style.FaceCorner,
				zIndex + 3,
				style.FaceGradient
			),
			XOutlineA = arm(
				"XOutlineA",
				45,
				UDim2.fromScale(style.XOutlineSize.X, style.XOutlineSize.Y),
				style.XOutline,
				zIndex + 4,
				nil,
				nil,
				style
			),
			XOutlineB = arm(
				"XOutlineB",
				-45,
				UDim2.fromScale(style.XOutlineSize.X, style.XOutlineSize.Y),
				style.XOutline,
				zIndex + 4,
				nil,
				nil,
				style
			),
			XFillA = arm(
				"XFillA",
				45,
				UDim2.fromScale(style.XFillSize.X, style.XFillSize.Y),
				Color3.new(1, 1, 1),
				zIndex + 5,
				style.XGradient,
				45,
				style
			),
			XFillB = arm(
				"XFillB",
				-45,
				UDim2.fromScale(style.XFillSize.X, style.XFillSize.Y),
				Color3.new(1, 1, 1),
				zIndex + 5,
				style.XGradient,
				135,
				style
			),
		}),
	})
end

return CloseButton
