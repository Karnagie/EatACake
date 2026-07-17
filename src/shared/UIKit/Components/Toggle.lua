local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local STYLE = Theme.Toggle

local function rounded(name, position, size, corner, zIndex, gradient, color, anchorPoint, backgroundTransparency)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
	}
	if gradient then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		})
	end

	return React.createElement("Frame", {
		Name = name,
		AnchorPoint = anchorPoint or Vector2.new(0, 0),
		Position = position,
		Size = size,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BackgroundTransparency = backgroundTransparency or 0,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function Toggle(props)
	local enabled = props.enabled ~= false
	local value = props.value == true
	local zIndex = props.zIndex or 5
	local trackGradient = value and STYLE.TrackOnGradient or STYLE.TrackOffGradient
	local knobGradient = nil
	local knobColor = nil
	if value then
		knobGradient = STYLE.KnobOnGradient
	else
		knobColor = STYLE.KnobOffColor
	end
	local knobOutlineColor = value and STYLE.KnobOnOutlineColor or STYLE.KnobOffOutlineColor
	local knobCenter = value and STYLE.KnobOnCenter or STYLE.KnobOffCenter

	return React.createElement("TextButton", {
		Name = props.name or "Toggle",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position or UDim2.fromScale(Theme.Layout.TogglePosition.X, Theme.Layout.TogglePosition.Y),
		Size = props.size or UDim2.fromScale(Theme.Layout.ToggleSize.X, Theme.Layout.ToggleSize.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		ZIndex = zIndex,
		[React.Event.MouseButton1Click] = function()
			if enabled and props.onChanged then
				props.onChanged(not value)
			end
		end,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = STYLE.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Outer = rounded(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			STYLE.OuterCorner,
			zIndex,
			STYLE.OuterGradient
		),
		Track = rounded(
			"Track",
			UDim2.fromScale(STYLE.TrackPosition.X, STYLE.TrackPosition.Y),
			UDim2.fromScale(STYLE.TrackSize.X, STYLE.TrackSize.Y),
			STYLE.TrackCorner,
			zIndex + 1,
			trackGradient
		),
		Knob = rounded(
			"Knob",
			UDim2.fromScale(knobCenter.X, knobCenter.Y),
			UDim2.fromScale(STYLE.KnobSize.X, STYLE.KnobSize.Y),
			1,
			zIndex + 2,
			nil,
			knobOutlineColor,
			Vector2.new(0.5, 0.5)
		),
		KnobFill = rounded(
			"KnobFill",
			UDim2.fromScale(
				knobCenter.X - STYLE.KnobSize.X * 0.5 + STYLE.KnobSize.X * STYLE.KnobFillPosition.X,
				knobCenter.Y - STYLE.KnobSize.Y * 0.5 + STYLE.KnobSize.Y * STYLE.KnobFillPosition.Y
			),
			UDim2.fromScale(
				STYLE.KnobSize.X * STYLE.KnobFillSize.X,
				STYLE.KnobSize.Y * STYLE.KnobFillSize.Y
			),
			1,
			zIndex + 3,
			knobGradient,
			knobColor
		),
	})
end

return Toggle
