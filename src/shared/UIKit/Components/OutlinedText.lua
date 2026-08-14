--[[ OutlinedText
	Sticker text: main label with a scaled UIStroke + ONE shadow copy offset
	down-left, also stroked. Replaces the old 8-clone outline — UIStroke with
	StrokeSizingMode.ScaledSize scales with TextScaled text, which is the only
	reason the clones ever existed.
	Legacy props (outlineMultiplier / outlineXMultiplier / outlineYMultiplier /
	outlineCenter) are accepted and IGNORED for backwards compatibility.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

-- Shadow copy offset (slight left + down = the kit's drop-shadow weight)
local OUTLINE_POSITION = UDim2.new(-0.003, 0, 0.1, 0)
local COPY_STROKE_THICKNESS = 0.06
local TEXT_STROKE_THICKNESS = 0.08

local function stroke(color, thickness, transparency)
	return React.createElement("UIStroke", {
		Color = color,
		LineJoinMode = Enum.LineJoinMode.Bevel,
		StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize,
		Thickness = thickness,
		Transparency = transparency or 0,
	})
end

local function labelProps(props, position, color, zIndex)
	return {
		AnchorPoint = Vector2.new(0, 0),
		Position = position,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.Font,
		Text = props.text,
		TextColor3 = color,
		TextScaled = true,
		-- Leaving this property UNSET preserves Roblox's established TextScaled
		-- behavior for every existing single-line label. Explicit false makes those
		-- labels stick near the default TextSize in Studio; only opt-in blocks wrap.
		TextWrapped = if props.textWrapped == true then true else nil,
		TextTransparency = props.transparency or 0,
		TextXAlignment = props.textXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex,
	}
end

local function OutlinedText(props)
	local outlineColor = props.outlineColor or Theme.Colors.TextOutline
	local strokeTransparency = props.disabled and 0.45 or 0

	local textChildren = {
		Stroke = stroke(outlineColor, TEXT_STROKE_THICKNESS, strokeTransparency),
	}
	if props.textGradient then
		textChildren.Gradient = React.createElement("UIGradient", {
			Color = props.textGradient,
			Rotation = 90,
		})
	end

	return React.createElement("Frame", {
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex or 1,
	}, {
		Outline = React.createElement("TextLabel", labelProps(
			props,
			OUTLINE_POSITION,
			outlineColor,
			props.zIndex or 1
		), {
			Stroke = stroke(outlineColor, COPY_STROKE_THICKNESS),
		}),
		Text = React.createElement("TextLabel", labelProps(
			props,
			UDim2.new(0, 0, 0, 0),
			props.textColor or (props.disabled and Theme.Colors.TextDisabled or Theme.Colors.Text),
			(props.zIndex or 1) + 1
		), textChildren),
	})
end

return OutlinedText
