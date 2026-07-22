--[[
	CakeSubs — the cake domain orchestrator (R4): simulation ticks, the
	EatAt remote (with anti-cheat), the cake cycle, treasures.

	Tick fabric (one Heartbeat connection, accumulator per job):
	  settle    20 Hz  CakeFieldService.SettleStep (budgeted automaton)
	  net       12 Hz  delta flush -> CakeDeltaUpdate (unreliable, buffer)
	  collision  5 Hz  CakeCollisionService.UpdateHeights
	  treasure   2 Hz  TreasureService.Tick (reveals + proximity collection)
	  scan       1 Hz  progress % / auto-sweep / bottom detection
	  cycle      1 Hz  CakeCycleUpdate broadcast (4 Hz during the boss)

	Anti-cheat (GDD §13): the client sends only a POSITION. Volume, layer,
	calories are computed server-side, so spoofed remotes can inflate
	nothing; what we validate is rate (token bucket from the eat-speed
	stat), reach (bite near the character) and payload types.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

-- RewardGrantSubs + PetSubs live in the COMMON partition — resolved from the
-- subscriptions registry in Start (a static require breaks once this sub is in
-- game/). BodySubs is in the SAME game partition, so it stays a static require.
local RewardGrantSubs
local PetSubs
local BodySubs = require(script.Parent.BodySubs)

local SCOPE = "CakeSubs"

local CakeSubs = {}

local uSnapshot, uDelta, uCycle, uStomach, uTreasure

local state -- CakeStateData
local cakeCfg, antiCheat, biomes
local runtime -- PlayerRuntimeData
local services_

--API
-- Full field push for one player (join / lifecycle initial state).
function CakeSubs.SendSnapshot(player: Player)
	if uSnapshot == nil then
		Log.Warn(SCOPE, `SendSnapshot({player.Name}) before Start ran — push dropped`)
		return
	end
	local buf, meta = services_.CakeFieldService.Snapshot()
	uSnapshot:FireClient(player, buf, meta)
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function CakeSubs.PushInitialState(player: Player)
	CakeSubs.SendSnapshot(player)
end

function CakeSubs.Start(data, services, subscriptions)
	RewardGrantSubs = subscriptions.RewardGrantSubs
	PetSubs = subscriptions.PetSubs
	services_ = services
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
	antiCheat = data.CakeConfigData.antiCheat
	biomes = data.MapConfigData.biomes
	runtime = data.PlayerRuntimeData

	uSnapshot = Net.Update("CakeSnapshotUpdate")
	uDelta = Net.Update("CakeDeltaUpdate")
	uCycle = Net.Update("CakeCycleUpdate")
	uStomach = Net.Update("StomachUpdate")
	uTreasure = Net.Update("TreasureUpdate")

	services.MapService.Build() -- platform/spawn/gym must exist before the first cake
	services.CakeCollisionService.BuildParts()
	-- Anchor the hourly-event clock at server start: lastRareEventAt = 0
	-- would force EVERY first cake golden (server-hop x3-calorie farming).
	state.lastRareEventAt = os.time()

	local function broadcastCycle(announce: string?)
		uCycle:FireAllClients({
			phase = state.phase,
			progress = state.progress,
			timer = math.max(0, math.floor(state.phaseTimer * 10) / 10),
			boss = state.boss and { hp = state.boss.hp, maxHp = state.boss.maxHp } or nil,
			rareKind = state.rareKind,
			biome = state.biome,
			activeBandIndex = state.activeBandIndex, -- layer gate (features/cake-sim.md)
			announce = announce,
		})
	end

	local function spawnNewCake()
		-- Biome: the highest rebirth tier online unlocks it for the server.
		local maxRebirths = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local r = services.ProgressService.GetRebirths(player.UserId)
			if r and r > maxRebirths then
				maxRebirths = r
			end
		end
		local biome = services.ProgressService.BiomeFor(maxRebirths)
		local playerCount = math.max(1, #Players:GetPlayers())
		local composition, footprint, rareKind = services.CakeCycleService.RollComposition(biome, playerCount)
		-- Hourly Cake Event (§12.2): at least one rare cake per hour.
		if rareKind == nil and os.time() - state.lastRareEventAt >= 3600 then
			rareKind = "golden"
		end
		if rareKind ~= nil then
			state.lastRareEventAt = os.time()
		end
		services.CakeFieldService.ResetCake(composition, footprint, rareKind, biome)
		services.TreasureService.SpawnForCake()
		services.MapService.ApplyBiome(biome)
		-- Checkpoint rides the fresh cake's TOP layer (the last band).
		services.MapService.SetCheckpointHeight(cakeCfg.grid.origin.y + composition[#composition].top)
		services.CakeCycleService.BeginEating()
		-- The new cake materializes AROUND anyone standing in its footprint —
		-- lift them onto the fresh frosting instead of burying them alive.
		local grid = cakeCfg.grid
		local topY = grid.origin.y + composition[#composition].top + 3
		local extentX = footprint.hx * grid.cell + 4
		local extentZ = footprint.hz * grid.cell + 4
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local dx = math.abs(root.Position.X - grid.origin.x)
				local dz = math.abs(root.Position.Z - grid.origin.z)
				if dx <= extentX and dz <= extentZ and root.Position.Y < topY then
					root.CFrame = CFrame.new(root.Position.X, topY, root.Position.Z)
				elseif services.MapService.IsOverCheckpoint(root.Position) then
					-- Standing on the checkpoint: the plate just jumped UP to the
					-- fresh cake — ride it up instead of being left on the floor.
					local cf = services.MapService.GetCheckpointCFrame()
					if cf then
						root.CFrame = cf
					end
				end
			end
		end
		local buf, meta = services.CakeFieldService.Snapshot()
		uSnapshot:FireAllClients(buf, meta)
		broadcastCycle(if rareKind then `rare-cake-{rareKind}` else "new-cake")
	end

	local function rewardAllPlayers()
		services.CakeCycleService.BeginReward()
		local minRarity = if state.rareKind == "rainbow" then cakeCfg.composition.rare.rainbow.guaranteedRarity else nil
		for _, player in ipairs(Players:GetPlayers()) do
			local userId = player.UserId
			if services.PersistenceService.IsLoaded(userId) then
				local roll = services.PetService.Roll(userId, "cycle", minRarity)
				if roll then
					roll.source = "cake"
					PetSubs.SendRoll(player, roll)
					PetSubs.SendPets(player)
				end
				services.ProgressService.AddStat(userId, "cakesEaten", 1)
				-- Milestone save: a cake-clear reward (pet roll + stat) is rare and
				-- high-value — persist before the ~300s autosave window.
				services.PersistenceService.Save(userId)
			end
		end
		services.CakeCycleService.StartSpawning()
		broadcastCycle("cake-cleared")
	end

	-- ── EatAt: bite (eating) or boss tap (boss) ─────────────────────────
	Net.Remote("EatAt").OnServerEvent:Connect(function(player, pos)
		if typeof(pos) ~= "Vector3" or pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
			Log.Once(SCOPE, `bad-eat-payload-{player.UserId}`, `{player.Name}: EatAt with non-Vector3/NaN payload — dropped`)
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			-- Joining: stats/stomach need the profile (R8 — never silent).
			Log.Once(SCOPE, `eat-preload-{userId}`, `{player.Name}: EatAt before profile load — bites dropped until loaded`)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end

		-- Token bucket: refill = eat rate * slack (client auto-fire jitter).
		local now = os.clock()
		local rate = services.StatsService.EatRate(userId) * antiCheat.biteRateSlack
		local bucket = runtime.biteTokens[userId]
		if not bucket then
			bucket = { tokens = antiCheat.biteRateBurst, lastRefill = now }
			runtime.biteTokens[userId] = bucket
		end
		bucket.tokens = math.min(bucket.tokens + (now - bucket.lastRefill) * rate, rate + antiCheat.biteRateBurst)
		bucket.lastRefill = now
		if bucket.tokens < 1 then
			return -- over rate: drop silently (legit clients never hit this)
		end
		bucket.tokens -= 1

		-- Reach: the bite point must be near the character (§13).
		local biteRadius = services.StatsService.BiteRadius(userId)
		local dx = pos.X - root.Position.X
		local dz = pos.Z - root.Position.Z
		local maxReach = antiCheat.maxBiteReachStuds + biteRadius
		if dx * dx + dz * dz > maxReach * maxReach then
			return
		end

		local phase = services.CakeCycleService.Phase()
		if phase == "boss" then
			local hp = services.CakeCycleService.DamageBoss(1)
			if hp ~= nil and hp <= 0 then
				rewardAllPlayers()
			end
			return
		end
		if phase ~= "eating" then
			return
		end

		-- Belly full = can't eat (GDD §8). Drop the bite BEFORE carving the
		-- cake so a full player leaves no phantom crater; the gym empties the
		-- belly. Not a failure path — the client gates itself too, so a legit
		-- client never reaches here (no log spam).
		local capacity = services.StatsService.Capacity(userId)
		if services.StomachService.IsFull(userId, capacity) then
			return
		end

		local surface = services.CakeFieldService.SurfaceHeightAt(pos.X, pos.Z)
		if surface == nil then
			return -- outside the cake footprint
		end
		-- The bite point must sit near the actual surface (§13 — no biting
		-- mid-air / deep underground through spoofed positions).
		local surfaceWorldY = cakeCfg.grid.origin.y + surface
		if math.abs(pos.Y - surfaceWorldY) > antiCheat.maxSurfaceDeltaStuds then
			return
		end

		local biteDepth = services.StatsService.BiteDepth(userId)
		local removed, layer = services.CakeFieldService.ApplyBite(pos.X, pos.Z, biteRadius, biteDepth)
		-- Also eat DIRECTLY BENEATH the player (user req): the front bite alone left
		-- the spot they stand on un-eaten (a pillar under their feet). GEOMETRY ONLY —
		-- its volume is NOT paid as calories, so one accepted EatAt (one rate-limited
		-- token) still credits exactly ONE bite (no double income from aiming the front
		-- bite at a SEPARATE spot). ApplyBite dirties + settles the field itself, so the
		-- beneath crater still clears + replicates. Server-chosen point (their own XZ),
		-- so no reach/surface anti-cheat needed; the layer gate still clamps it.
		services.CakeFieldService.ApplyBite(root.Position.X, root.Position.Z, biteRadius, biteDepth)
		if removed <= 0 then
			-- Core / already-bare cells, or the layer gate stopped the bite at
			-- the active floor (the layer beneath stays locked until the top
			-- one is gone) — nothing to eat. The client shows the "eat the top
			-- layer first" cue; here it's a normal no-op, no log spam.
			return
		end

		local biomeMult = (biomes[state.biome] and biomes[state.biome].caloriesMult) or 1
		local baseCalories = removed * (layer.calories or 0)
			* services.CakeCycleService.CakeCaloriesMult()
			* biomeMult
		local result = services.StomachService.Ingest(
			userId, removed, baseCalories,
			services.StatsService.CaloriesMult(userId),
			capacity
		)
		if result then
			result.capacity = capacity
			result.layerId = layer.id
			uStomach:FireClient(player, result)
			BodySubs.RefreshBody(player)
		end
	end)

	-- ReturnToCheckpoint: teleport onto the checkpoint platform (features/
	-- checkpoint.md) — F key / HUD button. The checkpoint's height is server
	-- truth, so the teleport is server-authoritative (no client-supplied
	-- destination). Debounced so a mashed key/button can't rag-doll the player.
	local returnCooldown: { [number]: number } = {}
	Net.Remote("ReturnToCheckpoint").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			Log.Once(SCOPE, `return-preload-{userId}`, `{player.Name}: ReturnToCheckpoint before profile load — ignored`)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			Log.Once(SCOPE, `return-nochar-{userId}`, `{player.Name}: ReturnToCheckpoint with no character — ignored`)
			return
		end
		local now = os.clock()
		local last = returnCooldown[userId]
		if last and now - last < 0.5 then
			return -- debounce (legit double-tap, not a failure — no log)
		end
		local cf = services.MapService.GetCheckpointCFrame()
		if cf == nil then
			Log.Once(SCOPE, "return-nocp", "ReturnToCheckpoint before the checkpoint was positioned — ignored")
			return
		end
		returnCooldown[userId] = now
		root.CFrame = cf
	end)
	Players.PlayerRemoving:Connect(function(player)
		returnCooldown[player.UserId] = nil
	end)

	-- Tick fabric (one Heartbeat connection, accumulator per job)
	local settleAcc, netAcc, collisionAcc, treasureAcc, scanAcc, cycleAcc = 0, 0, 0, 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		-- Cycle timers run every frame (cheap), transitions are rare.
		local event = services.CakeCycleService.Step(dt)
		if event == "boss-defeated" or event == "boss-timeout" then
			rewardAllPlayers()
		elseif event == "spawn-cake" then
			spawnNewCake()
		end

		settleAcc += dt
		if settleAcc >= 1 / cakeCfg.sim.settleHz then
			settleAcc = 0
			services.CakeFieldService.SettleStep()
		end

		netAcc += dt
		if netAcc >= 1 / cakeCfg.net.syncHz then
			netAcc = 0
			-- Several SMALL packets per flush: one oversized unreliable fire
			-- (> ~900 B) would be dropped by the engine entirely.
			for packet = 1, cakeCfg.net.maxPacketsPerFlush do
				local delta = services.CakeFieldService.CollectDelta(packet == 1)
				if delta == nil then
					break
				end
				uDelta:FireAllClients(state.cakeIndex, delta)
			end
		end

		collisionAcc += dt
		if collisionAcc >= 1 / cakeCfg.net.collisionHz then
			collisionAcc = 0
			services.CakeCollisionService.UpdateHeights()
		end

		treasureAcc += dt
		if treasureAcc >= 0.5 then
			treasureAcc = 0
			-- Only loaded players may consume finds — an unloaded collector
			-- would flag the find collected and then fail the grant.
			local loaded = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if services.PersistenceService.IsLoaded(player.UserId) then
					loaded[player.UserId] = true
				end
			end
			local spawned, collected = services.TreasureService.Tick(loaded)
			for _, find in ipairs(spawned) do
				local part = find.part :: BasePart
				uTreasure:FireAllClients({ event = "spawned", findId = find.def.id, position = part.Position })
			end
			for _, entry in ipairs(collected) do
				local granted = RewardGrantSubs.Grant(entry.player, entry.find.def.reward, "find")
				if granted then
					services.ProgressService.AddStat(entry.player.UserId, "findsCollected", 1)
					uTreasure:FireAllClients({
						event = "collected",
						findId = entry.find.def.id,
						byUserId = entry.player.UserId,
						position = entry.position,
					})
					-- Milestone save: a treasure grant (gems/boost/egg) — persist so a
					-- crash before the ~300s autosave can't lose the find.
					services.PersistenceService.Save(entry.player.UserId)
				else
					Log.Warn(SCOPE, `find '{entry.find.def.id}' reward grant declined for {entry.player.Name} — reward lost (check kind handlers)`)
				end
			end
		end

		scanAcc += dt
		if scanAcc >= 1 / cakeCfg.sim.statsScanHz then
			scanAcc = 0
			if state.phase == "eating" then
				local prevActiveBand = state.activeBandIndex
				local stats = services.CakeFieldService.ScanStats()
				-- Step the checkpoint down to the current TOP layer's height.
				local topBand = stats and state.composition[stats.topBandIndex]
				if topBand then
					services.MapService.SetCheckpointHeight(cakeCfg.grid.origin.y + topBand.top)
				end
				-- Layer gate: the moment the active band advances, push it on the
				-- reliable cycle channel NOW — don't wait for the periodic cycle tick
				-- (phase-drifted from this scan after the boss's 4 Hz cycle). The
				-- freshly-swept surface reaches the client on the fast delta channel;
				-- if the new floor lagged behind it the client would briefly re-lock
				-- and flash "eat the top layer first" right after clearing the layer.
				if state.activeBandIndex ~= prevActiveBand then
					broadcastCycle(nil)
				end
				if services.CakeFieldService.IsBottomReached() then
					services.CakeCycleService.BeginBoss(math.max(1, #Players:GetPlayers()))
					broadcastCycle("boss-spawned")
				end
			end
		end

		cycleAcc += dt
		local cycleRate = if state.phase == "boss" then 4 else 1
		if cycleAcc >= 1 / cycleRate then
			cycleAcc = 0
			broadcastCycle(nil)
		end
	end)

	-- First cake of the server session.
	spawnNewCake()
end

return CakeSubs
