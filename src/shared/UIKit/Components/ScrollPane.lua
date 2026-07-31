local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function ScrollPane(props)
	local style = props.scrollbarStyle or Theme.Scrollbar
	local zIndex = props.zIndex or 1
	local windowFraction = props.windowFraction or 0.96
	local barWidth = props.barWidth or 0.026

	local scrollRef = React.useRef(nil)
	local trackRef = React.useRef(nil)
	local dragRef = React.useRef(nil)
	local scrollState, setScrollState = React.useBinding({ pos = 0, window = 1, canvas = 1 })

	React.useEffect(function()
		local frame = scrollRef.current
		if not frame then
			return
		end
		local connections = {}
		local function update()
			setScrollState({
				pos = frame.CanvasPosition.Y,
				window = frame.AbsoluteWindowSize.Y,
				canvas = math.max(frame.AbsoluteCanvasSize.Y, 1),
			})
		end
		table.insert(connections, frame:GetPropertyChangedSignal("CanvasPosition"):Connect(update))
		table.insert(connections, frame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update))
		table.insert(connections, frame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(update))
		update()
		return function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end, {})

	React.useEffect(function()
		local moveConnection = UserInputService.InputChanged:Connect(function(input)
			local drag = dragRef.current
			if not drag then
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			local frame = scrollRef.current
			local track = trackRef.current
			if not frame or not track then
				return
			end
			local windowY = frame.AbsoluteWindowSize.Y
			local canvasY = math.max(frame.AbsoluteCanvasSize.Y, 1)
			local range = math.max(canvasY - windowY, 0)
			if range <= 0 then
				return
			end
			local thumbFraction = math.clamp(windowY / canvasY, style.MinThumbFraction, 1)
			local trackSpan = track.AbsoluteSize.Y * (1 - thumbFraction)
			if trackSpan <= 0 then
				return
			end
			-- Incremental deltas: immune to the event coordinate space (gui inset) mismatch
			if drag.lastY ~= nil then
				local delta = input.Position.Y - drag.lastY
				frame.CanvasPosition = Vector2.new(
					0,
					math.clamp(frame.CanvasPosition.Y + delta * range / trackSpan, 0, range)
				)
			end
			drag.lastY = input.Position.Y
		end)
		local endConnection = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragRef.current = nil
			end
		end)
		return function()
			moveConnection:Disconnect()
			endConnection:Disconnect()
		end
	end, {})

	local thumbSize = scrollState:map(function(state)
		local fraction = math.clamp(state.window / math.max(state.canvas, 1), style.MinThumbFraction, 1)
		return UDim2.fromScale(1, fraction)
	end)
	local thumbPosition = scrollState:map(function(state)
		local fraction = math.clamp(state.window / math.max(state.canvas, 1), style.MinThumbFraction, 1)
		local range = math.max(state.canvas - state.window, 0)
		local t = 0
		if range > 0 then
			t = math.clamp(state.pos / range, 0, 1)
		end
		return UDim2.fromScale(0, t * (1 - fraction))
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
			Size = UDim2.fromScale(windowFraction, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- CanvasSize scale resolves against the ScrollingFrame's PARENT (like Size),
			-- so X must be windowFraction to make the canvas match the window width.
			CanvasSize = props.canvasHeightScale and UDim2.fromScale(windowFraction, props.canvasHeightScale)
				or UDim2.fromScale(windowFraction, 0),
			AutomaticCanvasSize = props.canvasHeightScale and Enum.AutomaticSize.None or Enum.AutomaticSize.Y,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			ZIndex = zIndex,
			ref = scrollRef,
		}, props.children),
		Track = React.createElement("TextButton", {
			Name = "Track",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(barWidth, 1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = zIndex,
			ref = trackRef,
			[React.Event.InputBegan] = function(_, input: InputObject)
				if
					input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local frame = scrollRef.current
				local track = trackRef.current
				if not frame or not track then
					return
				end
				-- INSET-AGNOSTIC (2026-07-30). This was `GetMouseLocation() -
				-- GuiService:GetGuiInset()`, which silently assumed an INSET root
				-- ScreenGui. The root went FULL-BLEED so modal scrims could cover the
				-- whole screen (UiRoot), which would have thrown every track click off
				-- by the topbar height. `input.Position` is in the SAME space as
				-- AbsolutePosition in either mode (the convention HexTreeOverlay uses
				-- too), and it also picks up TOUCH — MouseButton1Down never fired for it.
				local relative = (input.Position.Y - track.AbsolutePosition.Y) / math.max(track.AbsoluteSize.Y, 1)
				local range = math.max(frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y, 0)
				frame.CanvasPosition = Vector2.new(0, math.clamp(relative, 0, 1) * range)
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
				Position = UDim2.fromScale(style.GrooveInset.X, style.GrooveInset.Y),
				Size = UDim2.fromScale(1 - style.GrooveInset.X * 2, 1 - style.GrooveInset.Y * 2),
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
				ZIndex = zIndex + 2,
				[React.Event.MouseButton1Down] = function()
					local frame = scrollRef.current
					if not frame then
						return
					end
					dragRef.current = { lastY = nil }
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
					Position = UDim2.fromScale(style.ThumbFaceInset.X, style.ThumbFaceInset.Y),
					Size = UDim2.fromScale(1 - style.ThumbFaceInset.X * 2, 1 - style.ThumbFaceInset.Y * 2),
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
		}),
	})
end

return ScrollPane
