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
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))

local SCOPE = "CakeSimulationSubs"

-- How many layer-depth beats one 1 Hz scan may report per player. The gate
-- normally advances one band per move, but a paid LayerEater clear (or a wide
-- scoop through thin frosting) can cross several inside one scan, and the
-- funnel is only readable if the skipped depths are filled in. Bounded so a
-- pathological jump cannot spend a whole minute's analytics budget in one
-- frame; the clamp is reported rather than silent (R8).
local MAX_LAYER_BEATS_PER_SCAN = 8

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
	-- The `layers` funnel declares a FIXED number of steps, one per layer of
	-- depth. A cake that can roll deeper than the funnel is long would clear
	-- layers with nowhere to report them, and Roblox would accept the extra
	-- step numbers and drop them -- exactly the silent loss R8 exists to stop.
	if AnalyticsSubs and cakeCfg.composition.maxLayers > AnalyticsConfig.maxLayerDepth then
		Log.Warn(
			SCOPE,
			`a cake can roll up to {cakeCfg.composition.maxLayers} layers but the analytics 'layers' funnel `
				.. `only declares {AnalyticsConfig.maxLayerDepth} steps -- depths past that will NOT appear on the `
				.. `funnel (raise AnalyticsConfig.maxLayerDepth)`
		)
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
		-- ── STUDIO DEV HOOK: skip N layers (R4 again — event here, logic in the
		-- service). Clearing a layer honestly takes MINUTES at production scale
		-- (clear time is AREA-driven), which made the ZONE GATE — the one thing
		-- that only happens at a layer boundary — untestable without shrinking the
		-- cake in config, i.e. testing a cake the game does not ship.
		--
		--   workspace:SetAttribute("DebugClearLayer", 3)  -- eat the next 3 layers
		--
		-- It goes through `ClearActiveBand`, the SAME call the paid LayerEater
		-- uses, so the 1 Hz `ScanStats` advances the gate and fires the mini-boss
		-- exactly as a real clear would. No calories are paid (this is a debug
		-- skip, not a grant). Studio-only: never a live-game surface.
		workspace:GetAttributeChangedSignal("DebugClearLayer"):Connect(function()
			local count = workspace:GetAttribute("DebugClearLayer")
			if type(count) ~= "number" or count < 1 then
				return
			end
			if state.debugSuppressFindRewards ~= true then
				state.debugSuppressFindRewards = true
				Log.Sum(
					SCOPE,
					`DebugClearLayer armed for cake #{state.cakeIndex} -- find reward/progress/analytics writes suppressed until the next cake`
				)
			end
			for step = 1, math.min(40, math.floor(count)) do
				local removed, band = services.CakeFieldService.ClearActiveBand()
				if removed <= 0 or band == nil then
					Log.Warn(SCOPE, `DebugClearLayer stopped after {step - 1} layer(s) -- nothing left to clear`)
					break
				end
				Log.Sum(SCOPE, `DebugClearLayer: band '{band.id}' flattened ({math.floor(removed)} studs³, unpaid)`)
			end
		end)
		Log.Info(SCOPE, "Studio dev hook armed: workspace:SetAttribute('DebugClearLayer', <n>)")
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
		elseif event == "miniboss-defeated" then
			-- Zone gate down (features/cake-cycle.md). CakeSubs already calls
			-- FinishMiniBoss on the killing tap for immediacy; this is the
			-- backstop for a mini-boss that reached 0 by any other path, and it
			-- no-ops once the phase has already moved on.
			CakeCycleSubs.FinishMiniBoss()
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
				if state.debugSuppressFindRewards == true then
					-- DebugClearLayer can flatten straight through buried finds. The
					-- model is already consumed by TreasureService.Tick, so preserve
					-- the shared collection pop while deliberately omitting the reward
					-- payload and every persistent/analytics mutation.
					uTreasure:FireAllClients({
						event = "collected",
						firstEver = false,
						findId = entry.find.def.id,
						nameKey = entry.find.def.nameKey,
						rarity = entry.find.def.rarity,
						color = entry.find.def.color,
						byUserId = entry.player.UserId,
						position = entry.position,
					})
					Log.Once(
						SCOPE,
						`debug-find-reward-suppressed-{state.cakeIndex}`,
						`Studio debug clear consumed find '{entry.find.def.id}' visually -- reward, discovery, progress, analytics, and save skipped for cake #{state.cakeIndex}`
					)
					continue
				end
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
						-- pcall'd: this runs inside the Heartbeat sim step,
						-- between the client broadcast and the milestone Save
						-- below. A throw here would abort the frame's
						-- simulation AND skip the save of a granted reward.
						local ok, err = pcall(function()
							AnalyticsSubs.Flow(entry.player, "first-find")
							AnalyticsSubs.Funnel(entry.player, "find", "collected")
							AnalyticsSubs.Event(entry.player, "find-collected", 1, {
								entry.find.def.id,
								tostring(entry.find.def.rarity or "unknown"),
								if firstEver then "first-ever" else "repeat",
							}, { tier = "normal" })
						end)
						if not ok then
							Log.Once(SCOPE, "find-analytics", `find analytics beat FAILED (telemetry only, reward unaffected): {err}`)
						end
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
				services.CakeFieldService.ScanStats()
				-- ScanStats owns the layer gate and may advance it by one or more
				-- bands. The checkpoint must follow that AUTHORITATIVE post-scan
				-- index, not the scan summary's sampled top cell. Its XZ placement
				-- also follows the active terrace footprint so it stays beside the
				-- reachable edge of every widening colour group.
				local topBand = state.composition[state.activeBandIndex]
				if topBand then
					services.MapService.SetCheckpointHeight(
						cakeCfg.grid.origin.y + topBand.top,
						topBand.footprint
					)
				end
				if state.activeBandIndex ~= previousBand then
					-- Finishing a layer is the game's core rhythm and it used to be
					-- SILENT. Announce it — but only when the gate moved DOWN, so a
					-- fresh cake (index jumps back up) never fakes a celebration.
					local cleared = previousBand > 0 and state.activeBandIndex < previousBand
					if cleared and AnalyticsSubs then
						-- HOW DEEP THEY GOT (features/analytics.md, `layers`
						-- funnel). Band 1 is the inedible core and the gate
						-- counts DOWN from the frosting, so the number of layers
						-- eaten off THIS cake is simply how far the gate has
						-- travelled -- and it reaches `bandCount - 1` exactly
						-- when nothing edible is left.
						local bandCount = #state.composition
						local edible = bandCount - 1
						local depth = bandCount - state.activeBandIndex
						-- max(1, ...): a cake swap re-rolls the band COUNT, so a
						-- stale `previousBand` must never produce depth 0 beats.
						local first = math.max(1, bandCount - previousBand + 1)
						if depth - first + 1 > MAX_LAYER_BEATS_PER_SCAN then
							-- Report the depths ACTUALLY reached (the tail), not
							-- the first few: the funnel is read from the deep end.
							Log.Once(
								SCOPE,
								"layer-beat-clamp",
								`the layer gate jumped {depth - first + 1} bands in one scan -- only the last `
									.. `{MAX_LAYER_BEATS_PER_SCAN} depths are reported to the funnel`
							)
							first = depth - MAX_LAYER_BEATS_PER_SCAN + 1
						end
						-- Same Heartbeat-step guard as the find beat above.
						local okBeat, beatErr = pcall(function()
							for _, player in ipairs(Players:GetPlayers()) do
								if authorizedPlayer(player) then
									AnalyticsSubs.Flow(player, "first-layer")
									AnalyticsSubs.Funnel(player, "match", "layer")
									for at = first, depth do
										local stepKey = AnalyticsConfig.LayerStep(at)
										if stepKey then
											AnalyticsSubs.Funnel(player, "layers", stepKey)
										end
										-- The counter carries the CAKE's side of
										-- the story (how deep, which flavour zone,
										-- how deep the cake goes at all); the
										-- funnel above carries the PLAYER's
										-- (cohort/platform/difficulty), so between
										-- them a cliff can be told apart from a
										-- cake that simply ended.
										local band = state.composition[bandCount - at + 1]
										AnalyticsSubs.Event(player, "layer-cleared", 1, {
											at,
											edible,
											if band then band.group else "unknown",
										}, { tier = "normal" })
									end
								end
							end
						end)
						if not okBeat then
							Log.Once(SCOPE, "layer-analytics", `layer analytics beat FAILED (telemetry only): {beatErr}`)
						end
					end
					-- ZONE BOUNDARY: the gate just stepped out of one flavour zone
					-- and into the next. Bands carry `group`; 1 is the TOP zone, so
					-- crossing DOWN means the index goes UP. The destination zone's
					-- `gateFromPrevious` decides whether a MINI-BOSS blocks it;
					-- visual colour terraces are not required to be boss chapters.
					-- The gate's own announce replaces "LAYER CLEARED!" — finishing
					-- the last layer of a zone is the boss's cue, not a routine beat,
					-- and two banners in one frame would stomp each other.
					local previousGroup = previousBand > 0
						and state.composition[previousBand]
						and state.composition[previousBand].group
					local currentBand = state.composition[state.activeBandIndex]
					local currentGroup = currentBand and currentBand.group
					local gated = false
					if cleared
						and previousGroup
						and currentGroup
						and currentGroup > previousGroup
					then
						-- Enumerate the WHOLE crossed interval. Looking only at the
						-- final destination skipped intermediate gates whenever multiple
						-- ClearActiveBand calls landed inside one scan window.
						local queued = services.CakeCycleService.QueueCrossedMiniBosses(previousGroup, currentGroup)
						if queued > 0 then
							gated = CakeCycleSubs.BeginNextMiniBoss()
							if not gated then
								Log.Warn(SCOPE, `{queued} crossed mini-boss gate(s) queued but the first could not start -- finale remains blocked`)
							end
						end
					end
					if not gated then
						CakeCycleSubs.BroadcastCycle(if cleared then "layer-cleared" else nil)
					end
				end
				local bottomReached = services.CakeFieldService.IsBottomReached()
				if bottomReached and state.phase == "eating" then
					-- Through the subscription, not the service: entering the boss phase
					-- also emits analytics and the authoritative cycle broadcast (R3 —
					-- cross-service work is orchestrated here).
					if CakeCycleSubs.BeginBoss(CakeCycleSubs.BossPlayerCount()) then
						CakeCycleSubs.BroadcastCycle("boss-spawned")
					end
				elseif bottomReached and state.phase == "miniboss" then
					Log.Once(
						SCOPE,
						`boss-deferred-for-gates-{state.cakeIndex}`,
						`cake #{state.cakeIndex} reached bottom with a zone gate active -- Cake Guardian deferred until all queued gates resolve`
					)
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
