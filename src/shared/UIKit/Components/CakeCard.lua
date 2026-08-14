--[[
	CakeCard — the showcase cell of the cake chooser (features/cake-select.md).

	A CARD IS NOT A BUTTON (style-rules §2b). It keeps an even outline and clear
	internal zones — the same discipline ShopCard was rebuilt around after its
	first cut shipped looking like a stretched button. The portrait chooser keeps
	an accent art window; the matchmaking-gallery style deliberately renders art
	directly on the card Face to avoid a nested-button look.
	Nominal 282x348, ratio-transferred from ShopCard (282x338) minus the shelf: a
	cake is chosen, not bought, so the shelf's row becomes a STATUS line.

	Composition, top to bottom:
	    ART          cake rendered big; portrait styles may add an accent window
	    TITLE        the cake's name
	    STATUS       compact block — the unlock requirement while locked

	FOUR STATES, and the difference between the middle two is the whole feature:
	    selected    gold Outer (the kit's existing selection accent, a gradient
	                swap only — never extra geometry, which clips)
	    unlocked    the normal navy body. Deliberately NOT quieted: grey is this
	                kit's LOCKED language and has misfired twice before, so
	                "not currently chosen" must not look like "you cannot have this"
	    locked      grey body + an optional grey art window + faded art (not tinted) +
	                a PADLOCK badge + the unlock requirement as the status line
	    comingSoon  the same grey language with a CLOCK badge — `locked` is still
	                true, because it is equally unpickable; only the glyph and the
	                copy separate "you can earn this" from "this does not exist
	                yet". One visual language, two messages.

	The locked card still shows its cake clearly, at 0.4 transparency. That is
	the point of rendering a locked card at all: the player has to be able to see
	what exists and read what earns it.

	⚠ Locked is a REAL disabled pressable, not an inert Frame. `usePressable`
	with `enabled = false` still reports the tap as a dead press, so "players keep
	tapping the locked cake" — the single most useful signal this feature can
	emit — arrives for free. A drag gallery may opt into controller focus for the
	locked card and route non-pointer activation to contextual feedback.

	props:
		id, label, iconName, accent, statusText
		selected, locked, comingSoon, enabled?, showSelectedBadge?, hoverScale?
		focusableWhenLocked?, onLockedActivated(id)?
		position, size, aspectRatio, layoutOrder, zIndex, style, name
		onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local Badge = require(script.Parent.Badge)

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

local function scaleRect(style, positionKey, sizeKey): (UDim2, UDim2)
	local position, size = style[positionKey], style[sizeKey]
	return UDim2.fromScale(position.X, position.Y), UDim2.fromScale(size.X, size.Y)
end

local function CakeCard(props)
	local style = props.style or Theme.CakeCard
	local zIndex = props.zIndex or 5
	local locked = props.locked == true
	local selected = props.selected == true
	local enabled = not locked and props.enabled ~= false
	-- A pointer-drag gallery may keep locked cards focusable for controller users
	-- so their contextual requirement is reachable. Pointer input is still owned
	-- by the gallery capture surface; this callback accepts only non-pointer
	-- activation and therefore cannot double-count a mouse/touch dead press.
	local lockedFocusable = locked and props.focusableWhenLocked == true and props.enabled ~= false
	local accent = Theme.ShopAccent(props.accent)
	-- The portrait chooser keeps the authored art window. Matchmaking can opt out
	-- because its landscape card Face already supplies enough structure; in that
	-- cut the cake renders directly on the card instead of inside a nested plate.
	local showArtPlate = style.ShowArtPlate ~= false

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
		-- Deps must never contain nil: a nil in a positional deps array makes
		-- jsdotlua's comparison skip and freezes the callback forever.
	end, { props.onActivated or false, props.id or false })

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		hoverScale = props.hoverScale,
		-- Named per CAKE. Without it every card on the panel reports as one
		-- bucket and "which cake do players tap" — including the locked one —
		-- is unanswerable.
		analyticsId = `Cake_{tostring(props.id or "unknown")}`,
	})

	-- State changes COLOUR, never geometry (the PetCard rule).
	local outerGradient = if locked
		then style.LockedOuterGradient
		elseif selected then style.SelectedOuterGradient
		else style.OuterGradient
	-- Matchmaking supplies a broad selected face value mass so the chosen cake
	-- survives heavy blur; styles without it keep the chooser's outer-only state.
	local faceGradient = if locked
		then style.LockedFaceGradient
		elseif selected and style.SelectedFaceGradient then style.SelectedFaceGradient
		else style.FaceGradient
	local artRingGradient = if locked
		then style.LockedOuterGradient
		elseif selected and style.SelectedArtRingGradient then style.SelectedArtRingGradient
		else accent.OuterGradient
	local artFaceGradient = if locked
		then style.LockedArtFaceGradient
		elseif selected and style.SelectedArtFaceGradient then style.SelectedArtFaceGradient
		else accent.FaceGradient
	local titleGradient = if locked then style.LockedTitleGradient else style.TitleGradient
	local statusGradient = if locked then style.LockedStatusGradient else style.StatusGradient

	local facePosition, faceSize = scaleRect(style, "FacePosition", "FaceSize")
	local artPosition, artSize = scaleRect(style, "ArtPosition", "ArtSize")
	local artFacePosition, artFaceSize = scaleRect(style, "ArtFacePosition", "ArtFaceSize")
	local iconPosition, iconSize = scaleRect(style, "IconPosition", "IconSize")
	local titlePosition, titleSize = scaleRect(style, "TitlePosition", "TitleSize")
	local statusPosition, statusSize = scaleRect(style, "StatusPosition", "StatusSize")

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			outerGradient
		),
		Face = roundedFrame("Face", facePosition, faceSize, style.FaceCorner, zIndex + 1, faceGradient),
		-- The portrait chooser keeps its accent art window. A style may remove both
		-- frames when the parent card Face is already the intended art stage.
		ArtRing = if showArtPlate
			then roundedFrame("ArtRing", artPosition, artSize, style.ArtCorner, zIndex + 2, artRingGradient)
			else nil,
		ArtFace = if showArtPlate
			then roundedFrame(
				"ArtFace",
				artFacePosition,
				artFaceSize,
				style.ArtFaceCorner,
				zIndex + 3,
				artFaceGradient
			)
			else nil,
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = iconPosition,
			Size = iconSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			-- FADED, never tinted: the cake has to stay recognisable while
			-- locked, because seeing it is what makes the unlock worth earning.
			ImageTransparency = if locked then style.LockedArtTransparency else 0,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 4,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.label or "",
			position = titlePosition,
			size = titleSize,
			textGradient = titleGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 4,
		}),
	}

	if props.statusText ~= nil and props.statusText ~= "" then
		layers.Status = React.createElement(OutlinedText, {
			text = props.statusText,
			position = statusPosition,
			size = statusSize,
			textWrapped = style.StatusTextWrapped == true,
			textGradient = statusGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 4,
		})
	end

	if locked then
		-- ONE unavailable visual language (grey body, grey window, faded art),
		-- and the GLYPH plus the status line say which kind: a padlock means "you
		-- can earn this", a clock means "this does not exist yet". Same geometry,
		-- same badge style — only the glyph differs, so the two never read as two
		-- unrelated card types.
		local comingSoon = props.comingSoon == true
		layers.LockBadge = React.createElement(Badge, {
			name = if comingSoon then "SoonBadge" else "LockBadge",
			style = Theme.CakeLockBadge,
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			iconName = if comingSoon then "BadgeClock" else "UiLock",
			zIndex = zIndex + 5,
		})
	elseif selected and props.showSelectedBadge == true then
		layers.SelectedBadge = React.createElement(Badge, {
			name = "SelectedBadge",
			style = Theme.Badge,
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			iconName = style.SelectedIconName or "UiCheck",
			zIndex = zIndex + 5,
		})
	end

	-- Matchmaking freezes every selector during launch. CakeCard cannot use an
	-- exact-size CanvasGroup for that state because CanvasGroup clips the card's
	-- normal press/hover motion, so styles that need an external disabled state
	-- provide a quiet overlay instead. Locked remains its own grey language.
	if props.enabled == false and style.DisabledOverlayColor then
		layers.DisabledOverlay = React.createElement("Frame", {
			Name = "DisabledOverlay",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = style.DisabledOverlayColor,
			BackgroundTransparency = style.DisabledOverlayTransparency or 0.4,
			BorderSizePixel = 0,
			ZIndex = zIndex + 6,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(style.OuterCorner, 0),
			}),
		})
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `CakeCard_{tostring(props.id)}`,
		AnchorPoint = props.anchorPoint,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled or lockedFocusable,
		Selectable = enabled or lockedFocusable,
		[React.Event.Activated] = if lockedFocusable
			then function(_, input)
				if
					input ~= nil
					and (
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					)
				then
					return
				end
				if props.onLockedActivated then
					props.onLockedActivated(props.id)
				end
			end
			else nil,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		ZIndex = zIndex,
	}, handlers), {
		-- The aspect constraint rides the HIT TARGET, not the press layer: the
		-- press pop must scale the visuals without resizing the layout cell.
		-- ⚠ WIDTH-dominant: this card lives in a grid cell whose width is the
		-- fixed quantity (the cell is shaved half a pixel to stop the last column
		-- wrapping), so binding to height would make the card a hair WIDER than
		-- its cell and clip it against the scroll window's right edge.
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = props.aspectRatio or style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, layers),
	})
end

return CakeCard
