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
	  hover). Activation flows through GuiButton.Activated, Roblox's shared
	  mouse/touch/gamepad event. Gamepad/keyboard activation adds its cue and
	  analytics at activation because it has no pointer-down edge here.

	SQUASH (the squishy theme's motion signature) — opt in with `config.squash`:

	  local scaleRef, handlers, squashRef = Interaction.usePressable({
	      enabled = enabled, onActivated = ..., squash = true })     -- or a table
	  Content = Interaction.pressLayer(scaleRef, zIndex, children, squashRef)

	UIScale is uniform and cannot squash, so the deform rides `Content.Size`
	instead — legal under ADR-0006 because React writes that prop exactly once
	with the constant `Interaction.FullSize` and then diffs it away forever.
	`squash = true` uses the button preset; a table `{press=, hover=,
	pressTween=, hoverTween=, releaseTween=}` overrides per surface (cards want a
	hover pose, buttons do not). Poses live in `Theme.Feel.Squish`.
	Panels cannot use this: a panel's root Size IS a live React prop, so the
	squash would have to ride an inner constant-sized frame. That variant is not
	built — add it with its call site.

	SOUND — every kit button clicks, from one place:

	  Interaction.SetSoundHandler(function(cue) ... end)   -- "hover" | "press"

	`usePressable` calls the handler on hover-in and on the AGGREGATE press edge
	(first finger down, so multi-touch and drag-off never double-fire). The kit
	stays CLIENT-FREE: shared code must not require a client module, so the
	handler is injected once by a subscription (AudioSubsClient) and defaults to
	a no-op — the kit is silent, and correct, without it. Cue -> sample mapping
	lives in AudioConfig.sounds (docs/features/audio.md).

	Components that are clickable but do NOT use `usePressable` (Toggle, PetCard,
	DayCard, the reveal overlay's dismiss catcher — each owns its own motion)
	call `Interaction.Cue("press")` from their activation handler instead. Never
	both: a `usePressable` button that also calls `Cue` clicks twice.

	ANALYTICS — every kit press is counted, from the same one place:

	  Interaction.SetTrackHandler(function(kind, id) ... end)  -- "press" | "dead"

	Injected once by a subscription (AnalyticsSubsClient), exactly like the
	sound handler, and a no-op until then — the kit stays client-free and
	works untracked. `id` identifies the control: `config.analyticsId` when
	the caller names it, otherwise DERIVED from the pressed Instance's own
	Name (components already name their buttons `StartButton`,
	`Difficulty_easy`, `Players_2`…), with the parent prefixed when the name
	is a generic one. That is what makes "track every tap" cost no per-button
	wiring: a control gets counted because it exists, not because someone
	remembered to instrument it.

	`"dead"` is a pointer press on a button that is currently DISABLED — the player
	tried and the game did not answer. It rides `InputBegan`, which fires for
	inputs over a GuiObject regardless of `Active` (unlike `Activated` /
	`Activated`, which a disabled button suppresses — which is the
	whole point: the press is real, the response is not). No `Active` value
	is changed to get it, so a disabled button still sinks exactly what it
	sank before.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Theme)

local Interaction = {}

-- Injected by the client (AudioSubsClient). nil = the kit makes no sound.
local soundHandler: ((string) -> ())? = nil

--API
-- Route kit interaction cues ("hover", "press") to a player-side sound layer.
-- Pass nil to silence the kit again. Errors in the handler must never break a
-- button, so the call is pcall'd at the call site.
function Interaction.SetSoundHandler(handler: ((string) -> ())?)
	soundHandler = handler
end

local function cue(name: string)
	local handler = soundHandler
	if handler then
		pcall(handler, name)
	end
end

-- Injected by the client (AnalyticsSubsClient). nil = the kit is untracked.
local trackHandler: ((string, string) -> ())? = nil

--API
-- Route kit press events ("press" = a live control, "dead" = a disabled one)
-- to the analytics layer. Pass nil to stop counting. Errors in the handler
-- must never break a button, so the call is pcall'd.
function Interaction.SetTrackHandler(handler: ((string, string) -> ())?)
	trackHandler = handler
end

-- Names too generic to identify anything on their own get their parent
-- prefixed, so `ShopTabs/Button` is distinguishable from `Footer/Button`.
local GENERIC_NAMES = {
	Button = true,
	TextButton = true,
	Content = true,
	Frame = true,
	Root = true,
	Hit = true,
	Catcher = true,
}

local function deriveId(rbx: any): string?
	if typeof(rbx) ~= "Instance" then
		return nil
	end
	local name = rbx.Name
	local parent = rbx.Parent
	if GENERIC_NAMES[name] and parent ~= nil then
		return `{parent.Name}/{name}`
	end
	return name
end

local function track(kind: string, id: string?)
	local handler = trackHandler
	if handler ~= nil and id ~= nil and id ~= "" then
		pcall(handler, kind, id)
	end
end

--API
-- Count a press by hand, for clickable components outside `usePressable`.
function Interaction.Track(kind: string, id: string)
	track(kind, id)
end

--API
-- Emit an interaction cue by hand. For clickable components that deliberately
-- do NOT take `usePressable`'s visual bounce (a Toggle owns its knob slide, a
-- card its selected pose) but must still CLICK — call it from the activation
-- handler. Components that use `usePressable` get this for free; calling it
-- there too would double the click.
-- `id` is optional and, when given, also COUNTS the press (those components
-- are invisible to `usePressable`'s automatic capture, so this is the only
-- place their taps can be seen).
function Interaction.Cue(name: string, id: string?)
	cue(name)
	if id ~= nil and name == "press" then
		track("press", id)
	end
