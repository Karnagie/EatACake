--[[
	ShopSectionHeader — the category divider in the shop's scroll canvas.

	Icon + label + right-aligned count over a full-width underline pill. The icon
	is what makes a category findable while scrolling: at a glance a player reads
	the shape (gift / gem / egg), not the word.

	props:
		title, iconName, count (string, optional), size, layoutOrder, zIndex
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function ShopSectionHeader(props)
	local style = props.style or Theme.ShopSectionHeader
	local zIndex = props.zIndex or 5

	local content = {
		Label = React.createElement(OutlinedText, {
			text = props.title or "",
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textGradient = style.LabelGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 1,
		}),
		Underline = React.createElement("Frame", {
			Name = "Underline",
			Position = UDim2.fromScale(style.UnderlinePosition.X, style.UnderlinePosition.Y),
			Size = UDim2.fromScale(style.UnderlineSize.X, style.UnderlineSize.Y),
			BackgroundColor3 = style.UnderlineColor,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(style.UnderlineCorner, 0),
			}),
		}),
	}

	if props.iconName then
		content.Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 1,
		})
	end

	if props.count then
		content.Count = React.createElement(OutlinedText, {
			text = props.count,
			position = UDim2.fromScale(style.CountPosition.X, style.CountPosition.Y),
			size = UDim2.fromScale(style.CountSize.X, style.CountSize.Y),
			textGradient = style.CountGradient,
			textXAlignment = Enum.TextXAlignment.Right,
			zIndex = zIndex + 1,
		})
	end

	-- Sized and positioned by the caller (ShopPanel's deterministic canvas). No
	-- aspect constraint: inside a scroll canvas that would fight the explicit
	-- height and render the header narrower than the window.
	return React.createElement("Frame", {
		Name = props.name or "SectionHeader",
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, content)
end

return ShopSectionHeader
