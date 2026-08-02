--[[ Button
	The kit's workhorse pressable: Outer / Rim / Face / Label on the style's
	nominal grid, with press + hover feedback from the shared `Interaction`
	primitive.

	Props: { style?, text?, textXAlignment?, enabled?, onActivated?,
	         name?, anchorPoint?, position?, size?, zIndex?, pulse? }

	`pulse = true` runs a looping ATTENTION breathe — for a button the game
	needs the player to notice right now (the tutorial's TO CHECKPOINT step).
	It rides a SECOND UIScale on the root TextButton, not the press one on
	`Content`: Roblox applies at most one UIScale per GuiObject, so stacking
	both on `Content` would make one of them silently dead. Two instances, two
	scales, multiplied — press feedback keeps working while pulsing.
	Neither UIScale ever receives a `Scale` prop from React (ADR-0006).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
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
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

local function Button(props)
	local STYLE = props.style or Theme.Button
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
		-- Optional. Without it the tap is counted under the rendered Name,
		-- which is already meaningful for most buttons ("StartButton").
		analyticsId = props.analyticsId,
	})

	-- Attention pulse (opt-in). The tween REVERSES and repeats forever, so it is
	-- the only writer of this UIScale's Scale; turning `pulse` off cancels it and
	-- eases back to 1 rather than snapping mid-breath.
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
			-- leaves the button frozen at whatever size the breath was mid-way.
			tween:Cancel()
			local instance = pulseRef.current
			if instance then
				instance.Scale = 1
			end
		end
	end, { pulse })

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "Button",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		ZIndex = zIndex,
	}, handlers), {
		-- Aspect stays on the (unscaled) hit target; the press pop lives on the
		-- centered Content layer so it grows from the button's middle.
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = STYLE.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		-- Mounted unconditionally: the effect above needs the instance in order
		-- to ease back to 1 when `pulse` turns off, and a Scale-1 UIScale on a
		-- non-pulsing button costs nothing.
		PulseScale = React.createElement("UIScale", { ref = pulseRef }),
		Content = Interaction.pressLayer(scaleRef, zIndex, {
			Outer = roundedFrame(
				"Outer",
				UDim2.fromScale(0, 0),
				UDim2.fromScale(1, 1),
				STYLE.OuterCorner,
				zIndex,
				STYLE.OuterGradient
			),
			Rim = roundedFrame(
				"Rim",
				UDim2.fromScale(STYLE.RimPosition.X, STYLE.RimPosition.Y),
				UDim2.fromScale(STYLE.RimSize.X, STYLE.RimSize.Y),
				STYLE.RimCorner,
				zIndex + 1,
				STYLE.RimGradient
			),
			Face = roundedFrame(
				"Face",
				UDim2.fromScale(STYLE.FacePosition.X, STYLE.FacePosition.Y),
				UDim2.fromScale(STYLE.FaceSize.X, STYLE.FaceSize.Y),
				STYLE.FaceCorner,
				zIndex + 2,
				STYLE.FaceGradient
			),
			Label = React.createElement(OutlinedText, {
				text = props.text or "Button",
				position = UDim2.fromScale(STYLE.TextPosition.X, STYLE.TextPosition.Y),
				size = UDim2.fromScale(STYLE.TextSize.X, STYLE.TextSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = STYLE.TextGradient,
				outlineColor = STYLE.OutlineColor,
				textXAlignment = props.textXAlignment,
				zIndex = zIndex + 3,
			}),
		}),
	})
end

return Button
