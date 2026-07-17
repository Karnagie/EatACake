--[[
	UpgradeRow — one upgrade line for the Upgrades window's vertical list
	(ShopRow family: label + sub text + right-side buy button; the buy
	button's style/enabled state is driven by props.state).

	props:
		id           -- passed to onBuy
		label        -- "Belly Size"
		subText      -- current -> next summary line ("" hides)
		buttonText   -- cost text ("250") or cap text ("MAX")
		state        -- "buy"  = green, clickable
		             -- "poor" = green, disabled fade (can't afford)
		             -- "max"  = neutral blue, disabled fade (cap reached)
		layoutOrder, zIndex, onBuy(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)

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

local function UpgradeRow(props)
	local style = props.style or Theme.UpgradeRow
	local zIndex = props.zIndex or 5
	local state = props.state or "buy"
	local canBuy = state ~= "poor" and state ~= "max"
	-- "max" = neutral blue; "buy"/"poor" = green cost button. Both use the
	-- 140x56-aspect variants so the button FILLS the buy zone (a 4.06-aspect
	-- style would self-constrain to ~60% height).
	local buttonStyle = if state == "max" then Theme.BuyButtonNeutral else Theme.BuyButton

	local buyButton = React.createElement(Button, {
		name = "BuyButton",
		style = buttonStyle,
		position = if canBuy
			then UDim2.fromScale(style.BuyPosition.X, style.BuyPosition.Y)
			else UDim2.fromScale(0, 0),
		size = if canBuy
			then UDim2.fromScale(style.BuySize.X, style.BuySize.Y)
			else UDim2.fromScale(1, 1),
		text = props.buttonText or "",
		textXAlignment = Enum.TextXAlignment.Center,
		enabled = canBuy,
		zIndex = zIndex + 3,
		onActivated = function()
			if canBuy and props.onBuy then
				props.onBuy(props.id)
			end
		end,
	})

	-- Kit disabled state: CanvasGroup fade over the buy zone only — the
	-- label/sub text stays fully readable (unlike ShopRow's whole-row dim).
	local buy = if canBuy
		then buyButton
		else React.createElement("CanvasGroup", {
			Name = "BuyDim",
			Position = UDim2.fromScale(style.BuyPosition.X, style.BuyPosition.Y),
			Size = UDim2.fromScale(style.BuySize.X, style.BuySize.Y),
			GroupTransparency = Theme.DayCard.DisabledTransparency,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, { Button = buyButton })

	local rowChildren = {
		Outer = roundedFrame("Outer", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), style.OuterCorner, zIndex, style.OuterGradient),
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
		Label = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textGradient = style.LabelGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		}),
		Sub = if props.subText ~= nil and props.subText ~= ""
			then React.createElement(OutlinedText, {
				text = props.subText,
				position = UDim2.fromScale(style.SubPosition.X, style.SubPosition.Y),
				size = UDim2.fromScale(style.SubSize.X, style.SubSize.Y),
				textGradient = style.SubGradient,
				textXAlignment = Enum.TextXAlignment.Left,
				zIndex = zIndex + 3,
			})
			else nil,
		Buy = buy,
	}

	-- List cell with the vertical gap baked into its aspect (see Theme note):
	-- the row content occupies the top ContentHeightInCell of the cell.
	-- In a PLAIN frame list the caller MUST pass an explicit scale height
	-- (props.size) — (1, 0) + FitWithinMaxSize collapses to zero outside an
	-- AutomaticCanvasSize ScrollPane (kit pitfall).
	return React.createElement("Frame", {
		Name = props.name or `UpgradeRow_{tostring(props.id)}`,
		Size = props.size or UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.CellAspectRatio,
		}),
		Cell = React.createElement("Frame", {
			Name = "Cell",
			Size = UDim2.fromScale(1, style.ContentHeightInCell),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Content = React.createElement("Frame", {
				Name = "Row",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, rowChildren),
		}),
	})
end

return UpgradeRow
