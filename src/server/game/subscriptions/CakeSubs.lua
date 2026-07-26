--[[
	CakeSubs -- player-facing cake input orchestration (R4): EatAt anti-cheat,
	checkpoint return, and initial cake snapshots. CakeCycleSubs owns lifecycle
	transitions; CakeSimulationSubs owns the single Heartbeat fabric.

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
local runtime -- PlayerRuntimeData
local services_
local CakeCycleSubs
local GameRoundSubs

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
	services_ = services
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData and data.CakeConfigData.cake
	antiCheat = data.CakeConfigData and data.CakeConfigData.antiCheat
	biomes = data.MapConfigData and data.MapConfigData.biomes
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
		local removed, layer = services.CakeFieldService.ApplyBite(
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

		local biomeMultiplier = (biomes[state.biome] and biomes[state.biome].caloriesMult) or 1
		local baseCalories = removed
			* (layer.calories or 0)
			* services.CakeCycleService.CakeCaloriesMult()
			* biomeMultiplier
		local result = services.StomachService.Ingest(
			userId,
			removed,
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
