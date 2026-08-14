--[[
	MatchPartyChoice -- the compact party-size selector used by matchmaking.

	Responsibility:
	- Render one BUTTON-family choice with a large numeric count on the left and
	  the configured group glyph on the right.
	- Present selection with the shared gold-perimeter compact-control state while
	  keeping all geometry stable.
	- Own shared press feedback and per-count tap analytics; party state and queue
	  behavior remain caller-owned.

	Props:
		count, name, selected, enabled
		anchorPoint, position, size, aspectRatio, layoutOrder, visible, zIndex, style
		onActivated(count)

	Public behavior:
	- A live press invokes onActivated with this choice's count and is tracked as
	  `Players_<count>`.
	- Disabled choices remain visible and report dead presses through Interaction,
	  but never invoke onActivated.
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

local function MatchPartyChoice(props)
	local style = props.style or Theme.MatchPartyChoice
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false
	local selected = props.selected == true
	local faceGradient = if selected and style.SelectedFaceGradient
		then style.SelectedFaceGradient
		else style.FaceGradient

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.count)
		end
	end, { props.onActivated or false, props.count or false })

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		-- This exact-size CanvasGroup provides disabled-state dimming, so an
		-- expanding hover would clip. The inward press pose remains animated.
		hoverScale = 1,
		analyticsId = `Players_{tostring(props.count or "unknown")}`,
	})

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.LayerColor,
			if selected then style.SelectedOuterGradient else style.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			style.LayerColor,
			if selected then style.SelectedRimGradient else style.RimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			style.LayerColor,
			faceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(style.IconName),
			ImageColor3 = style.LayerColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		}),
		Count = React.createElement(OutlinedText, {
			text = if props.count == nil then "" else tostring(props.count),
			position = UDim2.fromScale(style.CountPosition.X, style.CountPosition.Y),
			size = UDim2.fromScale(style.CountSize.X, style.CountSize.Y),
			textColor = style.LayerColor,
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			disabled = not enabled,
			zIndex = zIndex + 3,
		}),
	}

	return React.createElement("CanvasGroup", {
		Name = props.name or `MatchPartyChoice_{tostring(props.count or "unknown")}`,
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
			Content = Interaction.pressLayer(scaleRef, zIndex, layers),
		}),
	})
end

return MatchPartyChoice
