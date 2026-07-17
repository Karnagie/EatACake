--[[ AnnounceBanner
	One-line gold announcement (HUD top-center, under the cake bar).
	Renders only while props.text is a non-empty string; nil/"" renders
	nothing. Auto-hide timing (Theme.AnnounceBanner.Duration) is the
	caller's job — this component is purely presentational. Style from
	Theme.AnnounceBanner (nominal 800x70).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function AnnounceBanner(props)
	local style = props.style or Theme.AnnounceBanner
	local zIndex = props.zIndex or 1
	local text = props.text

	if type(text) ~= "string" or text == "" then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "AnnounceBanner",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0),
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Label = React.createElement(OutlinedText, {
			text = text,
			position = UDim2.fromScale(0, 0),
			size = UDim2.fromScale(1, 1),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 1,
		}),
	})
end

return AnnounceBanner
