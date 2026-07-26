--[[
	ShopRow — one purchasable row for the shop's vertical sectioned list
	(archetype: "Shop — portrait vertical sectioned list", NOT a grid).

	props:
		id           -- passed to onActivated
		label        -- "Starter Pack"
		subText      -- grant/benefit summary line ("" hides)
		buttonText   -- "R$ 149" / "FREE" / "Owned"
		owned        -- true = dim row, disable button
		buttonStyle  -- default Theme.EquipGreen
		size, layoutOrder, zIndex, onActivated(id)
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

local function ShopRow(props)
	local style = props.style or Theme.ShopRow
	local zIndex = props.zIndex or 5
	local enabled = props.owned ~= true

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
		Buy = React.createElement(Button, {
			name = "BuyButton",
			style = props.buttonStyle or Theme.EquipGreen,
			position = UDim2.fromScale(style.BuyPosition.X, style.BuyPosition.Y),
			size = UDim2.fromScale(style.BuySize.X, style.BuySize.Y),
			text = props.buttonText or "",
			enabled = enabled,
			zIndex = zIndex + 3,
			onActivated = function()
				if enabled and props.onActivated then
					props.onActivated(props.id)
				end
			end,
		}),
	}

	local content = React.createElement("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, rowChildren)

	if props.owned then
		content = React.createElement("CanvasGroup", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			GroupTransparency = Theme.DayCard.DisabledTransparency,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, { Row = content })
	end

	-- List cell with the vertical gap baked into its aspect (see Theme note):
	-- the row content occupies the top ContentHeightInCell of the cell.
	return React.createElement("Frame", {
		Name = props.name or `ShopRow_{tostring(props.id)}`,
		Size = props.size or UDim2.fromScale(1, Theme.ShopLayout.RowCellHeight),
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
		}, { Content = content }),
	})
end

return ShopRow
