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
local AnalyticsSubs -- optional; features/analytics.md
local uSnapshot
local uCycle

-- Telemetry, never on the cycle's critical path (R8).
local function beatCycle(players: { Player }, funnelStep: string?, eventKey: string?, a: any?, b: any?)
	if AnalyticsSubs == nil then
		return
	end
	for _, player in ipairs(players) do
		local ok, err = pcall(function()
			if funnelStep then
				AnalyticsSubs.Funnel(player, "match", funnelStep)
			end
			if eventKey then
				AnalyticsSubs.Event(player, eventKey, 1, { a, b, "game" }, { tier = "critical" })
			end
		end)
		if not ok then
			-- `continue`, not `return`: one player's failure must not cost the
			-- rest of the party their beat.
			Log.Once(SCOPE, "cycle-analytics", `cycle analytics beat FAILED (telemetry only): {err}`)
			continue
		end
	end
end

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
	local matchMode = matchExpectedCount() ~= nil
	-- The boss PRIZE is per-player (each fighter has their own pre-rolled squishy),
	-- so once prizes exist this update stops being one broadcast payload. A
	-- shallow clone per recipient rather than mutating one shared table: cheap
	-- (<=4 players at 4 Hz) and it cannot leak one player's prize to another if a
	-- future change makes the fire path yield.
	local prizes = state.pendingPetRolls
	local perPlayer = next(prizes) ~= nil
	if not matchMode and not perPlayer then
		uCycle:FireAllClients(payload)
		return
	end
	local recipients = if matchMode then loadedCakePlayers() else Players:GetPlayers()
	for _, player in ipairs(recipients) do
		if perPlayer then
			local personal = table.clone(payload)
			personal.pendingPet = prizes[player.UserId]
			uCycle:FireClient(player, personal)
		else
			uCycle:FireClient(player, payload)
		end
	end
end

-- Decide (but do NOT grant) the squishy each fighter is playing for. Called when
-- the boss phase opens so the HUD can advertise the prize — the fight used to be
-- a blind tap race with no visible stake. Committed by rewardPlayers on a win.
local function prepareBossPrizes()
	table.clear(state.pendingPetRolls)
	local minRarity = if state.rareKind == "rainbow" then cakeCfg.composition.rare.rainbow.guaranteedRarity else nil
	local shown = 0
	for _, player in ipairs(loadedCakePlayers()) do
		local preview = services_.PetService.Preview(player.UserId, "cycle", minRarity)
		if preview ~= nil then
			state.pendingPetRolls[player.UserId] = preview
			shown += 1
		else
			-- Not fatal: the win path falls back to a fresh roll, they just fight
			-- without seeing the prize.
			Log.Warn(
				SCOPE,
				`boss prize could not be pre-rolled for {player.Name} (profile not loaded) — `
					.. `no prize shown; a fresh roll is granted on the win instead`
			)
		end
	end
	Log.Sum(SCOPE, `boss prizes pre-rolled for {shown} player(s){if minRarity then ` (floored to {minRarity}+)` else ""}`)
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
			-- COMMIT the prize the boss HUD has been showing this player, so the
			-- squishy they fought for is the squishy they get. Fresh roll only as a
			-- fallback: no preview exists for someone whose profile finished loading
			-- after the boss opened, or who arrived mid-fight.
			local pending = state.pendingPetRolls[userId]
			local roll = nil
			if pending ~= nil then
				roll = services_.PetService.Grant(userId, pending.petId)
				if roll == nil then
					Log.Warn(
						SCOPE,
						`advertised boss prize '{pending.petId}' could not be granted to {player.Name} `
							.. `(id missing from PetConfig?) — rolling a fresh one instead`
					)
				end
			end
			if roll == nil then
				roll = services_.PetService.Roll(userId, "cycle", minRarity)
			end
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

-- Nil-safe: the counts are cosmetic, never worth dropping a cycle update over.
local function findCounts(): { found: number, total: number }?
	local service = services_ and services_.TreasureService
	if service == nil or type(service.FindCounts) ~= "function" then
		Log.Once(SCOPE, "find-counts-missing", "TreasureService.FindCounts missing -- HUD find goal hidden")
		return nil
	end
	local ok, found, total = pcall(service.FindCounts)
	if not ok or type(found) ~= "number" or type(total) ~= "number" or total <= 0 then
		return nil
	end
	return { found = found, total = total }
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
		-- Per-cake find goal for the HUD ("FINDS 7/40"). The cake % bar is hidden
		-- while eating, which is ~all of the playtime, so this is the only
		-- progress signal the player gets during the loop.
		finds = findCounts(),
		announce = announce,
		-- `pendingPet = { petId, rarity }` is attached PER RECIPIENT by fireCycle
		-- (each fighter has their own pre-rolled prize), so it is deliberately not
		-- set here.
	})
