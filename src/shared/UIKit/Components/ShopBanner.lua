--[[
	ShopBanner — the full-width GIVE row (the group reward).

	A landscape card in the same language as the grid cells: neutral body, ART
	WINDOW left, info column, price shelf right. It used to be an 870-wide field
	of flat green with a white CIRCULAR plate — the widest possible button, with
	an icon container that wasted its own corners under `ScaleType.Fit`.

	Green (Rare) accent in the art window: a give must not read as a sell, and
	the paid hero next to it wears the gold frame.

	props:
		id, label, subText, iconName
		priceText, priceIcon, state ("buy"|"owned"|"unavailable")
		ribbonText, ribbonVariant, accent ("paid"|"free")
		size, layoutOrder, zIndex, onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local PriceButton = require(script.Parent.PriceButton)
local Ribbon = require(script.Parent.Ribbon)
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

local function ShopBanner(props)
	local base = props.style or Theme.ShopBanner
	local body = props.bodyStyle or Theme.ShopCardBody
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local enabled = state == "buy"

	-- Same rule as the grid cells: the body is the shared neutral, the accent
	-- lives in the art window. `accent = "free"` is the legacy spelling of the
	-- green give-row and still resolves to the same colour.
	local accentKey = base.Accent
	if props.accent and props.accent ~= "free" then
		accentKey = props.accent
	end
	local accent = Theme.ShopAccent(accentKey)
	local outlineColor = body.OutlineColor
	local nameGradient = body.TitleGradient

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
		-- deps must never contain nil: onActivated is optional by this
		-- component's own contract, and a nil in a positional deps array
		-- makes the comparison skip and freeze the callback.
	end, { props.onActivated or false, props.id or false })

	-- Grid-cell poses + the uniform UIScale pinned to 1: a ScrollingFrame clips,
	-- and these cells are packed to the canvas edges with zero horizontal slack,
	-- so any X growth shaves the outer columns' outline. See
	-- Theme.Feel.Squish.GridCellHoverPose.
	local scaleRef, handlers, squashRef = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		hoverScale = 1,
		pressScale = 1,
		squash = {
			press = Theme.Feel.Squish.GridCellPressPose,
			hover = Theme.Feel.Squish.GridCellHoverPose,
		},
	})

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			base.OuterCorner,
			zIndex,
			body.OuterGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(base.FacePosition.X, base.FacePosition.Y),
			UDim2.fromScale(base.FaceSize.X, base.FaceSize.Y),
			base.FaceCorner,
			zIndex + 1,
			body.FaceGradient
		),
		ArtRing = roundedFrame(
			"ArtRing",
			UDim2.fromScale(base.ArtPosition.X, base.ArtPosition.Y),
			UDim2.fromScale(base.ArtSize.X, base.ArtSize.Y),
			base.ArtCorner,
			zIndex + 2,
			accent.OuterGradient
		),
		ArtFace = roundedFrame(
			"ArtFace",
			UDim2.fromScale(base.ArtFacePosition.X, base.ArtFacePosition.Y),
			UDim2.fromScale(base.ArtFaceSize.X, base.ArtFaceSize.Y),
			base.ArtFaceCorner,
			zIndex + 3,
			accent.FaceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(base.IconPosition.X, base.IconPosition.Y),
			Size = UDim2.fromScale(base.IconSize.X, base.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 4,
		}),
		Name_ = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(base.NamePosition.X, base.NamePosition.Y),
			size = UDim2.fromScale(base.NameSize.X, base.NameSize.Y),
			textGradient = nameGradient,
			outlineColor = outlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		}),
		Price = React.createElement(PriceButton, {
			style = Theme.ShopPriceCard,
			position = UDim2.fromScale(base.PricePosition.X, base.PricePosition.Y),
			size = UDim2.fromScale(base.PriceSize.X, base.PriceSize.Y),
			text = props.priceText or "",
			iconName = props.priceIcon,
			state = state,
			zIndex = zIndex + 3,
			onActivated = activate,
		}),
	}

	if props.subText and props.subText ~= "" then
		layers.Desc = React.createElement(OutlinedText, {
			text = props.subText,
			position = UDim2.fromScale(base.DescPosition.X, base.DescPosition.Y),
			size = UDim2.fromScale(base.DescSize.X, base.DescSize.Y),
			textGradient = body.PerkGradient,
			outlineColor = outlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		})
	end

	if props.ribbonText and props.ribbonText ~= "" then
		layers.Ribbon = React.createElement(Ribbon, {
			text = props.ribbonText,
			variant = props.ribbonVariant,
			position = UDim2.fromScale(base.RibbonPosition.X, base.RibbonPosition.Y),
			size = UDim2.fromScale(base.RibbonSize.X, base.RibbonSize.Y),
			zIndex = zIndex + 4,
		})
	end

	if state == "owned" then
		layers.OwnedBadge = React.createElement(Badge, {
			name = "OwnedBadge",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(base.BadgeCenter.X, base.BadgeCenter.Y),
			size = UDim2.fromScale(base.BadgeSize.X, base.BadgeSize.Y),
			iconName = "UiCheck",
			zIndex = zIndex + 5,
		})
	end

	-- Sized and positioned by the caller (ShopPanel's deterministic canvas).
	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `ShopBanner_{tostring(props.id)}`,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		ZIndex = zIndex,
	}, handlers), {
		Content = Interaction.pressLayer(scaleRef, zIndex, layers, squashRef),
	})
end

return ShopBanner
