--[[
	MatchmakingPanel -- wide two-step lobby match configurator.

	Players choose one difficulty and one party size, then start the match.
	Selections are local presentation state and reset whenever `sessionKey`
	changes. Server-owned busy/error/status state arrives through props.
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

local function MatchmakingPanel(props)
	local layout = props.layout or Theme.MatchmakingLayout
	local zIndex = props.contentZIndex or layout.ContentZIndex
	local busy = props.busy == true
	local selectedDifficulty, setSelectedDifficulty = React.useState(nil :: string?)
	local selectedMaxPlayers, setSelectedMaxPlayers = React.useState(nil :: number?)

	-- A queue/configuration session owns its selections. Reopening for a new
	-- session must never carry choices from the previous party.
	React.useEffect(function()
		setSelectedDifficulty(nil)
		setSelectedMaxPlayers(nil)
	end, { props.sessionKey or false })

	local difficultyChildren = {}
	for index, option in ipairs(props.difficultyOptions or {}) do
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
			end,
		})
	end

	local playerChildren = {}
	for index, option in ipairs(props.playerCounts or {}) do
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
			Start = React.createElement("CanvasGroup", {
				Name = "Start",
				Position = UDim2.fromScale(layout.StartPosition.X, layout.StartPosition.Y),
				Size = UDim2.fromScale(layout.StartSize.X, layout.StartSize.Y),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				GroupTransparency = if canStart then 0 else layout.StartDisabledTransparency,
				ZIndex = zIndex,
			}, {
				Button = React.createElement(Button, {
					name = "StartButton",
					text = if busy then (props.busyText or "") else (props.startText or ""),
					style = Theme.MatchmakingStartButton,
					textXAlignment = Enum.TextXAlignment.Center,
					enabled = canStart,
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
