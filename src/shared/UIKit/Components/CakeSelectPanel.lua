--[[
	CakeSelectPanel — the cake chooser (features/cake-select.md).

	Archetype: the "teleport / worlds" window — a set of LARGE cards, each an art
	plate + a name + an unlock requirement, unavailable ones dimmed under a badge.
	Landscape 1000x600 on Theme.PanelWide / Theme.HeaderWide.

	A BROWSABLE GALLERY: a 3-column grid in the kit's ScrollPane. The catalogue
	grows — it already carries a "coming soon" slot whose entire job is to say so
	— and three columns filling 870 of the 904 pane is what makes the CAKES the
	subject of the panel rather than the margins around them.

	⚠ Grid math is DETERMINISTIC (patterns.md): rows -> canvasHeightScale, cell
	height as a fraction of that canvas, `FillDirectionMaxCells` always set. Never
	AutomaticCanvasSize with scale-sized cells, and never an aspect constraint
	relied on for cell HEIGHT — both collapse grid cells to 1x1.

	⚠ Each grid child is a transparent CELL WRAPPER and the card fills only
	`CardHeightInCell` of it. The leftover IS the row gap: UIGridLayout's own Y
	padding would fight the deterministic canvas height.

	⚠ ScrollPane hides its track when the canvas provably fits, so a single row of
	cakes shows NO scrollbar by design (a thumb that cannot move advertises
	content that is not there). It appears by itself at the 4th cake.

	props:
		name, title, visible, size, zIndex, layout
		cakes = { { id, label, iconName, accent, selected, locked, comingSoon, statusText } }
		onSelect(id), onClose
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local ScrollPane = require(script.Parent.ScrollPane)
local CakeCard = require(script.Parent.CakeCard)

local function CakeSelectPanel(props)
	local layout = props.layout or Theme.CakeSelectLayout
	local zIndex = props.contentZIndex or layout.ContentZIndex
	local cakes = props.cakes or {}

	local rows = math.max(math.ceil(#cakes / layout.Columns), 1)
	local canvasHeightScale = math.max(rows * layout.CellHeightWithGap, 1)

	local cells = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromScale(layout.CellWidth, layout.CellHeightWithGap / canvasHeightScale),
			CellPadding = UDim2.fromScale(layout.CellPaddingX, 0),
			FillDirection = Enum.FillDirection.Horizontal,
			-- ALWAYS explicit: an exact-fit grid can wrap its last cell on float
			-- rounding without it (kit pitfall 6).
			FillDirectionMaxCells = layout.Columns,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, cake in ipairs(cakes) do
		cells[`Cell_{tostring(cake.id)}`] = React.createElement("Frame", {
			Name = `Cell_{tostring(cake.id)}`,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = zIndex,
		}, {
			Card = React.createElement(CakeCard, {
				name = `CakeCard_{tostring(cake.id)}`,
				id = cake.id,
				label = cake.label,
				iconName = cake.iconName,
				accent = cake.accent,
				statusText = cake.statusText,
				selected = cake.selected,
				locked = cake.locked,
				comingSoon = cake.comingSoon,
				size = UDim2.fromScale(1, layout.CardHeightInCell),
				zIndex = zIndex,
				onActivated = props.onSelect,
			}),
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "CakeSelectPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "",
		onClose = props.onClose,
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.HeaderWide,
		headerSize = UDim2.fromScale(1, layout.HeaderHeight),
		zIndex = props.zIndex,
	}, {
		Grid = React.createElement(ScrollPane, {
			name = "CakeGrid",
			position = UDim2.fromScale(layout.GridPosition.X, layout.GridPosition.Y),
			size = UDim2.fromScale(layout.GridSize.X, layout.GridSize.Y),
			windowFraction = layout.ScrollWindowFraction,
			barWidth = layout.ScrollBarWidth,
			canvasHeightScale = canvasHeightScale,
			zIndex = zIndex,
		}, cells),
	})
end

return CakeSelectPanel
