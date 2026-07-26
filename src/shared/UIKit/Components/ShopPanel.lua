--[[
	ShopPanel — LANDSCAPE sectioned shop: balance strip + a long scroll whose
	sections each hold their own multi-column grid.

	Replaces the portrait one-column list, which occupied 36% of screen width,
	rendered every item as the same 418x88 blue row, and could not put two cells
	side by side at all.

	CANVAS MODEL — deterministic, never automatic. The panel walks the sections,
	sums their nominal heights, and positions every cell by an explicit fraction
	of the resulting canvas. There is no UIListLayout, no AutomaticCanvasSize and
	no UIGridLayout in this window, so none of the kit's three grid pitfalls can
	occur: aspect-constrained cells cannot collapse, scale padding cannot chase a
	growing canvas, and the canvas cannot end up wider than the window.
	(The list-with-aspect-constraints version was built first and measurably
	failed — rows rendered 377px wide inside a 596px window.)

	props:
		title, size, visible, zIndex, onClose
		sections -- ARRAY of {
		    id, title, iconName, count,
		    kind = "banner" | "tile" | "pack",
		    items = ARRAY of cell props (see ShopTile / ShopPackCard / ShopBanner)
		}
		balances -- ARRAY of { iconName, value } (left-aligned chips)
		onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local ScrollPane = require(script.Parent.ScrollPane)
local StatPill = require(script.Parent.StatPill)
local ShopSectionHeader = require(script.Parent.ShopSectionHeader)
local ShopTile = require(script.Parent.ShopTile)
local ShopPackCard = require(script.Parent.ShopPackCard)
local ShopBanner = require(script.Parent.ShopBanner)

-- Nominal height of one section block, so the canvas total can be summed before
-- anything is positioned.
local function sectionHeightPx(layout, kind: string, itemCount: number): number
	local height = layout.SectionHeaderPx + layout.SectionHeaderGapPx
	if kind == "banner" then
		height += itemCount * layout.BannerPx + math.max(itemCount - 1, 0) * layout.BannerGapPx
	elseif kind == "pack" then
		local rows = math.ceil(itemCount / layout.PackColumns)
		height += rows * layout.PackPx + (rows - 1) * layout.PackRowGapPx
	else
		local rows = math.ceil(itemCount / layout.TileColumns)
		height += rows * layout.TilePx + (rows - 1) * layout.TileRowGapPx
	end
	return height
end

local function ShopPanel(props)
	local layout = props.layout or Theme.ShopLayout
	local sections = props.sections or {}
	local onActivated = props.onActivated

	local canvasWidth = layout.CanvasWidthPx
	local windowHeight = layout.WindowHeightPx

	-- Pass 1: total canvas height.
	local totalPx = 0
	local live = {}
	for _, section in ipairs(sections) do
		local items = section.items or {}
		if #items > 0 then
			table.insert(live, section)
			totalPx += sectionHeightPx(layout, section.kind or "tile", #items) + layout.SectionGapPx
		end
	end
	if #live > 0 then
		totalPx = totalPx - layout.SectionGapPx + layout.CanvasBottomPadPx
	end
	local canvasPx = math.max(totalPx, windowHeight)

	-- Pass 2: place everything.
	local children = {}
	local y = 0

	for sectionIndex, section in ipairs(live) do
		local items = section.items
		local kind = section.kind or "tile"
		-- One key stem for every child of this section: interpolating a nil
		-- section.id raw would collide two id-less sections onto one React key.
		local stem = tostring(section.id or sectionIndex)

		children[`Section_{stem}`] = React.createElement(ShopSectionHeader, {
			name = `Section_{stem}`,
			title = section.title,
			iconName = section.iconName,
			count = section.count,
			position = UDim2.fromScale(0, y / canvasPx),
			size = UDim2.fromScale(1, layout.SectionHeaderPx / canvasPx),
			zIndex = 5,
		})
		y += layout.SectionHeaderPx + layout.SectionHeaderGapPx

		if kind == "banner" then
			for itemIndex, item in ipairs(items) do
				children[`Banner_{stem}_{itemIndex}`] = React.createElement(ShopBanner, {
					id = item.id,
					label = item.label,
					subText = item.subText,
					iconName = item.iconName,
					priceText = item.priceText,
					priceIcon = item.priceIcon,
					state = item.state,
					ribbonText = item.ribbonText,
					ribbonVariant = item.ribbonVariant,
					accent = item.accent,
					position = UDim2.fromScale(0, y / canvasPx),
					size = UDim2.fromScale(1, layout.BannerPx / canvasPx),
					zIndex = 5,
					onActivated = onActivated,
				})
				y += layout.BannerPx
				if itemIndex < #items then
					y += layout.BannerGapPx
				end
			end
		else
			local isPack = kind == "pack"
			local columns = if isPack then layout.PackColumns else layout.TileColumns
			local cellW = if isPack then layout.PackWidthPx else layout.TileWidthPx
			local stride = if isPack then layout.PackStridePx else layout.TileStridePx
			local cellH = if isPack then layout.PackPx else layout.TilePx
			local rowGap = if isPack then layout.PackRowGapPx else layout.TileRowGapPx
			local rows = math.ceil(#items / columns)

			for row = 0, rows - 1 do
				for column = 0, columns - 1 do
					local item = items[row * columns + column + 1]
					if item then
						local cellProps = {
							id = item.id,
							iconName = item.iconName,
							priceText = item.priceText,
							priceIcon = item.priceIcon,
							state = item.state,
							position = UDim2.fromScale(column * stride / canvasWidth, y / canvasPx),
							size = UDim2.fromScale(cellW / canvasWidth, cellH / canvasPx),
							zIndex = 5,
							onActivated = onActivated,
						}
						local key = `Cell_{stem}_{row}_{column}`
						if isPack then
							cellProps.amountText = item.label
							cellProps.ribbonText = item.ribbonText
							cellProps.ribbonVariant = item.ribbonVariant
							cellProps.best = item.best
							children[key] = React.createElement(ShopPackCard, cellProps)
						else
							cellProps.label = item.label
							cellProps.subText = item.subText
							children[key] = React.createElement(ShopTile, cellProps)
						end
					end
				end
				y += cellH
				if row < rows - 1 then
					y += rowGap
				end
			end
		end
		y += layout.SectionGapPx
	end

	local balanceChildren = {}
	for index, balance in ipairs(props.balances or {}) do
		balanceChildren[`Balance{index}`] = React.createElement(StatPill, {
			name = `Balance{index}`,
			position = UDim2.fromScale((index - 1) * layout.BalanceChipStride, 0),
			size = UDim2.fromScale(layout.BalanceChipWidth, 1),
			iconImage = Theme.Icon(balance.iconName),
			value = balance.value,
			zIndex = 6,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "ShopPanel",
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.HeaderWide,
		headerSize = UDim2.fromScale(1, layout.HeaderHeight),
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, {
		Balance = React.createElement("Frame", {
			Name = "Balance",
			Position = UDim2.fromScale(layout.BalancePosition.X, layout.BalancePosition.Y),
			Size = UDim2.fromScale(layout.BalanceSize.X, layout.BalanceSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, balanceChildren),
		Pane = React.createElement("Frame", {
			Name = "Pane",
			Position = UDim2.fromScale(layout.PanePosition.X, layout.PanePosition.Y),
			Size = UDim2.fromScale(layout.PaneSize.X, layout.PaneSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, {
			Scroll = React.createElement(ScrollPane, {
				windowFraction = layout.ScrollWindowFraction,
				barWidth = layout.ScrollBarWidth,
				canvasHeightScale = canvasPx / windowHeight,
				zIndex = 5,
			}, children),
		}),
	})
end

-- AppRoot re-renders at bite rate while the player eats, and this tree is
-- ~700 elements (25 cells x ~18, each carrying a PriceButton subtree). Its
-- inputs (`sections`, `balances`) are already memoised upstream, so memo
-- turns every one of those renders into a props compare.
return React.memo(ShopPanel)
