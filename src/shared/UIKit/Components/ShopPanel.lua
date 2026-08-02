--[[
	ShopPanel — LANDSCAPE tabbed shop: a category tab row over a scroll whose
	sections each hold their own multi-column grid.

	TABS (2026-07-31). The previous version stacked every section into ONE
	scroll: 2046 nominal px of canvas in a 367 px window — 5.6 screens, whose
	first screen was the balance chips, one section header and one banner. Every
	category but the first was below the fold, which is what made a 16-item shop
	feel like an endless list. Tabs cap the worst tab at 1.9 screens (Offers 1.6)
	and let the other two render with no scroll at all. The 56 px the tab row costs
	is paid back by moving the balance chips into the header band, which was
	empty either side of the centred title.

	A section header is drawn ONLY when its tab holds more than one section —
	inside a single-section tab the tab label already names the content, and a
	header repeating it is chrome that says nothing.

	CANVAS MODEL — deterministic, never automatic. The panel walks the ACTIVE
	tab's sections, sums their nominal heights, and positions every cell by an
	explicit fraction of the resulting canvas. There is no UIListLayout, no
	AutomaticCanvasSize and no UIGridLayout in this window, so none of the kit's
	three grid pitfalls can occur: aspect-constrained cells cannot collapse,
	scale padding cannot chase a growing canvas, and the canvas cannot end up
	wider than the window.
	(The list-with-aspect-constraints version was built first and measurably
	failed — rows rendered 377px wide inside a 596px window.)

	props:
		title, size, visible, zIndex, onClose
		tabs -- ARRAY of { id, label, icon?, sections = ARRAY of section }
		     -- (preferred; icon = Theme.Icons key for the tab's glyph — the
		     -- liveTabs REBUILD must carry every field here or it is dropped)
		sections -- ARRAY of section (legacy, untabbed: renders as one scroll)
		    section = {
		        id, title, iconName, count,
		        kind = "banner"    -> full-width give banner   (ShopBanner)
		             | "hero"      -> full-width bundle offer  (ShopHeroCard)
		             | "card"      -> 3-across product card    (ShopCard)
		             | "smallcard" -> 4-across product card    (ShopCard, small)
		             | "tile"|"pack" -> the retired button-style cells, kept working
		        items = ARRAY of cell props
		    }
		balances -- ARRAY of { iconName, value, jumpTabId? } (chips in the
		         -- header band; jumpTabId adds a green "+" badge and makes
		         -- the chip a tap-shortcut to that tab — the genre's "get
		         -- more currency" loop)
		onActivated(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local ScrollPane = require(script.Parent.ScrollPane)
local StatPill = require(script.Parent.StatPill)
local ShopSectionHeader = require(script.Parent.ShopSectionHeader)
local ShopTab = require(script.Parent.ShopTab)
local ShopTile = require(script.Parent.ShopTile)
local ShopPackCard = require(script.Parent.ShopPackCard)
local ShopBanner = require(script.Parent.ShopBanner)
local ShopCard = require(script.Parent.ShopCard)
local ShopHeroCard = require(script.Parent.ShopHeroCard)
local OutlinedText = require(script.Parent.OutlinedText)

-- Per-kind cell metrics. ONE table so `sectionHeightPx` and the placement loop
-- can never disagree: they used to read the same constants from two places, and
-- a kind added to one but not the other desyncs the canvas silently (cells
-- overlap, or the last section is unreachable — no error, no warning).
local function metricsFor(layout, kind: string)
	if kind == "card" then
		return {
			columns = layout.CardColumns,
			width = layout.CardWidthPx,
			stride = layout.CardStridePx,
			height = layout.CardPx,
			rowGap = layout.CardRowGapPx,
		}
	elseif kind == "smallcard" then
		return {
			columns = layout.SmallCardColumns,
			width = layout.SmallCardWidthPx,
			stride = layout.SmallCardStridePx,
			height = layout.SmallCardPx,
			rowGap = layout.SmallCardRowGapPx,
		}
	elseif kind == "pack" then
		return {
			columns = layout.PackColumns,
			width = layout.PackWidthPx,
			stride = layout.PackStridePx,
			height = layout.PackPx,
			rowGap = layout.PackRowGapPx,
		}
	end
	return {
		columns = layout.TileColumns,
		width = layout.TileWidthPx,
		stride = layout.TileStridePx,
		height = layout.TilePx,
		rowGap = layout.TileRowGapPx,
	}
end

local function isFullWidth(kind: string): boolean
	return kind == "banner" or kind == "hero"
end

-- Nominal height of one section block, so the canvas total can be summed before
-- anything is positioned. `withHeader` is false inside a single-section tab.
local function sectionHeightPx(layout, kind: string, itemCount: number, withHeader: boolean): number
	local height = if withHeader then layout.SectionHeaderPx + layout.SectionHeaderGapPx else 0
	if isFullWidth(kind) then
		local cell = if kind == "hero" then layout.HeroPx else layout.BannerPx
		local gap = if kind == "hero" then layout.HeroGapPx else layout.BannerGapPx
		height += itemCount * cell + math.max(itemCount - 1, 0) * gap
	else
		local metrics = metricsFor(layout, kind)
		local rows = math.ceil(itemCount / metrics.columns)
		height += rows * metrics.height + (rows - 1) * metrics.rowGap
	end
	return height
end

local SCOPE = "UIKit/ShopPanel"

-- Empties are COLLECTED, not warned about here. Before ShopUpdate lands every
-- section is empty, and warning on that first render is the late-arriving-
-- dependency false positive R8 explicitly forbids: `Log.Once` fires immediately
-- and never re-checks, so the console would permanently claim the whole shop is
-- misconfigured. `reportEmpties` below decides when the report is actually meaningful.
local function liveSections(sections, empties)
	local live = {}
	for _, section in ipairs(sections or {}) do
		if #(section.items or {}) > 0 then
			table.insert(live, section)
		elseif empties then
			table.insert(empties, tostring(section.id))
		end
	end
	return live
end

-- Tabs whose sections are all empty are dropped: an empty "Gems" tab that opens
-- onto nothing is worse than no tab, and the shop legitimately has empty
-- categories (no group configured, no product ids set yet).
local function liveTabs(tabs, sections)
	local empties, hiddenTabs = {}, {}
	if not tabs then
		return { { id = "all", sections = liveSections(sections, empties) } }, empties, hiddenTabs
	end
	local live = {}
	for _, tab in ipairs(tabs) do
		local kept = liveSections(tab.sections, empties)
		if #kept > 0 then
			table.insert(live, {
				id = tab.id,
				label = tab.label,
				-- carried through explicitly — this rebuild silently ATE the
				-- icon field once (icon-first tabs rendered text-only)
				icon = tab.icon,
				sections = kept,
			})
		else
			table.insert(hiddenTabs, tostring(tab.id))
		end
	end
	return live, empties, hiddenTabs
end

-- R8, with the timing right: an empty section only means something once the
-- payload has DEMONSTRABLY arrived, and the proof of that is at least one live
-- tab. When nothing is live the `no-live-tabs` GraceOnce covers it instead —
-- deferred, so a slow ShopUpdate never reports as a broken catalogue.
local function reportEmpties(liveCount: number, empties, hiddenTabs)
	if liveCount == 0 then
		return
	end
	for _, id in ipairs(empties) do
		Log.Once(
			SCOPE,
			`empty-section-{id}`,
			`section '{id}' has no items — it is NOT rendered. Check the ShopData section keys `
				.. "and ShopSubs.shopPayload."
		)
	end
	for _, id in ipairs(hiddenTabs) do
		Log.Once(
			SCOPE,
			`empty-tab-{id}`,
			`tab '{id}' has no live sections — the TAB IS HIDDEN. Expected while that category's `
				.. "ids are 0 (docs/recipes/publish-readiness.md)."
		)
	end
end

local function ShopPanel(props)
	local layout = props.layout or Theme.ShopLayout
	local onActivated = props.onActivated

	local tabbed = props.tabs ~= nil
	-- Memoised so `selectTab`'s deps are stable: without this every render of a
	-- panel that re-renders at bite rate would rebuild the callback and push a
	-- new prop into all four tabs.
	local tabs = React.useMemo(function()
		local live, empties, hiddenTabs = liveTabs(props.tabs, props.sections)
		reportEmpties(#live, empties, hiddenTabs)
		return live
	end, { props.tabs or false, props.sections or false })

	-- Selection is held by ID, with the index only as a FALLBACK. Holding an
	-- index means a tab appearing or disappearing EARLIER in the live list
	-- shifts every later one, so a ShopUpdate could silently move the player to
	-- a different category mid-look. Holding the id keeps the player where they
	-- were for as long as that tab exists, and the clamp covers the case where
	-- it stops existing (the shop legitimately hides an all-empty tab).
	local activeId, setActiveId = React.useState(nil)
	local index, active = 1, nil
	if activeId ~= nil then
		for position, tab in ipairs(tabs) do
			if tab.id == activeId then
				index, active = position, tab
				break
			end
		end
	end
	if active == nil then
		index = math.clamp(index, 1, math.max(#tabs, 1))
		active = tabs[index]
	end
	local sections = if active then active.sections else {}
	-- A tab that carries one section does not repeat its name in a header; the
	-- untabbed legacy path always keeps them (nothing else names the sections).
	local withHeaders = (not tabbed) or #sections > 1

	-- `onTabChanged` is observation only (the state above already switched) —
	-- which tab a player browses never reaches the server unless they buy,
	-- so this is the only place a browse can be seen (features/analytics.md).
	-- It rides a ref so the memo deps stay empty and the four tab buttons keep
	-- their stable callback prop.
	local tabChangedRef = React.useRef(nil)
	tabChangedRef.current = props.onTabChanged
	local selectTab = React.useCallback(function(id)
		setActiveId(id)
		if tabChangedRef.current then
			tabChangedRef.current(id)
		end
	end, {})

	-- R8: a shop with no live tab renders an empty window. That is EXPECTED for
	-- a beat or two after join (ShopUpdate has not landed yet), which is exactly
	-- the late-arriving-dependency case GraceOnce exists for — warn only if it
	-- is still empty after the payload has had time to arrive.
	-- The re-check reads a REF, not this render's value: the whole point is that
	-- a later ShopUpdate may have filled the panel by the time the grace expires,
	-- and a closure over `#tabs` would report the state at the moment of the
	-- first empty render forever.
	local tabCountRef = React.useRef(0)
	tabCountRef.current = #tabs
	if #tabs == 0 then
		Log.GraceOnce(SCOPE, "no-live-tabs", 10, function()
			return tabCountRef.current == 0
		end, "shop has NO live tabs — the panel renders an empty window. Either ShopUpdate never "
			.. "arrived, or every product/pass id is 0 (see docs/recipes/publish-readiness.md).")
	end

	local canvasWidth = layout.CanvasWidthPx
	local windowHeight = layout.WindowHeightPx

	-- Pass 1: total canvas height.
	local contentPx = 0
	for _, section in ipairs(sections) do
		contentPx += sectionHeightPx(layout, section.kind or "tile", #section.items, withHeaders) + layout.SectionGapPx
	end
	if #sections > 0 then
		contentPx -= layout.SectionGapPx
	end
	local naturalPx = layout.CanvasTopPadPx + contentPx + layout.CanvasBottomPadPx
	local canvasPx = math.max(naturalPx, windowHeight)

	-- A tab whose content fits is CENTRED in the window. Four egg cards in a
	-- 370px zone left 106px of empty panel below them and none above, which
	-- reads as a layout that ran out of content rather than a category with four
	-- items. (The kit's own note — "a grid zone taller than one row of cards is
	-- dead space" — has no fix when the column count is what caps the card
	-- width, so the remaining lever is where the dead space sits.)
	-- When it does NOT fit, the top pad is still non-zero: a ribbon overhangs
	-- its card's top edge by up to 12px, and with section headers gone from
	-- single-section tabs the first row starts at canvas y = 0, where that
	-- overhang would be clipped by the scroll window.
	-- Centering is CAPPED (composition audit 2026-08-01): pure centering gave
	-- every tab a different content start (fitting tabs ~53px, scrolling tabs
	-- 20px) so the whole block jumped vertically on every tab switch. The cap
	-- keeps short content visually seated without the jump.
	-- max is floored at min: `layout` is a public prop, and math.clamp ERRORS
	-- on min > max — one bad custom layout must not kill the whole panel.
	local topPad = if naturalPx < windowHeight
		then math.clamp(
			(windowHeight - contentPx) / 2,
			layout.CanvasTopPadPx,
			math.max(layout.CanvasMaxTopPadPx or math.huge, layout.CanvasTopPadPx)
		)
		else layout.CanvasTopPadPx

	-- Pass 2: place everything.
	local children = {}
	local y = topPad

	for sectionIndex, section in ipairs(sections) do
		local items = section.items
		local kind = section.kind or "tile"
		-- One key stem for every child of this section: interpolating a nil
		-- section.id raw would collide two id-less sections onto one React key.
		local stem = tostring(section.id or sectionIndex)

		if withHeaders then
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
		end

		if isFullWidth(kind) then
			local isHero = kind == "hero"
			local cellH = if isHero then layout.HeroPx else layout.BannerPx
			local gap = if isHero then layout.HeroGapPx else layout.BannerGapPx
			for itemIndex, item in ipairs(items) do
				children[`Banner_{stem}_{itemIndex}`] = React.createElement(if isHero then ShopHeroCard else ShopBanner, {
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
					bundle = item.bundle,
					position = UDim2.fromScale(0, y / canvasPx),
					size = UDim2.fromScale(1, cellH / canvasPx),
					zIndex = 5,
					onActivated = onActivated,
				})
				y += cellH
				if itemIndex < #items then
					y += gap
				end
			end
		else
			local metrics = metricsFor(layout, kind)
			local columns, cellH, rowGap = metrics.columns, metrics.height, metrics.rowGap
			local rows = math.ceil(#items / columns)
			local isCard = kind == "card" or kind == "smallcard"
			local isPack = kind == "pack"
			local cardStyle = if kind == "smallcard" then Theme.ShopCardSmall else Theme.ShopCard

			for row = 0, rows - 1 do
				for column = 0, columns - 1 do
					local item = items[row * columns + column + 1]
					if item then
						-- Every cell kind gets the FULL prop set. The tile branch
						-- used to drop ribbonText/ribbonVariant/best/accent and the
						-- pack branch dropped subText, so a ribbon computed
						-- upstream was silently thrown away depending on which
						-- section a product happened to land in.
						local cellProps = {
							id = item.id,
							label = item.label,
							subText = item.subText,
							iconName = item.iconName,
							priceText = item.priceText,
							priceIcon = item.priceIcon,
							state = item.state,
							accent = item.accent,
							premium = item.premium,
							ribbonText = item.ribbonText,
							ribbonVariant = item.ribbonVariant,
							best = item.best,
							position = UDim2.fromScale(column * metrics.stride / canvasWidth, y / canvasPx),
							size = UDim2.fromScale(metrics.width / canvasWidth, cellH / canvasPx),
							zIndex = 5,
							onActivated = onActivated,
						}
						local key = `Cell_{stem}_{row}_{column}`
						if isCard then
							cellProps.style = cardStyle
							children[key] = React.createElement(ShopCard, cellProps)
						elseif isPack then
							cellProps.amountText = item.label
							children[key] = React.createElement(ShopPackCard, cellProps)
						else
							-- R8: `metricsFor` falls through to TILE metrics for any
							-- unrecognised kind, so a typo in the view-model renders
							-- the RETIRED button-style cell — the exact thing the card
							-- redesign removed — with a consistent canvas and no error.
							Log.Once(
								SCOPE,
								`unknown-kind-{tostring(kind)}`,
								`section kind '{tostring(kind)}' is not a card kind — falling back to the RETIRED `
									.. "ShopTile cell. Valid: banner | hero | card | smallcard (docs/features/shop.md)."
							)
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

	-- R8 zone guards. Both rows close at EXACTLY their designed count
	-- (4 * 229 + 217 would be 1133/904 > 1; 2 * 184 + 172 > 356), and neither
	-- container clips, so an extra entry does not get cut off — it renders
	-- somewhere wrong (off the panel, or through the centred title) and looks
	-- like a positioning bug rather than a capacity one.
	local balances = props.balances or {}
	if #balances > 0 and (#balances - 1) * layout.BalanceChipStride + layout.BalanceChipWidth > 1.0001 then
		Log.Once(
			SCOPE,
			"balance-row-overflow",
			`{#balances} balance chips do not fit the header band — the last ones render past it. `
				.. "Widen Theme.ShopLayout.BalanceSize or shrink BalanceChipStride/Width."
		)
	end

	local balanceChildren = {}
	for balanceIndex, balance in ipairs(balances) do
		local key = `Balance{balanceIndex}`
		local chipChildren = {
			Pill = React.createElement(StatPill, {
				name = "Pill",
				-- StatPill holds a hard 190/48 aspect, so in this slot it
				-- renders slightly shorter than the frame — anchor it to the
				-- vertical CENTER or it sags to the top and the Jump badge
				-- (centered on the slot) sits visibly off its midline.
				anchorPoint = Vector2.new(0, 0.5),
				position = UDim2.fromScale(0, 0.5),
				size = UDim2.fromScale(1, 1),
				iconImage = Theme.Icon(balance.iconName),
				value = balance.value,
				-- Above the header's own layers (Header draws Outer/Rim/Face
				-- at zIndex 10..12 and its close button at 20).
				zIndex = 15,
			}),
		}
		if balance.jumpTabId ~= nil then
			-- The genre's "get more" loop: a green "+" on the currency chip,
			-- and the WHOLE chip taps through to the named tab (a broke
			-- player on a gem price otherwise dead-ends with no visible path
			-- to the gem packs — UX audit 2026-08-01).
			chipChildren.Jump = React.createElement("Frame", {
				Name = "Jump",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1.04, 0.5),
				Size = UDim2.fromScale(0.30, 0.66),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 17,
			}, {
				Aspect = React.createElement("UIAspectRatioConstraint", {
					AspectRatio = 1,
					DominantAxis = Enum.DominantAxis.Height,
				}),
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = React.createElement("UIGradient", {
					Color = Theme.EquipGreen.OuterGradient,
					Rotation = 90,
				}),
				Face = React.createElement("Frame", {
					Name = "Face",
					Position = UDim2.fromScale(0.1, 0.1),
					Size = UDim2.fromScale(0.8, 0.8),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					ZIndex = 18,
				}, {
					Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Gradient = React.createElement("UIGradient", {
						Color = Theme.EquipGreen.FaceGradient,
						Rotation = 90,
					}),
				}),
				Plus = React.createElement(OutlinedText, {
					text = "+",
					position = UDim2.fromScale(0.16, 0.08),
					size = UDim2.fromScale(0.68, 0.78),
					textGradient = Theme.EquipGreen.TextGradient,
					outlineColor = Theme.EquipGreen.OutlineColor,
					zIndex = 19,
				}),
			})
			chipChildren.Hit = React.createElement("TextButton", {
				Name = "Hit",
				-- 1.06, not more: covers the badge overhang (1.04) while
				-- staying inside the chip stride, so a second jump chip's hit
				-- zone could never eat its neighbour's left edge.
				Size = UDim2.fromScale(1.06, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 20,
				[React.Event.MouseButton1Click] = function()
					selectTab(balance.jumpTabId)
				end,
			})
		end
		balanceChildren[key] = React.createElement("Frame", {
			Name = key,
			Position = UDim2.fromScale((balanceIndex - 1) * layout.BalanceChipStride, 0),
			Size = UDim2.fromScale(layout.BalanceChipWidth, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 15,
		}, chipChildren)
	end

	local panelChildren = {
		-- The chips ride the header band now, so they sit at the header's
		-- zIndex, not the body's.
		Balance = React.createElement("Frame", {
			Name = "Balance",
			Position = UDim2.fromScale(layout.BalancePosition.X, layout.BalancePosition.Y),
			Size = UDim2.fromScale(layout.BalanceSize.X, layout.BalanceSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 15,
		}, balanceChildren),
		Pane = React.createElement("Frame", {
			Name = "Pane",
			Position = UDim2.fromScale(layout.PanePosition.X, layout.PanePosition.Y),
			Size = UDim2.fromScale(layout.PaneSize.X, layout.PaneSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, {
			-- The child KEY carries the tab id so switching tabs REMOUNTS the
			-- scroll: a ScrollingFrame keeps its CanvasPosition across a
			-- re-render, so jumping from a 2-row tab to a 1-row tab left the new
			-- tab scrolled past its own content — a blank window.
			[`Scroll_{tostring(active and active.id or "all")}`] = React.createElement(ScrollPane, {
				windowFraction = layout.ScrollWindowFraction,
				barWidth = layout.ScrollBarWidth,
				canvasHeightScale = canvasPx / windowHeight,
				zIndex = 5,
			}, children),
		}),
	}

	if tabbed and #tabs > 1 then
		if (#tabs - 1) * layout.TabStride + layout.TabWidth > 1.0001 then
			Log.Once(
				SCOPE,
				"tab-row-overflow",
				`{#tabs} tabs do not fit the 904px tab row — the last ones render past the panel. `
					.. "Re-cut Theme.ShopLayout.TabWidth/TabStride for the new count."
			)
		end
		local tabChildren = {}
		for tabIndex, tab in ipairs(tabs) do
			tabChildren[`Tab_{tostring(tab.id or tabIndex)}`] = React.createElement(ShopTab, {
				id = tab.id,
				label = tab.label,
				iconName = tab.icon,
				selected = tabIndex == index,
				position = UDim2.fromScale((tabIndex - 1) * layout.TabStride, 0),
				size = UDim2.fromScale(layout.TabWidth, 1),
				zIndex = 6,
				onActivated = selectTab,
			})
		end
		panelChildren.Tabs = React.createElement("Frame", {
			Name = "Tabs",
			Position = UDim2.fromScale(layout.TabsPosition.X, layout.TabsPosition.Y),
			Size = UDim2.fromScale(layout.TabsSize.X, layout.TabsSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, tabChildren)
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
	}, panelChildren)
end

-- AppRoot re-renders at bite rate while the player eats, and one tab of this
-- tree is ~150 elements (6 cells x ~18, each carrying a PriceButton subtree).
-- Every input is memoised upstream — `tabs`, `balances` AND the two CALLBACKS,
-- which is the half that is easy to miss: a fresh
-- `onActivated = function() ... end` in the props fails a shallow compare every
-- time, so the memo would be pure overhead. If AppRoot ever inlines those
-- closures again, this memo silently stops working.
return React.memo(ShopPanel)
