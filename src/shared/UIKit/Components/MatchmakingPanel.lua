--[[
	MatchmakingPanel -- wide two-step lobby match configurator.

	Players choose one difficulty and one party size, then start the match.
	Selections are local presentation state and reset whenever `sessionKey`
	changes. Server-owned busy/error/status state arrives through props.

	`onSelectDifficulty(id, isDefault)` / `onSelectPlayers(count, isDefault)` fire
	on each choice — they change nothing here (the state above already did), they
	exist so the choice itself is observable. Neither selection reaches the server
	unless START is pressed, which makes "chose a difficulty, then left" a real and
	otherwise unmeasurable outcome (docs/features/analytics.md).

	DEFAULTS (`defaultDifficulty` / `defaultPlayers`, from MatchConfig.defaults):
	a session opens with them already selected, so START is live on the first
	frame and a solo-easy run is ONE tap. They are applied per session, exactly
	where the old "clear the previous party's choices" reset was — and they are
	REPORTED through the same two callbacks with `isDefault = true`, because the
	player flow's `difficulty-pick` / `party-pick` steps sit between
	`selector-open` and `start-press`: leave them unreported and every player who
	simply presses START looks like a drop-off. What is lost by reporting is
	nothing, because "did a finger actually land on a choice" is carried by the
	kit's own press counting on the `Difficulty_*` / `Players_*` buttons.
	A default that is not among the offered options (a party size above the pad's
	cap, a retired difficulty) is ignored, leaving that row unselected.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local MatchChoice = require(script.Parent.MatchChoice)
local OutlinedText = require(script.Parent.OutlinedText)

local function optionParts(option)
	if type(option) == "table" then
		return option.id or option.value, option.label or ""
	end
	return option, tostring(option)
end

-- Is `value` one of the options this selector is actually offering right now?
-- The party-size row is filtered by the pad's cap and the difficulty list comes
-- from config, so a default can legitimately be absent.
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

local function MatchmakingPanel(props)
	local layout = props.layout or Theme.MatchmakingLayout
	local zIndex = props.contentZIndex or layout.ContentZIndex
	local busy = props.busy == true
	local difficultyOptions = props.difficultyOptions or {}
	local playerCounts = props.playerCounts or {}
	local defaultDifficulty = if offered(difficultyOptions, props.defaultDifficulty)
		then props.defaultDifficulty
		else nil
	local defaultMaxPlayers = if offered(playerCounts, props.defaultPlayers) then props.defaultPlayers else nil

	local selectedDifficulty, setSelectedDifficulty = React.useState(nil :: string?)
	local selectedMaxPlayers, setSelectedMaxPlayers = React.useState(nil :: number?)

	-- Read through a ref, never the effect's deps: the option lists and the two
	-- report callbacks are rebuilt by AppRoot on renders this effect must not
	-- re-run on. The effect's ONE trigger is a new session.
	local sessionRef = React.useRef(nil)
	sessionRef.current = {
		difficulty = defaultDifficulty,
		maxPlayers = defaultMaxPlayers,
		onDifficulty = props.onSelectDifficulty,
		onPlayers = props.onSelectPlayers,
	}

	-- A queue/configuration session owns its selections. Reopening for a new
	-- session must never carry choices from the previous party — it starts from
	-- the configured defaults instead of from nothing.
	local sessionKey = props.sessionKey or false
	React.useEffect(function()
		local latest = sessionRef.current
		setSelectedDifficulty(latest.difficulty)
		setSelectedMaxPlayers(latest.maxPlayers)
		-- Only a REAL session reports. This effect also runs on mount, and the
		-- panel is mounted (hidden) for the whole lobby visit — reporting there
		-- would put a "difficulty chosen" beat on every player who never went near
		-- a pad.
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

	local difficultyChildren = {}
	for index, option in ipairs(difficultyOptions) do
		local id, label = optionParts(option)
		difficultyChildren[`Choice_{tostring(id)}`] = React.createElement(MatchChoice, {
			name = `Difficulty_{tostring(id)}`,
			text = label,
			selected = selectedDifficulty == id,
			enabled = not busy,
			position = UDim2.fromScale(
				(index - 1) * (layout.DifficultyChoiceWidth + layout.DifficultyChoiceGap),
				0
			),
			size = UDim2.fromScale(layout.DifficultyChoiceWidth, 1),
			aspectRatio = layout.DifficultyChoiceAspectRatio,
			zIndex = zIndex,
			onActivated = function()
				setSelectedDifficulty(id)
				-- Reported OUT, not just kept in local state: a player who
				-- picks a difficulty and then walks away never sends anything
				-- to the server, so without this the most interesting drop-off
				-- in the lobby is invisible.
				if props.onSelectDifficulty then
					props.onSelectDifficulty(id)
				end
			end,
		})
	end

	local playerChildren = {}
	for index, option in ipairs(playerCounts) do
		local value, label = optionParts(option)
		playerChildren[`Choice_{tostring(value)}`] = React.createElement(MatchChoice, {
			name = `Players_{tostring(value)}`,
			text = label,
			selected = selectedMaxPlayers == value,
			enabled = not busy,
			position = UDim2.fromScale(
				(index - 1) * (layout.PlayerChoiceWidth + layout.PlayerChoiceGap),
				0
			),
			size = UDim2.fromScale(layout.PlayerChoiceWidth, 1),
			aspectRatio = layout.PlayerChoiceAspectRatio,
			zIndex = zIndex,
			onActivated = function()
				setSelectedMaxPlayers(value)
				if props.onSelectPlayers then
					props.onSelectPlayers(value)
				end
			end,
		})
	end

	local selectedCount = (if selectedDifficulty ~= nil then 1 else 0)
		+ (if selectedMaxPlayers ~= nil then 1 else 0)
	local ready = selectedCount == 2
	local canStart = ready and not busy
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
		statusText = props.busyStatusText or ""
	elseif selectedCount == 0 then
		statusText = props.unselectedStatusText or ""
	elseif selectedCount == 1 then
		statusText = props.partialStatusText or ""
	else
		statusText = props.readyStatusText or ""
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "MatchmakingPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "",
		onClose = props.onClose,
		closeEnabled = not busy,
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.HeaderWide,
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
			DifficultyTitle = React.createElement(OutlinedText, {
				text = props.difficultyTitle or "",
				position = UDim2.fromScale(
					layout.DifficultyTitlePosition.X,
					layout.DifficultyTitlePosition.Y
				),
				size = UDim2.fromScale(layout.DifficultyTitleSize.X, layout.DifficultyTitleSize.Y),
				textGradient = layout.HeadingGradient,
				outlineColor = layout.TextOutlineColor,
				textXAlignment = Enum.TextXAlignment.Left,
				zIndex = zIndex,
			}),
			DifficultyRow = React.createElement("Frame", {
				Name = "DifficultyRow",
				Position = UDim2.fromScale(layout.DifficultyRowPosition.X, layout.DifficultyRowPosition.Y),
				Size = UDim2.fromScale(layout.DifficultyRowSize.X, layout.DifficultyRowSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, difficultyChildren),
			PlayersTitle = React.createElement(OutlinedText, {
				text = props.playersTitle or "",
				position = UDim2.fromScale(layout.PlayersTitlePosition.X, layout.PlayersTitlePosition.Y),
				size = UDim2.fromScale(layout.PlayersTitleSize.X, layout.PlayersTitleSize.Y),
				textGradient = layout.HeadingGradient,
				outlineColor = layout.TextOutlineColor,
				textXAlignment = Enum.TextXAlignment.Left,
				zIndex = zIndex,
			}),
			PlayersRow = React.createElement("Frame", {
				Name = "PlayersRow",
				Position = UDim2.fromScale(layout.PlayersRowPosition.X, layout.PlayersRowPosition.Y),
				Size = UDim2.fromScale(layout.PlayersRowSize.X, layout.PlayersRowSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, playerChildren),
			Status = React.createElement(OutlinedText, {
				text = statusText,
				position = UDim2.fromScale(layout.StatusPosition.X, layout.StatusPosition.Y),
				size = UDim2.fromScale(layout.StatusSize.X, layout.StatusSize.Y),
				textGradient = if hasError then layout.ErrorGradient else layout.StatusGradient,
				outlineColor = layout.TextOutlineColor,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex,
			}),
			-- START. The CanvasGroup exists only to dim the whole button when it is
			-- not pressable — and a CanvasGroup CLIPS to its own bounds, which the
			-- attention pulse would grow straight through. So the group is inflated
			-- about the button's centre by StartPulseHeadroom and the button is
			-- deflated by the same factor inside it: the rest geometry is exactly
			-- what it was, with room for the breath (and for the press/hover bounce
			-- riding the same button).
			Start = React.createElement("CanvasGroup", {
				Name = "Start",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(
					layout.StartPosition.X + layout.StartSize.X / 2,
					layout.StartPosition.Y + layout.StartSize.Y / 2
				),
				Size = UDim2.fromScale(
					layout.StartSize.X * layout.StartPulseHeadroom,
					layout.StartSize.Y * layout.StartPulseHeadroom
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
					size = UDim2.fromScale(1 / layout.StartPulseHeadroom, 1 / layout.StartPulseHeadroom),
					text = if busy then (props.busyText or "") else (props.startText or ""),
					style = Theme.MatchmakingStartButton,
					textXAlignment = Enum.TextXAlignment.Center,
					enabled = canStart,
					-- Breathe exactly while the press would DO something. Tying it to
					-- `canStart` (not to `ready`) means the pulse also stops the moment
					-- the queue goes busy, so a button reading "STARTING..." never
					-- looks like it is still asking to be pressed.
					-- ⚠ ALSO gated on `visible`: with a default preselected `canStart`
					-- is true from MOUNT, and this panel is mounted-but-hidden for the
					-- whole lobby visit AND in the game place — so without this it
					-- would run an infinite TweenService tween on a button nobody can
					-- see, in both places, for the entire session.
					pulse = canStart and props.visible ~= false,
					zIndex = zIndex,
					onActivated = function()
						if props.onStart then
							props.onStart(selectedDifficulty, selectedMaxPlayers)
						end
					end,
				}),
			}),
		}),
	})
end

return MatchmakingPanel
