--[[
	GlobalLeaderboardSubs — publishes each player's leaderboard numbers to the
	cross-server ordered stores (COMMON: gems are earned in BOTH places, cakes
	and speedrun times only in the game place, and the boards themselves are
	rendered in the lobby by LobbyLeaderboardSubs).

	The profile is the source of truth; these stores are a projection of it
	(ADR-0022). So publishing is just "write what the profile says", which makes
	it idempotent and safe to repeat.

	TWO triggers, deliberately, and neither is PlayerRemoving:
	  * OnProfileLoaded — the profile has just been read, so it carries every
	    number the LAST session ended with. This is what covers the player who
	    quit straight out of a match: their win lands on the board the next time
	    they join. PlayerLifecycleSubs' own PlayerRemoving handler UNLOADS the
	    profile, and the order of two handlers on the same event is not a
	    contract — a leave-time publish would be racing a nil profile.
	  * a `publishSeconds` tick — catches everything earned DURING the session
	    (a find, a cake cleared) without a write per gem.

	Only CHANGED boards are written (`published-by-user-id`), so a lobby full of
	idle players costs nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "TopBoards"

local GlobalLeaderboardSubs = {}

local boardData
local services_

-- Board-id keyed values for one player, or nil when the profile isn't readable.
local function valuesFor(userId: number): { [string]: number }?
	if not services_.PersistenceService.IsLoaded(userId) then
		return nil
	end
	local summary = services_.ProgressService.Summary(userId)
	if summary == nil then
		return nil
	end
	local values = {}
	for _, board in ipairs(boardData.boards) do
		local value = summary[board.statKey]
		if type(value) == "number" then
			values[board.id] = value
		end
	end
	return values
end

-- Returns only the boards worth writing: a value that differs from the last
-- COMMITTED write and is a real score. Non-positive values are skipped here as
-- well as inside Publish, so a brand-new player (three zeroes) produces no work
-- at all rather than a call that drops everything.
local function changedValues(userId: number, values: { [string]: number }): ({ [string]: number }, number)
	local published = boardData["published-by-user-id"][userId]
	if published == nil then
		published = {}
		boardData["published-by-user-id"][userId] = published
	end
	local changed = {}
	local count = 0
	for boardId, value in pairs(values) do
		if value > 0 and published[boardId] ~= value then
			changed[boardId] = value
			count += 1
		end
	end
	return changed, count
end

local function publishPlayer(userId: number, reason: string)
	local values = valuesFor(userId)
	if values == nil then
		Log.Info(SCOPE, `publish skipped for userId {userId} ({reason}): profile not loaded`)
		return
	end
	local changed, count = changedValues(userId, values)
	if count == 0 then
		return
	end
	local committed = services_.GlobalLeaderboardService.Publish(userId, changed)
	-- ⚠ Mark ONLY the boards that actually landed, per board. A partial failure
	-- (one SetAsync throttled) that marked the whole batch would strand the
	-- failed value for the life of the server: a first-ever cake time never
	-- changes again unless the player beats it, so it would simply never appear.
	local published = boardData["published-by-user-id"][userId]
	local written = 0
	if published ~= nil then
		for boardId, value in pairs(changed) do
			if committed[boardId] then
				published[boardId] = value
				written += 1
			end
		end
	end
	if written > 0 then
		Log.Info(SCOPE, `published {written} board value(s) for userId {userId} ({reason})`)
	end
end

--API
-- Profile-load hook (PlayerLifecycleSubs). Runs before anything is replicated;
-- the write itself is spawned because a DataStore call yields and the join path
-- must not wait on it.
function GlobalLeaderboardSubs.OnProfileLoaded(player: Player)
	if boardData == nil or services_ == nil then
		return -- Start already warned; a second line per join would be noise
	end
	local userId = player.UserId
	task.spawn(function()
		publishPlayer(userId, "join")
	end)
end

local function publishTick(periodSeconds: number)
	if boardData["publish-busy"] then
		-- A previous sweep is still yielding on the DataStore (throttled server).
		-- Skipping is normally correct: the next tick re-reads the same profiles.
		-- But a latch that never clears would stop publishing FOREVER while
		-- saying nothing after the first line, which is exactly the silent-skip
		-- R8 forbids — so a sweep that outlives several periods is force-cleared.
		local age = os.clock() - (boardData["publish-busy-since"] or 0)
		if age > periodSeconds * 3 then
			Log.Warn(SCOPE, `publish sweep has been running {math.floor(age)}s (> 3 periods) -- latch force-cleared, publishing resumes`)
			boardData["publish-busy"] = false
		else
			Log.Once(SCOPE, "publish-overlap", "a publish sweep was still running when the next tick fired -- skipped")
			return
		end
	end
	boardData["publish-busy"] = true
	boardData["publish-busy-since"] = os.clock()
	task.spawn(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(publishPlayer, player.UserId, "tick")
			if not ok then
				Log.Warn(SCOPE, `publish sweep failed for {player.Name} — {err}`)
			end
		end
		boardData["publish-busy"] = false
	end)
end

function GlobalLeaderboardSubs.Start(data, services)
	boardData = data.GlobalLeaderboardData
	services_ = services
	if boardData == nil or boardData["board-config"] == nil then
		Log.Warn(SCOPE, "GlobalLeaderboardData missing -- leaderboard values will NOT be published")
		boardData = nil
		return
	end
	if services.GlobalLeaderboardService == nil
		or services.ProgressService == nil
		or services.PersistenceService == nil
	then
		Log.Warn(
			SCOPE,
			"GlobalLeaderboardService/ProgressService/PersistenceService missing -- leaderboard values will NOT be published"
		)
		boardData = nil
		return
	end
	if not services.GlobalLeaderboardService.IsAvailable() then
		-- Init already said why. Stay armed anyway: a store can be resolved and
		-- still fail its first call, and the reverse is not worth a special case.
		Log.Warn(SCOPE, "no ordered store resolved -- publishing will report the first failure and stop being noisy")
	end

	local publishSeconds = boardData["board-config"].publishSeconds
	-- R1: the scheduling clock is STATE, so it lives in the data module, not in
	-- a module local (mirrors LobbyQueueData's "last-scan-at").
	boardData["publish-accumulator"] = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		boardData["publish-accumulator"] += dt
		if boardData["publish-accumulator"] >= publishSeconds then
			boardData["publish-accumulator"] = 0
			publishTick(publishSeconds)
		end
	end)
	table.insert(boardData.connections, connection)

	Players.PlayerRemoving:Connect(function(player)
		-- Drop the per-player write cache. Keeping it would leak one small table
		-- per visitor for the life of the server.
		boardData["published-by-user-id"][player.UserId] = nil
	end)

	Log.Info(SCOPE, `publishing armed: every {publishSeconds}s and on every profile load`)
end

return GlobalLeaderboardSubs
