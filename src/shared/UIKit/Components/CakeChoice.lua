--[[
	CakeChoice — the picture-first cake control used by matchmaking
	(features/cake-select.md).

	MatchChoice's sibling, and deliberately built to the same BUTTON recipe. The
	standalone cut is nominal 442x60; matchmaking supplies a compact 294x58 style
	for its fixed-width setup rail. It carries a thumbnail because the cake is
	recognised by picture, not by name.

	Selection uses the kit's gold trim and, when the supplied style defines it, a
	filled gold face so the active state survives blur at compact sizes. Locked
	dims the strip and shows the lock badge.

	⚠ `analyticsId` is passed EXPLICITLY. The semantic name sits on the outer
	CanvasGroup while the actual pressable is a child named `HitTarget`; automatic
	derivation therefore sees the child, not the option. MatchChoice follows the
	same explicit-id contract.

	The caller hands in width/aspect; catalogue growth is handled by its scroll
	pane and never by shrinking this control.

	props:
		id, label, iconName
		selected, locked, comingSoon, enabled (false while the queue is busy)
		position, size, aspectRatio, layoutOrder, zIndex, style, name
		onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local Badge = require(script.Parent.Badge)

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

local function CakeChoice(props)
	local style = props.style or Theme.CakeChoice
	local zIndex = props.zIndex or 1
	local locked = props.locked == true
	local selected = props.selected == true
	-- Two independent reasons to be unpressable: the cake is not unlocked, or
	-- the queue is mid-launch. Both dim; only the first shows a lock.
	local enabled = props.enabled ~= false and not locked
	local outerGradient = if selected then style.SelectedOuterGradient else style.OuterGradient
	local rimGradient = if selected then style.SelectedRimGradient else style.RimGradient
	local faceGradient = if selected and style.SelectedFaceGradient
		then style.SelectedFaceGradient
		else style.FaceGradient

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
	end, { props.onActivated or false, props.id or false })

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		-- Rows sit flush inside a clipping scroll window. Do not grow beyond the
		-- exact-size dimming CanvasGroup; the inward press pose still animates.
		hoverScale = 1,
		analyticsId = `Cake_{tostring(props.id or "unknown")}`,
	})

	local children = {
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
			faceGradient
		),
		Thumb = React.createElement("ImageLabel", {
			Name = "Thumb",
			Position = UDim2.fromScale(style.ThumbPosition.X, style.ThumbPosition.Y),
			Size = UDim2.fromScale(style.ThumbSize.X, style.ThumbSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ImageTransparency = if locked then style.LockedArtTransparency else 0,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		}),
		Label = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
			size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
			textColor = style.LayerColor,
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			disabled = not enabled,
			zIndex = zIndex + 3,
		}),
	}

	if locked then
		-- Same split as CakeCard: padlock = "you can earn this", clock = "this
		-- does not exist yet". One dim, two glyphs.
		local comingSoon = props.comingSoon == true
		children.LockBadge = React.createElement(Badge, {
			name = if comingSoon then "SoonBadge" else "LockBadge",
			style = Theme.CakeLockBadge,
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			iconName = if comingSoon then "BadgeClock" else "UiLock",
			zIndex = zIndex + 4,
		})
	end

	return React.createElement("CanvasGroup", {
		Name = props.name or `CakeChoice_{tostring(props.id)}`,
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
			Content = Interaction.pressLayer(scaleRef, zIndex, children),
		}),
	})
end

return CakeChoice
