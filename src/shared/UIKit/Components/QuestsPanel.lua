--[[
	QuestsPanel — portrait Quests window (vertical row-list archetype):
	PanelWithHeader + fixed vertical UIListLayout of QuestRow
	(3 rows fit the zone, no scroll: 3*96 + 2*10 = 308 <= 563; each
	106-cell bakes its own 10px gap).

	props:
		name?, title, visible, size, zIndex?, onClose
		quests      -- ARRAY of QuestRow prop tables ({ id, name, progress01,
		               progressText, rewardText, buttonText, state })
		onClaim(id) -- forwarded to every row
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Log = require(ReplicatedStorage.Shared.Log)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local QuestRow = require(script.Parent.QuestRow)

local function QuestsPanel(props)
	local layout = props.layout or Theme.QuestsLayout
	local quests = props.quests or {}

	-- NO UIListLayout Padding: the 10px vertical gap is baked into each
	-- cell's aspect (Theme.QuestRow.CellAspectRatio, ShopPanel pattern).
	local rowChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	-- Explicit cell height (RowHeight / ContentHeightInCell = 106/563):
	-- (1, 0) + aspect collapses to zero in a plain frame (kit pitfall).
	local cellHeight = layout.RowHeight / Theme.QuestRow.ContentHeightInCell
	-- No scroll in this window (R8: overflow must not be silent).
	local maxRows = math.floor(1 / cellHeight)
	if #quests > maxRows then
		Log.Once("QuestsPanel", "overflow", `{#quests} quests but the zone fits {maxRows} — extra rows overflow; add a ScrollPane`)
	end
	for index, quest in ipairs(quests) do
		rowChildren[`Quest_{tostring(quest.id)}`] = React.createElement(QuestRow, {
			id = quest.id,
			name = quest.name,
			progress01 = quest.progress01,
			progressText = quest.progressText,
			rewardText = quest.rewardText,
			buttonText = quest.buttonText,
			state = quest.state,
			size = UDim2.fromScale(1, cellHeight),
			layoutOrder = index,
			onClaim = props.onClaim,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "QuestsPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "Quests",
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

return QuestsPanel