end

--API
-- Shallow-merge `extra` (event handlers) into a copy of `base` (element props).
function Interaction.merge(base: { [any]: any }, extra: { [any]: any }): { [any]: any }
	local out = table.clone(base)
	for key, value in pairs(extra) do
		out[key] = value
	end
	return out
end

-- The ONE value `Content.Size` is ever given by React. Hoisted so the ownership
-- invariant is auditable: this prop is written once with a constant, then the
-- reconciler diffs it away and the squash tween owns the property (ADR-0006,
-- same class of constant as ZERO_FILL / KNOB_INITIAL).
local FULL_SIZE = UDim2.fromScale(1, 1)
Interaction.FullSize = FULL_SIZE

--API
-- Center-anchored, transparent wrapper holding the press UIScale + the visual
-- children. Scaling this frame pops the button's visuals around their centre.
-- Pass `squashRef` to also let the squash tween own this frame's Size.
function Interaction.pressLayer(scaleRef, zIndex: number?, children: { [any]: any }, squashRef)
	local wrapped = table.clone(children)
	wrapped.PressScale = React.createElement("UIScale", { ref = scaleRef })
	return React.createElement("Frame", {
		Name = "Content",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = FULL_SIZE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex or 1,
		ref = squashRef,
	}, wrapped)
end

