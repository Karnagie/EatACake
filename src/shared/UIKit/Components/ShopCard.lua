--[[
	ShopCard — the shop's product cell: game passes, eggs/boosts and gem packs.

	A CARD IS NOT A BUTTON. That distinction is the whole design, and the version
	this replaces lost it: it was drawn with the kit's BUTTON layer recipe
	(dark outline 8px at the top and 30px at the bottom — a 3.75x lip), on a
	single flat colour field, at a near-square 282x296. Bottom-weighted outline +
	one colour field + squat = the exact recipe for "a stretched button", which is
	what it looked like.

	The rule this component now follows:
	    BUTTON = a slab   -> one colour field, outline bottom-weighted 2x+
	    CARD   = a frame  -> EVEN outline, and internal ZONES

	Composition, top to bottom:
	    ART WINDOW   accent-coloured inset window, the icon centred in it
	    TITLE        the product
	    PERK LINE    one line, one value step down
	    PRICE SHELF  the only thing on the card that is a button, and the only
	                 thing still drawn with the button recipe

	COLOUR IS CONTAINED. The body is one neutral navy on every card
	(`Theme.ShopCardBody`) and the per-item accent lives in the art window only.
	Six passes in six saturated hues gave the grid no hierarchy — every cell
	shouted equally, which is what "cluttered" looks like. Now a row reads as one
	object with N coloured windows, and the strongest contrast on each cell is
	around the product art, which is where the eye should land.

	The art window is not the "plate behind the icon" that was rejected twice
	(a white circle; then a well + shelf + gloss + shadow + halo all at once). It
	is the card's top zone, full content width, and it does a job nothing else
	can: `ScaleType.Fit` draws an image at the SHORTER side of its box, so art of
	different aspect ratios (a tall flame, a wide egg cluster, a square pack) drew
	at wildly different visual sizes when placed straight on the face. One window
	normalises them all. Icon area went 13.5% -> 22% of the cell.

	Two geometries, one component (`style`): Theme.ShopCard (282x338, 3 across —
	passes) and Theme.ShopCardSmall (208x264, 4 across — eggs, gems).

	props:
		id, label, subText, iconName
		priceText, priceIcon,
		state ("buy"|"owned"|"unavailable"|"unaffordable") — ONLY "buy" is
			clickable; the other three colour the shelf and disable the cell.
			"unaffordable" is the gem row's: a grey shelf that still shows the
			gem glyph and the price, because the number is the information the
			player needs. A disabled kit button is correctly silent, so it gets
			no extra cue.
		accent, premium, ribbonText, ribbonVariant
		position, size, layoutOrder, zIndex, style, name, onActivated(id)
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

local function scaleRect(style, positionKey, sizeKey): (UDim2, UDim2)
	local position, size = style[positionKey], style[sizeKey]
	return UDim2.fromScale(position.X, position.Y), UDim2.fromScale(size.X, size.Y)
end

local function ShopCard(props)
	local style = props.style or Theme.ShopCard
	local body = props.bodyStyle or Theme.ShopCardBody
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local enabled = state == "buy"
	local accent = Theme.ShopAccent(props.accent)

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

	-- Premium swaps the card's dark outline to the kit's existing gold selection
	-- accent — a gradient swap, no extra geometry (the PetCard rule: state
	-- changes colour, never shape).
	-- Text outlines stay the dark navy in BOTH cases: white-on-navy is what the
	-- labels are tuned for, and the gold frame never touches the type.
	local premium = props.premium == true
	local outerGradient = if premium then body.PremiumOuterGradient else body.OuterGradient

	local facePosition, faceSize = scaleRect(style, "FacePosition", "FaceSize")
	local artPosition, artSize = scaleRect(style, "ArtPosition", "ArtSize")
	local artFacePosition, artFaceSize = scaleRect(style, "ArtFacePosition", "ArtFaceSize")
	local titlePosition, titleSize = scaleRect(style, "TitlePosition", "TitleSize")
	local iconPosition, iconSize = scaleRect(style, "IconPosition", "IconSize")
	local pricePosition, priceSize = scaleRect(style, "PricePosition", "PriceSize")

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			outerGradient
		),
		Face = roundedFrame("Face", facePosition, faceSize, style.FaceCorner, zIndex + 1, body.FaceGradient),
		-- The art window: the accent's own dark outline as an even ring, the
		-- accent face inside it. Two frames, both zones of the card.
		ArtRing = roundedFrame("ArtRing", artPosition, artSize, style.ArtCorner, zIndex + 2, accent.OuterGradient),
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
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 4,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.label or "",
			position = titlePosition,
			size = titleSize,
			textGradient = body.TitleGradient,
			outlineColor = body.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 4,
		}),
		Price = React.createElement(PriceButton, {
			-- The buy tap is counted per ITEM; without this every shelf in the
			-- shop reports as one bucket named "PriceButton".
			analyticsId = `Buy/{tostring(props.id or "unknown")}`,
			style = Theme.ShopPriceCard,
			position = pricePosition,
			size = priceSize,
			text = props.priceText or "",
			iconName = props.priceIcon,
			state = state,
			zIndex = zIndex + 4,
			onActivated = activate,
		}),
	}

	if props.subText and props.subText ~= "" then
		local perkPosition, perkSize = scaleRect(style, "PerkPosition", "PerkSize")
		layers.Perk = React.createElement(OutlinedText, {
			text = props.subText,
			position = perkPosition,
			size = perkSize,
			textGradient = body.PerkGradient,
			outlineColor = body.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 4,
		})
	end

	-- The tag overhangs the card's TOP edge into the row gap, so it competes with
	-- nothing. (It was tried over the art first and covered a quarter of it.)
	-- Top-only: the first and last grid columns sit flush against the canvas
	-- edges, so a horizontal overhang would be clipped by the scroll window.
	if props.ribbonText and props.ribbonText ~= "" then
		local ribbonPosition, ribbonSize = scaleRect(style, "RibbonPosition", "RibbonSize")
		layers.Ribbon = React.createElement(Ribbon, {
			text = props.ribbonText,
			variant = props.ribbonVariant,
			position = ribbonPosition,
			size = ribbonSize,
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
			zIndex = zIndex + 5,
		})
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `ShopCard_{tostring(props.id)}`,
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

return ShopCard
