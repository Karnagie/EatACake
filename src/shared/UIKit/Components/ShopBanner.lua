--[[
	ShopBanner — the full-width hero cell (Featured offer, Free reward).

	Every shop in this genre opens with one. It exists so the highest-value item
	does not render identically to "+100 Gems": big art plate, name, a real
	description line, a ribbon, and an oversized price button.

	Two accents, both from the rarity ladder so the palette stays closed:
	  gold (Legendary)  = the paid hero
	  green (Rare)      = the FREE / group reward — a give must not read as a sell

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
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local enabled = state == "buy"

	-- Accent swap: gradients + outline + name gradient only. Geometry identical.
	local accent = if props.accent == "free" then Theme.ShopBannerFree else nil
	local outerGradient = accent and accent.OuterGradient or base.OuterGradient
	local rimGradient = accent and accent.RimGradient or base.RimGradient
	local faceGradient = accent and accent.FaceGradient or base.FaceGradient
	local outlineColor = accent and accent.OutlineColor or base.OutlineColor
	local nameGradient = accent and accent.NameGradient or base.NameGradient

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
		-- deps must never contain nil: onActivated is optional by this
		-- component's own contract, and a nil in a positional deps array
		-- makes the comparison skip and freeze the callback.
	end, { props.onActivated or false, props.id or false })

	local scaleRef, handlers, squashRef = Interaction.usePressable({
		enabled = enabled,
		onActivated = activate,
		squash = {
			press = Theme.Feel.Squish.CardPressPose,
			hover = Theme.Feel.Squish.CardHoverPose,
		},
	})

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			base.OuterCorner,
			zIndex,
			outerGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(base.RimPosition.X, base.RimPosition.Y),
			UDim2.fromScale(base.RimSize.X, base.RimSize.Y),
			base.RimCorner,
			zIndex + 1,
			rimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(base.FacePosition.X, base.FacePosition.Y),
			UDim2.fromScale(base.FaceSize.X, base.FaceSize.Y),
			base.FaceCorner,
			zIndex + 2,
			faceGradient
		),
		Plate = React.createElement("Frame", {
			Name = "Plate",
			Position = UDim2.fromScale(base.PlatePosition.X, base.PlatePosition.Y),
			Size = UDim2.fromScale(base.PlateSize.X, base.PlateSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = base.PlateTransparency,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = base.PlateGradient,
				Rotation = 90,
			}),
			Icon = React.createElement("ImageLabel", {
				Name = "Icon",
				Position = UDim2.fromScale(base.IconInset, base.IconInset),
				Size = UDim2.fromScale(1 - base.IconInset * 2, 1 - base.IconInset * 2),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = Theme.Icon(props.iconName),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = zIndex + 4,
			}),
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
			style = Theme.ShopPriceWide,
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
			textGradient = base.DescGradient,
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
