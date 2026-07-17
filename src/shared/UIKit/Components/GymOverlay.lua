--[[ GymOverlay
	Gym mash overlay: full-screen transparent layer shown while a mash
	session is active. Big round green TAP button (Outer/Rim/Face circle
	stack, whole button is the hit area), a draining timer pill above it,
	and a tap-counter label. The timer fill drains from 1 to 0 over
	props.duration seconds starting at props.startedAt (os.clock() base),
	animated by a ~10 Hz task-loop ticker into a binding.
	Props: { active: boolean, duration: number?, startedAt: number?,
		tapText: string, buttonText: string, onTap: () -> (), zIndex: number? }.
	Style: Theme.GymOverlay (override via props.style). Defaults to the
	open-panel layer (zIndex 50) so it renders above the HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

-- Ticker step for the timer drain (~10 updates/sec is enough for a pill fill)
local TICK_SECONDS = 0.1

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

local function tapButton(style, active, buttonText, onTap, zIndex)
	return React.createElement("TextButton", {
		Name = "TapButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(style.ButtonPosition.X, style.ButtonPosition.Y),
		Size = UDim2.fromScale(0.5, style.ButtonHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = active,
		Selectable = active,
		ZIndex = zIndex,
		[React.Event.Activated] = function()
			if active and onTap then
				onTap()
			end
		end,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.ButtonAspect,
		}),
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.ButtonOuterCorner,
			zIndex,
			style.ButtonOuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.ButtonOuterCorner,
			zIndex + 1,
			style.ButtonRimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.ButtonOuterCorner,
			zIndex + 2,
			style.ButtonFaceGradient
		),
		Label = React.createElement(OutlinedText, {
			text = buttonText,
			position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
			size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.ButtonTextGradient,
			outlineColor = style.ButtonOutline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	})
end

local function timerBar(style, fillSize, zIndex)
	return React.createElement("Frame", {
		Name = "TimerBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(style.TimerPosition.X, style.TimerPosition.Y),
		Size = UDim2.fromScale(0.5, style.TimerHeight),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.TimerAspect,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = style.TimerOuterGradient,
			Rotation = 90,
		}),
		Groove = React.createElement("Frame", {
			Name = "Groove",
			Position = UDim2.fromScale(style.TimerGrooveInset.X, style.TimerGrooveInset.Y),
			Size = UDim2.fromScale(1 - style.TimerGrooveInset.X * 2, 1 - style.TimerGrooveInset.Y * 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = style.TimerGrooveGradient,
				Rotation = 90,
			}),
			Fill = React.createElement("Frame", {
				Name = "Fill",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = fillSize,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 2,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = React.createElement("UIGradient", {
					Color = style.TimerFillGradient,
					Rotation = 90,
				}),
			}),
		}),
	})
end

local function GymOverlay(props)
	local style = props.style or Theme.GymOverlay
	local zIndex = props.zIndex or 50
	local active = props.active == true

	local fillFraction, setFillFraction = React.useBinding(1)

	-- Refs so the ticker always reads the LATEST duration/startedAt without
	-- putting optional (possibly nil) numbers into the dependency array.
	local durationRef = React.useRef(nil)
	local startedAtRef = React.useRef(nil)
	durationRef.current = props.duration
	startedAtRef.current = props.startedAt

	-- BOOLEAN dep only (jsdotlua: nil in a dep array breaks comparison)
	local timerRunning = active
		and type(props.duration) == "number"
		and type(props.startedAt) == "number"

	React.useEffect(function()
		if not timerRunning then
			setFillFraction(1)
			return
		end
		local alive = true
		task.spawn(function()
			while alive do
				local duration = durationRef.current
				local startedAt = startedAtRef.current
				local fraction = 1
				if type(duration) == "number" and duration > 0 and type(startedAt) == "number" then
					fraction = math.clamp(1 - (os.clock() - startedAt) / duration, 0, 1)
				end
				setFillFraction(fraction)
				task.wait(TICK_SECONDS)
			end
		end)
		return function()
			alive = false
		end
	end, { timerRunning })

	local fillSize = fillFraction:map(function(fraction)
		return UDim2.fromScale(fraction, 1)
	end)

	return React.createElement("Frame", {
		Name = props.name or "GymOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = active,
		ZIndex = zIndex,
	}, {
		TapButton = tapButton(style, active, props.buttonText, props.onTap, zIndex + 1),
		TimerBar = timerBar(style, fillSize, zIndex + 1),
		Counter = React.createElement("Frame", {
			Name = "Counter",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(style.CounterPosition.X, style.CounterPosition.Y),
			Size = UDim2.fromScale(0.5, style.CounterHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Value = React.createElement(OutlinedText, {
				text = props.tapText,
				position = UDim2.fromScale(0, 0),
				size = UDim2.fromScale(1, 1),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.CounterGradient,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 1,
			}),
		}),
	})
end

return GymOverlay
