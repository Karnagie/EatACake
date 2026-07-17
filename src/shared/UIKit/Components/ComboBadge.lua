--[[ ComboBadge
	Text-only combo counter "x{combo}" (HUD, right of center). Gradient
	switches blue (LowGradient) -> gold (HighGradient) when intensity01
	passes 0.5. Pulses (UIScale up by PulseScale for PulseTime) every time
	combo changes. Hidden entirely when props.visible is false. Style from
	Theme.ComboBadge (nominal 160x90).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function ComboBadge(props)
	local style = props.style or Theme.ComboBadge
	local zIndex = props.zIndex or 1
	local combo = props.combo or 0
	local intensity01 = props.intensity01 or 0

	local pulsing, setPulsing = React.useState(false)
	local mountedRef = React.useRef(false)

	-- Pulse on combo CHANGE (skip the mount run); guard the delayed
	-- setState against unmount/re-trigger via the cleanup flag.
	React.useEffect(function()
		if not mountedRef.current then
			mountedRef.current = true
			return
		end
		local alive = true
		setPulsing(true)
		task.delay(style.PulseTime, function()
			if alive then
				setPulsing(false)
			end
		end)
		return function()
			alive = false
		end
	end, { combo })

	-- After hooks (hook order must not change between renders)
	if props.visible == false then
		return nil
	end

	local textGradient = intensity01 > 0.5 and style.HighGradient or style.LowGradient
	local pulseScale = pulsing and (1 + style.PulseScale) or 1

	return React.createElement("Frame", {
		Name = props.name or "ComboBadge",
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
		Pulse = React.createElement("UIScale", { Scale = pulseScale }),
		Label = React.createElement(OutlinedText, {
			text = `x{combo}`,
			position = UDim2.fromScale(0, (1 - style.TextHeight) * 0.5),
			size = UDim2.fromScale(1, style.TextHeight),
			textColor = Color3.new(1, 1, 1),
			textGradient = textGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 1,
		}),
	})
end

return ComboBadge
