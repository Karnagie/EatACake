--[[
	TextInput — kit-styled single-line text field (dark well + light groove).

	props:
		value        -- controlled text
		placeholder
		maxLength    -- clamp (default 32)
		enabled
		onChanged(text), onSubmit(text) -- Enter/return
		name, position, size, zIndex
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)

local function TextInput(props)
	local style = props.style or Theme.TextInput
	local zIndex = props.zIndex or 5
	local enabled = props.enabled ~= false
	local maxLength = props.maxLength or 32

	return React.createElement("Frame", {
		Name = props.name or "TextInput",
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.OuterCorner, 0) }),
		Gradient = React.createElement("UIGradient", { Color = style.OuterGradient, Rotation = 90 }),
		Groove = React.createElement("Frame", {
			Name = "Groove",
			Position = UDim2.fromScale(style.GroovePosition.X, style.GroovePosition.Y),
			Size = UDim2.fromScale(style.GrooveSize.X, style.GrooveSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(style.GrooveCorner, 0) }),
			Gradient = React.createElement("UIGradient", { Color = style.GrooveGradient, Rotation = 90 }),
			Box = React.createElement("TextBox", {
				Name = "Box",
				Position = UDim2.fromScale(style.TextPosition.X - style.GroovePosition.X, 0),
				Size = UDim2.fromScale(style.TextSize.X / style.GrooveSize.X, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = props.value or "",
				PlaceholderText = props.placeholder or "",
				TextColor3 = style.TextColor,
				PlaceholderColor3 = style.PlaceholderColor,
				FontFace = Theme.Font,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false,
				TextEditable = enabled,
				ZIndex = zIndex + 2,
				[React.Change.Text] = function(box)
					local text = box.Text
					if #text > maxLength then
						text = string.sub(text, 1, maxLength)
						box.Text = text
					end
					if props.onChanged then
						props.onChanged(text)
					end
				end,
				[React.Event.FocusLost] = function(box, enterPressed)
					if enterPressed and props.onSubmit then
						props.onSubmit(box.Text)
					end
				end,
			}),
		}),
	})
end

return TextInput
