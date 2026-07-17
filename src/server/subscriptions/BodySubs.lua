--[[
	BodySubs — body/gym domain orchestration (R4, GDD §8):
	  * GymStart / GymTap remotes + the 4 Hz session-payout loop
	  * auto-gym for pass holders
	  * body replication: "StomachFill" player attribute (clients morph
	    locally) + authoritative WalkSpeed (fullness penalty, caramel slow)

	Cross-subs contract: CakeSubs/UpgradeSubs call RefreshBody(player) after
	anything that changes fill or stats.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local EconomySubs = require(script.Parent.EconomySubs)
local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "BodySubs"

local BodySubs = {}

local services_
local bodyCfg
local stomachCfg
local runtime
local uGym, uStomach

-- Wiring state (not game data): last caramel slow factor per player so
-- RefreshBody between 1 Hz surface checks stays consistent.
local caramelMult: { [Player]: number } = {}

--API
-- Recomputes WalkSpeed + the replicated StomachFill attribute.
function BodySubs.RefreshBody(player: Player)
	if services_ == nil then
		Log.Warn(SCOPE, `RefreshBody({player.Name}) before Start ran — skipped`)
		return
	end
	local userId = player.UserId
	local capacity = services_.StatsService.Capacity(userId)
	local fill01 = services_.StomachService.Fullness(userId, capacity)

	local rounded = math.floor(fill01 * 100 + 0.5) / 100
	if runtime.lastMorphFill[userId] ~= rounded then
		runtime.lastMorphFill[userId] = rounded
		player:SetAttribute("StomachFill", rounded)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local base = services_.StatsService.WalkSpeed(userId)
		local penalty = 1 - stomachCfg.fullSpeedPenalty * fill01
		humanoid.WalkSpeed = base * penalty * (caramelMult[player] or 1)
	end
end

--API
-- Initial stomach push (lifecycle).
function BodySubs.SendStomach(player: Player)
	if uStomach == nil then
		Log.Warn(SCOPE, `SendStomach({player.Name}) before Start ran — push dropped`)
		return
	end
	local userId = player.UserId
	local stomachState = services_.StomachService.GetState(userId)
	if not stomachState then
		Log.Warn(SCOPE, `SendStomach({player.Name}): profile not loaded — push dropped`)
		return
	end
	stomachState.capacity = services_.StatsService.Capacity(userId)
	stomachState.gained = 0
	uStomach:FireClient(player, stomachState)
	BodySubs.RefreshBody(player)
end

function BodySubs.Start(data, services)
	services_ = services
	bodyCfg = data.CakeConfigData.body
	stomachCfg = bodyCfg.stomach
	runtime = data.PlayerRuntimeData
	local cakeOriginY = data.CakeConfigData.cake.grid.origin.y
	uGym = Net.Update("GymUpdate")
	uStomach = Net.Update("StomachUpdate")

	local gymCfg = bodyCfg.gym

	local function payout(player: Player, bonus: number, event: string)
		local userId = player.UserId
		local banked = services.StomachService.Burn(
			userId, services.StatsService.GymEfficiency(userId), bonus
		)
		if banked == nil then
			return
		end
		if banked > 0 then
			services.EconomyService.AddCalories(userId, banked)
			services.ProgressService.AddStat(userId, "lifetimeCalories", banked)
			EconomySubs.SendCurrency(player)
		end
		uGym:FireClient(player, { event = event, banked = banked, bonus = bonus })
		-- Full stomach resync (fill/stored just changed) — includes RefreshBody.
		BodySubs.SendStomach(player)
	end

	-- Gym sessions start from the machine's ProximityPrompt (server-side
	-- event — no client remote to spoof a start from across the map).
	local ProximityPromptService = game:GetService("ProximityPromptService")
	local promptName = data.MapConfigData.gym.promptName
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name ~= promptName then
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not services.MapService.NearGym(root.Position) then
			return -- not at a machine (§13 range validation)
		end
		local ok = services.GymService.StartSession(userId)
		if ok then
			uGym:FireClient(player, { event = "started", duration = gymCfg.duration })
		end
	end)

	Net.Remote("GymTap").OnServerEvent:Connect(function(player)
		services.GymService.RegisterTap(player.UserId)
	end)

	-- Reward kind "burn": instant fat burn (dev product) — a full gym
	-- payout at neutral bonus, anywhere, no machine needed.
	RewardGrantSubs.Register("burn", function(player: Player, reward, source: string?)
		local stomachState = services.StomachService.GetState(player.UserId)
		if not stomachState then
			return nil
		end
		payout(player, 1, "instant")
		return { kind = "burn" }
	end)

	-- Session payouts (4 Hz) + auto-gym + 1 Hz surface/caramel check.
	local payoutAcc, surfaceAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		payoutAcc += dt
		if payoutAcc >= 0.25 then
			payoutAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				if services.GymService.IsFinishDue(userId) then
					local bonus = services.GymService.FinishSession(userId)
					if bonus then
						payout(player, bonus, "result")
					end
				elseif services.StatsService.HasAutoGym(userId) and runtime.gymSessions[userId] == nil then
					local stomachState = services.StomachService.GetState(userId)
					local last = runtime.lastAutoBurn[userId] or 0
					if
						stomachState
						and stomachState.stored >= gymCfg.minStoredToBurn
						and os.clock() - last >= gymCfg.autoBurnInterval
					then
						runtime.lastAutoBurn[userId] = os.clock()
						payout(player, 1, "auto")
					end
				end
			end
		end

		surfaceAcc += dt
		if surfaceAcc >= 1 then
			surfaceAcc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local mult = 1
				if root then
					local surface = services.CakeFieldService.SurfaceHeightAt(root.Position.X, root.Position.Z)
					-- surface is relative to the cake origin; compare world Y.
					if surface ~= nil and math.abs(root.Position.Y - (cakeOriginY + surface)) < 8 then
						local layer = services.CakeFieldService.SurfaceLayerAt(root.Position.X, root.Position.Z)
						if layer and layer.walkSpeedMult then
							mult = layer.walkSpeedMult
						end
					end
				end
				if caramelMult[player] ~= mult then
					caramelMult[player] = mult
					BodySubs.RefreshBody(player)
				end
			end
		end
	end)

	-- Respawn keeps the belly: reapply speed + attribute to new characters.
	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(BodySubs.RefreshBody, player)
		end)
	end
	Players.PlayerAdded:Connect(watchCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		watchCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		caramelMult[player] = nil
	end)
end

return BodySubs
