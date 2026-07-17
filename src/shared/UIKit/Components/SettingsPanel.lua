local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local SettingRow = require(script.Parent.SettingRow)

local DEFAULT_ROWS = {
	{ id = "Shadows", label = "Shadows", enabled = true },
	{ id = "Music", label = "Music", enabled = true },
	{ id = "Weather", label = "Weather", enabled = true },
	{ id = "Players", label = "Players", enabled = true },
	{ id = "Invites", label = "Invites", enabled = true },
}

local function SettingsPanel(props)
	local rows = props.rows or DEFAULT_ROWS
	local values = props.values or {}

	local rowChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(Theme.Layout.RowGap, 0),
		}),
	}

	for index, row in ipairs(rows) do
		rowChildren[row.id] = React.createElement(SettingRow, {
			id = row.id,
			label = row.label,
			value = values[row.id],
			enabled = row.enabled,
			layoutOrder = index,
			onChanged = function(value)
				if props.onToggle then
					props.onToggle(row.id, value)
				end
			end,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = "SettingsPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "Settings",
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, {
		Rows = React.createElement("Frame", {
			Name = "Rows",
			Position = UDim2.fromScale(
				Theme.Layout.RowsPosition.X,
				Theme.Layout.RowsPosition.Y
			),
			Size = UDim2.fromScale(
				Theme.Layout.RowsSize.X,
				Theme.Layout.RowsSize.Y
			),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, rowChildren),
	})
end

return SettingsPanel
