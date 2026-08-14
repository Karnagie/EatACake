--[[
	MatchDifficultyChoice -- the compact difficulty selector used by matchmaking.

	Responsibility:
	- Render one icon-first BUTTON-family difficulty choice with a localized label
	  and optional passive reward cue.
	- Present selection with a gold perimeter and blue face while keeping
	  the nominal 142x112 portrait geometry stable.
	- Own shared press feedback and per-difficulty tap analytics; selection and
	  queue behavior remain caller-owned.

	Props:
		id, label, iconName, rewardText, accent
		selected, enabled
		name, anchorPoint, position, size, aspectRatio, layoutOrder, visible, zIndex, style
		onActivated(id)

	Public behavior:
	- A live press invokes onActivated with this choice's id and is tracked as
	  `Difficulty_<id>`.
	- Disabled choices remain visible and report dead presses through Interaction,
	  but never invoke onActivated.
	- Matchmaking omits the reward multiplier to keep the setup scan quiet;
	  compatible style overrides may retain the legacy passive cue.
	- accent is accepted for difficulty view-model parity; the compact control's
	  visual cue is its icon and Theme.MatchDifficultyChoice surface.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

local function roundedFrame(name, position, size, corner, zIndex, color, gradient, children)
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
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, frameChildren)
end

local function MatchDifficultyChoice(props)
	local style = props.style or Theme.MatchDifficultyChoice
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
		-- The exact-size CanvasGroup owns disabled dimming and may be clipped by
		-- its setup strip, so hover keeps the nominal footprint.
		hoverScale = 1,
		analyticsId = `Difficulty_{tostring(props.id or "unknown")}`,
	})
	local showReward = style.ShowReward ~= false
	local showRewardPlate = showReward and style.ShowRewardPlate ~= false

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
			if selected then style.SelectedFaceGradient else style.FaceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ImageColor3 = style.LayerColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		}),
		Label = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textColor = style.LayerColor,
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = style.LabelTextXAlignment or Enum.TextXAlignment.Left,
			disabled = not enabled,
			zIndex = zIndex + 3,
		}),
		Reward = if showRewardPlate then roundedFrame(
			"Reward",
			UDim2.fromScale(style.RewardPosition.X, style.RewardPosition.Y),
			UDim2.fromScale(style.RewardSize.X, style.RewardSize.Y),
			style.RewardCorner,
			zIndex + 3,
			style.LayerColor,
			style.RewardOuterGradient,
			{
				Face = roundedFrame(
					"Face",
					UDim2.fromScale(style.RewardFacePosition.X, style.RewardFacePosition.Y),
					UDim2.fromScale(style.RewardFaceSize.X, style.RewardFaceSize.Y),
					style.RewardFaceCorner,
					zIndex + 4,
					style.LayerColor,
					style.RewardFaceGradient
				),
				Icon = React.createElement("ImageLabel", {
					Name = "Icon",
					Position = UDim2.fromScale(
						style.RewardIconPosition.X,
						style.RewardIconPosition.Y
					),
					Size = UDim2.fromScale(style.RewardIconSize.X, style.RewardIconSize.Y),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = Theme.Icon(style.RewardIconName),
					ImageColor3 = style.LayerColor,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = zIndex + 5,
				}),
				Text = React.createElement(OutlinedText, {
					text = props.rewardText or "",
					position = UDim2.fromScale(style.RewardTextPosition.X, style.RewardTextPosition.Y),
					size = UDim2.fromScale(style.RewardTextSize.X, style.RewardTextSize.Y),
					textColor = style.LayerColor,
					textGradient = style.RewardTextGradient,
					outlineColor = style.OutlineColor,
					textXAlignment = Enum.TextXAlignment.Center,
					disabled = not enabled,
					zIndex = zIndex + 5,
				}),
			}
		) else nil,
	}

	if showReward and not showRewardPlate then
		layers.RewardIcon = React.createElement("ImageLabel", {
			Name = "RewardIcon",
			Position = UDim2.fromScale(
				style.DirectRewardIconPosition.X,
				style.DirectRewardIconPosition.Y
			),
			Size = UDim2.fromScale(style.DirectRewardIconSize.X, style.DirectRewardIconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(style.RewardIconName),
			ImageColor3 = style.LayerColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		})
		layers.RewardText = React.createElement(OutlinedText, {
			text = props.rewardText or "",
			position = UDim2.fromScale(
				style.DirectRewardTextPosition.X,
				style.DirectRewardTextPosition.Y
			),
			size = UDim2.fromScale(style.DirectRewardTextSize.X, style.DirectRewardTextSize.Y),
			textColor = style.LayerColor,
			textGradient = style.RewardTextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			disabled = not enabled,
			zIndex = zIndex + 3,
		})
	end

	return React.createElement("CanvasGroup", {
		Name = props.name or `MatchDifficultyChoice_{tostring(props.id or "unknown")}`,
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

return MatchDifficultyChoice
