--[[
	PriceButton — the buy affordance on every shop cell: currency icon + amount.

	It is the largest coloured element on a cell on purpose; in this genre the
	price IS the call to action, and a player scans a shop by comparing prices.

	STATES (the previous shop had only two, and one of them was a lie):
		buy         green, icon + amount, enabled
		owned       blue, check icon + "OWNED", disabled — the cell stays fully
		            readable (the old ShopRow dimmed the WHOLE row including the
		            product name, so owned items became unreadable)
		unavailable grey, "SOON", disabled — for a product whose dev-product /
		            gamepass id is still 0. That used to render a live BUY button
		            whose purchase the server refused with no player-visible
		            result: a silent failure, which R8 says is a bug. Now the UI
		            states it.

	props:
		text            -- "149" (buy) or an override label
		state           -- "buy" | "owned" | "unavailable" (default "buy")
		iconName        -- Theme.Icons key, default UiRobux; nil in text-only states
		size, position, zIndex, style (Theme.ShopPrice | Theme.ShopPriceWide)
		onActivated()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

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

local function PriceButton(props)
	local style = props.style or Theme.ShopPrice
	local zIndex = props.zIndex or 1
	local state = props.state or "buy"
	local accent = Theme.ShopPriceStates[state] or Theme.ShopPriceStates.buy
	local enabled = state == "buy"

	-- Squash on press: the "squishy" signature. Opt-in per Interaction's
	-- contract; the pose rides Content.Size, never a React-computed prop.
	local scaleRef, handlers, squashRef = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
		squash = true,
	})

	local hasIcon = props.iconName ~= nil
	local textPosition = if hasIcon then style.TextPosition else style.WideTextPosition
	local textSize = if hasIcon then style.TextSize else style.WideTextSize

	local layers = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			accent.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			accent.RimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			accent.FaceGradient
		),
		Label = React.createElement(OutlinedText, {
			text = props.text or "",
			position = UDim2.fromScale(textPosition.X, textPosition.Y),
			size = UDim2.fromScale(textSize.X, textSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = accent.TextGradient,
			outlineColor = accent.OutlineColor,
			textXAlignment = if hasIcon then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	}

	if hasIcon then
		layers.Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		})
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "PriceButton",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
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

return PriceButton
