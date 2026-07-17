--[[
	UpgradesPanel — portrait Upgrades window (vertical row-list archetype):
	PanelWithHeader + fixed vertical UIListLayout of UpgradeRow
	(6 rows fit the zone, no scroll: 6*92-cell = 552 <= 563).

	props:
		name?, title, visible, size, zIndex, onClose
		rows      -- ARRAY of UpgradeRow prop tables
		             ({ id, label, subText, buttonText, state })
		onBuy(id) -- forwarded to every row
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Log = require(ReplicatedStorage.Shared.Log)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local UpgradeRow = require(script.Parent.UpgradeRow)

local function UpgradesPanel(props)
	local layout = props.layout or Theme.UpgradesLayout
	local rows = props.rows or {}

	-- NO UIListLayout Padding: the 10px vertical gap is baked into each
	-- cell's aspect (Theme.UpgradeRow.CellAspectRatio, ShopPanel pattern).
	local rowChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Explicit cell height: content RowHeight expanded to the gap-baked cell
	-- (RowHeight / ContentHeightInCell = 92/563) — (1, 0) + aspect collapses
	-- to zero height in a plain frame (kit pitfall).
	local cellHeight = layout.RowHeight / Theme.UpgradeRow.ContentHeightInCell
	-- No scroll in this window: rows beyond the zone silently overflow —
	-- warn once so a 7th upgrade never degrades silently (R8).
	local maxRows = math.floor(1 / cellHeight)
	if #rows > maxRows then
		Log.Once("UpgradesPanel", "overflow", `{#rows} rows but the zone fits {maxRows} — extra rows overflow; add a ScrollPane`)
	end
	for index, row in ipairs(rows) do
		rowChildren[`Row_{tostring(row.id)}`] = React.createElement(UpgradeRow, {
			id = row.id,
			label = row.label,
			subText = row.subText,
			buttonText = row.buttonText,
			state = row.state,
			size = UDim2.fromScale(1, cellHeight),
			layoutOrder = index,
			onBuy = props.onBuy,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "UpgradesPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "Upgrades",
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, {
		Rows = React.createElement("Frame", {
			Name = "Rows",
			Position = UDim2.fromScale(layout.ListPosition.X, layout.ListPosition.Y),
			Size = UDim2.fromScale(layout.ListSize.X, layout.ListSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, rowChildren),
	})
end

return UpgradesPanel
