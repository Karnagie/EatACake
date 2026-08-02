--[[ HintArrow
	Screen-space objective pointer that tracks a WORLD position:
	  * target on screen  -> bobs above it, pointing straight down
	  * target off screen -> pins to the padded viewport edge and rotates to
	                         point at it (the standard objective marker)
	with a chip label underneath. Used by the tutorial to point at the upgrades
	computer (features/tutorial.md, step 4).

	MOTION OWNERSHIP (ADR-0006, ADR-0016). The marker is repositioned every
	frame, so it CANNOT be a React prop: pushing 60 Hz screen coordinates
	through `AppRoot.Set` would reconcile the whole App — including the shop's
	~700-element tree — once per frame. Instead React writes `Position`,
	`Rotation` and `Visible` exactly ONCE with the constants below and then
	diffs them away forever; a `RunService.RenderStepped` connection owned by
	this component's `useEffect` writes them thereafter. Same invariant as the
	press `UIScale` and `Interaction.ZeroFill`, one property class wider.

	The connection lives and dies with `visible`, so a hidden arrow costs
	nothing. `getTarget` is read through a ref — the caller may pass a fresh
	closure every render without reconnecting anything.

	⚠ Coordinates are VIEWPORT coordinates (`WorldToViewportPoint`), which is
	the space of a FULL-BLEED ScreenGui — which is what UiRoot renders into.
	Pairing them with an inset gui would drift everything down by the topbar.

	Props: {
		visible: boolean,
		getTarget: () -> Vector3?,   -- nil = nothing to point at (arrow hides)
		labelText: string?,
		zIndex: number? (45), style: table? (Theme.TutorialArrow), name: string?
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

-- The ONE value React ever writes for each loop-owned property (ADR-0006).
-- Off-screen + hidden, so a frame between mount and the first RenderStepped
-- never flashes an arrow in the corner.
local PARKED = UDim2.fromScale(-1, -1)
local START_HIDDEN = false

local TWO_PI = math.pi * 2

local function HintArrow(props)
	local style = props.style or Theme.TutorialArrow
	local zIndex = props.zIndex or 45
	local visible = props.visible == true

	local arrowRef = React.useRef(nil)
	local labelRef = React.useRef(nil)
	local targetRef = React.useRef(nil)
	targetRef.current = props.getTarget

	React.useEffect(function()
		if not visible then
			return
		end
		local connection = RunService.RenderStepped:Connect(function()
			local arrow, label = arrowRef.current, labelRef.current
			if arrow == nil then
				return
			end
			local camera = Workspace.CurrentCamera
			local getTarget = targetRef.current
			local target = if camera ~= nil and getTarget ~= nil then getTarget() else nil
			if camera == nil or typeof(target) ~= "Vector3" then
				-- Nothing to point at (target not replicated yet, or gone).
				arrow.Visible = false
				if label then
					label.Visible = false
				end
				return
			end

			local viewport = camera.ViewportSize
			if viewport.X <= 0 or viewport.Y <= 0 then
				return
			end
			local point = camera:WorldToViewportPoint(target)
			-- Z < 0 means BEHIND the camera, where the projection is MIRRORED
			-- through the viewport centre. Flipping recovers the correct
			-- DIRECTION — but not a usable magnitude: a target straight behind
			-- maps onto the centre itself, so the flip is a no-op there.
			local px, py = point.X, point.Y
			local behind = point.Z <= 0
			if behind then
				px, py = viewport.X - px, viewport.Y - py
			end

			local pad = style.EdgePadding
			local sx, sy = px / viewport.X, py / viewport.Y
			local onScreen = not behind and sx >= pad and sx <= 1 - pad and sy >= pad and sy <= 1 - pad

			local ax, ay, rotation
			if onScreen then
				-- Float above the target, pointing DOWN at it (the arrow art
				-- points +X at rotation 0; GuiObject.Rotation is clockwise).
				local bob = math.sin(os.clock() * TWO_PI / style.BobPeriod) * style.BobAmplitude
				ax = sx
				ay = math.max(pad, sy - style.OnScreenLift + bob)
				rotation = 90
			else
				-- Pin to the padded rect by pushing the point OUT along its own
				-- direction until it meets the boundary — not by clamping each
				-- axis. Clamping leaves an interior point where it is, which is
				-- exactly the behind-the-camera case above: the arrow would
				-- park mid-screen over the gameplay view instead of pointing
				-- back over the player's shoulder.
				-- ⚠ Everything here is PIXEL space. Taking the angle from
				-- viewport FRACTIONS scales x and y by different lengths, and
				-- the resulting arrow misses the target by up to ~20° on a wide
				-- viewport (worst near the diagonals).
				local cx, cy = viewport.X / 2, viewport.Y / 2
				local dx, dy = px - cx, py - cy
				if math.abs(dx) < 1 and math.abs(dy) < 1 then
					dx, dy = 0, 1 -- degenerate (straight behind): pin below
				end
				local halfW = math.max(cx - pad * viewport.X, 1)
				local halfH = math.max(cy - pad * viewport.Y, 1)
				local reach = math.max(math.abs(dx) / halfW, math.abs(dy) / halfH)
				if reach > 0 then
					dx, dy = dx / reach, dy / reach
				end
				ax = (cx + dx) / viewport.X
				ay = (cy + dy) / viewport.Y
				rotation = math.deg(math.atan2(dy, dx))
			end

			arrow.Visible = true
			arrow.Position = UDim2.fromScale(ax, ay)
			arrow.Rotation = rotation
			if label then
				label.Visible = true
				label.Position = UDim2.fromScale(ax, ay + style.LabelOffset)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { visible })

	if not visible then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "HintArrow",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		-- Never intercept input: the player is walking to the thing it points at.
		Active = false,
		ZIndex = zIndex,
	}, {
		Arrow = React.createElement("ImageLabel", {
			Name = "Arrow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = PARKED, -- constant; the RenderStepped loop owns it
			Visible = START_HIDDEN, -- constant; ditto
			Size = UDim2.fromScale(0.4, style.ArrowHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(style.ArrowIcon),
			ImageColor3 = style.ArrowColor,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 1,
			ref = arrowRef,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = style.ArrowAspect,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
		}),
		Label = if props.labelText ~= nil and props.labelText ~= ""
			then React.createElement("Frame", {
				Name = "Label",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = PARKED,
				Visible = START_HIDDEN,
				Size = UDim2.fromScale(0.5, style.LabelHeight),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 1,
				ref = labelRef,
			}, {
				Aspect = React.createElement("UIAspectRatioConstraint", {
					AspectRatio = style.LabelAspect,
					AspectType = Enum.AspectType.FitWithinMaxSize,
				}),
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = React.createElement("UIGradient", {
					Color = style.LabelOuterGradient,
					Rotation = 90,
				}),
				Face = React.createElement("Frame", {
					Name = "Face",
					Position = UDim2.fromScale(style.LabelFaceInset.X, style.LabelFaceInset.Y),
					Size = UDim2.fromScale(1 - style.LabelFaceInset.X * 2, 1 - style.LabelFaceInset.Y * 2),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					ZIndex = zIndex + 2,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Gradient = React.createElement("UIGradient", {
						Color = style.LabelFaceGradient,
						Rotation = 90,
					}),
				}),
				Text = React.createElement(OutlinedText, {
					text = props.labelText,
					position = UDim2.fromScale(0.06, 0.14),
					size = UDim2.fromScale(0.88, 0.72),
					textColor = Color3.new(1, 1, 1),
					textGradient = style.LabelTextGradient,
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex + 3,
				}),
			})
			else nil,
	})
end

return HintArrow
