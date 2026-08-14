--[[
	GlobalLeaderboardService — the three cross-server leaderboards, over
	OrderedDataStore (R2: logic only; every name/number lives in
	GlobalLeaderboardData).

	⚠ This is the ONE documented carve-out from P5 (ADR-0022). P5 forbids direct
	DataStoreService use because a profile must never be read or written outside
	the ProfileStore SESSION. These stores hold no profile data: they are a
	throw-away PROJECTION of three numbers the profile already owns, keyed by
	userId, written only from the profile and never read back into it. Losing
	them costs a board, not a save. Nothing here touches a profile — the caller
	passes values in and gets rows out.

	Read/write split:
	  Publish(userId, values)  one SetAsync per CHANGED board (the caller does
	                           the change test); the profile stays the source of
	                           truth, so a re-publish is idempotent and a
	                           BETTER-only stat like the speedrun time can never
	                           be made worse by a later write.
	  Fetch(boardId)           one GetSortedAsync page, newest good page cached
	                           by the caller in the data module.

	Zero is NOT a score. A player with no gems, no cake and no run has three
	zeroes, and on the ASCENDING speedrun board a zero would take first place
	forever. `Publish` drops non-positive values instead of writing them.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "TopBoards"

local GlobalLeaderboardService = {}

local boardData
local persistenceData

local function config()
	return boardData and boardData["board-config"]
end

-- Every DataStore failure funnels through here so that "no DataStore access"
-- (Studio with API services off, unpublished place) is reported ONCE and loudly
-- rather than once per tick per board (R8).
local function reportFailure(what: string, err: any)
	if boardData["store-state"] ~= "unavailable" then
		boardData["store-state"] = "unavailable"
		Log.Warn(
			SCOPE,
			`{what} FAILED — the in-world leaderboards will not update ({err}). `
				.. `(Studio: Game Settings -> Security -> Enable Studio Access to API Services, and publish the place.)`
		)
	else
		Log.Once(SCOPE, `store-fail-{what}`, `{what} FAILED — {err}`)
	end
end

local function reportSuccess()
	if boardData["store-state"] ~= "ok" then
		boardData["store-state"] = "ok"
		Log.Sum(SCOPE, "OrderedDataStore access OK — global leaderboards are live")
	end
end

-- `PersistenceData.useMockInStudio` promises "nothing is written to live
-- DataStore keys" in a Studio test. That promise covered ProfileStore only, so
-- the day someone flips the flag, Studio would run a throwaway mock profile and
-- still SetAsync to the LIVE boards — with debug-shortened cakes behind it.
-- Mirror the flag here so the two halves of "Studio is sandboxed" agree.
local function mockGuardActive(): boolean
	if not RunService:IsStudio() or persistenceData == nil or persistenceData.useMockInStudio ~= true then
		return false
	end
	Log.Once(
		SCOPE,
		"studio-mock",
		"PersistenceData.useMockInStudio is ON — leaderboard writes are SUPPRESSED in Studio so a test session cannot reach the live boards"
	)
	return true
end

function GlobalLeaderboardService.Init(data)
	boardData = data.GlobalLeaderboardData
	persistenceData = data.PersistenceData
	if boardData == nil then
		Log.Warn(SCOPE, "GlobalLeaderboardData missing — global leaderboards disabled")
		return
	end
	local cfg = config()
	if cfg == nil then
		Log.Warn(SCOPE, "GlobalLeaderboardData['board-config'] missing — global leaderboards disabled")
		boardData = nil
		return
	end

	-- GetOrderedDataStore does not yield and does not need API access; only the
	-- async calls do. Resolving here means a missing store is a boot-time warn.
	local resolved = 0
	for _, board in ipairs(boardData.boards) do
		local storeName = `{cfg.storePrefix}{board.id}_v{cfg.storeVersion}`
		local ok, store_or_err = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, storeName)
		if ok and store_or_err ~= nil then
			boardData["store-by-board"][board.id] = store_or_err
			resolved += 1
		else
			Log.Warn(SCOPE, `board '{board.id}': GetOrderedDataStore('{storeName}') failed — {store_or_err}`)
		end
	end
	Log.Info(SCOPE, `{resolved}/{#boardData.boards} ordered store(s) resolved (v{cfg.storeVersion})`)
end

--API
-- True when the feature has its data module and at least one store.
function GlobalLeaderboardService.IsAvailable(): boolean
	if boardData == nil then
		return false
	end
	return next(boardData["store-by-board"]) ~= nil
end

--API
-- Writes one player's values. `values` is keyed by BOARD ID (not stat key) so
-- the caller decides what changed; non-positive and non-finite values are
-- dropped, never written.
-- Returns the SET of board ids that actually COMMITTED, `{ [boardId] = true }`.
-- ⚠ A count would be a lie the caller cannot detect: with two boards changed
-- and one SetAsync throttled, "1 written" tells the caller nothing about WHICH,
-- and marking both as published would strand the failed value until it changes
-- again (a first-ever cake time never changes again unless it is beaten).
-- ⚠ YIELDS (one SetAsync per changed board). Call it from a spawned thread.
function GlobalLeaderboardService.Publish(userId: number, values: { [string]: number }): { [string]: boolean }
	local committed = {}
	if boardData == nil or type(userId) ~= "number" or type(values) ~= "table" then
		Log.Once(SCOPE, "publish-disabled", "Publish called with no data module or bad arguments -- nothing is being written")
		return committed
	end
	if mockGuardActive() then
		return committed
	end
	local key = tostring(userId)
	for _, board in ipairs(boardData.boards) do
		local value = values[board.id]
		local store = boardData["store-by-board"][board.id]
		if store ~= nil and type(value) == "number" and value == value and value > 0 and value < math.huge then
			local rounded = math.floor(value + 0.5)
			local ok, err = pcall(store.SetAsync, store, key, rounded)
			if ok then
				committed[board.id] = true
				reportSuccess()
			else
				reportFailure(`SetAsync(board '{board.id}')`, err)
			end
		end
	end
	return committed
end

--API
-- One page of a board, best first. Returns an array of { userId, value } (may
-- be empty) or NIL when the read failed — the caller keeps its last good page
-- rather than blanking the board on one throttled call.
-- ⚠ YIELDS. Call it from a spawned thread.
function GlobalLeaderboardService.Fetch(boardId: string): { { userId: number, value: number } }?
	if boardData == nil then
		return nil
	end
	local board = boardData.Board(boardId)
	local store = boardData["store-by-board"][boardId]
	if board == nil or store == nil then
		Log.Once(SCOPE, `fetch-no-store-{boardId}`, `board '{boardId}' has no ordered store — it will stay empty`)
		return nil
	end
	local cfg = config()
	local pageSize = math.clamp(math.floor(cfg.entryCount), 1, 100)
	local ok, pages = pcall(store.GetSortedAsync, store, board.ascending == true, pageSize)
	if not ok then
		reportFailure(`GetSortedAsync(board '{boardId}')`, pages)
		return nil
	end
	local page_ok, page = pcall(pages.GetCurrentPage, pages)
	if not page_ok then
		reportFailure(`GetCurrentPage(board '{boardId}')`, page)
		return nil
	end
	reportSuccess()

	local entries = {}
	for _, row in ipairs(page) do
		local id = tonumber(row.key)
		local value = tonumber(row.value)
		-- A row whose key is not a userId cannot be rendered (no name to
		-- resolve) and a non-positive value is the "no score" state Publish
		-- refuses to write — both mean legacy or corrupt data, so skip them.
		if id ~= nil and id > 0 and value ~= nil and value > 0 then
			table.insert(entries, { userId = math.floor(id), value = value })
		end
	end
	return entries
end

--API
-- Fills the shared name cache for every uncached id. One batched UserService
-- call covers the whole board; ids it cannot answer for fall back to the
-- Players endpoint, and an id that fails both is cached as the placeholder so a
-- deleted account cannot re-request forever.
-- ⚠ YIELDS. Call it from a spawned thread.
function GlobalLeaderboardService.ResolveNames(userIds: { number })
	if boardData == nil then
		return
	end
	local cache = boardData["name-by-user-id"]
	local missing = {}
	local seen = {}
	for _, userId in ipairs(userIds) do
		if cache[userId] == nil and not seen[userId] then
			seen[userId] = true
			table.insert(missing, userId)
		end
	end
	if #missing == 0 then
		return
	end

	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and type(infos) == "table" then
		for _, info in ipairs(infos) do
			local id = tonumber(info.Id)
			if id ~= nil then
				-- DisplayName is what the player calls themselves; Username is the
				-- guaranteed-present fallback.
				local name = info.DisplayName
				if type(name) ~= "string" or name == "" then
					name = info.Username
				end
				if type(name) == "string" and name ~= "" then
					cache[math.floor(id)] = name
				end
			end
		end
	else
		Log.Once(SCOPE, "userservice-batch", `UserService.GetUserInfosByUserIdsAsync failed — falling back per id ({infos})`)
	end

	local cfg = config()
	for _, userId in ipairs(missing) do
		if cache[userId] == nil then
			local name_ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if name_ok and type(name) == "string" and name ~= "" then
				cache[userId] = name
			else
				-- Cache the placeholder too: a banned/deleted account never
				-- resolves, and retrying it every refresh is a web call per tick.
				cache[userId] = cfg.unknownName
				Log.Once(SCOPE, `name-{userId}`, `could not resolve a name for userId {userId} — showing '{cfg.unknownName}'`)
			end
		end
	end
end

--API
-- R2: the placeholder is `board-config.unknownName`, never a literal here. With
-- no config the feature is disabled anyway, so there is nothing to render.
function GlobalLeaderboardService.NameFor(userId: number): string
	local cfg = config()
	if boardData == nil or cfg == nil then
		return ""
	end
	return boardData["name-by-user-id"][userId] or cfg.unknownName
end

--API
-- "#1", "#12", ...
function GlobalLeaderboardService.FormatRank(rank: number): string
	local cfg = config()
	if cfg == nil then
		return ""
	end
	return `{cfg.rankPrefix}{math.floor(rank)}`
end

local function formatCount(value: number): string
	local cfg = config()
	local n = math.floor(value + 0.5)
	if cfg == nil or type(cfg.countSuffixes) ~= "table" then
		return tostring(n) -- no config: a plain number still reads correctly
	end
	for _, step in ipairs(cfg.countSuffixes) do
		if n >= step.at then
			-- One decimal, truncated (not rounded) so 999_999 reads "999.9K"
			-- and never rolls up into a "1000.0K" that the next suffix owns.
			local scaled = math.floor(n / step.at * 10) / 10
			return `{string.format("%.1f", scaled)}{step.suffix}`
		end
	end
	return tostring(n)
end

local function formatTime(millis: number): string
	local total = math.max(0, math.floor(millis / 1000 + 0.5))
	local hours = math.floor(total / 3600)
	local minutes = math.floor(total % 3600 / 60)
	local seconds = total % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%d:%02d", minutes, seconds)
end

--API
-- Renders a stored value for its board's `format`. An unknown format renders as
-- a plain number rather than blanking the row (R8: degrade, don't vanish).
function GlobalLeaderboardService.FormatValue(format: string, value: number): string
	if type(value) ~= "number" or value ~= value then
		return "-"
	end
	if format == "time" then
		return formatTime(value)
	end
	if format == "count" then
		return formatCount(value)
	end
	Log.Once(SCOPE, `format-{tostring(format)}`, `unknown board value format '{tostring(format)}' — rendering the raw number`)
	return tostring(math.floor(value + 0.5))
end

return GlobalLeaderboardService
