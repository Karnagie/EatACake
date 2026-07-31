--[[
	CakeSimulationSubs -- the cake server's single Heartbeat fabric (R4).

	High-frequency settling/network/collision work and low-frequency treasure,
	progress, checkpoint, and cycle updates share one connection with independent
	accumulators. Rare lifecycle transitions delegate to CakeCycleSubs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local SCOPE = "CakeSimulationSubs"

local CakeSimulationSubs = {}

function CakeSimulationSubs.Start(data, services, subscriptions)
	local state = data.CakeStateData
	local cakeCfg = data.CakeConfigData and data.CakeConfigData.cake
	local CakeCycleSubs = subscriptions and subscriptions.CakeCycleSubs
	local GameRoundSubs = subscriptions and subscriptions.GameRoundSubs
	local RewardGrantSubs = subscriptions and subscriptions.RewardGrantSubs
	-- Retention instrumentation (features/analytics.md). Optional on purpose: a
	-- missing telemetry sub must never stop the simulation.
	local AnalyticsSubs = subscriptions and subscriptions.AnalyticsSubs
	if AnalyticsSubs == nil then
		Log.Warn(SCOPE, "AnalyticsSubs missing -- find/layer retention beats will not be logged")
	end
	if state == nil or cakeCfg == nil then
		Log.Warn(SCOPE, "CakeStateData/CakeConfigData missing -- simulation tick disabled")
		return
	end
	-- ── STUDIO DEV HOOK (R4: the event lives here, the logic lives in the
	-- service). Set the attribute from the command bar in SERVER context
	-- (`Test > Toggle Client View`) to force the nearest find up to the surface:
	--
	--   workspace:SetAttribute("DebugUncoverFind", 0.5)  -- revealed, mid-strain
	--   workspace:SetAttribute("DebugUncoverFind", 0)    -- uncovered, frees next tick
	--
	-- Attribute rather than a direct service call because the command bar keeps
	-- its OWN require cache even in play mode, so `require(TreasureService)` there
	-- returns a fresh module with empty state — the running server is only
	-- reachable through something it is already watching. Studio-only: this must
	-- never be a live-game surface.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("DebugUncoverFind"):Connect(function()
			local keep = workspace:GetAttribute("DebugUncoverFind")
			if type(keep) ~= "number" then
				return
			end
			local player = Players:GetPlayers()[1]
			local character = player and player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local at = root and (root :: BasePart).Position or Vector3.new(0, 0, 0)
			services.TreasureService.DebugUncoverNearest(at, keep)
		end)
		Log.Info(SCOPE, "Studio dev hook armed: workspace:SetAttribute('DebugUncoverFind', <0..1>)")
	end

	local clocks = state.simulationAccumulators
	if type(clocks) ~= "table" then
		Log.Warn(SCOPE, "CakeStateData.simulationAccumulators missing -- simulation tick disabled")
		return
	end
	if CakeCycleSubs == nil then
		Log.Warn(SCOPE, "CakeCycleSubs missing -- simulation tick disabled")
		return
	end
	if RewardGrantSubs == nil then
		Log.Warn(SCOPE, "RewardGrantSubs missing -- treasure grants will be declined")
	end

	local uDelta = Net.Update("CakeDeltaUpdate")
	local uTreasure = Net.Update("TreasureUpdate")
	local function roundSimulationEnabled(): boolean
		if GameRoundSubs == nil then
			return true
		end
		if type(GameRoundSubs.IsActive) ~= "function" then
			Log.Once(SCOPE, "round-active-gate-missing", "GameRoundSubs.IsActive missing -- simulation remains safely paused")
			return false
		end
		if not GameRoundSubs.IsActive() then
			return true
		end
		if type(GameRoundSubs.IsStarted) ~= "function" then
			Log.Once(SCOPE, "round-start-gate-missing", "GameRoundSubs.IsStarted missing -- simulation remains safely paused")
			return false
		end
		return GameRoundSubs.IsStarted()
	end
	local function authorizedPlayer(player: Player): boolean
		if GameRoundSubs == nil then
			return true
		end
		if type(GameRoundSubs.IsActive) ~= "function" then
			Log.Once(SCOPE, "round-auth-gate-missing", "GameRoundSubs.IsActive missing -- player simulation authorization denied")
			return false
		end
		if not GameRoundSubs.IsActive() then
			return true
		end
		if type(GameRoundSubs.IsStarted) ~= "function" or not GameRoundSubs.IsStarted() then
			return false
		end
		return type(GameRoundSubs.IsParticipant) == "function" and GameRoundSubs.IsParticipant(player)
	end
	RunService.Heartbeat:Connect(function(dt)
		-- CakeStateData begins in spawning with a zero timer. Keep every cake
		-- mutation paused or the first Heartbeat would build a provisional edible
		-- cake before the roster/profile barrier and BeginMatch commit.
		if not roundSimulationEnabled() then
			return
		end
		local event = services.CakeCycleService.Step(dt)
		if event == "boss-defeated" then
			CakeCycleSubs.FinishBoss("win")
		elseif event == "boss-timeout" then
			CakeCycleSubs.FinishBoss("loss")
		elseif event == "spawn-cake" then
			CakeCycleSubs.SpawnNewCake()
		end

		clocks.settle += dt
		if clocks.settle >= 1 / cakeCfg.sim.settleHz then
			clocks.settle = 0
			services.CakeFieldService.SettleStep()
		end

		clocks.net += dt
		if clocks.net >= 1 / cakeCfg.net.syncHz then
			clocks.net = 0
			for packet = 1, cakeCfg.net.maxPacketsPerFlush do
				local delta = services.CakeFieldService.CollectDelta(packet == 1)
				if delta == nil then
					break
				end
				uDelta:FireAllClients(state.cakeIndex, delta)
			end
		end

		clocks.collision += dt
		if clocks.collision >= 1 / cakeCfg.net.collisionHz then
			clocks.collision = 0
			services.CakeCollisionService.UpdateHeights()
		end

		clocks.treasure += dt
		if clocks.treasure >= 0.5 then
			local elapsed = clocks.treasure
			clocks.treasure = 0
			local loaded = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if services.PersistenceService.IsLoaded(player.UserId) and authorizedPlayer(player) then
					loaded[player.UserId] = true
				end
			end
			local near, revealed, collected = services.TreasureService.Tick(loaded, elapsed)
			for _, find in ipairs(near) do
				-- The surface is CLOSE to this find. The cake glints above it so
				-- digging becomes a decision ("something's under there") instead
				-- of blind mowing — Drain the Lake's flag-marker lesson.
				uTreasure:FireAllClients({
					event = "near",
					findId = find.def.id,
					rarity = find.def.rarity,
					color = find.def.color,
					position = find.crown,
				})
			end
			for _, find in ipairs(revealed) do
				-- First crown out of the cake: dust puff + "there is something
				-- here" chime at the spot, for EVERY player (a shared cake).
				uTreasure:FireAllClients({
					event = "revealed",
					findId = find.def.id,
					rarity = find.def.rarity,
					color = find.def.color,
					position = find.crown,
				})
			end
			for _, entry in ipairs(collected) do
				-- PER-HEAD gem payout, the same rule calories already follow. The find
				-- COUNT is fixed by cake volume and a find is consumed by whoever
				-- reaches it first, so a 4-player cake hands each player a quarter of
				-- the finds — and gems are what boosts are priced against (one cleared
				-- cake ≈ one boost). Without this, that rule only held solo.
				-- A COPY, never the config table: `def.reward` is shared by every
				-- spawn of that find for the lifetime of the server.
				local reward = services.CakeCycleService.ScaleFindReward(entry.find.def.reward)
				local granted = RewardGrantSubs and RewardGrantSubs.Grant(entry.player, reward, "find")
				if granted then
					services.ProgressService.AddStat(entry.player.UserId, "findsCollected", 1)
					-- FIRST time this player has ever dug up this KIND: a memorable
					-- one-off, and the strongest reason to come back for the rest.
					local firstEver = services.ProgressService.MarkFindDiscovered(
						entry.player.UserId,
						entry.find.def.id
					)
					uTreasure:FireAllClients({
						event = "collected",
						firstEver = firstEver,
						findId = entry.find.def.id,
						nameKey = entry.find.def.nameKey,
						rarity = entry.find.def.rarity,
						color = entry.find.def.color,
						-- The GRANT RESULT, not the input descriptor. Two multipliers sit
						-- between the config amount and the balance: the per-head co-op
						-- scale applied above, and GemsMult (x2-gems pass, VIP, gems pets)
						-- applied inside the handler. Sending the input floated "+70" over
						-- a find that banked 140 for exactly the players who PAID for the
						-- perk. The handler returns what EconomyService actually added.
						reward = granted,
						byUserId = entry.player.UserId,
						position = entry.position,
					})
					if AnalyticsSubs then
						AnalyticsSubs.Onboard(entry.player, "firstFind")
						AnalyticsSubs.Count(entry.player, "find_collected", 1)
					end
					services.PersistenceService.Save(entry.player.UserId)
				else
					Log.Warn(SCOPE, `find '{entry.find.def.id}' reward grant declined for {entry.player.Name} -- reward lost (check kind handlers)`)
				end
			end
		end

		clocks.scan += dt
		if clocks.scan >= 1 / cakeCfg.sim.statsScanHz then
			clocks.scan = 0
			if state.phase == "eating" then
				local previousBand = state.activeBandIndex
				local stats = services.CakeFieldService.ScanStats()
				local topBand = stats and state.composition[stats.topBandIndex]
				if topBand then
					services.MapService.SetCheckpointHeight(cakeCfg.grid.origin.y + topBand.top)
				end
				if state.activeBandIndex ~= previousBand then
					-- Finishing a layer is the game's core rhythm and it used to be
					-- SILENT. Announce it — but only when the gate moved DOWN, so a
					-- fresh cake (index jumps back up) never fakes a celebration.
					local cleared = previousBand > 0 and state.activeBandIndex < previousBand
					if cleared and AnalyticsSubs then
						for _, player in ipairs(Players:GetPlayers()) do
							if authorizedPlayer(player) then
								AnalyticsSubs.Onboard(player, "firstLayer")
								AnalyticsSubs.Count(player, "layer_cleared", 1)
							end
						end
					end
					CakeCycleSubs.BroadcastCycle(if cleared then "layer-cleared" else nil)
				end
				if services.CakeFieldService.IsBottomReached() then
					-- Through the subscription, not the service: entering the boss phase
					-- also pre-rolls the squishy each fighter is playing for so the HUD
					-- can show the stake (R3 — cross-service work is orchestrated there).
					CakeCycleSubs.BeginBoss(CakeCycleSubs.BossPlayerCount())
					CakeCycleSubs.BroadcastCycle("boss-spawned")
				end
			end
		end

		clocks.cycle += dt
		local cycleRate = if state.phase == "boss" then 4 else 1
		if clocks.cycle >= 1 / cycleRate then
			clocks.cycle = 0
			CakeCycleSubs.BroadcastCycle(nil)
		end
	end)
end

return CakeSimulationSubs
