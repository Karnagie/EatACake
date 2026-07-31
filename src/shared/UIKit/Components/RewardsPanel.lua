--[[
	RewardsPanel — landscape rewards window (the DAILY login track). Grid strip of
	DayCards + footer line. Archetype: "Daily rewards — landscape grid strip"
	(references/window-archetypes.md). It carried a second consumer, the
	playtime-today track, until time rewards were removed (2026-07-31); the props
	are still track-agnostic, so a future one needs no change here.

	props:
		title, size, visible, zIndex, onClose
		cards      -- ARRAY of { id, title, rewardText, iconName, subText, state }
		           -- (state: "claimable"|"claimed"|"locked"|"tomorrow")
		footerText -- bottom status line ("Come back tomorrow!")
		onClaim(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local OutlinedText = require(script.Parent.OutlinedText)
local DayCard = require(script.Parent.DayCard)

local function RewardsPanel(props)
	local layout = props.layout or Theme.RewardsLayout
	local cards = props.cards or {}

	local gridChildren = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromScale(layout.CellWidth, layout.CellHeight),
			CellPadding = UDim2.fromScale(layout.CellPaddingX, 0),
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = layout.Columns,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, card in ipairs(cards) do
		gridChildren[`Card{index}`] = React.createElement(DayCard, {
			id = card.id,
			title = card.title,
			rewardText = card.rewardText,
			iconName = card.iconName,
			subText = card.subText,
			state = card.state,
			layoutOrder = index,
			onActivated = props.onClaim,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "RewardsPanel",
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.HeaderWide,
		headerSize = UDim2.fromScale(1, layout.HeaderHeight),
	}, {
		Grid = React.createElement("Frame", {
			Name = "Grid",
			Position = UDim2.fromScale(layout.GridPosition.X, layout.GridPosition.Y),
			Size = UDim2.fromScale(layout.GridSize.X, layout.GridSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, gridChildren),
		Footer = React.createElement(OutlinedText, {
			text = props.footerText or "",
			position = UDim2.fromScale(layout.FooterPosition.X, layout.FooterPosition.Y),
			size = UDim2.fromScale(layout.FooterSize.X, layout.FooterSize.Y),
			textGradient = layout.FooterGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = 5,
		}),
	})
end

return RewardsPanel
