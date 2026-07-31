--[[
	PlayerLifecycleSubs — join/leave wiring + initial-state push
	(R4: events are connected ONLY in subscription modules).

	Initial state is pushed only after BOTH gates:
	  1. the profile finished loading (LoadProfile returned), AND
	  2. the client reported ClientReady (fired at the end of LocalBootstrap).
	RemoteEvents fired before the client connects its OnClientEvent listeners
	are silently LOST — pushing right after LoadProfile alone can drop the
	first sync on fast loads (especially with the Studio mock store).

	Feature onboarding: each domain sub defines PushInitialState(player); this
	module DISCOVERS them from the merged subscriptions table (no hardcoded
	sibling requires — a sub absent in this place is simply skipped, which is
	what lets the SAME file run in the lobby and the game place).

	Two discovered hooks, in this order:
	  OnProfileLoaded(player) — the profile exists but NOTHING has been sent yet.
	    For work that must MUTATE the profile before the client is told about it
	    (RunResetSubs wipes the run-scoped upgrade tree / calories / belly here —
	    ADR-0013). Ordering matters: PushInitialState hooks run alphabetically, so
	    a sub that reset state from its own PushInitialState would be racing
	    EconomySubs/UpgradeSubs, which sort earlier and would push stale values.
	  PushInitialState(player) — replicate to a client that is ready to listen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Lifecycle"

local PlayerLifecycleSubs = {}

function PlayerLifecycleSubs.Start(data, services, subscriptions)
	-- Wiring state (not game data): which sync gates each player has passed.
	local profileLoaded: { [Player]: boolean } = {}
	local clientReady: { [Player]: boolean } = {}

	-- Discover every subscription that defines PushInitialState(player) from the
	-- merged subscriptions table the bootstrap passes in. No hardcoded sibling
	-- requires (which would nil-error in a place that doesn't load that sub) —
	-- this is what lets the SAME file run in the lobby and the game place. Each
	-- hook is captured once (the table is fully populated before any Start runs).
	local pushHooks: { { name: string, fn: (Player) -> () } } = {}
	local loadHooks: { { name: string, fn: (Player) -> () } } = {}
	do
		local names = {}
		for name in pairs(subscriptions or {}) do
			table.insert(names, name)
		end
		table.sort(names) -- deterministic order for reproducible logs
		for _, name in ipairs(names) do
			local mod = subscriptions[name]
			if type(mod) == "table" then
				if type(mod.OnProfileLoaded) == "function" then
					table.insert(loadHooks, { name = name, fn = mod.OnProfileLoaded })
				end
				if type(mod.PushInitialState) == "function" then
					table.insert(pushHooks, { name = name, fn = mod.PushInitialState })
				end
			end
		end
		local function nameList(hooks): string
			local out = {}
			for _, h in ipairs(hooks) do
				table.insert(out, h.name)
			end
			return table.concat(out, ", ")
		end
		Log.Info(SCOPE, `profile-loaded hooks ({#loadHooks}): {nameList(loadHooks)}`)
		Log.Info(SCOPE, `initial-state hooks ({#pushHooks}): {nameList(pushHooks)}`)
	end

	-- Runs BEFORE any push, while the profile is loaded but still private to the
	-- server. A hook failing here must not strand the join (R8: log, don't die).
	local function runProfileLoadedHooks(player: Player)
		for _, hook in ipairs(loadHooks) do
			local ok, err = pcall(hook.fn, player)
			if not ok then
				Log.Warn(SCOPE, `{hook.name}.OnProfileLoaded({player.Name}) FAILED — {err}`)
			end
		end
	end

	local function pushInitialState(player: Player)
		local pushed = {}
		for _, hook in ipairs(pushHooks) do
			-- One domain failing must not drop the others (R8: log, don't die).
			local ok, err = pcall(hook.fn, player)
			if ok then
				table.insert(pushed, hook.name)
			else
				Log.Warn(SCOPE, `{hook.name}.PushInitialState({player.Name}) FAILED — {err}`)
			end
		end
		Log.Info(SCOPE, `initial state pushed to {player.Name} — {#pushed}/{#pushHooks} domain(s): {table.concat(pushed, ", ")}`)
	end

	local function onPlayerAdded(player: Player)
		local profile, isNew = services.PersistenceService.LoadProfile(player)
		if not profile then
			return -- player left or was kicked during load
		end
		-- Mutate the fresh profile BEFORE `profileLoaded` opens the push gate:
		-- both push paths below require that flag, so nothing can have been sent
		-- to this client yet.
		runProfileLoadedHooks(player)
		profileLoaded[player] = true
		if clientReady[player] then
			pushInitialState(player)
		end

		if isNew then
			-- First-ever join. Reliable signal: true only when a fresh
			-- profile was created, never after a failed read. Use for
			-- analytics cohorts / one-time starter grants.
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		-- Players who joined before Start ran (fast server start). DEFERRED, not
		-- spawned: this module sorts before several of the subs whose hooks it
		-- discovered, and a spawned body runs immediately — so it could reach
		-- OnProfileLoaded before that sub's own Start had armed it. task.defer
		-- resumes after the bootstrap's remaining Start calls have finished.
		task.defer(onPlayerAdded, player)
	end

	Net.Remote("ClientReady").OnServerEvent:Connect(function(player)
		if clientReady[player] then
			return -- once per session
		end
		clientReady[player] = true
		if profileLoaded[player] then
			pushInitialState(player)
		else
			Log.Info(SCOPE, `{player.Name}: client ready, waiting for profile load`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		profileLoaded[player] = nil
		clientReady[player] = nil
		data.PlayerRuntimeData.Clear(player.UserId)
		services.PersistenceService.Unload(player.UserId)
	end)

	-- Deliberately absent (handled inside ProfileStore — see ADR-0001):
	-- * autosave loop  — auto-saves every ~300s (first ~150s after a profile loads are skipped)
	-- * BindToClose    — final save on server shutdown
	-- * retry logic    — DataStore call retries
end

return PlayerLifecycleSubs
