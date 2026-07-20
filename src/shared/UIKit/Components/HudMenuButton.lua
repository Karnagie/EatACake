--[[ HudMenuButton
	Bare HUD menu button: a standalone icon with a label sitting just BELOW it
	and NO background/frame behind either (the "icon column" archetype used by
	simulator HUDs). The whole icon+label rectangle is the tap target (a
	transparent TextButton) so it stays comfortable on phones.

	Props: name, icon (image asset id), label (text), badge (bool),
	onActivated, size, position, anchorPoint, layoutOrder, zIndex, style.
	Geometry/colors from Theme.HudMenuButton (nominal 100x118: icon zone on top,
	label zone below — as fractions of the button, so they hold at any cell
	shape). The button FILLS its layout cell (biggest tap area); the icon stays
	square via ScaleType.Fit and the label auto-scales, so no aspect constraint
	is needed on the button itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local Badge = require(script.Parent.Badge)

local function HudMenuButton(props)
	local style = props.style or Theme.HudMenuButton
	local zIndex = props.zIndex or 1

	local scaleRef, handlers = Interaction.usePressable({
		onActivated = props.onActivated,
	})

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "MenuButton",
		AnchorPoint = props.anchorPoint,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = zIndex,
	}, handlers), {
		-- Icon + label + badge pop together from the cell centre on tap/hover.
		Content = Interaction.pressLayer(scaleRef, zIndex, {
			Icon = React.createElement("ImageLabel", {
				Name = "Icon",
				Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
				Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = props.icon or "",
				ImageColor3 = style.IconColor,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = zIndex + 1,
			}),
			Label = React.createElement(OutlinedText, {
				text = props.label or "",
				position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
				size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.LabelGradient,
				outlineColor = style.LabelOutlineColor,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 2,
			}),
			Badge = React.createElement(Badge, {
				visible = props.badge == true,
				anchorPoint = style.BadgeAnchor,
				position = UDim2.fromScale(style.BadgePosition.X, style.BadgePosition.Y),
				size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
				zIndex = zIndex + 3,
			}),
		}),
	})
end

return HudMenuButton
