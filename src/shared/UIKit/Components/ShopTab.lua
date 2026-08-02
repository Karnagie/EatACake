--[[
	ShopTab — one category button in the shop's tab row.

	Exists because the shop's single stacked scroll was 5.6 screens tall: the
	window opened on the balance chips, one section header and one banner, and
	every other category was below the fold. Tabs cut the worst case to 1.9
	screens and let two of the four categories render with no scroll at all.

	Selected/idle is a GRADIENT SWAP on the same geometry (the PetCard rule):
	selected wears a DEEPER gold than Rarity.Legendary (a VALUE anchor — the
	bright gold sat in the white panel's own L* band and vanished in
	grayscale) and idle is a light WASH of the panel surface. The first idle
	cut was a "muted" slate — desaturated but DARK, dL* −58 vs the panel, so
	the three idle tabs tonally out-shouted the selected one 3.6x (tonal
	audit 2026-08-01; quiet means close in VALUE, not just low chroma —
	style-rules §4).

	props: id, label, iconName?, selected, position, size, zIndex, name,
	onActivated(id) — iconName leads the label with the section's glyph
	(icon-first: squint-test skill)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Log = require(script.Parent.Parent.Parent.Log)
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

local function ShopTab(props)
	local style = props.style or Theme.ShopTab
	local zIndex = props.zIndex or 5
	local selected = props.selected == true
	local accent = if selected then Theme.ShopTabStates.selected else Theme.ShopTabStates.idle

	local activate = React.useCallback(function()
		if props.onActivated then
			props.onActivated(props.id)
		end
		-- Never put a nil in a positional deps array: the comparison skips and
		-- the callback freezes on its first closure (ShopCard's note).
	end, { props.onActivated or false, props.id or false })

	-- A selected tab is not pressable — pressing it again does nothing, and a
	-- squash on it would read as a failed action.
	local scaleRef, handlers, squashRef = Interaction.usePressable({
		enabled = not selected,
		onActivated = activate,
		squash = true,
	})

	-- Icon-first (squint-test skill): with an iconName the tab leads with its
	-- section's glyph and the label shifts right — a non-reader navigates the
	-- row by shapes. Without one, the label spans the face as before.
	-- The guard checks EVERY key the icon path reads, and a dropped icon is
	-- never silent (R8) — a custom style missing the keys must say so.
	local styleHasIconKeys = style.IconPosition ~= nil
		and style.IconSize ~= nil
		and style.LabelWithIconPosition ~= nil
		and style.LabelWithIconSize ~= nil
	if props.iconName ~= nil and not styleHasIconKeys then
		Log.Once(
			"UIKit",
			"shoptab-style-no-icon-keys",
			`ShopTab got iconName '{tostring(props.iconName)}' but the style lacks the Icon*/LabelWithIcon* `
				.. "keys — the icon is NOT rendered. Add the four keys to the custom style (see Theme.ShopTab)."
		)
	end
	local hasIcon = props.iconName ~= nil and styleHasIconKeys
	local labelPosition = if hasIcon then style.LabelWithIconPosition else style.LabelPosition
	local labelSize = if hasIcon then style.LabelWithIconSize else style.LabelSize

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
		Icon = hasIcon and React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(style.IconPosition.X, style.IconPosition.Y),
			Size = UDim2.fromScale(style.IconSize.X, style.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		}) or nil,
		Label = React.createElement(OutlinedText, {
			text = props.label or "",
			position = UDim2.fromScale(labelPosition.X, labelPosition.Y),
			size = UDim2.fromScale(labelSize.X, labelSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = accent.TextGradient,
			outlineColor = accent.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	}

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or `ShopTab_{tostring(props.id)}`,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = not selected,
		Selectable = not selected,
		ZIndex = zIndex,
	}, handlers), {
		Content = Interaction.pressLayer(scaleRef, zIndex, layers, squashRef),
	})
end

return ShopTab
