--[[
	LobbySubsClient -- lobby-only UI/event wiring (R4).

	- LobbyQueueUpdate opens/closes the kit matchmaking selector.
	- LobbyQueueRequest sends session-correlated configure/leave intents; destination and
	  roster remain server-authoritative.
	- Touching the authored Forest/Chocolate/Meshes/chocolate part opens the
	  existing Shop panel. DescendantAdded handles the late-cloned LobbyMap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local SCOPE = "LobbyClient"

local LobbySubsClient = {}

local function allowedPlayerCount(config, value: any): boolean
	if type(value) ~= "number" or value % 1 ~= 0 then
		return false
	end
	for _, allowed in ipairs(config.playerCounts) do
		if value == allowed then
			return true
		end
	end
	return false
end

local function isChocolateTrigger(instance: Instance, config): boolean
	if not instance:IsA("BasePart") or instance.Name ~= config.client.chocolatePartName then
		return false
	end
	local chocolate = instance.Parent
	local forest = chocolate and chocolate.Parent
	local environment = forest and forest.Parent
	local map = environment and environment.Parent
	return chocolate ~= nil
		and chocolate.Name == config.client.chocolateModelName
		and forest ~= nil
		and forest.Name == config.client.forestName
		and environment ~= nil
		and environment.Name == config.queue.environmentName
		and map ~= nil
		and map.Name == config.queue.mapName
end

function LobbySubsClient.Start(data, modules, subscriptions)
	local lobbyData = data.LobbyUiData
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	-- Optional (features/analytics.md): the three lobby choices never reach
	-- the server unless START is pressed and accepted, so they can only be
	-- recorded here.
	local Analytics = modules.LocalAnalyticsService
	if lobbyData == nil or AppRoot == nil then
		Log.Warn(SCOPE, "LobbyUiData/AppRoot missing -- lobby UI wiring skipped")
		return
	end
	if Analytics == nil then
		Log.Warn(SCOPE, "LocalAnalyticsService missing -- difficulty/party/start selections will not be logged")
	end

	local config = lobbyData["match-config"]
	local request = Net.Remote("LobbyQueueRequest")
	local update = Net.Update("LobbyQueueUpdate")

	local function closeMatchPanel()
		local wasOpen = AppRoot.GetOpenPanel() == "Matchmaking"
		lobbyData.CloseMatch()
		AppRoot.Set({ matchmaking = false })
		if wasOpen then
			AppRoot.Open(nil)
		end
	end

	AppRoot.SetCallbacks({
		-- `isDefault` = the selector applied MatchConfig.defaults when the session
		-- opened rather than the player tapping a choice. The flow/funnel beat
		-- fires either way: these two steps sit between `selector-open` and
		-- `start-press`, so skipping them would show every one-tap start as a
		-- drop-off. The "did they actually choose" signal is not lost — the kit
		-- counts the `Difficulty_*` / `Players_*` presses themselves, and those
		-- exist only when a finger lands on one (features/analytics.md).
		onMatchDifficultyPick = function(difficulty, isDefault)
			if Analytics then
				Analytics.Flow("difficulty-pick")
				Analytics.Funnel("queue", "difficulty")
			end
		end,
		onMatchPartyPick = function(maxPlayers, isDefault)
			if Analytics then
				Analytics.Flow("party-pick")
				Analytics.Funnel("queue", "party")
			end
		end,
		onConfigureMatch = function(difficulty, maxPlayers)
			-- Recorded BEFORE validation: a press the client itself rejects is
			-- still a press, and the gap between `start-press` and the server's
			-- `countdown` is exactly the set of players whose START did nothing.
			if Analytics then
				Analytics.Flow("start-press")
				Analytics.Funnel("queue", "start")
			end
			if type(difficulty) ~= "string" or config.difficulties[difficulty] == nil then
				Log.Warn(SCOPE, `selector produced invalid difficulty '{tostring(difficulty)}' -- request dropped`)
				return
			end
			if not allowedPlayerCount(config, maxPlayers) then
				Log.Warn(SCOPE, `selector produced invalid maxPlayers '{tostring(maxPlayers)}' -- request dropped`)
				return
			end
			local state = lobbyData.PatchMatch({
				busy = true,
				statusText = "Starting queue...",
				error = false,
			})
			if state == nil then
				Log.Warn(SCOPE, "configure callback fired without an open matchmaking session -- request dropped")
				return
			end
			if type(state.sessionKey) ~= "string" or state.sessionKey == "" then
				Log.Warn(SCOPE, "configure callback has no active session key -- request dropped")
				return
			end
			AppRoot.Set({ matchmaking = state })
			request:FireServer("configure", state.sessionKey, difficulty, maxPlayers)
		end,
		onCancelMatch = function()
			local state = lobbyData["matchmaking"]
			if type(state) == "table" and type(state.sessionKey) == "string" and state.sessionKey ~= "" then
				request:FireServer("leave", state.sessionKey)
			else
				Log.Info(SCOPE, "match selector closed without an active server session -- no leave request sent")
			end
			closeMatchPanel()
		end,
	})

	update.OnClientEvent:Connect(function(kind, payload)
		if type(kind) ~= "string" then
			Log.Warn(SCOPE, "LobbyQueueUpdate kind was not a string -- update dropped")
			return
		end
		if kind == "open" then
			if type(payload) ~= "table" or type(payload.sessionKey) ~= "string" then
				Log.Warn(SCOPE, "LobbyQueueUpdate open payload invalid -- selector not opened")
				return
			end
			local state = lobbyData.OpenMatch({
				sessionKey = payload.sessionKey,
				currentPlayers = if type(payload.currentPlayers) == "number" then payload.currentPlayers else 1,
				maxPlayers = if type(payload.maxPlayers) == "number" then payload.maxPlayers else config.queue.maxPlayers,
				busy = false,
				statusText = false,
				error = false,
			})
			AppRoot.Set({ matchmaking = state })
			-- No open cue here: AppRoot's `openPanel` effect owns the panel whoosh
			-- (audio.md — ONE source), and a second play of the same sample in the
			-- same frame just doubles its amplitude.
			AppRoot.Open("Matchmaking")
		elseif kind == "close" then
			closeMatchPanel()
		elseif kind == "error" or kind == "busy" then
			if type(payload) ~= "table" or type(payload.message) ~= "string" then
				Log.Warn(SCOPE, `LobbyQueueUpdate {kind} payload invalid -- update dropped`)
				return
			end
			local patch = if kind == "error"
				then { busy = false, error = payload.message, statusText = false }
				else { busy = true, error = false, statusText = payload.message }
			local state = lobbyData.PatchMatch(patch)
			if state == nil then
				Log.Warn(SCOPE, `LobbyQueueUpdate {kind} arrived without an open selector -- update dropped`)
				return
			end
			if SoundPool then
				-- "busy" = the queue accepted us and the countdown is running.
				SoundPool.Play(if kind == "error" then "uiError" else "queueTick")
			end
			AppRoot.Set({ matchmaking = state })
		else
			Log.Once(SCOPE, `unknown-update-{kind}`, `unknown LobbyQueueUpdate kind '{kind}' -- ignored`)
		end
	end)

	local localPlayer = Players.LocalPlayer
	local bound = lobbyData["bound-shop-parts"]
	local function bindShopPart(instance: Instance)
		if not isChocolateTrigger(instance, config) or bound[instance] then
			return
		end
		local part = instance :: BasePart
		bound[part] = true
		part.Touched:Connect(function(hit)
			local character = localPlayer.Character
			if character == nil or not hit:IsDescendantOf(character) then
				return
			end
			local openPanel = AppRoot.GetOpenPanel()
			local matchmakingState = if openPanel == "Matchmaking"
				then lobbyData["matchmaking"]
				else nil
			-- World movement can continue while a modal is open. Match the pointer
			-- scrim: chocolate may open Shop from the world, but it never replaces an
			-- unrelated modal underneath the player's hands/controller focus.
			if openPanel ~= nil and openPanel ~= "Matchmaking" then
				return
			end
			-- Walking onto chocolate is a panel-replacement gesture. During launch
			-- busy it must obey the same no-close contract as X and the scrim, or a
			-- rejected late leave hides a countdown that is still running.
			if type(matchmakingState) == "table" and matchmakingState.busy == true then
				return
			end
			local now = os.clock()
			if now - lobbyData["last-shop-open-at"] < config.client.shopOpenDebounceSeconds then
				return
			end
			lobbyData["last-shop-open-at"] = now
			if openPanel == "Matchmaking" then
				local state = matchmakingState
				if type(state) == "table" and type(state.sessionKey) == "string" and state.sessionKey ~= "" then
					request:FireServer("leave", state.sessionKey)
				else
					Log.Info(SCOPE, "shop replaced a selector without an active server session -- no leave request sent")
				end
				lobbyData.CloseMatch()
				AppRoot.Set({ matchmaking = false })
			end
			AppRoot.Open("Shop")
		end)
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		bindShopPart(descendant)
	end
	Workspace.DescendantAdded:Connect(bindShopPart)

	local boundCount = 0
	for _ in pairs(bound) do
		boundCount += 1
	end
	if boundCount == 0 then
		Log.GraceOnce(SCOPE, "no-chocolate-trigger", 10, function()
			return next(bound) == nil
		end, "lobby chocolate shop trigger never replicated -- expected LobbyMap/LobbyEnvironment/Forest/Chocolate/Meshes/chocolate (docs/features/lobby-matchmaking.md)")
	else
		Log.Info(SCOPE, `bound {boundCount} chocolate shop touch trigger(s)`)
	end
end

return LobbySubsClient
