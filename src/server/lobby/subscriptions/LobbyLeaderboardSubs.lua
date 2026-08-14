--[[
	LobbyLeaderboardSubs — the three authored leaderboard screens in the lobby
	hub (lobby partition; the boards only exist in LobbyEnvironment).

	This file owns the CONNECTIONS and the async ticks (R4). Authored-board
	resolution, row cloning and rendering live in `LobbyLeaderboard/Rows.lua`
	(R7) — that is where the ScrollingFrame geometry contract is explained.

	Bound from LobbySubs AFTER LobbyMapService.Build, exactly like
	LobbyQueueSubs.Bind: the models are place-authored (ADR-0007), so nothing
	here creates a view object — it CLONES the authored `FrameRank` row (R5).

	Authored contract (docs/features/leaderboards.md):
	  <Board Model>.Screen1.SurfaceGui.MainFrame.ScrollingFrame
	    UIListLayout
	    FrameRank            row TEMPLATE, authored Visible = false
	      Rank               "#1"
	      PlayerName         the player
	      <value label>      the number; the authored name differs per board
	                         (Kills / Rebirths / Strength) — GlobalLeaderboardData
	                         carries the mapping
	      <icon>             authored ImageLabel, cloned untouched

	Everything the server writes replicates as ordinary instance properties;
	there is no remote and no client module for this feature.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Helpers = script.Parent:WaitForChild("LobbyLeaderboard")
local Rows = require(Helpers:WaitForChild("Rows"))

local SCOPE = "TopBoards"

local LobbyLeaderboardSubs = {}

local boardData
local services_
local armed = false

local function cfg()
	return boardData["board-config"]
end

-- One pass over all three boards. Yields (DataStore + name resolution), so it
-- always runs inside a spawned thread behind the `refresh-busy` latch.
local function refreshAll()
	for _, board in ipairs(boardData.boards) do
		if boardData["bound-boards"][board.id] ~= nil then
			local ok, entries = pcall(services_.GlobalLeaderboardService.Fetch, board.id)
			if not ok then
				Log.Warn(SCOPE, `board '{board.id}': fetch threw — {entries}`)
			elseif entries ~= nil then
				-- nil means the read failed and the service already reported it:
				-- keep the last good page rather than blanking a live board.
				boardData["entries-by-board"][board.id] = entries
				local userIds = {}
				for _, entry in ipairs(entries) do
					table.insert(userIds, entry.userId)
				end
				local names_ok, err = pcall(services_.GlobalLeaderboardService.ResolveNames, userIds)
				if not names_ok then
					Log.Once(SCOPE, `names-{board.id}`, `board '{board.id}': name resolution failed — {err}`)
				end
			end
			local render_ok, render_err = pcall(Rows.Render, board.id)
			if not render_ok then
				Log.Warn(SCOPE, `board '{board.id}': render failed — {render_err}`)
			end
		end
	end
end

local function refreshTick()
	if boardData["refresh-busy"] then
		-- Skipping an overlapping pass is normally correct — the next tick reads
		-- the same stores. But a latch that never clears would freeze the boards
		-- FOREVER while saying nothing after the first line, which is the silent
		-- skip R8 forbids; past three periods it is force-cleared and reported.
		local age = os.clock() - (boardData["refresh-busy-since"] or 0)
		if age > cfg().refreshSeconds * 3 then
			Log.Warn(SCOPE, `board refresh has been running {math.floor(age)}s (> 3 periods) -- latch force-cleared`)
			boardData["refresh-busy"] = false
		else
			Log.Once(SCOPE, "refresh-overlap", "a board refresh was still running when the next tick fired -- skipped")
			return
		end
	end
	boardData["refresh-busy"] = true
	boardData["refresh-busy-since"] = os.clock()
	task.spawn(function()
		local ok, err = pcall(refreshAll)
		if not ok then
			Log.Warn(SCOPE, `board refresh FAILED — {err}`)
		end
		boardData["refresh-busy"] = false
	end)
end

--API
-- Wires the authored boards of a freshly built lobby map. Returns how many of
-- the three bound. Safe to call again — on a rebuilt map (the old rows died
-- with the old clone) AND on the same map (Rows.Build clears the previous
-- generation and reuses the row height captured at the first bind).
function LobbyLeaderboardSubs.Bind(map: Instance): number
	if boardData == nil or services_ == nil then
		Log.Warn(SCOPE, "Bind skipped: Start dependencies unavailable")
		return 0
	end
	if typeof(map) ~= "Instance" then
		Log.Warn(SCOPE, "Bind skipped: LobbyMapService returned no map instance")
		return 0
	end

	local previous = boardData["bound-boards"]
	local bound = {}
	local names = cfg()
	local count = 0
	for _, board in ipairs(boardData.boards) do
		local model = Rows.FindBoardModel(map, board.modelName)
		if model == nil then
			Log.Warn(
				SCOPE,
				`board '{board.id}': authored Model '{board.modelName}' not found under {map:GetFullName()} — `
					.. "that board stays blank (docs/features/leaderboards.md)"
			)
			continue
		end
		local screen = model:FindFirstChild(names.screenName)
		local gui = screen and screen:FindFirstChildOfClass("SurfaceGui")
		local main = gui and gui:FindFirstChild(names.mainFrameName)
		local scroll = main and main:FindFirstChild(names.scrollFrameName)
		local template = scroll and scroll:FindFirstChild(names.rowTemplateName)
		if scroll == nil or not scroll:IsA("ScrollingFrame") or template == nil or not template:IsA("Frame") then
			Log.Warn(
				SCOPE,
				`board '{board.id}': GUI contract incomplete — expected `
					.. `{board.modelName}.{names.screenName}.SurfaceGui.{names.mainFrameName}.{names.scrollFrameName}.{names.rowTemplateName} `
					.. "(docs/features/leaderboards.md); that board stays blank"
			)
			continue
		end
		if scroll:FindFirstChildOfClass("UIListLayout") == nil then
			Log.Warn(SCOPE, `board '{board.id}': the ScrollingFrame has no UIListLayout — rows would stack on top of each other`)
			continue
		end
		-- The template must never show: it is the "ExamplePlayerName / 999.9B"
		-- placeholder. A UIListLayout skips invisible children, so leaving it
		-- parented costs nothing.
		template.Visible = false

		local record = Rows.Build(board, scroll, template, previous[board.id])
		if record ~= nil then
			bound[board.id] = record
			count += 1
		end
	end
	boardData["bound-boards"] = bound

	if count == 0 then
		Log.Warn(SCOPE, "no authored leaderboard bound -- the lobby boards will stay empty")
		return 0
	end
	Log.Sum(SCOPE, `{count}/{#boardData.boards} leaderboard(s) bound, {cfg().entryCount} rows each`)

	-- Paint whatever a previous refresh already fetched, then read fresh.
	for boardId in pairs(bound) do
		pcall(Rows.Render, boardId)
	end
	-- Delayed, not immediate: the map has just been parented and the first read
	-- is a yielding web call that would otherwise land inside the boot report.
	task.delay(cfg().firstRefreshDelaySeconds, refreshTick)
	boardData["refresh-accumulator"] = 0
	return count
end

function LobbyLeaderboardSubs.Start(data, services)
	boardData = data.GlobalLeaderboardData
	services_ = services
	if boardData == nil or boardData["board-config"] == nil then
		Log.Warn(SCOPE, "GlobalLeaderboardData missing -- the lobby leaderboards cannot render")
		boardData = nil
		return
	end
	if services.GlobalLeaderboardService == nil then
		Log.Warn(SCOPE, "GlobalLeaderboardService missing -- the lobby leaderboards cannot render")
		boardData = nil
		return
	end
	if armed then
		return
	end
	armed = true
	Rows.Init(boardData, services.GlobalLeaderboardService)

	local refreshSeconds = cfg().refreshSeconds
	boardData["refresh-accumulator"] = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		if next(boardData["bound-boards"]) == nil then
			return -- nothing bound yet (or no authored boards in this place)
		end
		boardData["refresh-accumulator"] += dt
		if boardData["refresh-accumulator"] >= refreshSeconds then
			boardData["refresh-accumulator"] = 0
			refreshTick()
		end
	end)
	table.insert(boardData.connections, connection)
	-- ⚠ "armed", not "running": in the COMBINED build LobbySubs never builds the
	-- hub, so Bind is never called and this tick can never fire. Saying so here
	-- keeps the console from claiming a live feature that structurally is not
	-- (R8) — LobbySubs logs the combined-build skip itself.
	Log.Info(SCOPE, `lobby boards armed: refresh every {refreshSeconds}s once LobbySubs binds a map`)
end

return LobbyLeaderboardSubs
