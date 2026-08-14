--[[
	LobbySubs — lobby-place orchestration (lobby partition): builds the hub scene
	on boot. Mirrors how CakeSubs.Start calls MapService.Build in the game place.

	After the clone is built, delegates queue-pad event wiring to
	LobbyQueueSubs.Bind(map). LobbyQueueSubs starts earlier alphabetically, so its
	remote/removal/reconciliation subscriptions are ready before binding.

	The three authored leaderboard screens ride the same clone and are bound the
	same way (LobbyLeaderboardSubs.Bind, features/leaderboards.md). They are
	COSMETIC: a board that fails to bind warns and stays blank, and must never
	stop the queue pads — the hub is playable without them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local LobbySubs = {}

function LobbySubs.Start(data, services, subscriptions)
	-- In the COMBINED build (default.project.json) both partitions load and the
	-- GAME's MapService builds the cake arena — don't stack the lobby hub on top
	-- of it. Build the lobby scene only when this is a lobby-only place (the
	-- game's MapService isn't present).
	if services.MapService ~= nil then
		Log.Info("LobbySubs", "combined build detected (MapService present) -- lobby hub and queues skipped")
		return
	end
	if services.LobbyMapService == nil then
		Log.Warn("LobbySubs", "LobbyMapService missing -- lobby hub and queues cannot start")
		return
	end
	if subscriptions.LobbyQueueSubs == nil or type(subscriptions.LobbyQueueSubs.Bind) ~= "function" then
		Log.Warn("LobbySubs", "LobbyQueueSubs.Bind missing -- lobby queue pads cannot be wired")
		return
	end

	local ok, map_or_error = pcall(services.LobbyMapService.Build)
	if not ok then
		Log.Warn("LobbySubs", `LobbyMapService.Build failed -- {map_or_error}`)
		return
	end
	if map_or_error == nil then
		Log.Warn("LobbySubs", "LobbyMapService.Build returned no map -- queue binding skipped")
		return
	end

	-- Before the queue bind, and never gated on it: the boards are decoration and
	-- a hub with broken pads should still show them (and vice versa).
	local boards = subscriptions.LobbyLeaderboardSubs
	if boards == nil or type(boards.Bind) ~= "function" then
		Log.Warn("LobbySubs", "LobbyLeaderboardSubs.Bind missing -- the in-world leaderboards will stay blank")
	else
		local boards_ok, boards_err = pcall(boards.Bind, map_or_error)
		if not boards_ok then
			Log.Warn("LobbySubs", `LobbyLeaderboardSubs.Bind failed -- {boards_err}`)
		end
	end

	local bind_ok, bound_or_error = pcall(subscriptions.LobbyQueueSubs.Bind, map_or_error)
	if not bind_ok then
		Log.Warn("LobbySubs", `LobbyQueueSubs.Bind failed -- {bound_or_error}`)
		return
	end
	if bound_or_error ~= true then
		Log.Warn("LobbySubs", "LobbyQueueSubs.Bind found no usable queue pads; lobby hub remains available")
		return
	end
	Log.Sum("LobbySubs", "lobby hub built and queue pads bound")
end

return LobbySubs
