--[[ EatButton
	HUD hold-to-eat button (TOUCH only). A big round candy-pink button in the
	bottom-right thumb zone: press & HOLD to keep eating the cake IN FRONT of you,
	a quick TAP fires one bite. It replaces the old "touch anywhere = eat" input
	so the movement joystick / camera drag never trigger eating
	(features/cake-sim.md input).

	Round-button visual recipe (Outer/Rim/Face circle stack + OutlinedText label)
	— the same one the gym TAP button uses, on the Epic (candy-magenta) palette.
	Hold is wired through the shared Interaction press primitive's
	onPressStart/onPressEnd (also gives the squish/spring feedback for free).

	⚠ SAFE AREA. This button shares the bottom-right corner with Roblox's own
	touch JUMP button, which is drawn ABOVE every player GUI and sized off the
	SHORTER viewport axis — while `style.Position` is a viewport FRACTION tuned
	at one aspect. The two therefore only cleared on a wide window (measured
	2026-08-09: 22 px of daylight at 1375x1031, a corner overlap at phone
	aspects). So the button is BOTTOM-anchored and its bottom edge is held
	`bottomReservePx` off the bottom of its parent — which is AppRoot's `Hud`
	layer, whose bottom edge IS the viewport's, so the offset is exact.
	`style.Position.Y` is now only the fallback for a caller that passes no
	reserve (0 = PC, where this button never renders anyway).

	Props: {
		name?: string, visible: boolean, style?: table (Theme.EatButton),
		buttonText: string, zIndex?: number, bottomReservePx?: number,
		onPressStart: (input: InputObject?) -> (),  -- start eating (finger down)
		onPressEnd: (input: InputObject?) -> (),     -- stop eating (finger up)
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

-- One rounded, vertically-graded circle layer of the button stack.
local function roundedFrame(name, position, size, corner, zIndex, gradient)
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

local function EatButton(props)
	local style = props.style or Theme.EatButton
	local zIndex = props.zIndex or 3
	local visible = props.visible == true

	-- enabled tracks visible so a button hidden mid-hold releases its hold
	-- (Interaction's disabled-reset fires onPressEnd) — no stuck-on eating.
	local scaleRef, handlers = Interaction.usePressable({
		enabled = visible,
		onPressStart = props.onPressStart,
		onPressEnd = props.onPressEnd,
	})

	local reserve = tonumber(props.bottomReservePx) or 0
	local position = if reserve > 0
		then UDim2.new(style.Position.X, 0, 1, -reserve) -- bottom edge on the reserve line
		else UDim2.fromScale(style.Position.X, style.Position.Y)

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "EatButton",
		AnchorPoint = if reserve > 0 then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromScale(0.5, style.Height),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = visible,
		Active = visible,
		Selectable = visible,
		ZIndex = zIndex,
	}, handlers), {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.Aspect,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, {
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
				style.OuterCorner,
				zIndex + 1,
				style.RimGradient
			),
			Face = roundedFrame(
				"Face",
				UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
				UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
				style.OuterCorner,
				zIndex + 2,
				style.FaceGradient
			),
			Label = React.createElement(OutlinedText, {
				text = props.buttonText,
				position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
				size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.TextGradient,
				outlineColor = style.Outline,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 3,
			}),
		}),
	})
end

return EatButton
