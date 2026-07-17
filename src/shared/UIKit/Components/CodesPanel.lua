--[[
	CodesPanel — small centered dialog (Promo-codes archetype): kit TextBox +
	submit button + status line.

	props:
		title, size, visible, zIndex, onClose
		value, onChanged(text)      -- controlled input
		submitText, onSubmit(text)
		statusText, statusKind      -- "ok" | "error" | nil (hides)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local TextInput = require(script.Parent.TextInput)
local OutlinedText = require(script.Parent.OutlinedText)

local function CodesPanel(props)
	local layout = props.layout or Theme.CodesLayout

	return React.createElement(PanelWithHeader, {
		name = props.name or "CodesPanel",
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, {
		Input = React.createElement(TextInput, {
			name = "CodeInput",
			position = UDim2.fromScale(layout.InputPosition.X, layout.InputPosition.Y),
			size = UDim2.fromScale(layout.InputSize.X, layout.InputSize.Y),
			value = props.value,
			placeholder = props.placeholder,
			onChanged = props.onChanged,
			onSubmit = props.onSubmit,
			zIndex = 5,
		}),
		Submit = React.createElement(Button, {
			name = "SubmitButton",
			style = Theme.EquipGreen,
			position = UDim2.fromScale(layout.ButtonPosition.X, layout.ButtonPosition.Y),
			size = UDim2.fromScale(layout.ButtonSize.X, layout.ButtonSize.Y),
			text = props.submitText or "",
			enabled = (props.value or "") ~= "",
			zIndex = 5,
			onActivated = function()
				if props.onSubmit then
					props.onSubmit(props.value or "")
				end
			end,
		}),
		Status = if props.statusText ~= nil and props.statusText ~= ""
			then React.createElement(OutlinedText, {
				text = props.statusText,
				position = UDim2.fromScale(layout.StatusPosition.X, layout.StatusPosition.Y),
				size = UDim2.fromScale(layout.StatusSize.X, layout.StatusSize.Y),
				textGradient = if props.statusKind == "ok" then layout.StatusOkGradient else layout.StatusErrorGradient,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = 5,
			})
			else nil,
	})
end

return CodesPanel
