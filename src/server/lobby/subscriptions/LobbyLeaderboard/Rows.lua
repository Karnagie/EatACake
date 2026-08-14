--[[
	LobbyLeaderboard.Rows -- authored-board resolution, row cloning and text
	rendering. LobbyLeaderboardSubs owns the connections and the async ticks
	(R4); this module owns no clock and no connection.

	Row geometry is DERIVED from the artist's template, never hardcoded. A
	child's scale inside a ScrollingFrame is relative to the CANVAS, so the
	authored `FrameRank` at 0.02 of a 5.0-window-height canvas means one row is
	0.1 of the WINDOW and ten are on screen. For N rows:

	    canvas.Y.Scale = N * rowFraction        (rowFraction = 0.02 * 5.0 = 0.1)
	    row.Size.Y.Scale = 1 / N

	which reproduces the authored row height for any N. `rowFraction` is
	captured at the FIRST bind and stored on the bound board: re-deriving it
	from a CanvasSize a previous bind already rewrote would shrink every row by
	a further factor on each re-bind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "TopBoards"

local Rows = {}

local boardData
local service

function Rows.Init(data, leaderboardService)
	boardData = data
	service = leaderboardService
end

local function cfg()
	return boardData["board-config"]
end

--API
-- The board Models sit inside the environment clone, which sits inside the map
-- container. Bounded two-level lookup instead of a recursive FindFirstChild: a
-- recursive search would happily bind a same-named prop from elsewhere in the
-- hub. A DUPLICATE is reported — the copy nobody binds keeps its authored
-- "ExamplePlayerName / 999.9B" placeholder in front of every player.
function Rows.FindBoardModel(map: Instance, modelName: string): Instance?
	local matches = {}
	local direct = map:FindFirstChild(modelName)
	if direct ~= nil then
		table.insert(matches, direct)
	end
	for _, child in ipairs(map:GetChildren()) do
		local nested = child:FindFirstChild(modelName)
		if nested ~= nil then
			table.insert(matches, nested)
		end
	end
	if #matches > 1 then
		Log.Warn(
			SCOPE,
			`{#matches} instances named '{modelName}' under {map:GetFullName()} -- binding the first; `
				.. "the others keep their authored placeholder row and are visible to players"
		)
	end
	return matches[1]
end

-- Named TextLabel or nil. A row whose Rank/PlayerName is missing (or is some
-- other class) must degrade to "the columns that ARE there", never error inside
-- the render loop.
local function textLabel(row: Instance, labelName: string, boardId: string): TextLabel?
	local child = row:FindFirstChild(labelName)
	if child ~= nil and child:IsA("TextLabel") then
		return child
	end
	Log.Once(
		SCOPE,
		`label-{boardId}-{labelName}`,
		`board '{boardId}': the row template has no TextLabel named '{labelName}' -- that column stays as authored`
	)
	return nil
end

-- The value label carries the number. Its authored NAME is per-board legacy
-- (Kills / Rebirths / Strength), so a rename in Studio would silently blank the
-- column -- fall back to "the one text label that is neither the rank nor the
-- name" and say so. Resolved ONCE per board off the template, never per row:
-- the same warn fifty times would bury the rest of the boot report (R8).
local function valueLabelName(template: Instance, board): string?
	local configured = template:FindFirstChild(board.valueLabelName)
	if configured ~= nil and configured:IsA("TextLabel") then
		return board.valueLabelName
	end
	local names = cfg()
	for _, child in ipairs(template:GetChildren()) do
		if child:IsA("TextLabel") and child.Name ~= names.rankLabelName and child.Name ~= names.nameLabelName then
			Log.Warn(
				SCOPE,
				`board '{board.id}': no TextLabel named '{board.valueLabelName}' in the row template -- `
					.. `falling back to '{child.Name}'. Update GlobalLeaderboardData.boards if the label was renamed.`
			)
			return child.Name
		end
	end
	Log.Warn(
		SCOPE,
		`board '{board.id}': the row template has no value TextLabel ('{board.valueLabelName}') -- `
			.. "rows will show a rank and a name with no number (docs/features/leaderboards.md)"
	)
	return nil
end

--API
-- Rebuilds a board's rows from its authored template. Returns the bound record
-- `{ rows, scroll, rowFraction }`, or nil if nothing usable was found.
function Rows.Build(board, scroll: ScrollingFrame, template: Frame, previous)
	local requested = math.floor(cfg().entryCount)
	-- The read side pages at 100 (GetSortedAsync's hard maximum), so rows past
	-- that could never be filled -- 50 permanently blank rows of dead scroll
	-- with nothing in the console to explain them.
	local count = math.clamp(requested, 1, 100)
	if count ~= requested then
		Log.Warn(SCOPE, `board-config.entryCount {requested} clamped to {count} -- GetSortedAsync pages at 100`)
	end

	-- Idempotence: a second Bind on the SAME map must not leave the previous
	-- generation of rows parented and visible underneath the new one.
	local cleared = 0
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and child ~= template then
			child:Destroy()
			cleared += 1
		end
	end
	if cleared > 0 then
		Log.Info(SCOPE, `board '{board.id}': cleared {cleared} row(s) from a previous bind`)
	end

	-- Captured at FIRST bind: `scroll.CanvasSize` is something this function
	-- writes, so re-deriving from it on a re-bind compounds.
	local rowFraction = previous and previous.rowFraction
	if type(rowFraction) ~= "number" or rowFraction <= 0 then
		rowFraction = template.Size.Y.Scale * scroll.CanvasSize.Y.Scale
	end
	if rowFraction <= 0 then
		rowFraction = cfg().rowFraction
		Log.Warn(
			SCOPE,
			`board '{board.id}': the authored row/canvas scales are zero -- using the {rowFraction} fallback row height`
		)
	end

	scroll.CanvasSize = UDim2.new(scroll.CanvasSize.X.Scale, scroll.CanvasSize.X.Offset, rowFraction * count, 0)
	if scroll.ScrollingDirection ~= Enum.ScrollingDirection.Y then
		-- Authored as XY. The rows are exactly canvas-wide, so a horizontal drag
		-- can only shake them; it is not a layout the artist chose.
		scroll.ScrollingDirection = Enum.ScrollingDirection.Y
		Log.Info(SCOPE, `board '{board.id}': ScrollingDirection XY -> Y`)
	end

	local valueName = valueLabelName(template, board)
	local rows = {}
	for index = 1, count do
		local row = template:Clone()
		row.Name = `Row{index}`
		-- A UIListLayout writes Position; an AnchorPoint of (0.5,0.5) would then
		-- shift every row half its own size up and left. The authored template
		-- keeps its anchor because it is placed by hand in Studio.
		row.AnchorPoint = Vector2.zero
		row.Position = UDim2.new(0, 0, 0, 0)
		row.Size = UDim2.new(template.Size.X.Scale, template.Size.X.Offset, 1 / count, 0)
		row.LayoutOrder = index
		row.Visible = false

		local entry = {
			frame = row,
			rank = textLabel(row, cfg().rankLabelName, board.id),
			name = textLabel(row, cfg().nameLabelName, board.id),
			value = if valueName ~= nil then textLabel(row, valueName, board.id) else nil,
		}
		-- Player names and scores are DATA. Auto-translation would run them
		-- through the cloud localization table (features/localization.md).
		-- ⚠ Not an array literal + ipairs: any of the three may legitimately be
		-- nil, and ipairs stops at the first hole.
		for _, label in pairs({ rank = entry.rank, name = entry.name, value = entry.value }) do
			label.AutoLocalize = false
		end
		row.Parent = scroll
		table.insert(rows, entry)
	end
	Log.Info(
		SCOPE,
		`board '{board.id}': {count} row(s) built (row = {string.format("%.3f", rowFraction)} of the window, `
			.. `anchor zeroed for the UIListLayout)`
	)
	return { rows = rows, scroll = scroll, rowFraction = rowFraction }
end

--API
-- Paints the cached page onto a bound board. Rows past the entry count hide.
function Rows.Render(boardId: string)
	local bound = boardData["bound-boards"][boardId]
	local board = boardData.Board(boardId)
	if bound == nil or board == nil then
		return
	end
	local entries = boardData["entries-by-board"][boardId] or {}
	for index, row in ipairs(bound.rows) do
		local entry = entries[index]
		if entry == nil then
			row.frame.Visible = false
		else
			if row.rank ~= nil then
				row.rank.Text = service.FormatRank(index)
			end
			if row.name ~= nil then
				row.name.Text = service.NameFor(entry.userId)
			end
			if row.value ~= nil then
				row.value.Text = service.FormatValue(board.format, entry.value)
			end
			row.frame.Visible = true
		end
	end
end

return Rows
