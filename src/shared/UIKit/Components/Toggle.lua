local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)

local STYLE = Theme.Toggle
-- Stable initial knob Position (React sets it once; the ref-tween owns it after).
local KNOB_INITIAL = UDim2.fromScale(STYLE.KnobOffCenter.X, STYLE.KnobOffCenter.Y)

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

	-- Slide the knob across the track on change (snap on first mount). The ref
	-- owns Position; React only ever writes the stable KNOB_INITIAL, so the
	-- tween is never clobbered. KnobFill rides along as a child of the knob.
	local knobRef = React.useRef(nil)
	local firstRun = React.useRef(true)
	React.useLayoutEffect(function()
		local knob = knobRef.current
		if not knob then
			return
		end
		local goal = UDim2.fromScale(knobCenter.X, knobCenter.Y)
		if firstRun.current then
			firstRun.current = false
			knob.Position = goal
			return
		end
		TweenService:Create(knob, Theme.Feel.ToggleTween, { Position = goal }):Play()
	end, { value })

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
			Interaction.Cue("press") -- the knob slide is this component's own motion
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
		Knob = React.createElement("Frame", {
			Name = "Knob",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = KNOB_INITIAL, -- ref-tweened to knobCenter (see effect above)
			Size = UDim2.fromScale(STYLE.KnobSize.X, STYLE.KnobSize.Y),
			BackgroundColor3 = knobOutlineColor,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
			ref = knobRef,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			KnobFill = React.createElement("Frame", {
				Name = "KnobFill",
				Position = UDim2.fromScale(STYLE.KnobFillPosition.X, STYLE.KnobFillPosition.Y),
				Size = UDim2.fromScale(STYLE.KnobFillSize.X, STYLE.KnobFillSize.Y),
				BackgroundColor3 = knobGradient and Color3.new(1, 1, 1) or knobColor,
				BorderSizePixel = 0,
				ZIndex = zIndex + 3,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = knobGradient and React.createElement("UIGradient", {
					Color = knobGradient,
					Rotation = 90,
				}) or nil,
			}),
		}),
	})
end

return Toggle
