--[[
	CakeSubs -- player-facing cake input orchestration (R4): EatAt anti-cheat,
	checkpoint return, the PAID layer clear (`eatlayer` grant kind, sold by the
	checkpoint's LayerEater prompt), and initial cake snapshots. CakeCycleSubs owns
	lifecycle transitions; CakeSimulationSubs owns the single Heartbeat fabric.

	The client sends only a position. Volume, layer, calories, boss damage, rate,
	and reach remain server-authoritative.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local BodySubs = require(script.Parent.BodySubs)

local SCOPE = "CakeSubs"

local CakeSubs = {}

local uSnapshot
local uStomach
local state -- CakeStateData
local cakeCfg
local antiCheat
local biomes
local mapCfg -- MapConfigData (checkpoint.layerEater* tuning)
local runtime -- PlayerRuntimeData
local services_
local CakeCycleSubs
local GameRoundSubs
local AnalyticsSubs -- optional retention instrumentation (features/analytics.md)

--API
function CakeSubs.SendSnapshot(player: Player)
	if uSnapshot == nil or services_ == nil then
		Log.Warn(SCOPE, `SendSnapshot({player.Name}) before Start ran -- push dropped`)
		return
	end
	local snapshot, metadata = services_.CakeFieldService.Snapshot()
	uSnapshot:FireClient(player, snapshot, metadata)
end

--API
function CakeSubs.PushInitialState(player: Player)
	if GameRoundSubs ~= nil then
		if type(GameRoundSubs.IsActive) ~= "function" then
			Log.Once(SCOPE, "round-active-gate-missing", "GameRoundSubs.IsActive missing -- initial cake snapshot withheld")
			return
		end
		if not GameRoundSubs.IsActive() then
			CakeSubs.SendSnapshot(player)
			return
		end
		if type(GameRoundSubs.HasCakeSnapshot) ~= "function" then
			Log.Once(SCOPE, "round-snapshot-gate-missing", "GameRoundSubs.HasCakeSnapshot missing -- initial cake snapshot withheld")
			return
		end
		if not GameRoundSubs.HasCakeSnapshot() then
			Log.Info(SCOPE, `{player.Name}: initial cake snapshot deferred until the reserved round starts`)
			return
		end
	end
	CakeSubs.SendSnapshot(player)
end

function CakeSubs.Start(data, services, subscriptions)
	CakeCycleSubs = subscriptions and subscriptions.CakeCycleSubs
	GameRoundSubs = subscriptions and subscriptions.GameRoundSubs
	AnalyticsSubs = subscriptions and subscriptions.AnalyticsSubs
	services_ = services
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData and data.CakeConfigData.cake
	antiCheat = data.CakeConfigData and data.CakeConfigData.antiCheat
	mapCfg = data.MapConfigData
	biomes = mapCfg and mapCfg.biomes
	runtime = data.PlayerRuntimeData
	if state == nil or cakeCfg == nil or antiCheat == nil or biomes == nil or runtime == nil then
		Log.Warn(SCOPE, "cake/player runtime data missing -- input subscriptions skipped")
		return
	end
	if CakeCycleSubs == nil then
		Log.Warn(SCOPE, "CakeCycleSubs missing -- boss completion cannot resolve")
	end

	uSnapshot = Net.Update("CakeSnapshotUpdate")
	uStomach = Net.Update("StomachUpdate")
	local function authorizedPlayer(player: Player): boolean
		if GameRoundSubs == nil then
			return true
		end
		if type(GameRoundSubs.IsActive) ~= "function" then
			Log.Once(SCOPE, "round-auth-gate-missing", "GameRoundSubs.IsActive missing -- cake input authorization denied")
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

	Net.Remote("EatAt").OnServerEvent:Connect(function(player, position)
		if typeof(position) ~= "Vector3"
			or position.X ~= position.X
			or position.Y ~= position.Y
			or position.Z ~= position.Z
		then
			Log.Once(SCOPE, `bad-eat-payload-{player.UserId}`, `{player.Name}: EatAt received a non-Vector3/NaN payload -- dropped`)
			return
		end

		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			Log.Once(SCOPE, `eat-preload-{userId}`, `{player.Name}: EatAt before profile load -- bite dropped`)
			return
		end
		if not authorizedPlayer(player) then
			Log.Once(SCOPE, `eat-nonparticipant-{userId}`, `{player.Name}: EatAt rejected outside the established round roster`)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			Log.Once(SCOPE, `eat-no-root-{userId}`, `{player.Name}: EatAt without a HumanoidRootPart -- bite dropped`)
			return
		end

		-- Token bucket: refill = eat rate * slack (client auto-fire jitter).
		local now = os.clock()
		local rate = services.StatsService.EatRate(userId) * antiCheat.biteRateSlack
		local bucket = runtime.biteTokens[userId]
		if bucket == nil then
			bucket = { tokens = antiCheat.biteRateBurst, lastRefill = now }
			runtime.biteTokens[userId] = bucket
		end
		bucket.tokens = math.min(bucket.tokens + (now - bucket.lastRefill) * rate, rate + antiCheat.biteRateBurst)
		bucket.lastRefill = now
		if bucket.tokens < 1 then
			return -- expected anti-spam drop, not a missing dependency
		end
		bucket.tokens -= 1
		if AnalyticsSubs then
			-- The bite is ACCEPTED here (auth + rate limit passed), which is the
			-- honest "the player is playing" moment for the funnel.
			-- pcall'd: this is the hottest remote handler in the game and a
			-- throw would abort the bite itself (R8 — telemetry never takes a
			-- gameplay path down).
			local ok, err = pcall(function()
				AnalyticsSubs.Flow(player, "first-bite")
				AnalyticsSubs.Funnel(player, "match", "bite")
				AnalyticsSubs.Funnel(player, "tutorial", "bite")
				-- Coalesced and BULK: bites are the densest event in the game by
				-- orders of magnitude, so they buy their count cheaply and yield
				-- the rate-limit budget to anything that happens once.
				AnalyticsSubs.Event(player, "bite", 1, nil, { tier = "bulk", coalesce = true })
			end)
			if not ok then
				Log.Once(SCOPE, "bite-analytics", `bite analytics beat FAILED (telemetry only, eating unaffected): {err}`)
			end
		end

		local biteRadius = services.StatsService.BiteRadius(userId)
		local dx = position.X - root.Position.X
		local dz = position.Z - root.Position.Z
		local maxReach = antiCheat.maxBiteReachStuds + biteRadius
		if dx * dx + dz * dz > maxReach * maxReach then
			return -- untrusted out-of-reach input
		end

		local phase = services.CakeCycleService.Phase()
		if phase == "boss" then
			local hp = services.CakeCycleService.DamageBoss(1)
			if hp ~= nil and hp <= 0 then
				if CakeCycleSubs and type(CakeCycleSubs.FinishBoss) == "function" then
					CakeCycleSubs.FinishBoss("win")
				else
					Log.Once(SCOPE, "finish-boss-missing", "boss reached zero HP but CakeCycleSubs.FinishBoss is missing")
				end
			end
			return
		end
		if phase ~= "eating" then
			return
		end

		local capacity = services.StatsService.Capacity(userId)
		if services.StomachService.IsFull(userId, capacity) then
			return
		end
		local surface = services.CakeFieldService.SurfaceHeightAt(position.X, position.Z)
		if surface == nil then
			return
		end
		local surfaceWorldY = cakeCfg.grid.origin.y + surface
		if math.abs(position.Y - surfaceWorldY) > antiCheat.maxSurfaceDeltaStuds then
			return
		end

		local biteDepth = services.StatsService.BiteDepth(userId)
		local removed, layer, band = services.CakeFieldService.ApplyBite(
			position.X,
			position.Z,
			biteRadius,
			biteDepth
		)
		-- Also carve directly beneath the character, but credit calories only for
		-- the accepted front bite so one rate-limited request cannot double-pay.
		services.CakeFieldService.ApplyBite(root.Position.X, root.Position.Z, biteRadius, biteDepth)
		if removed <= 0 then
			return
		end

		-- FOOD, not raw volume: the band's `density` (the pacing curve, see
		-- CakeConfig.composition) says how filling/rich this depth is per stud³,
		-- so one bite is worth ~the same belly + calories anywhere in any cake —
		-- that is what keeps the gym rhythm and the income steady while the
		-- scoops shrink with depth.
		local food = removed * ((band and band.density) or 1)
		local biomeMultiplier = (biomes[state.biome] and biomes[state.biome].caloriesMult) or 1
		local baseCalories = food
			* (layer.calories or 0)
			* services.CakeCycleService.CakeCaloriesMult()
			* biomeMultiplier
		local result = services.StomachService.Ingest(
			userId,
			food,
			baseCalories,
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

	-- Reward kind "eatlayer": the paid LayerEater at the checkpoint
	-- (features/checkpoint.md). GAME-partition only, like `burn` — a receipt that
	-- surfaces in the lobby is deferred by ShopSubs and delivered in a game server.
	--
	-- It pays the buyer for what it actually removed, priced through EXACTLY the
	-- bite formula above (food = volume x band.density, then the layer's calories,
	-- the cake multiplier and the biome multiplier) so a bought layer and an eaten
	-- one are worth the same. The BELLY is deliberately not filled: a paid
	-- convenience that ends with the player over capacity and walking to the gym
	-- is a punishment for buying.
	local RewardGrantSubs = subscriptions and subscriptions.RewardGrantSubs
	if RewardGrantSubs == nil then
		Log.Warn(SCOPE, "RewardGrantSubs missing -- the paid layer clear cannot be delivered in this place")
	else
		-- Readiness runs BEFORE the receipt is committed (RewardGrantSubs header):
		-- everything that makes this undeliverable right now has to be said here,
		-- or the player pays and the handler's nil arrives too late to refuse.
		RewardGrantSubs.RegisterReady("eatlayer", function(player: Player)
			if not authorizedPlayer(player) then
				return false, "buyer is not a participant in the established round"
			end
			if services.CakeCycleService.Phase() ~= "eating" then
				return false, `the cake is in the '{services.CakeCycleService.Phase()}' phase, not eating`
			end
			-- Band 1 is the inedible core, so there is no layer left to eat.
			-- Read the TOP band from the field, not `state.activeBandIndex`: that
			-- index only refreshes at 1 Hz, and this predicate is the last gate
			-- before the Roblox dialog opens.
			local fill, index = services.CakeFieldService.TopBandFill()
			if index <= 1 then
				return false, "no edible layer left on this cake"
			end
			-- Don't sell scraps. Fixed price, permanent (a dev product cannot be
			-- repriced), and the player cannot see how much of the layer is left
			-- before paying — so the SERVER refuses rather than letting them find
			-- out afterwards. Refusing here means the dialog never opens.
			local minFill = mapCfg.checkpoint.layerEaterMinRemainingFraction or 0
			if fill < minFill then
				return false,
					`only {math.floor(fill * 100)}% of this layer is left (needs {math.floor(minFill * 100)}%) — not worth the price`
			end
			return true
		end)

		RewardGrantSubs.Register("eatlayer", function(player: Player, reward, source: string?)
			local removed, band, layer = services.CakeFieldService.ClearActiveBand()
			if removed <= 0 or band == nil or layer == nil then
				-- Readiness said yes, so this is a race (someone else's bite or the
				-- auto-sweep finished the band in between), not a config bug.
				Log.Warn(SCOPE, `{player.Name}: paid layer clear found nothing left to remove -- no calories paid`)
				return nil
			end
			local food = removed * (band.density or 1)
			local biomeMultiplier = (biomes[state.biome] and biomes[state.biome].caloriesMult) or 1
			local baseCalories = food
				* (layer.calories or 0)
				* services.CakeCycleService.CakeCaloriesMult()
				* biomeMultiplier
			local calories = math.floor(baseCalories * services.StatsService.CaloriesMult(player.UserId))
			-- Through the registry, not EconomyService directly: the `calories`
			-- handler is what pushes CurrencyUpdate and books the economy SOURCE, so
			-- a bought layer shows up on the same chart as every other calorie.
			local granted = RewardGrantSubs.Grant(
				player,
				{ kind = "calories", amount = calories },
				source or "layer-eater"
			)
			Log.Sum(
				SCOPE,
				`{player.Name} bought a layer clear: band '{band.id}', {math.floor(removed)} studs³ -> {calories} calories`
			)
			return { kind = "eatlayer", layerId = band.id, calories = (granted and granted.amount) or 0 }
		end)
	end

	Net.Remote("ReturnToCheckpoint").OnServerEvent:Connect(function(player)
		local userId = player.UserId
		if not authorizedPlayer(player) then
			Log.Once(SCOPE, `return-nonparticipant-{userId}`, `{player.Name}: ReturnToCheckpoint rejected outside the established round roster`)
			return
		end
		if not services.PersistenceService.IsLoaded(userId) then
			Log.Once(SCOPE, `return-preload-{userId}`, `{player.Name}: ReturnToCheckpoint before profile load -- ignored`)
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			Log.Once(SCOPE, `return-no-root-{userId}`, `{player.Name}: ReturnToCheckpoint without a HumanoidRootPart -- ignored`)
			return
		end

		local now = os.clock()
		local previous = runtime.returnCooldown[userId]
		if previous and now - previous < 0.5 then
			return
		end
		local checkpoint = services.MapService.GetCheckpointCFrame()
		if checkpoint == nil then
			Log.Once(SCOPE, "return-no-checkpoint", "ReturnToCheckpoint before the checkpoint was positioned -- ignored")
			return
		end
		runtime.returnCooldown[userId] = now
		root.CFrame = checkpoint
	end)
end

return CakeSubs
