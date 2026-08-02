--[[
	ShopTile — the workhorse shop cell (game passes, eggs, boosts).

	Nominal 282x160, icon LEFT / name + perk + price RIGHT, three across the
	870-wide canvas. The perk line is the point: the old ShopRow hardcoded
	subText = "" everywhere, so every row read "Auto-Eat / R$ 399" and a player
	had no way to learn what the thing actually does.

	The WHOLE tile is the tap target, not just the price button (on a phone the
	other 250px of the cell used to be dead).

	Owned state does NOT dim the card — a green check lands on the plate and the
	price button turns blue "OWNED", so the name stays readable. (The old
	whole-row CanvasGroup dim faded the product name along with everything else;
	UpgradeRow already documents that as the wrong pattern.)

	props:
		id, label, subText, iconName
		priceText, priceIcon, state ("buy"|"owned"|"unavailable")
		size, layoutOrder, zIndex, onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local PriceButton = require(script.Parent.PriceButton)
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

local function ShopTile(props)
	local style = props.style or Theme.ShopTile
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

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			style.RimGradient
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
		Name_ = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.NamePosition.X, style.NamePosition.Y),
			size = UDim2.fromScale(style.NameSize.X, style.NameSize.Y),
			textGradient = style.NameGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Left,
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

	if props.subText and props.subText ~= "" then
		layers.Sub = React.createElement(OutlinedText, {
			text = props.subText,
			position = UDim2.fromScale(style.SubPosition.X, style.SubPosition.Y),
			size = UDim2.fromScale(style.SubSize.X, style.SubSize.Y),
			textGradient = style.SubGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
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
		Name = props.name or `ShopTile_{tostring(props.id)}`,
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

return ShopTile
