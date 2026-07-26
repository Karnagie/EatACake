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
	if state == nil or cakeCfg == nil then
		Log.Warn(SCOPE, "CakeStateData/CakeConfigData missing -- simulation tick disabled")
		return
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
			clocks.treasure = 0
			local loaded = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if services.PersistenceService.IsLoaded(player.UserId) and authorizedPlayer(player) then
					loaded[player.UserId] = true
				end
			end
			local spawned, collected = services.TreasureService.Tick(loaded)
			for _, find in ipairs(spawned) do
				local part = find.part :: BasePart
				uTreasure:FireAllClients({ event = "spawned", findId = find.def.id, position = part.Position })
			end
			for _, entry in ipairs(collected) do
				local granted = RewardGrantSubs and RewardGrantSubs.Grant(entry.player, entry.find.def.reward, "find")
				if granted then
					services.ProgressService.AddStat(entry.player.UserId, "findsCollected", 1)
					uTreasure:FireAllClients({
						event = "collected",
						findId = entry.find.def.id,
						byUserId = entry.player.UserId,
						position = entry.position,
					})
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
					CakeCycleSubs.BroadcastCycle(nil)
				end
				if services.CakeFieldService.IsBottomReached() then
					services.CakeCycleService.BeginBoss(CakeCycleSubs.BossPlayerCount())
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
