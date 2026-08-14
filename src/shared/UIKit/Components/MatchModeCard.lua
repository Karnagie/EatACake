--[[
	MatchModeCard -- the difficulty card used by the matchmaking configurator.

	Responsibility:
	- Render one neutral CARD-family surface with an accent art window, mode copy,
	  and a passive reward chip.
	- Present selection through the kit's gold Outer-gradient swap and UiCheck
	  badge without changing geometry.
	- Own press feedback and per-mode tap analytics while leaving selection state
	  and queue behavior to the caller.

	Props:
		id, name, label, description, rewardText, iconName, accent
		selected, enabled
		anchorPoint, position, size, aspectRatio, layoutOrder, visible, zIndex, style
		onActivated(id)

	Public behavior:
	- A live press invokes onActivated with this card's id and is tracked as
	  `Difficulty_<id>`.
	- Disabled cards remain visible and report dead presses through Interaction,
	  but never invoke onActivated.
	- The art window and reward chip are presentation zones, not nested buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local Badge = require(script.Parent.Badge)

local function roundedFrame(name, position, size, corner, zIndex, gradient, children)
	local frameChildren = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	}
	for key, child in pairs(children or {}) do
		frameChildren[key] = child
	end

	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, frameChildren)
end

local function scaleRect(style, positionKey, sizeKey): (UDim2, UDim2)
	local position, size = style[positionKey], style[sizeKey]
	return UDim2.fromScale(position.X, position.Y), UDim2.fromScale(size.X, size.Y)
end

local function MatchModeCard(props)
	local style = props.style or Theme.MatchModeCard
	local accent = Theme.MatchModeAccent(props.accent)
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false
	local selected = props.selected == true

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
	end, { props.onActivated or false, props.id or false })

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		-- The card sits flush against a clipping scroll window. Keep hover at its
		-- nominal footprint; the inward press pose still supplies tactile motion.
		hoverScale = 1,
		analyticsId = `Difficulty_{tostring(props.id or "unknown")}`,
	})

	local facePosition, faceSize = scaleRect(style, "FacePosition", "FaceSize")
	local artPosition, artSize = scaleRect(style, "ArtPosition", "ArtSize")
	local artFacePosition, artFaceSize = scaleRect(style, "ArtFacePosition", "ArtFaceSize")
	local iconPosition, iconSize = scaleRect(style, "IconPosition", "IconSize")
	local titlePosition, titleSize = scaleRect(style, "TitlePosition", "TitleSize")
	local descriptionPosition, descriptionSize = scaleRect(style, "DescriptionPosition", "DescriptionSize")
	local rewardPosition, rewardSize = scaleRect(style, "RewardPosition", "RewardSize")

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			if selected then style.SelectedOuterGradient else style.OuterGradient
		),
		Face = roundedFrame("Face", facePosition, faceSize, style.FaceCorner, zIndex + 1, style.FaceGradient),
		ArtOuter = roundedFrame("ArtOuter", artPosition, artSize, style.ArtCorner, zIndex + 2, accent.OuterGradient),
		ArtFace = roundedFrame(
			"ArtFace",
			artFacePosition,
			artFaceSize,
			style.ArtFaceCorner,
			zIndex + 3,
			accent.FaceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = iconPosition,
			Size = iconSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ImageColor3 = style.IconColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 4,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.label or "",
			position = titlePosition,
			size = titleSize,
			textGradient = style.TitleGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			disabled = not enabled,
			zIndex = zIndex + 4,
		}),
		Description = React.createElement(OutlinedText, {
			text = props.description or "",
			position = descriptionPosition,
			size = descriptionSize,
			textGradient = style.DescriptionGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			disabled = not enabled,
			zIndex = zIndex + 4,
		}),
		Reward = roundedFrame(
			"Reward",
			rewardPosition,
			rewardSize,
			style.RewardOuterCorner,
			zIndex + 2,
			style.RewardOuterGradient,
			{
				Face = roundedFrame(
					"Face",
					UDim2.fromScale(style.RewardFacePosition.X, style.RewardFacePosition.Y),
					UDim2.fromScale(style.RewardFaceSize.X, style.RewardFaceSize.Y),
					style.RewardFaceCorner,
					zIndex + 3,
					style.RewardFaceGradient
				),
				Icon = React.createElement("ImageLabel", {
					Name = "Icon",
					Position = UDim2.fromScale(style.RewardIconPosition.X, style.RewardIconPosition.Y),
					Size = UDim2.fromScale(style.RewardIconSize.X, style.RewardIconSize.Y),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = Theme.Icon(style.RewardIconName),
					ImageColor3 = style.RewardIconColor,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = zIndex + 4,
				}),
				Text = React.createElement(OutlinedText, {
					text = props.rewardText or "",
					position = UDim2.fromScale(style.RewardTextPosition.X, style.RewardTextPosition.Y),
					size = UDim2.fromScale(style.RewardTextSize.X, style.RewardTextSize.Y),
					textGradient = style.RewardTextGradient,
					outlineColor = style.OutlineColor,
					textXAlignment = Enum.TextXAlignment.Left,
					disabled = not enabled,
					zIndex = zIndex + 4,
				}),
			}
		),
	}

	if selected then
		layers.SelectedBadge = React.createElement(Badge, {
			name = "SelectedBadge",
			style = Theme.Badge,
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			iconName = style.SelectedIconName,
			zIndex = zIndex + 5,
		})
	end

	return React.createElement("CanvasGroup", {
		Name = props.name or `MatchModeCard_{tostring(props.id or "unknown")}`,
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

return MatchModeCard
