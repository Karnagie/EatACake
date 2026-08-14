--[[ HudMenuButton
	Bare HUD menu button: a standalone icon with a label sitting just BELOW it
	and NO background/frame behind either (the "icon column" archetype used by
	simulator HUDs). The whole icon+label rectangle is the tap target (a
	transparent TextButton) so it stays comfortable on phones.

	Props: name, icon (image asset id), label (text), badge (bool), pulse (bool),
	selectable (bool, default true), onActivated, size, position, anchorPoint,
	layoutOrder, zIndex, style.

	Geometry/colors from Theme.HudMenuButton (nominal 100x118: icon zone on top,
	label zone below — as fractions of the button, so they hold at any cell
	shape). The button FILLS its layout cell (biggest tap area); the icon stays
	square via ScaleType.Fit and the label auto-scales, so no aspect constraint
	is needed on the button itself.

	⚠ `selectable = false` takes the button out of GAMEPAD selection while leaving
	it visible and pointer-live. Every other pressable in the kit ties `Selectable`
	to `enabled`; this one had no `Selectable` at all, so its TextButton defaulted
	to true and a D-pad could reach a HUD button sitting UNDER a modal scrim (the
	scrim is deliberately `Selectable = false` so focus does not land on it). Pass
	`selectable = <no panel is open>` from any HUD that can be covered.

	`pulse = true` runs the kit's looping ATTENTION breathe (Theme.Feel.Pulse) —
	"there is something to collect behind this icon". Same recipe as
	Components/Button and HexNode: a ref-owned repeating tween is the ONLY writer
	of that UIScale's Scale (ADR-0006), and `pulse = false` cancels it back to 1
	rather than freezing mid-breath.
	⚠ It rides an INNER centre-anchored frame, not the root TextButton the way
	Components/Button does. This button is laid out by a UIGridLayout, which owns
	the cell's Position — a UIScale on the root grows from its (0,0) anchor, so
	the icon would swell down-and-right into its neighbours instead of breathing
	in place. The frame nests INSIDE `pressLayer`'s Content (which carries the
	press UIScale), so the two scales compose: press pop × attention breathe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

	local pulse = props.pulse == true
	local pulseRef = React.useRef(nil)
	React.useEffect(function()
		local scale = pulseRef.current
		if scale == nil then
			return
		end
		local feel = Theme.Feel.Pulse
		if not pulse then
			TweenService:Create(scale, feel.StopTween, { Scale = 1 }):Play()
			return
		end
		local tween = TweenService:Create(scale, feel.Tween, { Scale = feel.Scale })
		tween:Play()
		return function()
			-- Cancel, then land on 1: an interrupted infinite tween otherwise
			-- leaves the icon frozen at whatever size the breath was mid-way.
			tween:Cancel()
			local instance = pulseRef.current
			if instance then
				instance.Scale = 1
			end
		end
	end, { pulse })

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
		-- Pointer input is contained by whatever covers this button; CONTROLLER
		-- selection is not, so it has to be switched off explicitly (see header).
		Selectable = props.selectable ~= false,
		ZIndex = zIndex,
	}, handlers), {
		-- Icon + label + badge pop together from the cell centre on tap/hover, and
		-- breathe together when `pulse` is on (the Pulse frame below is full-size
		-- and centre-anchored, so every zone fraction inside it is unchanged).
		Content = Interaction.pressLayer(scaleRef, zIndex, {
			Pulse = React.createElement("Frame", {
				Name = "Pulse",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, {
				-- Mounted unconditionally: the effect above needs the instance in
				-- order to ease back to 1 when `pulse` turns off, and a Scale-1
				-- UIScale on a still button costs nothing.
				PulseScale = React.createElement("UIScale", { ref = pulseRef }),
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
		}),
	})
end

return HudMenuButton
