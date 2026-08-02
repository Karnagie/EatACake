--[[ InputGlyph
	The "press THIS" picture for a tutorial hint — vectored from kit primitives
	because the icon registry has no mouse/finger art and the kit's tradition is
	to draw small glyphs by hand (the HUD bolt, the badge check, the close X).

	Two modes, chosen by the CALLER from the device (never guessed here — a
	shared module must not read UserInputService):
	  "mouse" — rounded body, TOP-LEFT quadrant lit = the left mouse button.
	  "tap"   — a MINIATURE of the real EAT button (identical Epic-pink recipe)
	            inside a white ripple ring, so the hint points at the actual
	            on-screen control rather than at "a button" in the abstract.

	Purely decorative: no Active surface, no handlers. It must never eat the
	click it is teaching (see TutorialHint's header).

	Props: {
		mode: "mouse" | "tap",
		label: string?,   -- "tap" mode only: the word on the real button ("EAT")
		position: UDim2?, size: UDim2?, anchorPoint: Vector2?,
		zIndex: number?, style: table? (Theme.TutorialGlyph), name: string?
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

-- A rounded, gradient-filled, optionally outlined block on the glyph's own
-- 0..1 square grid. Everything in here is one of these.
local function shape(name, position, size, corner, gradient, zIndex, outlineColor, outlineThickness)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
	}
	if typeof(gradient) == "ColorSequence" then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		})
	end
	if outlineColor then
		children.Stroke = React.createElement("UIStroke", {
			Color = outlineColor,
			LineJoinMode = Enum.LineJoinMode.Round,
			StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
			Thickness = outlineThickness or 0.03,
		})
	end
	return React.createElement("Frame", {
		Name = name,
		Position = UDim2.fromScale(position.X, position.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		BackgroundColor3 = if typeof(gradient) == "Color3" then gradient else Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function mouseChildren(style, zIndex)
	return {
		Body = shape(
			"Body",
			style.MouseBodyPosition,
			style.MouseBodySize,
			style.MouseBodyCorner,
			style.MouseBodyGradient,
			zIndex,
			style.MouseOutline,
			0.045
		),
		-- The unlit sibling. Its only job is to make the LEFT one mean "left".
		RightButton = shape(
			"RightButton",
			style.MouseRightPosition,
			style.MouseRightSize,
			style.MouseButtonCorner,
			style.MouseRightGradient,
			zIndex + 1,
			style.MouseOutline,
			0.05
		),
		-- The action: the left button lit in the theme's candy magenta.
		LeftButton = shape(
			"LeftButton",
			style.MouseButtonPosition,
			style.MouseButtonSize,
			style.MouseButtonCorner,
			style.MouseButtonGradient,
			zIndex + 1,
			style.MouseOutline,
			0.05
		),
		Wheel = shape(
			"Wheel",
			style.MouseWheelPosition,
			style.MouseWheelSize,
			style.MouseWheelCorner,
			style.MouseWheelColor,
			zIndex + 2
		),
	}
end

local function tapChildren(style, zIndex, labelText)
	local face = {
		X = style.TapButtonPosition.X + style.TapButtonSize.X * style.TapFaceInset.X,
		Y = style.TapButtonPosition.Y + style.TapButtonSize.Y * style.TapFaceInset.Y,
	}
	local faceSize = {
		X = style.TapButtonSize.X * (1 - style.TapFaceInset.X * 2),
		Y = style.TapButtonSize.Y * (1 - style.TapFaceInset.Y * 2),
	}
	return {
		-- Ripple: a ring, i.e. a transparent circle wearing only a stroke.
		Ripple = React.createElement("Frame", {
			Name = "Ripple",
			Position = UDim2.fromScale(style.TapRingPosition.X, style.TapRingPosition.Y),
			Size = UDim2.fromScale(style.TapRingSize.X, style.TapRingSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = React.createElement("UIStroke", {
				Color = style.TapRingColor,
				StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
				Thickness = style.TapRingThickness,
				Transparency = 0.25,
			}),
		}),
		Outer = shape(
			"Outer",
			style.TapButtonPosition,
			style.TapButtonSize,
			1,
			style.TapOuterGradient,
			zIndex + 1,
			style.TapOutline,
			0.03
		),
		Face = shape(
			"Face",
			Vector2.new(face.X, face.Y),
			Vector2.new(faceSize.X, faceSize.Y),
			1,
			style.TapFaceGradient,
			zIndex + 2
		),
		Label = if labelText ~= nil and labelText ~= ""
			then React.createElement(OutlinedText, {
				text = labelText,
				position = UDim2.fromScale(style.TapLabelPosition.X, style.TapLabelPosition.Y),
				size = UDim2.fromScale(style.TapLabelSize.X, style.TapLabelSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.TapLabelGradient,
				outlineColor = style.TapLabelOutline,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 3,
			})
			else nil,
	}
end

local function InputGlyph(props)
	local style = props.style or Theme.TutorialGlyph
	local zIndex = props.zIndex or 1
	local children = if props.mode == "tap"
		then tapChildren(style, zIndex, props.label)
		else mouseChildren(style, zIndex)
	-- Square: both glyphs are drawn on a 0..1 SQUARE grid, so a non-square box
	-- would shear the mouse body and turn the ripple into an ellipse.
	children.Aspect = React.createElement("UIAspectRatioConstraint", {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
	})

	return React.createElement("Frame", {
		Name = props.name or "InputGlyph",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

return InputGlyph
