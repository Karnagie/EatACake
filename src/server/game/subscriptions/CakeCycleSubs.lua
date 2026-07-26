--[[
	CakeCycleSubs -- cake lifecycle orchestration: map/cake construction, match
	beginning, boss resolution, rewards, and cycle-state broadcasts.

	CakeSubs owns player input. CakeSimulationSubs owns the Heartbeat fabric and
	calls this module for rare transitions. GameRoundSubs begins the one reserved
	match through BeginMatch. All mutable cake/round state remains in data modules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local SCOPE = "CakeCycleSubs"

local CakeCycleSubs = {}

local state -- CakeStateData
local cakeCfg
local services_
local PetSubs
local GameRoundSubs
local uSnapshot
local uCycle

local function matchExpectedCount(): number?
	if GameRoundSubs == nil then
		return nil
	end
	if type(GameRoundSubs.IsActive) ~= "function" then
		Log.Once(SCOPE, "round-active-missing", "GameRoundSubs.IsActive is missing -- endless population fallback used")
		return nil
	end
	if not GameRoundSubs.IsActive() then
		return nil
	end
	if type(GameRoundSubs.ExpectedCount) ~= "function" then
		Log.Once(SCOPE, "round-count-missing", "GameRoundSubs.ExpectedCount is missing -- endless population fallback used")
		return nil
	end
	local expectedCount = GameRoundSubs.ExpectedCount()
	return if expectedCount > 0 then expectedCount else nil
end

local function loadedCakePlayers(): { Player }
	local candidates = Players:GetPlayers()
	local expectedCount = matchExpectedCount()
	if expectedCount ~= nil then
		if type(GameRoundSubs.Participants) ~= "function" then
			Log.Once(SCOPE, "round-participants-missing", "GameRoundSubs.Participants is missing -- match cake has no safe player audience")
			return {}
		end
		candidates = GameRoundSubs.Participants()
	end

	local loaded = {}
	for _, player in ipairs(candidates) do
		if services_.PersistenceService.IsLoaded(player.UserId) then
			table.insert(loaded, player)
		end
	end
	return loaded
end

local function fireCycle(payload)
	if matchExpectedCount() == nil then
		uCycle:FireAllClients(payload)
		return
	end
	for _, player in ipairs(loadedCakePlayers()) do
		uCycle:FireClient(player, payload)
	end
end

local function fireSnapshot(bufferValue, metadata)
	if matchExpectedCount() == nil then
		uSnapshot:FireAllClients(bufferValue, metadata)
		return
	end
	for _, player in ipairs(loadedCakePlayers()) do
		uSnapshot:FireClient(player, bufferValue, metadata)
	end
end

local function rewardPlayers(players: { Player })
	local minRarity = if state.rareKind == "rainbow" then cakeCfg.composition.rare.rainbow.guaranteedRarity else nil
	for _, player in ipairs(players) do
		local userId = player.UserId
		if services_.PersistenceService.IsLoaded(userId) then
			local roll = services_.PetService.Roll(userId, "cycle", minRarity)
			if roll then
				roll.source = "cake"
				if PetSubs then
					PetSubs.SendRoll(player, roll)
					PetSubs.SendPets(player)
				else
					Log.Once(SCOPE, "pet-subs-missing", "PetSubs is missing -- cake pet reward granted but its reveal push was dropped")
				end
			end
			services_.ProgressService.AddStat(userId, "cakesEaten", 1)
			-- A cake-clear reward is a high-value milestone. Persist it now even in
			-- match mode; the later intentional unload is a separate final save.
			services_.PersistenceService.Save(userId)
		else
			Log.Warn(SCOPE, `cake-clear reward skipped for {player.Name}: profile is not loaded`)
		end
	end
end

--API
function CakeCycleSubs.BroadcastCycle(announce: string?)
	if uCycle == nil or state == nil then
		Log.Once(SCOPE, "broadcast-before-start", "BroadcastCycle called before Start -- update dropped")
		return
	end
	fireCycle({
		phase = state.phase,
		progress = state.progress,
		timer = math.max(0, math.floor(state.phaseTimer * 10) / 10),
		boss = state.boss and { hp = state.boss.hp, maxHp = state.boss.maxHp } or nil,
		rareKind = state.rareKind,
		biome = state.biome,
		activeBandIndex = state.activeBandIndex,
		announce = announce,
	})
end

--API
function CakeCycleSubs.SpawnNewCake(fixedPlayerCount: number?)
	if services_ == nil or state == nil then
		Log.Warn(SCOPE, "SpawnNewCake called before Start -- cake not spawned")
		return false
	end

	local cakePlayers = loadedCakePlayers()
	local maxRebirths = 0
	for _, player in ipairs(cakePlayers) do
		local rebirths = services_.ProgressService.GetRebirths(player.UserId)
		if rebirths and rebirths > maxRebirths then
			maxRebirths = rebirths
		end
	end
	local biome = services_.ProgressService.BiomeFor(maxRebirths)
	local playerCount = math.max(1, fixedPlayerCount or #cakePlayers)
	local composition, footprint, rareKind = services_.CakeCycleService.RollComposition(biome, playerCount)
	if rareKind == nil and os.time() - state.lastRareEventAt >= 3600 then
		rareKind = "golden"
	end
	if rareKind ~= nil then
		state.lastRareEventAt = os.time()
	end

	services_.CakeFieldService.ResetCake(composition, footprint, rareKind, biome)
	services_.TreasureService.SpawnForCake()
	services_.MapService.ApplyBiome(biome)
	services_.MapService.SetCheckpointHeight(cakeCfg.grid.origin.y + composition[#composition].top)
	services_.CakeCycleService.BeginEating()

	-- Lift characters out of the materialized cake, and carry checkpoint users
	-- with the plate when it jumps to the fresh top layer.
	local grid = cakeCfg.grid
	local topY = grid.origin.y + composition[#composition].top + 3
	local extentX = footprint.hx * grid.cell + 4
	local extentZ = footprint.hz * grid.cell + 4
	for _, player in ipairs(cakePlayers) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dx = math.abs(root.Position.X - grid.origin.x)
			local dz = math.abs(root.Position.Z - grid.origin.z)
			if dx <= extentX and dz <= extentZ and root.Position.Y < topY then
				root.CFrame = CFrame.new(root.Position.X, topY, root.Position.Z)
			elseif services_.MapService.IsOverCheckpoint(root.Position) then
				local checkpoint = services_.MapService.GetCheckpointCFrame()
				if checkpoint then
					root.CFrame = checkpoint
				end
			end
		end
	end

	local buffer, metadata = services_.CakeFieldService.Snapshot()
	fireSnapshot(buffer, metadata)
	CakeCycleSubs.BroadcastCycle(if rareKind then `rare-cake-{rareKind}` else "new-cake")
	return true
end

--API
function CakeCycleSubs.BeginMatch(difficulty: string, expectedCount: number): boolean
	if type(difficulty) ~= "string"
		or type(expectedCount) ~= "number"
		or expectedCount < 1
		or expectedCount % 1 ~= 0
	then
		Log.Warn(SCOPE, `BeginMatch received invalid difficulty/count ('{tostring(difficulty)}', {tostring(expectedCount)})`)
		return false
	end
	Log.Sum(SCOPE, `beginning {difficulty} match against fixed expected count {expectedCount}`)
	return CakeCycleSubs.SpawnNewCake(expectedCount)
end

--API
function CakeCycleSubs.BossPlayerCount(): number
	local expectedCount = matchExpectedCount()
	if expectedCount ~= nil then
		-- The lobby roster is fixed at launch. Departures must not lower the boss
		-- requirement after the party selected and accepted its match size.
		return math.max(1, expectedCount)
	end
	return math.max(1, #Players:GetPlayers())
end

--API
function CakeCycleSubs.FinishBoss(result: string): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, `FinishBoss('{result}') called before Start -- ignored`)
		return false
	end
	if result ~= "win" and result ~= "loss" then
		Log.Warn(SCOPE, `FinishBoss received invalid result '{tostring(result)}' -- ignored`)
		return false
	end
	if state.phase ~= "boss" then
		return false
	end

	-- BeginReward changes phase immediately, guarding reward/result from a
	-- simultaneous boss tap and timeout transition.
	services_.CakeCycleService.BeginReward()
	local expectedCount = matchExpectedCount()
	local matchMode = expectedCount ~= nil
	if result == "win" then
		local recipients = Players:GetPlayers()
		if matchMode then
			if type(GameRoundSubs.Participants) == "function" then
				recipients = GameRoundSubs.Participants()
			else
				Log.Warn(SCOPE, "GameRoundSubs.Participants is missing -- match win has no safe reward roster")
				recipients = {}
			end
		end
		rewardPlayers(recipients)
	end

	CakeCycleSubs.BroadcastCycle(if result == "win" then "cake-cleared" else "match-lost")
	if matchMode then
		if type(GameRoundSubs.Finish) ~= "function" then
			Log.Warn(SCOPE, `GameRoundSubs.Finish is missing -- terminal {result} cannot return participants to the lobby`)
			return true
		end
		local ok, finished = pcall(GameRoundSubs.Finish, result)
		if not ok then
			Log.Warn(SCOPE, `GameRoundSubs.Finish('{result}') FAILED: {finished}`)
		elseif finished == false then
			Log.Warn(SCOPE, `GameRoundSubs.Finish('{result}') declined the terminal result`)
		end
	else
		services_.CakeCycleService.StartSpawning()
	end
	return true
end

function CakeCycleSubs.Start(data, services, subscriptions)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData and data.CakeConfigData.cake
	services_ = services
	PetSubs = subscriptions and subscriptions.PetSubs
	GameRoundSubs = subscriptions and subscriptions.GameRoundSubs
	if state == nil or cakeCfg == nil then
		Log.Warn(SCOPE, "CakeStateData/CakeConfigData missing -- cake lifecycle disabled")
		return
	end
	if GameRoundSubs == nil then
		Log.Warn(SCOPE, "GameRoundSubs is missing -- cake cycle will use endless fallback mode")
	end

	uSnapshot = Net.Update("CakeSnapshotUpdate")
	uCycle = Net.Update("CakeCycleUpdate")
	services_.MapService.Build()
	services_.CakeCollisionService.BuildParts()
	state.lastRareEventAt = os.time()
	local roundActive = data.RoundStateData and data.RoundStateData["round-active"] == true
	if GameRoundSubs == nil or not roundActive then
		CakeCycleSubs.SpawnNewCake()
	else
		Log.Info(SCOPE, "reserved-round gate armed -- fresh cake deferred until BeginMatch succeeds")
	end
end

return CakeCycleSubs
