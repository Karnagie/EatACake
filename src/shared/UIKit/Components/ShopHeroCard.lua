--[[
	ShopHeroCard — the Starter Pack's own cell. Full width, one per shop.

	It is deliberately NOT a wide ShopCard. A starter pack sells a BUNDLE, and a
	bundle that renders as one icon and one line of text ("200 Gems + a x2 boost
	+ a Lucky Egg", squeezed into a 26-character zone) is indistinguishable from
	a single product at four times the price. So the contents get their own row:
	one chip per grant, art + amount, laid out beside an oversized art plate and
	an oversized price button. That row is the whole reason this component
	exists — it is what the genre's featured offer does (the reference banners
	spell out every item in the pack, with its value, above the buy buttons).

	Gold (Legendary) accent: the paid hero. The FREE / group-reward row keeps the
	green ShopBanner, so a give never renders like a sell.

	props:
		id, label, subText, iconName
		priceText, priceIcon, state ("buy"|"owned"|"unavailable"|"unaffordable")
		bundle -- ARRAY of { iconName, text } (the contents chips; the row fits
		       -- Theme.ShopHero.BundleColumns of them and the text zone caps at
		       -- ~8 characters — see Theme.ShopHeroItem)
		accent -- key into Theme.ShopCardAccents (default Theme.ShopHero.Accent)
		ribbonText, ribbonVariant
		position, size, zIndex, style, name, onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
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

-- One "what you get" chip. Small element (<50px nominal) so it drops the Rim
-- and is Outer + Face only, per the kit's thickness rule.
local function bundleChip(key: string, item, style, position, zIndex)
	local chip = Theme.ShopHeroItem
	return React.createElement("Frame", {
		Name = key,
		Position = position,
		Size = UDim2.fromScale(style.BundleSize.X, style.BundleSize.Y),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(chip.OuterCorner, 0) }),
		Gradient = React.createElement("UIGradient", { Color = chip.OuterGradient, Rotation = 90 }),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(chip.FacePosition.X, chip.FacePosition.Y),
			UDim2.fromScale(chip.FaceSize.X, chip.FaceSize.Y),
			chip.FaceCorner,
			zIndex + 1,
			chip.FaceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(chip.IconPosition.X, chip.IconPosition.Y),
			Size = UDim2.fromScale(chip.IconSize.X, chip.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(item.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 2,
		}),
		Label = React.createElement(OutlinedText, {
			text = item.text or "",
			position = UDim2.fromScale(chip.TextPosition.X, chip.TextPosition.Y),
			size = UDim2.fromScale(chip.TextSize.X, chip.TextSize.Y),
			textGradient = chip.TextGradient,
			outlineColor = chip.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 2,
		}),
	})
end

local function ShopHeroCard(props)
	local style = props.style or Theme.ShopHero
	local body = props.bodyStyle or Theme.ShopCardBody
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local enabled = state == "buy"
	local accent = Theme.ShopAccent(props.accent or style.Accent)
	-- The featured offer is the ONE cell allowed to wear the gold premium frame:
	-- if everything can be highlighted, nothing is.
	local outerGradient = if style.Premium then body.PremiumOuterGradient else body.OuterGradient

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
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
			style.OuterCorner,
			zIndex,
			outerGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 1,
			body.FaceGradient
		),
		ArtRing = roundedFrame(
			"ArtRing",
			UDim2.fromScale(style.ArtPosition.X, style.ArtPosition.Y),
			UDim2.fromScale(style.ArtSize.X, style.ArtSize.Y),
			style.ArtCorner,
			zIndex + 2,
			accent.OuterGradient
		),
		ArtFace = roundedFrame(
			"ArtFace",
			UDim2.fromScale(style.ArtFacePosition.X, style.ArtFacePosition.Y),
			UDim2.fromScale(style.ArtFaceSize.X, style.ArtFaceSize.Y),
			style.ArtFaceCorner,
			zIndex + 3,
			accent.FaceGradient
		),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 4,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textGradient = body.TitleGradient,
			outlineColor = body.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 4,
		}),
		Price = React.createElement(PriceButton, {
			style = Theme.ShopPriceCard,
			position = UDim2.fromScale(style.PricePosition.X, style.PricePosition.Y),
			size = UDim2.fromScale(style.PriceSize.X, style.PriceSize.Y),
			text = props.priceText or "",
			iconName = props.priceIcon,
			state = state,
			zIndex = zIndex + 4,
			onActivated = activate,
		}),
	}

	if props.subText and props.subText ~= "" then
		layers.Desc = React.createElement(OutlinedText, {
			text = props.subText,
			position = UDim2.fromScale(style.DescPosition.X, style.DescPosition.Y),
			size = UDim2.fromScale(style.DescSize.X, style.DescSize.Y),
			textGradient = body.PerkGradient,
			outlineColor = body.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 4,
		})
	end

	-- Contents row. Capped at the designed column count: the zone arithmetic
	-- closes at exactly BundleColumns chips, and drawing a fourth would run it
	-- off the card's right edge. Truncating is right; doing it QUIETLY is not —
	-- a bundle whose 4th item is advertised in ShopData and never rendered is a
	-- paid offer that under-sells itself with nothing in the console (R8).
	local bundle = props.bundle
	if type(bundle) == "table" then
		if #bundle > style.BundleColumns then
			Log.Once(
				"UIKit",
				`hero-bundle-overflow-{tostring(props.id)}`,
				`'{tostring(props.id)}' lists {#bundle} bundle items but the hero card fits {style.BundleColumns} — `
					.. `the rest are NOT shown. Trim the bundle in ShopData or widen Theme.ShopHero.`
			)
		end
		for index = 1, math.min(#bundle, style.BundleColumns) do
			local item = bundle[index]
			if type(item) == "table" then
				layers[`Bundle{index}`] = bundleChip(
					`Bundle{index}`,
					item,
					style,
					UDim2.fromScale(style.BundlePosition.X + (index - 1) * style.BundleStride, style.BundlePosition.Y),
					zIndex + 4
				)
			end
		end
	end

	if props.ribbonText and props.ribbonText ~= "" then
		layers.Ribbon = React.createElement(Ribbon, {
			text = props.ribbonText,
			variant = props.ribbonVariant,
			position = UDim2.fromScale(style.RibbonPosition.X, style.RibbonPosition.Y),
			size = UDim2.fromScale(style.RibbonSize.X, style.RibbonSize.Y),
			zIndex = zIndex + 5,
		})
	end

	if state == "owned" then
		layers.OwnedBadge = React.createElement(Badge, {
			name = "OwnedBadge",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			iconName = "UiCheck",
			zIndex = zIndex + 6,
		})
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `ShopHeroCard_{tostring(props.id)}`,
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

return ShopHeroCard
