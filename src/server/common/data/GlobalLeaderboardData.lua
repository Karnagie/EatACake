--[[
	GlobalLeaderboardData — the three in-world LOBBY leaderboards (R1: every
	constant and every piece of runtime state for the feature lives here).

	Three boards, all authored under ReplicatedStorage.Assets.LobbyEnvironment
	and cloned into workspace.LobbyMap by LobbyMapService (ADR-0007):

	  TopGems         lifetime gems COLLECTED (not the spendable balance)
	  TopSpeedrunners fastest single cake, ASCENDING (lower is better)
	  TopCakeCount    lifetime cakes finished

	`boards` is the whole contract between the profile, the OrderedDataStores and
	the authored GUI:
	  id             stable board id; also the DataStore name suffix
	  modelName      authored Model under the LobbyEnvironment clone
	  valueLabelName the authored TextLabel inside the row template that carries
	                 the NUMBER. The three boards were authored from different
	                 kit sources, so these names are legacy and inconsistent
	                 (Kills / Rebirths / Strength) — renaming them in Studio would
	                 mean re-saving the place, so the code reads what is there.
	  statKey        field of ProgressService.Summary (== the profile field)
	  ascending      sort order of GetSortedAsync; TRUE means "smallest wins"
	  format         how GlobalLeaderboardService renders the value

	⚠ `store-version` is part of every DataStore name: bumping it starts every
	board EMPTY and is the only way to wipe one (an OrderedDataStore has no
	"clear"). Change it if a stat's UNITS or meaning ever change — e.g. if
	`bestCakeMillis` stopped being milliseconds, every old row would outrank
	every new one forever.

	Runtime shape (owned by GlobalLeaderboardService / the two subscriptions):
	  store-by-board        [boardId] = OrderedDataStore
	  store-state           "unknown" | "ok" | "unavailable" (R8 boot report)
	  entries-by-board      [boardId] = { { userId, value } } — last good fetch
	  name-by-user-id       [userId] = display name (resolved once, cached)
	  published-by-user-id  [userId] = { [boardId] = last value COMMITTED }
	  bound-boards          [boardId] = { rows, scroll, rowFraction }
	  connections           subscription-owned RBXScriptConnections
	  refresh-accumulator / publish-accumulator   Heartbeat scheduling clocks
	  refresh-busy / publish-busy                 re-entry guards for the async
	                        ticks, with a *-busy-since os.clock stamp so a latch
	                        that never clears is force-cleared and reported
	                        instead of silently stopping the feature (R8)
]]

local GlobalLeaderboardData = {}

GlobalLeaderboardData["board-config"] = {
	-- DataStore naming. Final name is `<store-prefix><board id>_v<store-version>`.
	storePrefix = "EatACakeTop_",
	storeVersion = 1,

	-- Rows per board. 50 is the AUTHORED canvas: the row template is 0.02 of a
	-- canvas that is 5.0 window-heights tall, i.e. 0.1 of the window per row and
	-- 10 rows visible at a time. Any other count still renders correctly (the
	-- canvas and the row height are both derived, see LobbyLeaderboardSubs), but
	-- 50 is what the artist sized the scroll bar for. Hard cap: GetSortedAsync
	-- pages at 100.
	entryCount = 50,

	-- Read/write cadence. Both are far inside the platform budgets
	-- (GetSortedAsync: 5 + 2/player per minute; SetAsync: 60 + 10/player).
	refreshSeconds = 60, -- lobby re-reads all three boards
	publishSeconds = 120, -- a live player's changed values are re-written
	firstRefreshDelaySeconds = 3, -- let the map finish replicating before the first read

	-- Authored GUI contract, resolved by exact name off each board Model.
	screenName = "Screen1",
	mainFrameName = "MainFrame",
	scrollFrameName = "ScrollingFrame",
	rowTemplateName = "FrameRank",
	nameLabelName = "PlayerName",
	rankLabelName = "Rank",

	-- Fallbacks. `rowFraction` is only used if the authored template has no
	-- usable scale (0.02 template * 5.0 canvas = 0.1 of the window per row).
	rowFraction = 0.1,
	unknownName = "?",

	-- Value rendering (R2: the service holds the logic, these are the values).
	-- The authored placeholder is "999.9B", so the boards were designed for
	-- abbreviated counts. Largest threshold first.
	countSuffixes = {
		{ at = 1e12, suffix = "T" },
		{ at = 1e9, suffix = "B" },
		{ at = 1e6, suffix = "M" },
		{ at = 1e3, suffix = "K" },
	},
	rankPrefix = "#",
}

GlobalLeaderboardData.boards = {
	{
		id = "gems",
		modelName = "TopGems",
		valueLabelName = "Kills",
		statKey = "lifetimeGems",
		ascending = false,
		format = "count",
	},
	{
		id = "speedrun",
		modelName = "TopSpeedrunners",
		valueLabelName = "Rebirths",
		statKey = "bestCakeMillis",
		ascending = true,
		format = "time",
	},
	{
		id = "cakes",
		modelName = "TopCakeCount",
		valueLabelName = "Strength",
		statKey = "cakesEaten",
		ascending = false,
		format = "count",
	},
}

GlobalLeaderboardData["store-by-board"] = {}
GlobalLeaderboardData["store-state"] = "unknown"
GlobalLeaderboardData["entries-by-board"] = {}
GlobalLeaderboardData["name-by-user-id"] = {}
GlobalLeaderboardData["published-by-user-id"] = {}
GlobalLeaderboardData["bound-boards"] = {}
GlobalLeaderboardData.connections = {}
GlobalLeaderboardData["refresh-accumulator"] = 0
GlobalLeaderboardData["publish-accumulator"] = 0
GlobalLeaderboardData["refresh-busy"] = false
GlobalLeaderboardData["publish-busy"] = false
GlobalLeaderboardData["refresh-busy-since"] = 0
GlobalLeaderboardData["publish-busy-since"] = 0

function GlobalLeaderboardData.Init()
	GlobalLeaderboardData["store-by-board"] = {}
	GlobalLeaderboardData["store-state"] = "unknown"
	GlobalLeaderboardData["entries-by-board"] = {}
	GlobalLeaderboardData["name-by-user-id"] = {}
	GlobalLeaderboardData["published-by-user-id"] = {}
	GlobalLeaderboardData["bound-boards"] = {}
	GlobalLeaderboardData.connections = {}
	GlobalLeaderboardData["refresh-accumulator"] = 0
	GlobalLeaderboardData["publish-accumulator"] = 0
	GlobalLeaderboardData["refresh-busy"] = false
	GlobalLeaderboardData["publish-busy"] = false
	GlobalLeaderboardData["refresh-busy-since"] = 0
	GlobalLeaderboardData["publish-busy-since"] = 0
end

--API
-- Board definition by id, or nil.
function GlobalLeaderboardData.Board(boardId: string)
	for _, board in ipairs(GlobalLeaderboardData.boards) do
		if board.id == boardId then
			return board
		end
	end
	return nil
end

return GlobalLeaderboardData
