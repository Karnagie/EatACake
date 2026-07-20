local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function roundedFrame(name, position, size, color, cornerRadius, zIndex, gradient)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(cornerRadius, 0),
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
		Position = position,
		Size = size,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function PanelShell(props)
	local style = props.style or Theme.Panel
	local feel = Theme.Feel
	local visible = props.visible ~= false

	-- Open = springy pop from PanelClosedScale; close = quick shrink, THEN hide
	-- (so the shrink is visible). `shown` gates Visible; the panel stays mounted
	-- either way so the UIScale ref persists across open/close cycles.
	local scaleRef = React.useRef(nil)
	local shown, setShown = React.useState(visible)
	local firstRun = React.useRef(true)

	React.useEffect(function()
		local scale = scaleRef.current
		if firstRun.current then
			-- No entrance animation on first mount — just match the initial state.
			firstRun.current = false
			if scale then
				scale.Scale = if visible then 1 else feel.PanelClosedScale
			end
			setShown(visible)
			return
		end
		if visible then
			setShown(true)
			if scale then
				scale.Scale = feel.PanelClosedScale
				TweenService:Create(scale, feel.PanelOpenTween, { Scale = 1 }):Play()
			end
			return
		end
		if not scale then
			setShown(false)
			return
		end
		local tween = TweenService:Create(scale, feel.PanelCloseTween, { Scale = feel.PanelClosedScale })
		local connection
		connection = tween.Completed:Connect(function()
			connection:Disconnect()
			setShown(false)
		end)
		tween:Play()
		return function()
			connection:Disconnect()
		end
	end, { visible })

	local children = {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		OpenScale = React.createElement("UIScale", { ref = scaleRef }),
		BodyShadow = roundedFrame(
			"BodyShadow",
			UDim2.fromScale(style.ShadowPosition.X, style.ShadowPosition.Y),
			UDim2.fromScale(style.ShadowSize.X, style.ShadowSize.Y),
			Color3.new(1, 1, 1),
			style.ShadowCorner,
			1,
			style.ShadowGradient
		),
		BodyBorder = roundedFrame(
			"BodyBorder",
			UDim2.fromScale(style.BorderPosition.X, style.BorderPosition.Y),
			UDim2.fromScale(style.BorderSize.X, style.BorderSize.Y),
			Color3.new(1, 1, 1),
			style.BorderCorner,
			2,
			style.BorderGradient
		),
		BodyFill = roundedFrame(
			"BodyFill",
			UDim2.fromScale(style.FillPosition.X, style.FillPosition.Y),
			UDim2.fromScale(style.FillSize.X, style.FillSize.Y),
			Color3.new(1, 1, 1),
			style.FillCorner,
			3,
			style.FillGradient
		),
	}

	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	return React.createElement("Frame", {
		Name = props.name or "PanelWithHeader",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = shown,
		ZIndex = props.zIndex or 1,
	}, children)
end

return PanelShell
