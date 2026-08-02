--[[
	ShopPackCard — a currency value pack (gems), portrait, four across.

	Packs are compare-at-a-glance content: the player is picking a TIER, so the
	four cards must sit side by side. Stacked vertically (the old shop) that
	comparison is impossible.

	The ribbon band at the top is RESERVED on every pack whether or not the pack
	wears a tag, so all four cards stay the same height and the BEST VALUE sash
	can never overlap the art or the price.

	props:
		id, amountText, iconName, priceText, priceIcon
		state ("buy"|"owned"|"unavailable"), ribbonText, ribbonVariant, best
		position, size, zIndex, onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local PriceButton = require(script.Parent.PriceButton)
local Ribbon = require(script.Parent.Ribbon)

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

local function ShopPackCard(props)
	local style = props.style or Theme.ShopPack
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local enabled = state == "buy"

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

	-- Best value swaps Outer/Rim to the gold selection accent. Geometry is
	-- unchanged (the kit's selection rule) — an external ring would clip at the
	-- scroll window edge.
	local outerGradient = if props.best then style.BestOuterGradient else style.OuterGradient
	local rimGradient = if props.best then style.BestRimGradient else style.RimGradient

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			outerGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			rimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			style.FaceGradient
		),
		Plate = React.createElement("Frame", {
			Name = "Plate",
			Position = UDim2.fromScale(style.PlatePosition.X, style.PlatePosition.Y),
			Size = UDim2.fromScale(style.PlateSize.X, style.PlateSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = style.PlateTransparency,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.PlateGradient,
				Rotation = 90,
			}),
			Icon = React.createElement("ImageLabel", {
				Name = "Icon",
				Position = UDim2.fromScale(style.IconInset, style.IconInset),
				Size = UDim2.fromScale(1 - style.IconInset * 2, 1 - style.IconInset * 2),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = Theme.Icon(props.iconName),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = zIndex + 4,
			}),
		}),
		Amount = React.createElement(OutlinedText, {
			text = props.amountText or "",
			position = UDim2.fromScale(style.AmountPosition.X, style.AmountPosition.Y),
			size = UDim2.fromScale(style.AmountSize.X, style.AmountSize.Y),
			textGradient = style.AmountGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
		Price = React.createElement(PriceButton, {
			-- The buy tap is counted per ITEM; without this every shelf in the
			-- shop reports as one bucket named "PriceButton".
			analyticsId = `Buy/{tostring(props.id or "unknown")}`,
			position = UDim2.fromScale(style.PricePosition.X, style.PricePosition.Y),
			size = UDim2.fromScale(style.PriceSize.X, style.PriceSize.Y),
			text = props.priceText or "",
			iconName = props.priceIcon,
			state = state,
			zIndex = zIndex + 3,
			onActivated = activate,
		}),
	}

	if props.ribbonText and props.ribbonText ~= "" then
		layers.Ribbon = React.createElement(Ribbon, {
			text = props.ribbonText,
			variant = props.ribbonVariant,
			position = UDim2.fromScale(style.RibbonPosition.X, style.RibbonPosition.Y),
			size = UDim2.fromScale(style.RibbonSize.X, style.RibbonSize.Y),
			zIndex = zIndex + 4,
		})
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `ShopPack_{tostring(props.id)}`,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
	}, handlers), {
		Content = Interaction.pressLayer(scaleRef, zIndex, layers, squashRef),
	})
end

return ShopPackCard
