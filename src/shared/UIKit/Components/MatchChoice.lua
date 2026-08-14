--[[
	MatchChoice -- selectable candy-style option used by MatchmakingPanel.

	The component keeps the Button family's Outer/Rim/Face construction and
	shared press feedback. A selected choice swaps its Outer/Rim gradients to
	the kit's existing gold selection accent; disabled choices remain visible
	but cannot activate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

local function roundedFrame(name, position, size, corner, zIndex, color, gradient)
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = color,
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

local function MatchChoice(props)
	local style = props.style or Theme.MatchChoice
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false
	local selected = props.selected == true
	local outerGradient = if selected then style.SelectedOuterGradient else style.OuterGradient
	local rimGradient = if selected then style.SelectedRimGradient else style.RimGradient

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
		-- The pressable is the child named HitTarget, not the outer
		-- Difficulty_*/Players_* CanvasGroup. Pass the semantic id explicitly or
		-- every option collapses into one analytics bucket called HitTarget.
		analyticsId = props.analyticsId or props.name,
	})

	return React.createElement("CanvasGroup", {
		Name = props.name or "MatchChoice",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = if enabled then 0 else style.DisabledTransparency,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = props.aspectRatio or style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		HitTarget = React.createElement("TextButton", Interaction.merge({
			Name = "HitTarget",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Active = enabled,
			Selectable = enabled,
			ZIndex = zIndex,
		}, handlers), {
			Content = Interaction.pressLayer(scaleRef, zIndex, {
				Outer = roundedFrame(
					"Outer",
					UDim2.fromScale(0, 0),
					UDim2.fromScale(1, 1),
					style.OuterCorner,
					zIndex,
					style.LayerColor,
					outerGradient
				),
				Rim = roundedFrame(
					"Rim",
					UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
					UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
					style.RimCorner,
					zIndex + 1,
					style.LayerColor,
					rimGradient
				),
				Face = roundedFrame(
					"Face",
					UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
					UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
					style.FaceCorner,
					zIndex + 2,
					style.LayerColor,
					style.FaceGradient
				),
				Label = React.createElement(OutlinedText, {
					text = props.text or "",
					position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
					size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
					textColor = style.LayerColor,
					textGradient = style.TextGradient,
					outlineColor = style.OutlineColor,
					textXAlignment = Enum.TextXAlignment.Center,
					disabled = not enabled,
					zIndex = zIndex + 3,
				}),
			}),
		}),
	})
end

return MatchChoice