-- Normalise `config.squash` into { press, hover, pressTween, hoverTween,
-- releaseTween }. `true` = the plain button preset (press squash, no hover
-- squash — two competing poses on one property fight each other).
local function resolveSquash(squash, feel)
	if not squash then
		return nil
	end
	local sq = feel.Squish
	if squash == true then
		return { press = sq.PressPose, hover = nil }
	end
	return {
		press = squash.press or sq.PressPose,
		hover = squash.hover,
		pressTween = squash.pressTween,
		hoverTween = squash.hoverTween,
		releaseTween = squash.releaseTween,
	}
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
-- config: { enabled=true, onActivated=fn?, onPressStart=fn(input)?,
--           onPressEnd=fn(input)?, hoverScale?, pressScale?, feel?,
--           analyticsId=string? }
-- `analyticsId` overrides the Instance-name-derived control id used for tap
-- counting. Only worth setting when the rendered Name is ambiguous.
-- onActivated fires on a click/tap (release); onPressStart/onPressEnd fire on
-- press-down / release for HOLD buttons (a tap fires both). `input` is the
-- Touch InputObject (nil for mouse) — lets a caller correlate the finger.
function Interaction.usePressable(config)
	config = config or {}
	local feel = config.feel or Theme.Feel
	local enabled = config.enabled ~= false
	local hoverScale = config.hoverScale or feel.HoverScale
	local pressScale = config.pressScale or feel.PressScale

	local scaleRef = React.useRef(nil)
	-- Squash is OPT-IN and read through a ref, never through the memo deps: the
	-- caller usually builds `config.squash` as a fresh table literal each render,
	-- and putting that in the deps would rebuild the handlers on every one of the
	-- HUD's ~14 re-renders per second.
	local squashRef = React.useRef(nil)
	local squashCfgRef = React.useRef(nil)
	squashCfgRef.current = resolveSquash(config.squash, feel)

	local flags = React.useRef(nil)
	if flags.current == nil then
		-- `pressed` is finger-aware: the button is held while the mouse is down
		-- OR any Touch that began on it is still down (a refcount set). This makes
		-- HOLD buttons multi-touch-correct — a second finger tapping the same
		-- button can't cancel the first finger's hold, and a drag-off release is
		-- caught when the LAST finger lifts (GuiObject delivers its InputEnded).
		flags.current = { hover = false, mouseDown = false, touches = {} }
	end
	-- Latest activation callback without rebuilding handlers each render.
	local activatedRef = React.useRef(nil)
	activatedRef.current = config.onActivated
	-- Optional HOLD callbacks: onPressStart fires when the FIRST press lands,
	-- onPressEnd when the LAST one releases (a TAP fires both). Read through refs
	-- so handlers stay stable across the HUD's bite-rate re-renders.
	local pressStartRef = React.useRef(nil)
	pressStartRef.current = config.onPressStart
	local pressEndRef = React.useRef(nil)
	pressEndRef.current = config.onPressEnd
	-- Read through a ref, never through the memo deps: callers build ids from
	-- props (`Difficulty_{id}`) and a new string every render would rebuild
	-- every handler on each of the HUD's ~14 re-renders per second.
	local analyticsRef = React.useRef(nil)
	analyticsRef.current = config.analyticsId

	local handlers = React.useMemo(function()
		if not enabled then
			-- A DISABLED button still reports that it was pressed. `InputBegan`
			-- fires for inputs over a GuiObject whatever its `Active` value, so
			-- this needs no property change and sinks nothing extra — while
			-- `Activated` stays correctly suppressed, which
			-- is exactly the event being recorded: a press with no answer.
			return {
				[React.Event.InputBegan] = function(rbx, input)
					if
						input.UserInputType == Enum.UserInputType.Touch
						or input.UserInputType == Enum.UserInputType.MouseButton1
					then
						track("dead", analyticsRef.current or deriveId(rbx))
					end
				end,
			}
		end

		local function isPressed(): boolean
			return flags.current.mouseDown or next(flags.current.touches) ~= nil
		end

		local function retarget()
			local pressed = isPressed()
			local scale = scaleRef.current
			if scale then
				local target, info
				if pressed then
					target, info = pressScale, feel.PressTween
				elseif flags.current.hover then
					target, info = hoverScale, feel.PressTween
				else
					target, info = 1, feel.ReleaseTween
				end
				TweenService:Create(scale, info, { Scale = target }):Play()
			end
			-- Squash rides the SAME state machine on the Content frame's Size.
			local squash, cfg = squashRef.current, squashCfgRef.current
			if squash and cfg then
				local pose, info
				if pressed then
					pose, info = cfg.press, cfg.pressTween or feel.Squish.PressTween
				elseif flags.current.hover and cfg.hover then
					pose, info = cfg.hover, cfg.hoverTween or feel.Squish.CardHoverTween
				else
					pose, info = nil, cfg.releaseTween or feel.Squish.ReleaseTween
				end
				TweenService:Create(squash, info, {
					Size = if pose then UDim2.fromScale(pose.X, pose.Y) else FULL_SIZE,
				}):Play()
			end
		end

		-- Call after mutating mouseDown / touches. Drives the squish tween and,
		-- on the AGGREGATE press edge (first-down / last-up), the optional HOLD
		-- callbacks — so multi-touch and drag-off release resolve correctly.
		-- `input` is the Touch InputObject (nil for mouse) that caused the edge.
		local function updatePress(wasPressed: boolean, input, rbx)
			retarget()
			local nowPressed = isPressed()
			if nowPressed == wasPressed then
				return
			end
			if nowPressed then
				cue("press") -- exactly one click per press, however many fingers
				-- Counted on the same AGGREGATE edge as the click, so a
				-- multi-touch press or a drag-off is one tap, not three.
				track("press", analyticsRef.current or deriveId(rbx))
			end
			local cb = if nowPressed then pressStartRef.current else pressEndRef.current
			if cb then
				cb(input)
			end
		end

		return {
			[React.Event.MouseEnter] = function()
				flags.current.hover = true
				cue("hover")
				retarget()
			end,
			[React.Event.MouseLeave] = function(rbx)
				local was = isPressed()
				flags.current.hover = false
				flags.current.mouseDown = false -- pointer left: drop a mouse hold
				updatePress(was, nil, rbx)
			end,
			[React.Event.MouseButton1Down] = function(rbx)
				local was = isPressed()
				flags.current.mouseDown = true
				updatePress(was, nil, rbx)
			end,
			[React.Event.MouseButton1Up] = function(rbx)
				local was = isPressed()
				flags.current.mouseDown = false
				updatePress(was, nil, rbx)
			end,
			[React.Event.InputBegan] = function(rbx, input)
				if input.UserInputType == Enum.UserInputType.Touch then
					local was = isPressed()
					flags.current.touches[input] = true
					updatePress(was, input, rbx)
				end
			end,
			[React.Event.InputEnded] = function(rbx, input)
				if input.UserInputType == Enum.UserInputType.Touch then
					local was = isPressed()
					flags.current.touches[input] = nil
					updatePress(was, input, rbx)
				end
			end,
			[React.Event.Activated] = function(rbx, input)
				-- Mouse/touch already cue + count on their aggregate pointer-down
				-- edge. Controller A/cross and keyboard UI activation have no such
				-- edge in this pointer state machine, so record them exactly once here.
				if
					input ~= nil
					and input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					cue("press")
					track("press", analyticsRef.current or deriveId(rbx))
				end
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
		local wasPressed = flags.current.mouseDown or next(flags.current.touches) ~= nil
		flags.current.hover = false
		flags.current.mouseDown = false
		table.clear(flags.current.touches)
		local scale = scaleRef.current
		if scale then
			TweenService:Create(scale, feel.ReleaseTween, { Scale = 1 }):Play()
		end
		-- Mirror the reset for squash, or a button disabled mid-press (an
		-- affordability gate flipping) stays permanently flattened.
		local squash = squashRef.current
		if squash then
			TweenService:Create(squash, feel.ReleaseTween, { Size = FULL_SIZE }):Play()
		end
		-- A HOLD button disabled/hidden mid-press must release its hold too
		-- (else eating would stick on after the eat button hides).
		if wasPressed and pressEndRef.current then
			pressEndRef.current(nil)
		end
	end, { enabled })

	-- Third return is OPTIONAL: every existing caller destructures two values and
	-- is unaffected. Attach it via pressLayer(scaleRef, z, children, squashRef).
	return scaleRef, handlers, squashRef
end

return Interaction