end

--API
function CakeCycleSubs.SpawnNewCake(fixedPlayerCount: number?)
	if services_ == nil or state == nil then
		Log.Warn(SCOPE, "SpawnNewCake called before Start -- cake not spawned")
		return false
	end

	local cakePlayers = loadedCakePlayers()
	-- A fresh cake has no boss and therefore no advertised prize (belt-and-braces:
	-- FinishBoss already clears these, but the endless fallback can reach a new
	-- cake without one).
	table.clear(state.pendingPetRolls)
	-- Biome used to be unlocked by the highest-rebirth player present; rebirth is
	-- gone (2026-07-26) so every cake takes the first biome. Kept as a call so
	-- re-introducing an unlock rule stays a one-liner (ProgressService.BiomeFor).
	local biome = services_.ProgressService.BiomeFor(0)
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
	-- "Inside the new cake" = the footprint's own rounded-rect SDF in WORLD studs,
	-- grown by a body width so someone hugging the rim is lifted too. This is
	-- GridUtil.InCake's test, but it deliberately does NOT go through the cell
	-- grid: the grown shape reaches past the 96-stud field along the axes, and
	-- an InBounds check would clip exactly the margin this is here to provide.
	-- ⚠ It used to be an AABB (`hx*cell+4` by `hz*cell+4`). Against the ROUND
	-- footprint (2026-08-03) a box over-reaches by sqrt(2) at the diagonals, so a
	-- player standing on a TRAY CORNER — where the landmark candles are — was
	-- inside the box, outside the cake, and got teleported to cake-top height
	-- with nothing under them: a ~170-stud fall on every new cake. The wrong
	-- region was 1597 studs² under the old loaf and would have been 3425 here.
	local edgeX = (footprint.hx - footprint.corner) * grid.cell
	local edgeZ = (footprint.hz - footprint.corner) * grid.cell
	local liftR = footprint.corner * grid.cell + cakeCfg.composition.liftMarginStuds
	for _, player in ipairs(cakePlayers) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local qx = math.max(math.abs(root.Position.X - grid.origin.x) - edgeX, 0)
			local qz = math.max(math.abs(root.Position.Z - grid.origin.z) - edgeZ, 0)
			if qx * qx + qz * qz <= liftR * liftR and root.Position.Y < topY then
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
-- eating -> boss. Wraps the service transition so the PRIZE is decided in the
-- same step: the boss HUD advertises the squishy each fighter is playing for
-- (features/cake-cycle.md), and rewardPlayers commits exactly that one on a win.
-- CakeSimulationSubs calls this instead of CakeCycleService.BeginBoss directly.
function CakeCycleSubs.BeginBoss(playerCount: number): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, "BeginBoss called before Start -- boss phase not started")
		return false
	end
	services_.CakeCycleService.BeginBoss(playerCount)
	prepareBossPrizes()
	-- Reaching the boss is the end of the cake and the start of the finale;
	-- it is also the last flow step anyone gets to before the result, so the
	-- gap between it and `match-win` is the fight's own difficulty curve.
	local fighters = loadedCakePlayers()
	if AnalyticsSubs ~= nil then
		for _, player in ipairs(fighters) do
			pcall(AnalyticsSubs.Flow, player, "boss")
		end
	end
	beatCycle(fighters, "boss", "boss-start", tostring(playerCount), nil)
	return true
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
	beatCycle(loadedCakePlayers(), nil, "boss-end", result, nil)
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
	-- Terminal either way: the advertised prizes are spent (win) or forfeited
	-- (timeout). Clearing here also takes `pendingPet` back off the cycle update,
	-- so the reward/spawning phases stop showing a prize card.
	table.clear(state.pendingPetRolls)

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
	AnalyticsSubs = subscriptions and subscriptions.AnalyticsSubs
	if AnalyticsSubs == nil then
		Log.Warn(SCOPE, "AnalyticsSubs missing -- boss start/end beats will not be logged")
	end
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
