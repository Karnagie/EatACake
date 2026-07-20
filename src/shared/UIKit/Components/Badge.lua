--[[ Badge — green notification dot (ring + gradient fill). Pops in (UIScale
	0 -> 1, springy) whenever it becomes visible, so a newly-available
	notification draws the eye instead of blinking in. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function Badge(props)
	local style = props.style or Theme.Badge
	local zIndex = props.zIndex or 60
	local visible = props.visible ~= false

	-- Hooks run before the early-return (Rules of Hooks). The frame + UIScale
	-- only exist while visible, so the ref is populated exactly when the pop
	-- should play (visible flips true -> ref attached -> this effect fires).
	local scaleRef = React.useRef(nil)
	-- Layout effect (pre-paint) so Scale is 0 before the first frame renders —
	-- no flash of the full-size badge before the pop.
	React.useLayoutEffect(function()
		local scale = scaleRef.current
		if not scale then
			return
		end
		scale.Scale = 0
		TweenService:Create(scale, Theme.Feel.BadgePopTween, { Scale = 1 }):Play()
	end, { visible })

	if not visible then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "Badge",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Pop = React.createElement("UIScale", { ref = scaleRef }),
		Ring = React.createElement("Frame", {
			Name = "Ring",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = style.RingColor,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
		Fill = React.createElement("Frame", {
			Name = "Fill",
			Position = UDim2.fromScale(style.FillPosition.X, style.FillPosition.Y),
			Size = UDim2.fromScale(style.FillSize.X, style.FillSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.FillGradient,
				Rotation = 90,
			}),
		}),
	})
end

return Badge
