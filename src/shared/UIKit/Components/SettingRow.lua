local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)
local Toggle = require(script.Parent.Toggle)

local function SettingRow(props)
	local disabled = props.enabled == false

	local children = {
		Surface = React.createElement(Button, {
			name = "Surface",
			text = props.label,
			enabled = not disabled,
			size = UDim2.fromScale(1, 1),
			zIndex = 2,
			-- The label surface carries NO onActivated: only the knob toggles.
			-- Counting it separately is the point — a pile of these means
			-- players expect the whole row to be the switch.
			analyticsId = `Setting/{tostring(props.id or "unknown")}/Label`,
		}),
		Toggle = React.createElement(Toggle, {
			id = props.id,
			value = props.value,
			enabled = not disabled,
			onChanged = props.onChanged,
			zIndex = 9,
		}),
	}

	if disabled then
		children.DisabledFade = React.createElement("Frame", {
			Name = "DisabledFade",
			Position = UDim2.fromScale(0.02, 0.42),
			Size = UDim2.fromScale(0.96, 0.43),
			BackgroundColor3 = Theme.Colors.PanelLight,
			BackgroundTransparency = 0.52,
			BorderSizePixel = 0,
			ZIndex = 15,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0.22, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0.18),
				}),
			}),
		})
	end

	return React.createElement("CanvasGroup", {
		Name = props.id,
		Size = UDim2.fromScale(1, Theme.Layout.RowHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = disabled and 0.22 or 0,
		LayoutOrder = props.layoutOrder,
	}, children)
end

return SettingRow
