--[[
	MatchmakingPanel -- child-first split lobby match configurator.

	Difficulty and party size use icon-first controls in the left setup column.
	The persisted cake preference owns a large horizontal peek carousel on the
	right: one cake is fully visible and half of the next card teaches swipe/scroll.
	One empty gutter separates the groups without another decorative backing panel.

	Difficulty and party size are per-session local presentation state. They reset
	to `defaultDifficulty` / `defaultPlayers` whenever `sessionKey` changes and
	report those defaults through the same observation callbacks used by taps.
	START remains a one-tap solo/easy path and sends exactly those two values.

	Cake remains presentation-only account state owned by cake-select. It has no
	useState here, does not reset with the queue session, does not participate in
	readiness, and never enters `onStart`. Its fixed-size carousel cards scroll on
	X instead of shrinking every tile. Locked requirements live on their cards;
	the default layout keeps transient launch/error copy inside START itself.

	Props:
		{ difficultyOptions = { {id,label,description,iconName,accent,rewardText} },
		  playerCounts = { number | {value,label} }, cakeOptions?,
		  defaultDifficulty?, defaultPlayers?, sessionKey?, busy?, status/error copy,
		  onSelectDifficulty(id,isDefault?), onSelectPlayers(count,isDefault?),
		  onSelectCake(id), onStart(difficulty,count), onClose() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local MatchDifficultyChoice = require(script.Parent.MatchDifficultyChoice)
local MatchPartyChoice = require(script.Parent.MatchPartyChoice)
local CakeCard = require(script.Parent.CakeCard)
local ScrollPane = require(script.Parent.ScrollPane)
local OutlinedText = require(script.Parent.OutlinedText)

local function optionParts(option)
	if type(option) == "table" then
		return option.id or option.value, option.label or ""
	end
	return option, tostring(option)
end

-- Is `value` one of the options this selector is actually offering right now?
-- The party list is filtered by the pad's cap and the mode list comes from
-- config, so a configured default can legitimately be absent.
local function offered(options, value): boolean
	if value == nil then
		return false
	end
	for _, option in ipairs(options) do
		local id = optionParts(option)
		if id == value then
			return true
		end
	end
	return false
end

-- Deterministic vertical gallery canvas. Child Y scales are fractions of the
-- canvas, not the visible window, so cards keep their nominal size.
local function galleryCanvas(
	count: number,
	columns: number,
	itemHeight: number,
	gap: number,
	windowHeight: number,
	padding: number
)
	local rows = if count > 0 then math.ceil(count / columns) else 0
	local contentHeight = if rows > 0
		then padding * 2 + rows * itemHeight + (rows - 1) * gap
		else 0
	local canvasHeight = math.max(contentHeight, windowHeight)
	return contentHeight, canvasHeight, canvasHeight / windowHeight
end

-- Deterministic one-row carousel. With the default 420px window, 8px side
-- padding, 264px cards, and 16px gaps, three cards close at exactly 840px.
local function carouselCanvas(
	count: number,
	itemWidth: number,
	gap: number,
	windowWidth: number,
	padding: number
)
	local contentWidth = if count > 0
		then padding * 2 + count * itemWidth + math.max(count - 1, 0) * gap
		else 0
	local canvasWidth = math.max(contentWidth, windowWidth)
	return contentWidth, canvasWidth, canvasWidth / windowWidth
end

local function carouselCardPosition(
	index: number,
	cardWidth: number,
	gap: number,
	padding: number,
	crossPadding: number
): (number, number)
	return padding + (index - 1) * (cardWidth + gap), crossPadding
end

local function carouselHitIndex(
	pointX: number,
	pointY: number,
	count: number,
	cardWidth: number,
	cardHeight: number,
	gap: number,
	padding: number,
	crossPadding: number
): number?
	if pointY < crossPadding or pointY >= crossPadding + cardHeight then
		return nil
	end
	local contentX = pointX - padding
	if contentX < 0 then
		return nil
	end
	local stride = cardWidth + gap
	local index = math.floor(contentX / stride) + 1
	local withinX = contentX - (index - 1) * stride
	if index < 1 or index > count or withinX < 0 or withinX >= cardWidth then
		return nil
	end
	return index
end

-- Placement and hit-testing MUST share one row origin. Matchmaking left-aligns
-- incomplete future rows so every card begins on the same column rails; legacy
-- layouts may retain the previous centred behavior.
local function galleryRowX(
	rowCount: number,
	canvasWidth: number,
	cardWidth: number,
	gap: number,
	incompleteAlignment: string?
): number
	local rowWidth = rowCount * cardWidth + math.max(rowCount - 1, 0) * gap
	if incompleteAlignment == "left" then
		return 0
	elseif incompleteAlignment == "right" then
		return canvasWidth - rowWidth
	end
	return (canvasWidth - rowWidth) / 2
end

local function galleryCardPosition(
	index: number,
	count: number,
	columns: number,
	canvasWidth: number,
	cardWidth: number,
	cardHeight: number,
	gap: number,
	padding: number,
	incompleteAlignment: string?
): (number, number)
	local row = math.floor((index - 1) / columns)
	local column = (index - 1) % columns
	local rowStart = row * columns + 1
	local rowCount = math.min(columns, count - rowStart + 1)
	local rowX = galleryRowX(rowCount, canvasWidth, cardWidth, gap, incompleteAlignment)
	return rowX + column * (cardWidth + gap), padding + row * (cardHeight + gap)
end

-- Match the pointer dispatcher to the exact same card geometry. Gaps and the
-- empty sides around a centred odd row deliberately hit nothing.
local function galleryHitIndex(
	pointX: number,
	pointY: number,
	count: number,
	columns: number,
	canvasWidth: number,
	cardWidth: number,
	cardHeight: number,
	gap: number,
	padding: number,
	incompleteAlignment: string?
): number?
	local stride = cardHeight + gap
	local contentY = pointY - padding
	if contentY < 0 then
		return nil
	end
	local row = math.floor(contentY / stride)
	local withinY = contentY - row * stride
	if row < 0 or withinY < 0 or withinY >= cardHeight then
		return nil
	end
	local rowStart = row * columns + 1
	if rowStart > count then
		return nil
	end
	local rowCount = math.min(columns, count - rowStart + 1)
	local rowX = galleryRowX(rowCount, canvasWidth, cardWidth, gap, incompleteAlignment)
	for column = 0, rowCount - 1 do
		local cardX = rowX + column * (cardWidth + gap)
		if pointX >= cardX and pointX < cardX + cardWidth then
			return rowStart + column
		end
	end
	return nil
end

local function MatchmakingPanel(props)
	local layout = props.layout or Theme.MatchmakingLayout
	local zIndex = props.contentZIndex or layout.ContentZIndex
	-- Custom/legacy layouts predate the pulse wrapper. A neutral factor preserves
	-- their original geometry instead of making an optional visual token fatal.
	local startPulseHeadroom = layout.StartPulseHeadroom or 1
	local busy = props.busy == true
	local panelVisible = props.visible ~= false
	local sessionKey = props.sessionKey or false
	-- START's callback patches AppRoot synchronously, but React may commit the
	-- resulting busy prop a frame later. A second held finger can release inside
	-- that gap, so refs guard every handler immediately instead of trusting only
	-- the rendered `enabled` props. `sawBusy` lets an error/recovery render unlock
	-- the same session once authoritative busy returns false.
	local launchLockRef = React.useRef({
		sessionKey = sessionKey,
		locked = false,
		sawBusy = false,
	})
	local launchLock = launchLockRef.current
	if launchLock.sessionKey ~= sessionKey or not panelVisible then
		launchLock = {
			sessionKey = sessionKey,
			locked = false,
			sawBusy = false,
		}
		launchLockRef.current = launchLock
	elseif busy then
		launchLock.locked = true
		launchLock.sawBusy = true
	elseif launchLock.locked and launchLock.sawBusy then
		launchLock.locked = false
		launchLock.sawBusy = false
	end
	local interactive = panelVisible and not busy and not launchLock.locked
	local difficultyOptions = props.difficultyOptions or {}
	local playerCounts = props.playerCounts or {}
	local cakeOptions = props.cakeOptions or {}
	local defaultDifficulty = if offered(difficultyOptions, props.defaultDifficulty)
		then props.defaultDifficulty
		else nil
	local defaultMaxPlayers = if offered(playerCounts, props.defaultPlayers) then props.defaultPlayers else nil

	-- Store the session alongside each choice. The panel stays mounted while
	-- hidden, so plain scalar state would expose the PREVIOUS pad's choices for
	-- one committed frame before an effect could reset them. Reading defaults
	-- synchronously whenever the key differs keeps START incapable of sending a
	-- stale difficulty/party pair.
	local difficultySelection, setDifficultySelection = React.useState({
		sessionKey = sessionKey,
		value = defaultDifficulty,
	})
	local playerSelection, setPlayerSelection = React.useState({
		sessionKey = sessionKey,
		value = defaultMaxPlayers,
	})
	-- React state owns what is drawn, while this session-keyed ref owns the exact
	-- pair START dispatches. A second finger can release START before a just-tapped
	-- setup tile commits; updating the ref in the tile handler prevents that race
	-- from launching the previously rendered Easy/1 pair.
	local choiceRef = React.useRef({
		sessionKey = sessionKey,
		difficulty = defaultDifficulty,
		maxPlayers = defaultMaxPlayers,
	})
	if choiceRef.current.sessionKey ~= sessionKey then
		choiceRef.current = {
			sessionKey = sessionKey,
			difficulty = defaultDifficulty,
			maxPlayers = defaultMaxPlayers,
		}
	end
	-- The default layout keeps earnable requirements on their cards. Preserve a
	-- semantic notice id only for legacy/custom layouts that explicitly provide a
	-- contextual notice slot; cake selection itself still has no local mirror.
	local cakeNoticeState, setCakeNoticeState = React.useState({
		sessionKey = sessionKey,
		id = nil,
	})
	local cakeNoticeId = if cakeNoticeState.sessionKey == sessionKey
		then cakeNoticeState.id
		else nil
	local function setCakeNoticeId(id)
		setCakeNoticeState({ sessionKey = sessionKey, id = id })
	end
	local selectedDifficulty = if difficultySelection.sessionKey == sessionKey
		and offered(difficultyOptions, difficultySelection.value)
		then difficultySelection.value
		else defaultDifficulty
	local selectedMaxPlayers = if playerSelection.sessionKey == sessionKey
		and offered(playerCounts, playerSelection.value)
		then playerSelection.value
		else defaultMaxPlayers

	-- Read through a ref, never the effect's deps: AppRoot rebuilds option lists
	-- and observation callbacks on renders this effect must not follow. A new
	-- session key is the only reset trigger.
	local sessionRef = React.useRef(nil)
	sessionRef.current = {
		difficulty = defaultDifficulty,
		maxPlayers = defaultMaxPlayers,
		onDifficulty = props.onSelectDifficulty,
		onPlayers = props.onSelectPlayers,
	}

	React.useEffect(function()
		local latest = sessionRef.current
		-- The panel stays mounted while hidden; mount alone must not create funnel
		-- beats for a player who never approached a matchmaking pad.
		if type(sessionKey) ~= "string" or sessionKey == "" then
			return
		end
		if latest.difficulty ~= nil and latest.onDifficulty then
			latest.onDifficulty(latest.difficulty, true)
		end
		if latest.maxPlayers ~= nil and latest.onPlayers then
			latest.onPlayers(latest.maxPlayers, true)
		end
	end, { sessionKey })

	-- The panel stays mounted while hidden. Never carry a contextual lock hint
	-- into another opening/session or into the launch/busy state.
	React.useEffect(function()
		setCakeNoticeId(nil)
	end, { sessionKey, panelVisible, busy })

	-- Matchmaking's child-first cut uses portrait tiles across the row. Legacy
	-- layouts may retain the stacked-list orientation; either way, fewer offered
	-- modes stay centred without stretching.
	local difficultyChildren = {}
	local difficultyCount = #difficultyOptions
	local difficultyHorizontal = layout.DifficultyOrientation == "horizontal"
	local difficultyGroupSize
	local difficultyStart
	if difficultyHorizontal then
		difficultyGroupSize = if difficultyCount > 0
			then difficultyCount * layout.DifficultyChoiceWidth
				+ (difficultyCount - 1) * layout.DifficultyChoiceGap
			else 0
	else
		difficultyGroupSize = if difficultyCount > 0
			then difficultyCount * layout.DifficultyChoiceHeight
				+ (difficultyCount - 1) * layout.DifficultyChoiceGap
			else 0
	end
	difficultyStart = (1 - difficultyGroupSize) / 2
	for index, option in ipairs(difficultyOptions) do
		local id, label = optionParts(option)
		local detail = if type(option) == "table" then option else {}
		difficultyChildren[`Choice_{tostring(id)}`] = React.createElement(MatchDifficultyChoice, {
			name = `Difficulty_{tostring(id)}`,
			id = id,
			label = label,
			rewardText = detail.rewardText or "",
			iconName = detail.iconName,
			accent = detail.accent or id,
			selected = selectedDifficulty == id,
			enabled = interactive,
			position = if difficultyHorizontal
				then UDim2.fromScale(
					difficultyStart
						+ (index - 1) * (layout.DifficultyChoiceWidth + layout.DifficultyChoiceGap),
					0
				)
				else UDim2.fromScale(
					0,
					difficultyStart
						+ (index - 1) * (layout.DifficultyChoiceHeight + layout.DifficultyChoiceGap)
				),
			size = if difficultyHorizontal
				then UDim2.fromScale(layout.DifficultyChoiceWidth, 1)
				else UDim2.fromScale(1, layout.DifficultyChoiceHeight),
			aspectRatio = layout.DifficultyChoiceAspectRatio,
			zIndex = zIndex,
			onActivated = function(selectedId)
				if launchLockRef.current.locked or choiceRef.current.sessionKey ~= sessionKey then
					return
				end
				choiceRef.current.difficulty = selectedId
				setDifficultySelection({ sessionKey = sessionKey, value = selectedId })
				if props.onSelectDifficulty then
					props.onSelectDifficulty(selectedId)
				end
			end,
		})
	end

	-- Party Size is a separate 101x84 strip rather than a continuation of the
	-- Difficulty tiles. Fewer offered sizes stay centred without stretching.
	local partyChildren = {}
	local partyCount = #playerCounts
	local partyGroupWidth = if partyCount > 0
		then partyCount * layout.PartyChoiceWidth + (partyCount - 1) * layout.PartyChoiceGap
		else 0
	local partyStartX = (1 - partyGroupWidth) / 2
	for index, option in ipairs(playerCounts) do
		local value = optionParts(option)
		partyChildren[`Choice_{tostring(value)}`] = React.createElement(MatchPartyChoice, {
			name = `Players_{tostring(value)}`,
			count = value,
			selected = selectedMaxPlayers == value,
			enabled = interactive,
			position = UDim2.fromScale(
				partyStartX + (index - 1) * (layout.PartyChoiceWidth + layout.PartyChoiceGap),
				0
			),
			size = UDim2.fromScale(layout.PartyChoiceWidth, 1),
			aspectRatio = layout.PartyChoiceAspectRatio,
			zIndex = zIndex,
			onActivated = function()
				if launchLockRef.current.locked or choiceRef.current.sessionKey ~= sessionKey then
					return
				end
				choiceRef.current.maxPlayers = value
				setPlayerSelection({ sessionKey = sessionKey, value = value })
				if props.onSelectPlayers then
					props.onSelectPlayers(value)
				end
			end,
		})
	end

	-- Persisted cake preference: fixed-size picture-first cards on a deterministic
	-- canvas. The default is a one-row X carousel; legacy layouts retain the
	-- multi-row Y gallery path.
	local cakeCount = #cakeOptions
	local cakeHorizontal = layout.CakeOrientation == "horizontal"
	local cakeColumns = layout.CakeColumns or 1
	local cakePaneWidthPx = layout.CakePaneWidthPx or layout.CakeCardWidthPx
	local cakePaneHeightPx = layout.CakePaneHeightPx or layout.CakeCardHeightPx
	local cakeCanvasPaddingPx = layout.CakeCanvasPaddingPx or 0
	local cakeCanvasCrossPaddingPx = layout.CakeCanvasCrossPaddingPx or cakeCanvasPaddingPx
	local cakeIncompleteRowAlignment = layout.CakeIncompleteRowAlignment
	local cakeNoticeUsesStatus = layout.CakeNoticeUsesStatus == true
	local hasCakeNoticeSlot = cakeNoticeUsesStatus
		or (layout.CakeNoticePosition ~= nil and layout.CakeNoticeSize ~= nil)
	local cakeContentWidth = cakePaneWidthPx
	local cakeCanvasWidth = cakePaneWidthPx
	local cakeContentHeight = cakePaneHeightPx
	local cakeCanvasHeight = cakePaneHeightPx
	local cakeCanvasScale = 1
	if cakeHorizontal then
		cakeContentWidth, cakeCanvasWidth, cakeCanvasScale = carouselCanvas(
			cakeCount,
			layout.CakeCardWidthPx,
			layout.CakeCardGapPx,
			cakePaneWidthPx,
			cakeCanvasPaddingPx
		)
	else
		cakeContentHeight, cakeCanvasHeight, cakeCanvasScale = galleryCanvas(
			cakeCount,
			cakeColumns,
			layout.CakeCardHeightPx,
			layout.CakeCardGapPx,
			cakePaneHeightPx,
			cakeCanvasPaddingPx
		)
	end
	local cakeChildren = {}
	local selectedCakeIndex = nil
	local selectedCakeId = nil
	for index, option in ipairs(cakeOptions) do
		if option.selected == true then
			selectedCakeIndex = index
			selectedCakeId = option.id
		end
		local cardX, cardY
		if cakeHorizontal then
			cardX, cardY = carouselCardPosition(
				index,
				layout.CakeCardWidthPx,
				layout.CakeCardGapPx,
				cakeCanvasPaddingPx,
				cakeCanvasCrossPaddingPx
			)
		else
			cardX, cardY = galleryCardPosition(
				index,
				cakeCount,
				cakeColumns,
				cakePaneWidthPx,
				layout.CakeCardWidthPx,
				layout.CakeCardHeightPx,
				layout.CakeCardGapPx,
				cakeCanvasPaddingPx,
				cakeIncompleteRowAlignment
			)
		end
		cakeChildren[`Card_{tostring(option.id)}`] = React.createElement(CakeCard, {
			name = `Cake_{tostring(option.id)}`,
			id = option.id,
			label = option.label,
			iconName = option.iconName,
			accent = option.accent,
			-- Default matchmaking cards own earnable unlock requirements. A coming-
			-- soon card already says that in its title and clock badge, so repeating
			-- the same sentence in its status block would add noise, not information.
			-- Legacy layouts with a contextual notice slot retain that route.
			statusText = if hasCakeNoticeSlot or option.comingSoon == true
				then nil
				else option.statusText,
			selected = option.selected,
			locked = option.locked,
			comingSoon = option.comingSoon,
			enabled = interactive,
			focusableWhenLocked = interactive,
			hoverScale = 1,
			style = Theme.MatchCakeCard,
			position = UDim2.fromScale(
				cardX / cakeCanvasWidth,
				cardY / cakeCanvasHeight
			),
			size = UDim2.fromScale(
				layout.CakeCardWidthPx / cakeCanvasWidth,
				layout.CakeCardHeightPx / cakeCanvasHeight
			),
			aspectRatio = layout.CakeCardAspectRatio,
			zIndex = zIndex,
			onActivated = function(id)
				if launchLockRef.current.locked then
					return
				end
				if hasCakeNoticeSlot then
					setCakeNoticeId(nil)
				end
				if props.onSelectCake then
					props.onSelectCake(id)
				end
			end,
			onLockedActivated = function(id)
				if launchLockRef.current.locked then
					return
				end
				if hasCakeNoticeSlot then
					setCakeNoticeId(id)
				end
				Interaction.Track("dead", `Cake_{tostring(id or "unknown")}`)
			end,
		})
	end

	-- Store only the semantic cake id. The localized copy is derived from the
	-- current view model every render, so a late translator or entitlement push
	-- cannot leave an English/stale lock sentence behind.
	local cakeNoticeText = nil
	local cakeNoticeStillLocked = false
	if interactive and cakeNoticeId ~= nil then
		for _, option in ipairs(cakeOptions) do
			if
				option.id == cakeNoticeId
				and (option.locked == true or option.comingSoon == true)
			then
				cakeNoticeStillLocked = true
				if type(option.statusText) == "string" then
					cakeNoticeText = option.statusText
				end
				break
			end
		end
	end
	React.useEffect(function()
		if cakeNoticeId ~= nil and not cakeNoticeStillLocked then
			setCakeNoticeId(nil)
		end
	end, { cakeNoticeId or false, cakeNoticeStillLocked })
	-- The default carousel centers the persisted selection. Classic clamps to the
	-- beginning (the authored one-card-plus-half-Rainbow opening); selecting
	-- Rainbow lands it exactly in the middle and fully visible. Legacy Y galleries
	-- keep the minimum offset needed to expose the selected row.
	local cakeScrollRange = if cakeHorizontal
		then math.max(cakeCanvasWidth - cakePaneWidthPx, 0)
		else math.max(cakeCanvasHeight - cakePaneHeightPx, 0)
	local selectedCakeOffset = 0
	if selectedCakeIndex ~= nil then
		if cakeHorizontal then
			local selectedCakeX = carouselCardPosition(
				selectedCakeIndex,
				layout.CakeCardWidthPx,
				layout.CakeCardGapPx,
				cakeCanvasPaddingPx,
				cakeCanvasCrossPaddingPx
			)
			selectedCakeOffset = math.clamp(
				selectedCakeX + layout.CakeCardWidthPx / 2 - cakePaneWidthPx / 2,
				0,
				cakeScrollRange
			)
		else
			local _, selectedCakeY = galleryCardPosition(
				selectedCakeIndex,
				cakeCount,
				cakeColumns,
				cakePaneWidthPx,
				layout.CakeCardWidthPx,
				layout.CakeCardHeightPx,
				layout.CakeCardGapPx,
				cakeCanvasPaddingPx,
				cakeIncompleteRowAlignment
			)
			local selectedCakeEnd = selectedCakeY + layout.CakeCardHeightPx
			selectedCakeOffset = math.clamp(
				selectedCakeEnd - cakePaneHeightPx,
				0,
				cakeScrollRange
			)
		end
	end
	local selectedCakeScrollFraction = if cakeScrollRange > 0
		then selectedCakeOffset / cakeScrollRange
		else 0
	local cakeResetKey = if cakeHorizontal
		then `{tostring(sessionKey)}|{tostring(selectedCakeId or "")}`
		else sessionKey

	local function onCakeCanvasTap(
		canvasPoint: Vector2,
		_inputType,
		startCanvasPoint: Vector2?
	)
		-- PanelShell keeps drawing during its close tween. Ignore the pointer as
		-- soon as the logical visibility flips so an exit-frame tap cannot persist
		-- a cake choice or leak dead-press telemetry.
		if not panelVisible or (launchLockRef.current.locked and not busy) then
			return
		end
		local function cakeIndexAt(point: Vector2): number?
			local pointX = point.X * cakeCanvasWidth
			local pointY = point.Y * cakeCanvasHeight
			if cakeHorizontal then
				if pointX < 0 or pointX >= cakeContentWidth then
					return nil
				end
				return carouselHitIndex(
					pointX,
					pointY,
					cakeCount,
					layout.CakeCardWidthPx,
					layout.CakeCardHeightPx,
					layout.CakeCardGapPx,
					cakeCanvasPaddingPx,
					cakeCanvasCrossPaddingPx
				)
			end
			if pointY < 0 or pointY >= cakeContentHeight then
				return nil
			end
			return galleryHitIndex(
				pointX,
				pointY,
				cakeCount,
				cakeColumns,
				cakePaneWidthPx,
				layout.CakeCardWidthPx,
				layout.CakeCardHeightPx,
				layout.CakeCardGapPx,
				cakeCanvasPaddingPx,
				cakeIncompleteRowAlignment
			)
		end
		local index = cakeIndexAt(canvasPoint)
		if index == nil then
			return
		end
		-- Sub-threshold jitter is still a tap only when it began on this SAME
		-- semantic card. A press that starts in a gutter/odd-row margin and drifts
		-- onto art must never manufacture a selection on release.
		if cakeIndexAt(startCanvasPoint or canvasPoint) ~= index then
			return
		end
		local option = cakeOptions[index]
		if option == nil then
			return
		end
		local analyticsId = `Cake_{tostring(option.id or "unknown")}`
		if busy then
			Interaction.Track("dead", analyticsId)
			return
		end
		if option.locked == true or option.comingSoon == true then
			if hasCakeNoticeSlot then
				setCakeNoticeId(option.id)
			end
			Interaction.Track("dead", analyticsId)
			return
		end
		if hasCakeNoticeSlot then
			setCakeNoticeId(nil)
		end
		Interaction.Cue("press", analyticsId)
		if props.onSelectCake then
			props.onSelectCake(option.id)
		end
	end

	local selectedCount = (if selectedDifficulty ~= nil then 1 else 0)
		+ (if selectedMaxPlayers ~= nil then 1 else 0)
	local ready = selectedCount == 2
	local canStart = ready and interactive
	local errorText = if type(props.error) == "string"
		then props.error
		elseif props.error == true then (props.errorText or "")
		else nil
	local hasError = errorText ~= nil and errorText ~= ""
	local statusText
	if hasError then
		statusText = errorText
	elseif props.statusText ~= nil then
		statusText = props.statusText
	elseif busy then
		statusText = if layout.ShowBusyStatus == false then "" else (props.busyStatusText or "")
	elseif selectedCount == 0 then
		statusText = if layout.ShowSelectionStatus == false then "" else (props.unselectedStatusText or "")
	elseif selectedCount == 1 then
		statusText = if layout.ShowSelectionStatus == false then "" else (props.partialStatusText or "")
	else
		statusText = if layout.ShowReadyStatus == false then "" else (props.readyStatusText or "")
	end
	local statusUsesCakeNotice = cakeNoticeUsesStatus
		and not hasError
		and type(cakeNoticeText) == "string"
		and cakeNoticeText ~= ""
	local statusDisplayText = if statusUsesCakeNotice then cakeNoticeText else statusText
	local function onClose()
		if launchLockRef.current.locked then
			return
		end
		-- Close is a logical transition before React can commit `visible = false`.
		-- Latch immediately so a second held pointer cannot release through this
		-- render's still-live setup/cake/START closures after the X is pressed.
		launchLockRef.current.locked = true
		launchLockRef.current.sawBusy = false
		if props.onClose then
			props.onClose()
		end
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "MatchmakingPanel",
		anchorPoint = props.anchorPoint,
		position = props.position,
		size = props.size,
		visible = props.visible,
		title = props.title or "",
		onClose = if props.onClose then onClose else nil,
		closeEnabled = interactive,
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.MatchmakingHeader,
		closeStyle = Theme.MatchmakingCloseButton,
		headerSize = UDim2.fromScale(1, layout.HeaderHeight),
		zIndex = props.zIndex,
	}, {
		Content = React.createElement("Frame", {
			Name = "Content",
			Position = UDim2.fromScale(layout.ContentPosition.X, layout.ContentPosition.Y),
			Size = UDim2.fromScale(layout.ContentSize.X, layout.ContentSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			CakeTitle = if cakeCount > 0
				then React.createElement(OutlinedText, {
					text = props.cakeTitle or "",
					position = UDim2.fromScale(layout.CakeTitlePosition.X, layout.CakeTitlePosition.Y),
					size = UDim2.fromScale(layout.CakeTitleSize.X, layout.CakeTitleSize.Y),
					textGradient = layout.CakeHeadingGradient,
					outlineColor = layout.CakeHeadingOutlineColor or layout.TextOutlineColor,
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex,
				})
				else nil,
			CakePane = if cakeCount > 0
				then React.createElement(ScrollPane, {
					name = "CakeRail",
					position = UDim2.fromScale(layout.CakePanePosition.X, layout.CakePanePosition.Y),
					size = UDim2.fromScale(layout.CakePaneSize.X, layout.CakePaneSize.Y),
					windowFraction = 1,
					showScrollbar = false,
					scrollingDirection = if cakeHorizontal
						then Enum.ScrollingDirection.X
						else Enum.ScrollingDirection.Y,
					canvasWidthScale = if cakeHorizontal then cakeCanvasScale else nil,
					canvasHeightScale = if cakeHorizontal then nil else cakeCanvasScale,
					resetKey = cakeResetKey,
					resetScrollFraction = selectedCakeScrollFraction,
					contentDrag = {
						-- Keep the surface mounted through the close tween; the full-panel
						-- blocker sits above it, and retaining capture prevents fall-through
						-- if the shell's animation timing changes later.
						enabled = true,
						-- Busy still CAPTURES pointer input, but freezes movement. Letting
						-- events fall through would make a drag log as a dead cake tap.
						scrollingEnabled = interactive,
						thresholdPx = 8,
						onTap = onCakeCanvasTap,
					},
					zIndex = zIndex,
				}, cakeChildren)
				else nil,
			CakeNotice = if cakeCount > 0
					and type(cakeNoticeText) == "string"
					and cakeNoticeText ~= ""
					and hasCakeNoticeSlot
					and not cakeNoticeUsesStatus
				then React.createElement(OutlinedText, {
					text = cakeNoticeText,
					position = UDim2.fromScale(
						layout.CakeNoticePosition.X,
						layout.CakeNoticePosition.Y
					),
					size = UDim2.fromScale(layout.CakeNoticeSize.X, layout.CakeNoticeSize.Y),
					textGradient = layout.CakeNoticeGradient or layout.StatusGradient,
					outlineColor = layout.CakeNoticeOutlineColor or layout.TextOutlineColor,
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex,
				})
				else nil,
			DifficultyTitle = React.createElement(OutlinedText, {
				text = props.difficultyTitle or "",
				position = UDim2.fromScale(
					layout.DifficultyTitlePosition.X,
					layout.DifficultyTitlePosition.Y
				),
				size = UDim2.fromScale(layout.DifficultyTitleSize.X, layout.DifficultyTitleSize.Y),
				textGradient = layout.SetupHeadingGradient,
				outlineColor = layout.TextOutlineColor,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex,
			}),
			DifficultyList = React.createElement("Frame", {
				Name = "DifficultyList",
				Position = UDim2.fromScale(layout.DifficultyListPosition.X, layout.DifficultyListPosition.Y),
				Size = UDim2.fromScale(layout.DifficultyListSize.X, layout.DifficultyListSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, difficultyChildren),
			PartyTitle = React.createElement(OutlinedText, {
				text = props.playersTitle or "",
				position = UDim2.fromScale(layout.PartyTitlePosition.X, layout.PartyTitlePosition.Y),
				size = UDim2.fromScale(layout.PartyTitleSize.X, layout.PartyTitleSize.Y),
				textGradient = layout.SetupHeadingGradient,
				outlineColor = layout.TextOutlineColor,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex,
			}),
			PartyRow = React.createElement("Frame", {
				Name = "PartyRow",
				Position = UDim2.fromScale(layout.PartyRowPosition.X, layout.PartyRowPosition.Y),
				Size = UDim2.fromScale(layout.PartyRowSize.X, layout.PartyRowSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, partyChildren),
			Status = if layout.ShowStatus ~= false
					and type(statusDisplayText) == "string"
					and statusDisplayText ~= ""
				then React.createElement(OutlinedText, {
				text = statusDisplayText,
				position = UDim2.fromScale(layout.StatusPosition.X, layout.StatusPosition.Y),
				size = UDim2.fromScale(layout.StatusSize.X, layout.StatusSize.Y),
				textGradient = if hasError
					then layout.ErrorGradient
					elseif statusUsesCakeNotice
					then (layout.CakeNoticeGradient or layout.StatusGradient)
					else layout.StatusGradient,
				outlineColor = if hasError
					then (layout.ErrorOutlineColor or layout.TextOutlineColor)
					elseif statusUsesCakeNotice
					then (layout.CakeNoticeOutlineColor or layout.TextOutlineColor)
					else (layout.StatusOutlineColor or layout.TextOutlineColor),
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex,
			})
				else nil,
			-- CanvasGroup clips its descendants. Inflate it around the CTA and
			-- inversely deflate the Button so pulse + hover stay visible at peak.
			Start = React.createElement("CanvasGroup", {
				Name = "Start",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(
					layout.StartPosition.X + layout.StartSize.X / 2,
					layout.StartPosition.Y + layout.StartSize.Y / 2
				),
				Size = UDim2.fromScale(
					layout.StartSize.X * startPulseHeadroom,
					layout.StartSize.Y * startPulseHeadroom
				),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				GroupTransparency = if canStart then 0 else layout.StartDisabledTransparency,
				ZIndex = zIndex,
			}, {
				Button = React.createElement(Button, {
					name = "StartButton",
					anchorPoint = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
					size = UDim2.fromScale(1 / startPulseHeadroom, 1 / startPulseHeadroom),
					text = if hasError and layout.ShowStatus == false
						then errorText
						elseif busy then (props.busyText or "")
						else (props.startText or ""),
					style = Theme.MatchmakingStartButton,
					textXAlignment = Enum.TextXAlignment.Center,
					enabled = canStart,
					pulse = canStart,
					zIndex = zIndex,
				onActivated = function()
					if launchLockRef.current.locked or not props.onStart then
						return
					end
					local latestChoice = choiceRef.current
					if latestChoice.sessionKey ~= sessionKey then
						return
					end
					local difficulty = if offered(difficultyOptions, latestChoice.difficulty)
						then latestChoice.difficulty
						else selectedDifficulty
					local maxPlayers = if offered(playerCounts, latestChoice.maxPlayers)
						then latestChoice.maxPlayers
						else selectedMaxPlayers
					if difficulty == nil or maxPlayers == nil then
						return
					end
					launchLockRef.current.locked = true
					launchLockRef.current.sawBusy = false
					props.onStart(difficulty, maxPlayers)
				end,
				}),
			}),
		}),
		-- `PanelShell` deliberately remains visible while it shrinks closed. This
		-- pointer-only layer appears on the same render that flips logical
		-- visibility, preventing any card/setup/START action during that tween.
		-- Underlying controls are also disabled above for controller input.
		ExitInputBlocker = if not panelVisible
			then React.createElement("TextButton", {
				Name = "ExitInputBlocker",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				Active = true,
				Selectable = false,
				ZIndex = zIndex + 100,
			})
			else nil,
	})
end

return MatchmakingPanel
