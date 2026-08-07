--[[ HexTreeOverlay
	Full-screen upgrades honeycomb (features/upgrades.md). One dim SCRIM is the
	single input surface: DRAG to pan, scroll / pinch / the +/- buttons to zoom,
	TAP to act (taps are hit-tested to the nearest hex — hexes are non-interactive
	visuals, so panning under them just works). A tapped tier opens a Detail card
	NEXT TO it (name / desc / green Buy button). Calories chip top-left, red X
	top-right, zoom buttons bottom-right. Category hexes carry a red "!" notifier
	when an affordable upgrade sits inside.

	The node model is built by the client (LocalUpgradeTree). Actions flow OUT
	through onNodeActivated(action): category tap → {open,id}, back → {back},
	Buy → {buy,id}. Tier focus + pan/zoom are overlay-local.

	Anything the player can buy RIGHT NOW BREATHES: a tier whose cost the current
	balance covers, and any category holding one (its "!" badge pulses on the same
	clock). The flag rides `node.pulse` from LocalUpgradeTree — deliberately a
	narrower set than the gold `available` hexes, which are merely unlocked.

	props: { name, visible, zIndex, treeKey, nodes, nodeWidth, nodeHeight,
		caloriesText, onNodeActivated(action), onClose }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local HexNode = require(script.Parent.HexNode)
local StatPill = require(script.Parent.StatPill)
local Button = require(script.Parent.Button)
local CloseButton = require(script.Parent.CloseButton)
local Interaction = require(script.Parent.Parent.Interaction)

local DRAG_THRESHOLD = 8 -- px of movement before a press counts as a pan (not a tap)

-- Detail card positioned next to a tapped tier. onRight flips it to the node's
-- left when the node is near the right edge.
local function detailCard(detail, onBuy, posX, posY, onRight, zIndex)
	local style = Theme.HexTree.Detail
	local children = {
		Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = style.AspectRatio }),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.OuterCorner, 0) }),
		Outer = React.createElement("UIGradient", { Color = style.OuterGradient, Rotation = 90 }),
		Face = React.createElement("Frame", {
			Name = "Face",
			Position = UDim2.fromScale(style.FaceInset.X, style.FaceInset.Y),
			Size = UDim2.fromScale(1 - style.FaceInset.X * 2, 1 - style.FaceInset.Y * 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.FaceCorner, 0) }),
			Gradient = React.createElement("UIGradient", { Color = style.FaceGradient, Rotation = 90 }),
		}),
		Title = React.createElement(OutlinedText, {
			text = detail.title,
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TitleGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 2,
		}),
		Desc = React.createElement("TextLabel", {
			Name = "Desc",
			Position = UDim2.fromScale(style.DescPosition.X, style.DescPosition.Y),
			Size = UDim2.fromScale(style.DescSize.X, style.DescSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			FontFace = Theme.Font,
			Text = detail.desc,
			TextColor3 = style.DescColor,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = zIndex + 2,
		}, {
			Constraint = React.createElement("UITextSizeConstraint", { MaxTextSize = 22 }),
		}),
	}
	if detail.state == "available" then
		children.Buy = React.createElement("Frame", {
			Name = "BuyZone",
			Position = UDim2.fromScale(style.BuyPosition.X, style.BuyPosition.Y),
			Size = UDim2.fromScale(style.BuySize.X, style.BuySize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = Theme.HexTree.BuyButton.AspectRatio }),
			Dim = React.createElement("CanvasGroup", {
				Name = "Dim",
				Size = UDim2.fromScale(1, 1),
				GroupTransparency = if detail.affordable then 0 else 0.5,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex + 3,
			}, {
				Button = React.createElement(Button, {
					name = "BuyButton",
					style = Theme.HexTree.BuyButton,
					text = detail.buyText or "Buy",
					textXAlignment = Enum.TextXAlignment.Center,
					enabled = detail.affordable == true,
					zIndex = zIndex + 3,
					onActivated = function()
						if detail.affordable and onBuy then
							onBuy()
						end
					end,
				}),
			}),
		})
	else
		children.Status = React.createElement(OutlinedText, {
			text = detail.statusLine or "",
			position = UDim2.fromScale(style.StatusPosition.X, style.StatusPosition.Y),
			size = UDim2.fromScale(style.StatusSize.X, style.StatusSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.StatusGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		})
	end

	return React.createElement("TextButton", {
		Name = "Detail",
		AnchorPoint = Vector2.new(if onRight then 0 else 1, 0.5),
		Position = UDim2.fromScale(posX, posY),
		Size = UDim2.fromScale(Theme.HexTree.DetailWidth, Theme.HexTree.DetailWidth),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		-- Active so taps/drags on the card body are inert (don't hit-test a hex
		-- behind it or pan the tree); the Buy button still works.
		Active = true,
		ZIndex = zIndex,
	}, children)
end

-- Red "!" notifier rendered in a TOP layer (above all hexes) at a node's
-- top-right corner, so neighbouring packed hexes can't cover it. World-space so
-- it pans/zooms with the tree. Size is square (the World is square).
--
-- A COMPONENT rather than a plain element builder because it owns a hook: the
-- badge marks a category holding an affordable upgrade, which is exactly when
-- that category's hex breathes — and a badge sitting perfectly still over a
-- moving hex reads as a detached sprite. It is not a child of the node (it lives
-- in the overlay's top layer), so it cannot inherit the node's UIScale and needs
-- its own on the same clock.
local function NotifierBadge(props)
	local n = Theme.HexTree.Notifier
	local cx, cy = props.cx, props.cy
	local nodeW, nodeH, zIndex = props.nodeW, props.nodeH, props.zIndex

	local pulse = props.pulse == true
	local pulseRef = React.useRef(nil)
	React.useEffect(function()
		local scale = pulseRef.current
		if scale == nil then
			return
		end
		local feel = Theme.HexTree.Pulse
		if not pulse then
			TweenService:Create(scale, feel.StopTween, { Scale = 1 }):Play()
			return
		end
		local tween = TweenService:Create(scale, feel.Tween, { Scale = feel.Scale })
		tween:Play()
		return function()
			tween:Cancel()
			local instance = pulseRef.current
			if instance then
				instance.Scale = 1
			end
		end
	end, { pulse })

	-- Placement comes from Theme (iron rule 2). `Center` is a fraction of the node
	-- box measured from its top-left, so it is converted to an offset from the
	-- node's CENTRE here; `Size` is a fraction of the node WIDTH on both axes so
	-- the badge stays circular inside the square World frame.
	return React.createElement("Frame", {
		Name = "Badge_" .. tostring(props.nodeKey),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx + nodeW * (n.Center.X - 0.5), cy + nodeH * (n.Center.Y - 0.5)),
		Size = UDim2.fromScale(nodeW * n.Size, nodeW * n.Size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		PulseScale = React.createElement("UIScale", { ref = pulseRef }),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Outer = React.createElement("UIGradient", { Color = n.OuterGradient, Rotation = 90 }),
		Face = React.createElement("Frame", {
			Name = "Face",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", { Color = n.FaceGradient, Rotation = 90 }),
			Mark = React.createElement(OutlinedText, {
				text = "!",
				position = UDim2.fromScale(0, 0),
				size = UDim2.fromScale(1, 1),
				textColor = Color3.new(1, 1, 1),
				textGradient = n.MarkGradient,
				outlineColor = n.Outline,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 2,
			}),
		}),
	})
end

local function zoomButton(text, center, onActivated, zIndex)
	return React.createElement("Frame", {
		Name = "Zoom_" .. text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(center.X, center.Y),
		Size = UDim2.fromScale(0.15, Theme.HexTree.ZoomButtonHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = 1 }),
		Button = React.createElement(Button, {
			name = "B",
			style = Theme.HexTree.ZoomButton,
			text = text,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex,
			onActivated = onActivated,
		}),
	})
end

local function HexTreeOverlay(props)
	local z = props.zIndex or 60
	local visible = props.visible == true
	local hx = Theme.HexTree
	local nodes = props.nodes or {}

	local focusedKey, setFocusedKey = React.useState(nil :: string?)
	local focus, setFocus = React.useState(nil) -- { x, y, onRight } screen frac of the card
	local zoom, setZoom = React.useBinding(1)
	local pan, setPan = React.useBinding(Vector2.new(0, 0))

	local overlayRef = React.useRef(nil)
	local viewportRef = React.useRef(nil)
	local inputs = React.useRef({}) -- [InputObject] = Vector2 pos
	local dragInput = React.useRef(nil)
	local lastPos = React.useRef(Vector2.zero)
	local startPos = React.useRef(Vector2.zero)
	local moved = React.useRef(false)
	local pinch = React.useRef(nil)

	-- Reset zoom/pan + focus when the tree changes or the overlay closes. Also
	-- clears input state so a leaked press (e.g. released off-window) can't
	-- wedge activeCount()/pinch/drag on the next open.
	React.useEffect(function()
		setZoom(1)
		setPan(Vector2.new(0, 0))
		setFocusedKey(nil)
		setFocus(nil)
		inputs.current = {}
		dragInput.current = nil
		pinch.current = nil
		moved.current = false
	end, { props.treeKey, visible })

	local function clampPan(p, zoomVal)
		local lim = math.max(0.12, zoomVal - 0.5)
		return Vector2.new(math.clamp(p.X, -lim, lim), math.clamp(p.Y, -lim, lim))
	end
	-- input.Position is already in GUI space (matches AbsolutePosition), so no
	-- inset conversion is needed.
	local function vpFrac(screen)
		local vp = viewportRef.current
		if not vp or vp.AbsoluteSize.X == 0 or vp.AbsoluteSize.Y == 0 then
			return 0.5, 0.5
		end
		return (screen.X - vp.AbsolutePosition.X) / vp.AbsoluteSize.X,
			(screen.Y - vp.AbsolutePosition.Y) / vp.AbsoluteSize.Y
	end
	local function zoomAround(newZoom, fx, fy)
		newZoom = math.clamp(newZoom, hx.MinZoom, hx.MaxZoom)
		local zv, p = zoom:getValue(), pan:getValue()
		local wfx = 0.5 + (fx - (0.5 + p.X)) / zv
		local wfy = 0.5 + (fy - (0.5 + p.Y)) / zv
		setZoom(newZoom)
		setPan(clampPan(Vector2.new(fx - 0.5 - (wfx - 0.5) * newZoom, fy - 0.5 - (wfy - 0.5) * newZoom), newZoom))
		-- The card is pinned to a screen point; zooming moves the hex under it, so
		-- dismiss it (no-op if already closed). Same for pan (onChanged) + buy.
		setFocusedKey(nil)
		setFocus(nil)
	end
	local function activeCount()
		local n = 0
		for _ in pairs(inputs.current) do
			n += 1
		end
		return n
	end
	local function twoPositions()
		local a, b
		for _, pos in pairs(inputs.current) do
			if a == nil then
				a = pos
			else
				b = pos
			end
		end
		return a, b
	end
	-- Resolve a tap position to the nearest hex; act on it.
	local function handleTap(screen)
		local vp = viewportRef.current
		if not vp then
			return
		end
		local zv, p = zoom:getValue(), pan:getValue()
		local best, bestDist
		for _, node in ipairs(nodes) do
			local nx = vp.AbsolutePosition.X + ((0.5 + p.X) + (node.cx - 0.5) * zv) * vp.AbsoluteSize.X
			local ny = vp.AbsolutePosition.Y + ((0.5 + p.Y) + (node.cy - 0.5) * zv) * vp.AbsoluteSize.Y
			local d = (screen - Vector2.new(nx, ny)).Magnitude
			if bestDist == nil or d < bestDist then
				bestDist, best = d, node
			end
		end
		if best == nil or bestDist > props.nodeHeight * zv * vp.AbsoluteSize.Y * 0.55 then
			setFocusedKey(nil) -- tapped empty space → dismiss the card
			setFocus(nil)
			return
		end
		-- Nodes are hit-tested through the pan surface rather than rendered as
		-- buttons, so `usePressable` never sees this press — cue it by hand, only
		-- once the tap has actually landed ON a node (empty space returned above).
		Interaction.Cue("press", `UpgradeTree/{best.kind}`)
		if best.kind == "category" or best.kind == "back" then
			setFocusedKey(nil)
			setFocus(nil)
			if props.onNodeActivated and best.action then
				props.onNodeActivated(best.action)
			end
		elseif best.kind == "tier" then
			if best.key == focusedKey then
				setFocusedKey(nil) -- tapping the open tier again dismisses the card
				setFocus(nil)
				return
			end
			setFocusedKey(best.key)
			local overlay = overlayRef.current
			if overlay and overlay.AbsoluteSize.X > 0 then
				local nx = vp.AbsolutePosition.X + ((0.5 + p.X) + (best.cx - 0.5) * zv) * vp.AbsoluteSize.X
				local ny = vp.AbsolutePosition.Y + ((0.5 + p.Y) + (best.cy - 0.5) * zv) * vp.AbsoluteSize.Y
				local ofx = (nx - overlay.AbsolutePosition.X) / overlay.AbsoluteSize.X
				local ofy = (ny - overlay.AbsolutePosition.Y) / overlay.AbsoluteSize.Y
				local onRight = ofx <= 0.6
				local gap = props.nodeWidth * zv * vp.AbsoluteSize.X / overlay.AbsoluteSize.X * 0.55 + 0.01
				setFocus({
					x = math.clamp(ofx + (if onRight then gap else -gap), 0.02, 0.98),
					y = math.clamp(ofy, 0.16, 0.84),
					onRight = onRight,
				})
			end
		end
	end

	local function toV2(p)
		return Vector2.new(p.X, p.Y)
	end
	local function onBegan(_, input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			inputs.current[input] = toV2(input.Position)
			local c = activeCount()
			if c == 1 then
				dragInput.current = input
				lastPos.current = toV2(input.Position)
				startPos.current = toV2(input.Position)
				moved.current = false
			elseif c == 2 then
				local a, b = twoPositions()
				pinch.current = { dist = (a - b).Magnitude, zoom = zoom:getValue() }
				dragInput.current = nil
			end
		end
	end
	local function onChanged(_, input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseWheel then
			local fx, fy = vpFrac(toV2(input.Position))
			zoomAround(zoom:getValue() * (if input.Position.Z > 0 then hx.ZoomStep else 1 / hx.ZoomStep), fx, fy)
			return
		end
		if t == Enum.UserInputType.Touch and inputs.current[input] then
			inputs.current[input] = toV2(input.Position)
		end
		if activeCount() >= 2 and pinch.current then
			local a, b = twoPositions()
			local fx, fy = vpFrac((a + b) / 2)
			if pinch.current.dist > 1 then
				zoomAround(pinch.current.zoom * (a - b).Magnitude / pinch.current.dist, fx, fy)
			end
			return
		end
		-- Single drag: a touch that IS the drag pointer, or mouse-move while the
		-- left button (the drag pointer) is down. (MouseMovement is a different
		-- InputObject than the MouseButton1 press — hence the type check.)
		local drag = dragInput.current
		local isDrag = (t == Enum.UserInputType.Touch and input == drag)
			or (t == Enum.UserInputType.MouseMovement and drag ~= nil and drag.UserInputType == Enum.UserInputType.MouseButton1)
		if not isDrag then
			return
		end
		local cur = toV2(input.Position)
		local delta = cur - lastPos.current
		lastPos.current = cur
		if (cur - startPos.current).Magnitude > DRAG_THRESHOLD then
			if not moved.current then
				setFocusedKey(nil) -- panning dismisses the card
				setFocus(nil)
			end
			moved.current = true
		end
		local vp = viewportRef.current
		if vp and vp.AbsoluteSize.X > 0 then
			local p = pan:getValue()
			setPan(clampPan(Vector2.new(p.X + delta.X / vp.AbsoluteSize.X, p.Y + delta.Y / vp.AbsoluteSize.Y), zoom:getValue()))
		end
	end
	-- Fires from UserInputService (global) so a release ANYWHERE — including over
	-- a higher-Z control, where GuiObject.InputEnded would never arrive — is
	-- reconciled. Only inputs that STARTED on the surface are tracked.
	local function onEnded(_, input)
		if inputs.current[input] == nil then
			return
		end
		local wasDrag = input == dragInput.current
		inputs.current[input] = nil
		local c = activeCount()
		if c < 2 then
			pinch.current = nil
		end
		if c == 1 then
			local remaining
			for i in pairs(inputs.current) do
				remaining = i
			end
			dragInput.current = remaining
			lastPos.current = inputs.current[remaining]
			startPos.current = inputs.current[remaining]
			moved.current = true -- pinch just ended: the trailing lift is NOT a tap
		elseif c == 0 then
			dragInput.current = nil
			if wasDrag and not moved.current then
				handleTap(toV2(input.Position))
			end
		end
	end

	-- Drag/pinch/end run on UserInputService (global) so moves/releases that
	-- leave the surface — over a higher-Z control, off-window, or an interrupted
	-- touch — are still caught (GuiObject.InputChanged/Ended aren't guaranteed
	-- there). onBegan stays on the surface so only presses on the TREE start a
	-- pan/tap. Refs feed the latest closures without reconnecting each render.
	local changedRef = React.useRef(nil)
	local endedRef = React.useRef(nil)
	changedRef.current = onChanged
	endedRef.current = onEnded
	React.useEffect(function()
		if not visible then
			return
		end
		local c1 = UserInputService.InputChanged:Connect(function(input)
			changedRef.current(nil, input)
		end)
		local c2 = UserInputService.InputEnded:Connect(function(input)
			endedRef.current(nil, input)
		end)
		return function()
			c1:Disconnect()
			c2:Disconnect()
		end
	end, { visible })

	-- ── nodes (inside the pan/zoom World) ────────────────────────────────
	-- Hexes first (z+2), then any "!" notifiers in a TOP pass (z+6) so packed
	-- neighbours never cover a badge.
	local worldChildren = {}
	local focusedDetail = nil
	for _, node in ipairs(nodes) do
		if node.key == focusedKey and node.detail then
			focusedDetail = node.detail
		end
		worldChildren[`Node_{node.key}`] = React.createElement(HexNode, {
			name = `Node_{node.key}`,
			position = UDim2.fromScale(node.cx, node.cy),
			size = UDim2.fromScale(props.nodeWidth, props.nodeHeight),
			state = node.state,
			icon = node.icon,
			title = node.title,
			status = node.status,
			-- "Affordable right now" (LocalUpgradeTree). NOT the gold `available`
			-- state — gold only means the tier is unlocked and priced.
			pulse = node.pulse == true,
			zIndex = z + 2,
		})
	end
	for _, node in ipairs(nodes) do
		if node.badge then
			worldChildren[`Badge_{node.key}`] = React.createElement(NotifierBadge, {
				nodeKey = node.key,
				cx = node.cx,
				cy = node.cy,
				nodeW = props.nodeWidth,
				nodeH = props.nodeHeight,
				-- A badge is only ever drawn for a category that HOLDS an affordable
				-- upgrade, so it breathes with its hex rather than sitting still on a
				-- moving one.
				pulse = node.pulse == true,
				zIndex = z + 6,
			})
		end
	end

	local overlayChildren = {
		-- Dim behind the tree.
		Scrim = React.createElement("Frame", {
			Name = "Scrim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = hx.ScrimColor,
			BackgroundTransparency = hx.ScrimTransparency,
			BorderSizePixel = 0,
			ZIndex = z,
		}),
		-- The single input surface: a TRANSPARENT full-screen Active button ABOVE
		-- the (non-interactive) hexes but BELOW the controls, so every pan / zoom /
		-- tap reliably lands here (input over a non-active child doesn't fall
		-- through consistently — this catches it). Taps hit-test to a hex.
		InputSurface = React.createElement("TextButton", {
			Name = "InputSurface",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			ZIndex = z + 7,
			-- Only the press-start is detected here (so a press must begin on the
			-- tree). Move/end are on UserInputService (above) for reliability.
			[React.Event.InputBegan] = onBegan,
		}),
		-- Clip only at the SCREEN edges (full-screen), so panning the tree doesn't
		-- cut it off at a small window. The Viewport is the SQUARE coordinate
		-- reference (does not itself clip); the World overflows it freely.
		Clip = React.createElement("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = z + 1,
		}, {
			Viewport = React.createElement("Frame", {
				Name = "Viewport",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(hx.CanvasCenter.X, hx.CanvasCenter.Y),
				Size = UDim2.fromScale(hx.CanvasMaxViewportFraction, hx.CanvasMaxViewportFraction),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = false,
				ZIndex = z + 1,
				ref = viewportRef,
			}, {
				Ratio = React.createElement("UIAspectRatioConstraint", { AspectRatio = 1 }),
				World = React.createElement("Frame", {
					Name = "World",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = pan:map(function(p)
						return UDim2.fromScale(0.5 + p.X, 0.5 + p.Y)
					end),
					Size = zoom:map(function(zv)
						return UDim2.fromScale(zv, zv)
					end),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = z + 1,
				}, worldChildren),
			}),
		}),
		Currency = React.createElement("Frame", {
			Name = "Currency",
			Position = UDim2.fromScale(hx.CurrencyPosition.X, hx.CurrencyPosition.Y),
			Size = UDim2.fromScale(0.5, hx.CurrencyHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true, -- sink input so a drag from the chip doesn't pan the tree
			ZIndex = z + 8,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = Theme.Hud.PillAspect }),
			Pill = React.createElement(StatPill, {
				value = props.caloriesText or "0",
				icon = "bolt",
				valueGradient = Theme.Hud.EnergyTextGradient,
				valueOutline = Theme.Hud.EnergyTextOutline,
				zIndex = z + 8,
			}),
		}),
		Close = React.createElement("Frame", {
			Name = "Close",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(hx.CloseCenter.X, hx.CloseCenter.Y),
			Size = UDim2.fromScale(0.2, hx.CloseHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = z + 8,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = 1 }),
			Button = React.createElement(CloseButton, {
				onActivated = function()
					if props.onClose then
						props.onClose()
					end
				end,
			}),
		}),
		ZoomIn = zoomButton("+", hx.ZoomInCenter, function()
			zoomAround(zoom:getValue() * hx.ZoomStep, 0.5, 0.5)
		end, z + 8),
		ZoomOut = zoomButton("-", hx.ZoomOutCenter, function()
			zoomAround(zoom:getValue() / hx.ZoomStep, 0.5, 0.5)
		end, z + 8),
		Reset = zoomButton("1x", hx.ResetCenter, function()
			setZoom(1)
			setPan(Vector2.new(0, 0))
		end, z + 8),
	}
	if focusedDetail and focus then
		overlayChildren.DetailCard = detailCard(focusedDetail, function()
			for _, node in ipairs(nodes) do
				if node.key == focusedKey and node.statId and props.onNodeActivated then
					props.onNodeActivated({ type = "buy", id = node.statId })
				end
			end
			-- Buying grows the stat's tier count → the tree reflows, so the pinned
			-- card would detach; dismiss it (tap the new tier to continue buying).
			setFocusedKey(nil)
			setFocus(nil)
		end, focus.x, focus.y, focus.onRight, z + 10)
	end

	return React.createElement("Frame", {
		Name = props.name or "HexTreeOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = visible,
		ZIndex = z,
		ref = overlayRef,
	}, overlayChildren)
end

return HexTreeOverlay
