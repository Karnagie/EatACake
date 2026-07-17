--[[
	ShopPanel — portrait vertical sectioned list (Shop archetype).

	props:
		title, size, visible, zIndex, onClose
		sections -- ARRAY of { title, rows = ARRAY of ShopRow props
		            ({ id, label, subText, buttonText, owned, buttonStyle }) }
		onActivated(id) -- forwarded to every row
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local ScrollPane = require(script.Parent.ScrollPane)
local OutlinedText = require(script.Parent.OutlinedText)
local ShopRow = require(script.Parent.ShopRow)

local function ShopPanel(props)
	local layout = props.layout or Theme.ShopLayout
	local sections = props.sections or {}

	-- NO scale Padding here: inside an AutomaticCanvasSize ScrollPane, scale
	-- padding references the GROWING canvas (kit pitfall). Gaps are baked
	-- into each cell's aspect (rows: Theme.ShopRow.CellAspectRatio, section
	-- headers: layout.SectionCellAspect).
	local listChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local order = 0
	for sectionIndex, section in ipairs(sections) do
		if #section.rows == 0 then
			continue
		end
		order += 1
		listChildren[`Section{sectionIndex}`] = React.createElement("Frame", {
			Name = `Section{sectionIndex}`,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = order,
			ZIndex = 5,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = layout.SectionCellAspect,
			}),
			Title = React.createElement(OutlinedText, {
				text = section.title or "",
				size = UDim2.fromScale(1, layout.SectionContentHeight),
				textGradient = layout.SectionGradient,
				textXAlignment = Enum.TextXAlignment.Left,
				zIndex = 5,
			}),
		})
		for rowIndex, row in ipairs(section.rows) do
			order += 1
			listChildren[`Row{sectionIndex}_{rowIndex}`] = React.createElement(ShopRow, {
				id = row.id,
				label = row.label,
				subText = row.subText,
				buttonText = row.buttonText,
				owned = row.owned,
				buttonStyle = row.buttonStyle,
				layoutOrder = order,
				onActivated = props.onActivated,
			})
		end
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "ShopPanel",
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, {
		List = React.createElement("Frame", {
			Name = "List",
			Position = UDim2.fromScale(layout.ListPosition.X, layout.ListPosition.Y),
			Size = UDim2.fromScale(layout.ListSize.X, layout.ListSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, {
			Scroll = React.createElement(ScrollPane, {
				windowFraction = layout.ScrollWindowFraction,
				barWidth = layout.ScrollBarWidth,
				-- canvasHeightScale nil -> AutomaticCanvasSize (list pattern)
				zIndex = 5,
			}, listChildren),
		}),
	})
end

return ShopPanel
