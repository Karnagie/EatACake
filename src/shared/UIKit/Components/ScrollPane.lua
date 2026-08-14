--[[
	ScrollPane -- axis-selectable scrolling surface with optional direct manipulation.

	Responsibility:
	- Render a ScrollingFrame plus an optional deterministic custom track/thumb on
	  the requested X or Y axis (Y by default for backwards compatibility).
	- Keep the thumb synchronized with wheel, swipe, track-tap, mouse drag, and
	  one correlated touch drag; additional fingers cannot hijack the active drag.
	- Optionally place a transparent pointer surface over interactive content so a
	  card can be both a tap target and the grab surface for direct scrolling. The
	  surface classifies the gesture before dispatching a tap, preventing a drag
	  from leaking click sound, analytics, or activation to the covered button.
	- Reset the main axis before paint whenever optional `resetKey` or its target
	  fraction changes; the cross axis returns to zero.

	Props:
		name, anchorPoint, position, size, zIndex, children
		windowFraction, barWidth, scrollbarStyle, showScrollbar
		resetKey, resetScrollFraction
		scrollingDirection -- Enum.ScrollingDirection.X or .Y; defaults to .Y
		canvasHeightScale  -- deterministic Y canvas; nil uses AutomaticCanvasSize.Y
		canvasWidthScale   -- deterministic X canvas; nil uses AutomaticCanvasSize.X
		resetScrollFraction -- optional 0..1 position on the selected main axis
		contentDrag? -- { enabled?, scrollingEnabled?, thresholdPx?,
		                  wheelStepFraction?,
		                  onTap(releaseCanvasPoint01, inputType, startCanvasPoint01)? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local InputBridge = require(script.Parent.Parent.InputBridge)

local function ScrollPane(props)
	local scrollingDirection = if props.scrollingDirection == Enum.ScrollingDirection.X
		then Enum.ScrollingDirection.X
		else Enum.ScrollingDirection.Y
	local horizontal = scrollingDirection == Enum.ScrollingDirection.X
	local defaultStyle = if horizontal and Theme.HorizontalScrollbar
		then Theme.HorizontalScrollbar
		else Theme.Scrollbar
	local style = props.scrollbarStyle or defaultStyle
	local zIndex = props.zIndex or 1
	local showScrollbar = props.showScrollbar ~= false
	local contentDrag = if type(props.contentDrag) == "table" then props.contentDrag else nil
	local contentDragEnabled = contentDrag ~= nil and contentDrag.enabled ~= false
	local contentScrollingEnabled = contentDrag == nil or contentDrag.scrollingEnabled ~= false
	local windowFraction = if props.windowFraction ~= nil
		then props.windowFraction
		elseif showScrollbar then 0.96
		else 1
	local barWidth = props.barWidth or 0.026
	local canvasScale = if horizontal then props.canvasWidthScale else props.canvasHeightScale

	-- Insets are physical X/Y fractions. The optional horizontal style is already
	-- authored in that orientation; when an older Theme only has the vertical
	-- style, transpose its long-axis/cross-axis values for a correct fallback.
	local transposeInsets = horizontal and style == Theme.Scrollbar
	local grooveInset = if transposeInsets
		then Vector2.new(style.GrooveInset.Y, style.GrooveInset.X)
		else style.GrooveInset
	local thumbFaceInset = if transposeInsets
		then Vector2.new(style.ThumbFaceInset.Y, style.ThumbFaceInset.X)
		else style.ThumbFaceInset

	local function axisValue(value)
		return if horizontal then value.X else value.Y
	end

	-- `main` is the scrolling axis and `cross` is the reserved scrollbar axis.
	-- For Y this deliberately emits the exact legacy (X=cross, Y=main) values.
	local function axisVector(main, cross)
		return if horizontal then Vector2.new(main, cross) else Vector2.new(cross, main)
	end

	local function axisScale(main, cross)
		return if horizontal then UDim2.fromScale(main, cross) else UDim2.fromScale(cross, main)
	end

	local windowSize = axisScale(1, windowFraction)
	local canvasSize = axisScale(canvasScale or 0, windowFraction)
	local automaticCanvasSize = if canvasScale ~= nil
		then Enum.AutomaticSize.None
		elseif horizontal then Enum.AutomaticSize.X
		else Enum.AutomaticSize.Y
	local trackAnchorPoint = axisVector(0, 1)
	local trackPosition = axisScale(0, 1)
	local trackSize = axisScale(1, barWidth)

	local scrollRef = React.useRef(nil)
	local trackRef = React.useRef(nil)
	local thumbRef = React.useRef(nil)
	local thumbDragRef = React.useRef(nil)
	local surfaceDragRef = React.useRef(nil)
	local surfaceConfigRef = React.useRef(nil)
	surfaceConfigRef.current = contentDrag
	local scrollState, setScrollState = React.useBinding({ pos = 0, window = 1, canvas = 1 })
	local resetKey = props.resetKey or false
	local resetScrollFraction = math.clamp(props.resetScrollFraction or 0, 0, 1)
	local function updateScrollState(frame)
		setScrollState({
			pos = axisValue(frame.CanvasPosition),
			window = axisValue(frame.AbsoluteWindowSize),
			canvas = math.max(axisValue(frame.AbsoluteCanvasSize), 1),
		})
	end

	-- Layout effect is deliberate: the panel remains mounted while hidden. A
	-- normal effect would briefly paint the previous session's scroll offset when
	-- it reopened, potentially hiding the newly restored default choice.
	React.useLayoutEffect(function()
		local frame = scrollRef.current
		if frame then
			local range = math.max(
				axisValue(frame.AbsoluteCanvasSize) - axisValue(frame.AbsoluteWindowSize),
				0
			)
			frame.CanvasPosition = axisVector(resetScrollFraction * range, 0)
			updateScrollState(frame)
		end
		thumbDragRef.current = nil
		surfaceDragRef.current = nil
	end, { resetKey, resetScrollFraction, horizontal })

	-- A pane may stay mounted beneath an invisible or busy panel. Any capture or
	-- scrolling-enabled transition invalidates the gesture that began under the
	-- previous interaction state; otherwise a press begun while disabled could
	-- become a live tap when interaction resumes before the finger is released.
	React.useLayoutEffect(function()
		surfaceDragRef.current = nil
	end, { contentDragEnabled, contentScrollingEnabled })

	React.useEffect(function()
		return InputBridge.Register(function(input)
			local surfaceDrag = surfaceDragRef.current
			if surfaceDrag then
				if surfaceDrag.touch then
					-- A touch gesture belongs to the exact finger that began it.
					if input ~= surfaceDrag.input then
						return
					end
				elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end

				local point = Vector2.new(input.Position.X, input.Position.Y)
				local delta = point - surfaceDrag.startScreen
				local config = surfaceConfigRef.current or {}
				local threshold = config.thresholdPx or 8
				if not surfaceDrag.moved and delta.Magnitude >= threshold then
					-- Crossing the threshold claims the gesture even when this pane
					-- cannot currently move (busy or no overflow). It must never fall
					-- back into a tap after the player's intentional swipe.
					surfaceDrag.moved = true
				end
				if surfaceDrag.moved and config.scrollingEnabled ~= false then
					local frame = scrollRef.current
					if frame then
						local range = math.max(
							axisValue(frame.AbsoluteCanvasSize)
								- axisValue(frame.AbsoluteWindowSize),
							0
						)
						local nextPosition = math.clamp(
							surfaceDrag.startCanvas - axisValue(delta),
							0,
							range
						)
						frame.CanvasPosition = axisVector(nextPosition, 0)
					end
				end
				return
			end

			local drag = thumbDragRef.current
			if not drag then
				return
			end
			if drag.touch then
				-- Only the finger that grabbed this thumb can move it. A second
				-- touch elsewhere must not hijack or terminate the drag.
				if input ~= drag.input then
					return
				end
			elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local frame = scrollRef.current
			local track = trackRef.current
			if not frame or not track then
				return
			end
			local windowExtent = axisValue(frame.AbsoluteWindowSize)
			local canvasExtent = math.max(axisValue(frame.AbsoluteCanvasSize), 1)
			local range = math.max(canvasExtent - windowExtent, 0)
			if range <= 0 then
				return
			end
			local thumbFraction = math.clamp(windowExtent / canvasExtent, style.MinThumbFraction, 1)
			local trackSpan = axisValue(track.AbsoluteSize) * (1 - thumbFraction)
			if trackSpan <= 0 then
				return
			end
			-- Incremental deltas: immune to the event coordinate space (gui inset) mismatch
			local inputPosition = axisValue(input.Position)
			if drag.lastPosition ~= nil then
				local delta = inputPosition - drag.lastPosition
				local nextPosition = math.clamp(
					axisValue(frame.CanvasPosition) + delta * range / trackSpan,
					0,
					range
				)
				frame.CanvasPosition = axisVector(nextPosition, 0)
			end
			drag.lastPosition = inputPosition
		end, function(input)
			local surfaceDrag = surfaceDragRef.current
			if surfaceDrag then
				local ownsRelease = if surfaceDrag.touch
					then input == surfaceDrag.input
					else input.UserInputType == Enum.UserInputType.MouseButton1
				if not ownsRelease then
					return
				end

				-- Clear ownership before invoking user code. A synchronous rerender,
				-- reset, or callback error cannot leave a stale gesture behind.
				surfaceDragRef.current = nil
				local frame = scrollRef.current
				local config = surfaceConfigRef.current or {}
				if
					frame
					and not surfaceDrag.moved
					and not surfaceDrag.cancelled
					and config.onTap
				then
					local point = Vector2.new(input.Position.X, input.Position.Y)
					local minimum = frame.AbsolutePosition
					local maximum = minimum + frame.AbsoluteWindowSize
					local inside = point.X >= minimum.X
						and point.X <= maximum.X
						and point.Y >= minimum.Y
						and point.Y <= maximum.Y
					if inside then
						local canvasPoint = point - minimum + frame.CanvasPosition
						local canvasSize = frame.AbsoluteCanvasSize
						local startCanvasPoint = surfaceDrag.startScreen
							- surfaceDrag.startWindow
							+ surfaceDrag.startCanvasPosition
						config.onTap(Vector2.new(
							canvasPoint.X / math.max(canvasSize.X, 1),
							canvasPoint.Y / math.max(canvasSize.Y, 1)
						), input.UserInputType, Vector2.new(
							startCanvasPoint.X / math.max(canvasSize.X, 1),
							startCanvasPoint.Y / math.max(canvasSize.Y, 1)
						))
					end
				end
				return
			end

			local drag = thumbDragRef.current
			if not drag then
				return
			end
			if drag.touch then
				if input == drag.input then
					thumbDragRef.current = nil
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				thumbDragRef.current = nil
			end
		end)
	end, { horizontal })

	local thumbSize = scrollState:map(function(state)
		local fraction = math.clamp(state.window / math.max(state.canvas, 1), style.MinThumbFraction, 1)
		return axisScale(fraction, 1)
	end)
	local thumbPosition = scrollState:map(function(state)
		local fraction = math.clamp(state.window / math.max(state.canvas, 1), style.MinThumbFraction, 1)
		local range = math.max(state.canvas - state.window, 0)
		local t = 0
		if range > 0 then
			t = math.clamp(state.pos / range, 0, 1)
		end
		return axisScale(t * (1 - fraction), 0)
	end)

	return React.createElement("Frame", {
		Name = props.name or "ScrollPane",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Window = React.createElement("ScrollingFrame", {
			Name = "Window",
			Size = windowSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- CanvasSize scale resolves against the ScrollingFrame's PARENT (like
			-- Size), so the cross axis must equal windowFraction to match the window.
			CanvasSize = canvasSize,
			AutomaticCanvasSize = automaticCanvasSize,
			ScrollBarThickness = 0,
			ScrollingDirection = scrollingDirection,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			ZIndex = zIndex,
			ref = scrollRef,
			[React.Change.CanvasPosition] = updateScrollState,
			[React.Change.AbsoluteWindowSize] = updateScrollState,
			[React.Change.AbsoluteCanvasSize] = updateScrollState,
		}, props.children),
		-- No track when the canvas provably fits (composition audit
		-- 2026-08-01): a full-span thumb on a non-scrolling pane is dead
		-- chrome that falsely advertises scrollable content. Only the
		-- deterministic-canvas path can know this statically; the
		-- AutomaticCanvasSize path keeps its track.
		Track = showScrollbar
			and (canvasScale == nil or canvasScale > 1.001)
			and React.createElement("TextButton", {
			Name = "Track",
			AnchorPoint = trackAnchorPoint,
			Position = trackPosition,
			Size = trackSize,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			-- Track/thumb have pointer drag semantics but no controller action.
			-- Keeping them out of selection prevents dead gamepad focus stops.
			Selectable = false,
			ZIndex = zIndex,
			ref = trackRef,
			[React.Event.InputBegan] = function(_, input: InputObject)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local activeDrag = thumbDragRef.current
				if activeDrag and activeDrag.touch and input ~= activeDrag.input then
					-- A second finger cannot jump the track underneath an active drag.
					return
				end
				local frame = scrollRef.current
				local track = trackRef.current
				if not frame or not track then
					return
				end
				-- Thumb is a child of Track, so Roblox also delivers the same
				-- InputBegan to this ancestor. Treat a point inside the live thumb as
				-- a drag grab, not a track jump; Thumb's own handler starts the drag.
				local thumb = thumbRef.current
				if thumb then
					local point = input.Position
					local thumbMin = thumb.AbsolutePosition
					local thumbMax = thumbMin + thumb.AbsoluteSize
					if
						point.X >= thumbMin.X
						and point.X <= thumbMax.X
						and point.Y >= thumbMin.Y
						and point.Y <= thumbMax.Y
					then
						return
					end
				end
				-- INSET-AGNOSTIC (2026-07-30). This was `GetMouseLocation() -
				-- GuiService:GetGuiInset()`, which silently assumed an INSET root
				-- ScreenGui. The root went FULL-BLEED so modal scrims could cover the
				-- whole screen (UiRoot), which would have thrown every track click off
				-- by the topbar height. `input.Position` is in the SAME space as
				-- AbsolutePosition in either mode (the convention HexTreeOverlay uses
				-- too), and it also picks up TOUCH — MouseButton1Down never fired for it.
				local relative = (axisValue(input.Position) - axisValue(track.AbsolutePosition))
					/ math.max(axisValue(track.AbsoluteSize), 1)
				local range = math.max(
					axisValue(frame.AbsoluteCanvasSize) - axisValue(frame.AbsoluteWindowSize),
					0
				)
				frame.CanvasPosition = axisVector(math.clamp(relative, 0, 1) * range, 0)
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = style.TrackOuterGradient,
				Rotation = 90,
			}),
			Groove = React.createElement("Frame", {
				Name = "Groove",
				Position = UDim2.fromScale(grooveInset.X, grooveInset.Y),
				Size = UDim2.fromScale(1 - grooveInset.X * 2, 1 - grooveInset.Y * 2),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 1,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = React.createElement("UIGradient", {
					Color = style.GrooveGradient,
					Rotation = 90,
				}),
			}),
			Thumb = React.createElement("TextButton", {
				Name = "Thumb",
				Position = thumbPosition,
				Size = thumbSize,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				Selectable = false,
				ZIndex = zIndex + 2,
				ref = thumbRef,
				[React.Event.InputBegan] = function(_, input: InputObject)
					if
						input.UserInputType ~= Enum.UserInputType.MouseButton1
						and input.UserInputType ~= Enum.UserInputType.Touch
					then
						return
					end
					local activeDrag = thumbDragRef.current
					if activeDrag and activeDrag.touch and input ~= activeDrag.input then
						-- Preserve correlation with the finger that already owns the drag.
						return
					end
					thumbDragRef.current = {
						input = input,
						touch = input.UserInputType == Enum.UserInputType.Touch,
						lastPosition = axisValue(input.Position),
					}
				end,
			}, {
				ThumbOuter = React.createElement("Frame", {
					Name = "ThumbOuter",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					ZIndex = zIndex + 2,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Gradient = React.createElement("UIGradient", {
						Color = style.ThumbOuterGradient,
						Rotation = 90,
					}),
				}),
				ThumbFace = React.createElement("Frame", {
					Name = "ThumbFace",
					Position = UDim2.fromScale(thumbFaceInset.X, thumbFaceInset.Y),
					Size = UDim2.fromScale(1 - thumbFaceInset.X * 2, 1 - thumbFaceInset.Y * 2),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					ZIndex = zIndex + 3,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Gradient = React.createElement("UIGradient", {
						Color = style.ThumbFaceGradient,
						Rotation = 90,
					}),
				}),
			}),
		}) or nil,
		InputSurface = contentDragEnabled and React.createElement("TextButton", {
			Name = "InputSurface",
			Size = windowSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			-- Real content buttons remain the controller focus targets beneath this
			-- pointer-only surface.
			Selectable = false,
			ZIndex = props.contentDragZIndex or (zIndex + 10),
			[React.Event.InputBegan] = function(_, input: InputObject)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local activeDrag = surfaceDragRef.current
				if activeDrag then
					-- Multi-touch cancels tap classification without letting the new
					-- finger steal or move the gesture owned by the first.
					activeDrag.cancelled = true
					return
				end
				local frame = scrollRef.current
				if not frame then
					return
				end
				local point = Vector2.new(input.Position.X, input.Position.Y)
				surfaceDragRef.current = {
					input = input,
					touch = input.UserInputType == Enum.UserInputType.Touch,
					startScreen = point,
					startWindow = frame.AbsolutePosition,
					startCanvasPosition = frame.CanvasPosition,
					startCanvas = axisValue(frame.CanvasPosition),
					moved = false,
					cancelled = false,
				}
			end,
			[React.Event.InputChanged] = function(_, input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.MouseWheel then
					return
				end
				-- A wheel tick can move a different card beneath a held mouse press.
				-- Cancel that pending tap before changing CanvasPosition so releasing
				-- Mouse1 cannot activate content the player never pressed.
				local activeSurfaceDrag = surfaceDragRef.current
				if activeSurfaceDrag then
					activeSurfaceDrag.cancelled = true
				end
				local config = surfaceConfigRef.current or {}
				if config.scrollingEnabled == false then
					return
				end
				local frame = scrollRef.current
				if not frame then
					return
				end
				local windowExtent = axisValue(frame.AbsoluteWindowSize)
				local range = math.max(
					axisValue(frame.AbsoluteCanvasSize) - windowExtent,
					0
				)
				local step = windowExtent * (config.wheelStepFraction or 0.18)
				local nextPosition = math.clamp(
					axisValue(frame.CanvasPosition) - input.Position.Z * step,
					0,
					range
				)
				frame.CanvasPosition = axisVector(nextPosition, 0)
			end,
		}) or nil,
	})
end

return ScrollPane
