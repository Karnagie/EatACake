--[[ Interaction — shared press/hover "juice" for kit buttons.

	`usePressable` wires a TextButton's pointer events to a smooth scale bounce
	(hover grows, press squishes, release springs back) driven by TweenService on
	a UIScale the caller renders. It returns `(scaleRef, handlers)`:

	  local scaleRef, handlers = Interaction.usePressable({
	      enabled = enabled, onActivated = props.onActivated })
	  return React.createElement("TextButton", Interaction.merge(rootProps, handlers), {
	      Aspect = ...,                                   -- aspect stays on the hit target
	      Content = Interaction.pressLayer(scaleRef, zIndex, visualChildren),
	  })

	`pressLayer` wraps the visual children in a CENTER-anchored, full-size,
	transparent frame carrying the UIScale, so the pop grows from the button's
	centre while the root TextButton stays a stable, unscaled tap target.

	Notes
	- No `Scale` prop is ever set on the UIScale — React would reset it on every
	  re-render and fight the tween. The instance defaults to Scale = 1 and only
	  the tween touches it thereafter.
	- Handlers are memoised (stable across renders) and read the latest
	  `onActivated` through a ref, so nothing reconnects on the HUD's bite-rate
	  re-renders. Feel constants live in `Theme.Feel`.
	- Desktop gets hover + press; touch gets press via InputBegan/Ended (no
	  hover). Activation flows through MouseButton1Click, which Roblox also fires
	  for touch taps — same contract the kit's buttons already used.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Theme)

local Interaction = {}

--API
-- Shallow-merge `extra` (event handlers) into a copy of `base` (element props).
function Interaction.merge(base: { [any]: any }, extra: { [any]: any }): { [any]: any }
	local out = table.clone(base)
	for key, value in pairs(extra) do
		out[key] = value
	end
	return out
end

--API
-- Center-anchored, transparent wrapper holding the press UIScale + the visual
-- children. Scaling this frame pops the button's visuals around their centre.
function Interaction.pressLayer(scaleRef, zIndex: number?, children: { [any]: any })
	local wrapped = table.clone(children)
	wrapped.PressScale = React.createElement("UIScale", { ref = scaleRef })
	return React.createElement("Frame", {
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
	}, wrapped)
end

local ZERO_FILL = UDim2.fromScale(0, 1)

--API
-- Glide a horizontal fill frame's width to `fill01` (0..1) instead of snapping.
-- Attach the returned ref to the Fill frame and give that frame a CONSTANT
-- `Size = Interaction.ZeroFill` so React never overwrites the tweened value.
function Interaction.useFillGlide(fill01: number, feel)
	feel = feel or Theme.Feel
	local target = math.clamp(fill01 or 0, 0, 1)
	local fillRef = React.useRef(nil)
	React.useEffect(function()
		local frame = fillRef.current
		if not frame then
			return
		end
		TweenService:Create(frame, feel.FillTween, { Size = UDim2.fromScale(target, 1) }):Play()
	end, { target })
	return fillRef
end
Interaction.ZeroFill = ZERO_FILL

--API
-- Returns (scaleRef, handlers). Spread `handlers` onto the TextButton props and
-- render `Interaction.pressLayer(scaleRef, ...)` as a child.
-- config: { enabled=true, onActivated=fn?, hoverScale?, pressScale?, feel? }
function Interaction.usePressable(config)
	config = config or {}
	local feel = config.feel or Theme.Feel
	local enabled = config.enabled ~= false
	local hoverScale = config.hoverScale or feel.HoverScale
	local pressScale = config.pressScale or feel.PressScale

	local scaleRef = React.useRef(nil)
	local flags = React.useRef(nil)
	if flags.current == nil then
		flags.current = { hover = false, press = false }
	end
	-- Latest activation callback without rebuilding handlers each render.
	local activatedRef = React.useRef(nil)
	activatedRef.current = config.onActivated

	local handlers = React.useMemo(function()
		if not enabled then
			return {}
		end

		local function retarget()
			local scale = scaleRef.current
			if not scale then
				return
			end
			local target, info
			if flags.current.press then
				target, info = pressScale, feel.PressTween
			elseif flags.current.hover then
				target, info = hoverScale, feel.PressTween
			else
				target, info = 1, feel.ReleaseTween
			end
			TweenService:Create(scale, info, { Scale = target }):Play()
		end

		return {
			[React.Event.MouseEnter] = function()
				flags.current.hover = true
				retarget()
			end,
			[React.Event.MouseLeave] = function()
				flags.current.hover = false
				flags.current.press = false
				retarget()
			end,
			[React.Event.MouseButton1Down] = function()
				flags.current.press = true
				retarget()
			end,
			[React.Event.MouseButton1Up] = function()
				flags.current.press = false
				retarget()
			end,
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType == Enum.UserInputType.Touch then
					flags.current.press = true
					retarget()
				end
			end,
			[React.Event.InputEnded] = function(_, input)
				if input.UserInputType == Enum.UserInputType.Touch then
					flags.current.press = false
					retarget()
				end
			end,
			[React.Event.MouseButton1Click] = function()
				if activatedRef.current then
					activatedRef.current()
				end
			end,
		}
	end, { enabled, hoverScale, pressScale, feel })

	-- When a button is disabled its pointer handlers are removed (memo returns
	-- {}), so no MouseLeave/Up can ever spring the scale back — a button
	-- disabled mid-hover/press would stay stuck at 1.05/0.93. Reset here whenever
	-- `enabled` flips false (affordability-gated buttons toggle it live).
	React.useEffect(function()
		if enabled then
			return
		end
		flags.current.hover = false
		flags.current.press = false
		local scale = scaleRef.current
		if scale then
			TweenService:Create(scale, feel.ReleaseTween, { Scale = 1 }):Play()
		end
	end, { enabled })

	return scaleRef, handlers
end

return Interaction
