--[[
	CakeCycleSubs -- cake lifecycle orchestration: map/cake construction, match
	beginning, ZONE-GATE mini-bosses, boss resolution, rewards, and cycle-state
	broadcasts.

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

-- ⚠ This was a PER-RECIPIENT fire while the boss advertised a pre-rolled squishy
-- ("FIGHTING FOR ..."). That preview was REMOVED 2026-08-07 by request — the
-- prize is a surprise again — so the payload is identical for everyone and this
-- is a plain broadcast outside a reserved match, exactly like fireSnapshot.
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
	-- How long this cake took, for the Top Speed Runners board
	-- (features/leaderboards.md). Measured ONCE for the whole cake — the clock
	-- belongs to the cake, not to a player — and awarded only to the spawn
	-- roster. A zero/absent stamp means the cake was never stamped (a cycle that
	-- somehow reached a win without SpawnNewCake), so no time is recorded at all
	-- rather than a fake one.
	local elapsedMillis = nil
	if state.debugSuppressFindRewards == true then
		-- ⚠ A DebugClearLayer cake reaches the boss in ~1 minute instead of ~35,
		-- and `bestCakeMillis` is a MINIMUM published to an ASCENDING ordered
		-- store — nothing in the game can ever displace that row again, and the
		-- only remedy is bumping `storeVersion`, which wipes all three boards
		-- (ADR-0022). The same latch already suppresses find/analytics writes for
		-- a debug-skipped cake (CakeSimulationSubs); the speedrun clock joins it.
		-- `cakesEaten` deliberately still counts: it is monotonic, self-corrects
		-- with real runs, and QA relies on it to unlock the rainbow cake.
		Log.Warn(SCOPE, "DebugClearLayer cake -- speedrun time NOT recorded (a debug clear would set an unbeatable record)")
	elseif type(state.cakeStartedAt) == "number" and state.cakeStartedAt > 0 then
		elapsedMillis = math.floor((os.clock() - state.cakeStartedAt) * 1000)
		if elapsedMillis <= 0 then
			elapsedMillis = nil
		end
	else
		Log.Once(SCOPE, "no-cake-clock", "cake cleared with no spawn stamp -- no speedrun time recorded")
	end
	for _, player in ipairs(players) do
		local userId = player.UserId
		if services_.PersistenceService.IsLoaded(userId) then
			-- Rolled AT THE WIN, not advertised during the fight: the prize preview
			-- was removed 2026-08-07 by request. `PetService.Roll` is still
			-- `Preview + Grant` internally (features/pets.md) — that split stays,
			-- it just has no second caller any more.
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
			if elapsedMillis ~= nil and type(state.cakeStartRoster) == "table" and state.cakeStartRoster[userId] then
				if services_.ProgressService.RecordCakeTime(userId, elapsedMillis) then
					Log.Info(SCOPE, `{player.Name}: new best cake time {string.format("%.1f", elapsedMillis / 1000)}s`)
				end
			end
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
	local mini = state.miniBoss
	fireCycle({
		phase = state.phase,
		progress = state.progress,
		timer = math.max(0, math.floor(state.phaseTimer * 10) / 10),
		boss = state.boss and { hp = state.boss.hp, maxHp = state.boss.maxHp } or nil,
		-- The ZONE GATE (features/cake-cycle.md). `model` is the authored rig name
		-- the client clones out of ReplicatedStorage.Assets.MiniBosses; `zoneKey`
		-- names the zone it is guarding, for the HUD/announce.
		miniBoss = mini and {
			hp = mini.hp,
			maxHp = mini.maxHp,
			index = mini.index,
			model = mini.model,
			zoneKey = mini.zoneKey,
		} or nil,
		rareKind = state.rareKind,
		cakeId = state.cakeId,
		biome = state.biome,
		activeBandIndex = state.activeBandIndex,
		-- Per-cake find goal for the HUD ("FINDS 7/40"). The cake % bar is hidden
		-- while eating, which is ~all of the playtime, so this is the only
		-- progress signal the player gets during the loop.
		finds = findCounts(),
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
	-- SPEEDRUN clock (features/leaderboards.md). The roster is snapshotted with
	-- the stamp because only these players ran the WHOLE cake: in a reserved
	-- match `beginMatchIfReady` has already waited for every arriving profile, so
	-- this is the final roster; in the endless fallback it excludes anyone who
	-- walks in on a half-eaten cake.
	state.cakeStartedAt = os.clock()
	if type(state.cakeStartRoster) == "table" then
		table.clear(state.cakeStartRoster)
	else
		state.cakeStartRoster = {}
	end
	for _, player in ipairs(cakePlayers) do
		state.cakeStartRoster[player.UserId] = true
	end
	-- A fresh cake starts with no live gate (belt-and-braces: FinishMiniBoss
	-- already clears it, but the endless fallback can reach a new cake from any
	-- phase). `zones` / `miniBossesDefeated` are re-rolled by RollComposition.
	state.miniBoss = nil
	if type(state.pendingMiniBossZones) == "table" then
		table.clear(state.pendingMiniBossZones)
	else
		state.pendingMiniBossZones = {}
	end
	-- DebugClearLayer may uncover/collect finds while QA skips through a cake.
	-- Its no-profile-write latch is cake-scoped; a normally spawned cake must
	-- always restore production reward behaviour.
	state.debugSuppressFindRewards = false
	-- Biome used to be unlocked by the highest-rebirth player present; rebirth is
	-- gone (2026-07-26) so every cake takes the first biome. Kept as a call so
	-- re-introducing an unlock rule stays a one-liner (ProgressService.BiomeFor).
	local biome = services_.ProgressService.BiomeFor(0)
	local playerCount = math.max(1, fixedPlayerCount or #cakePlayers)
	local composition, footprint, rareKind = services_.CakeCycleService.RollComposition(biome, playerCount)
	local variant = cakeCfg.variants and cakeCfg.variants[state.cakeId] or {}
	local environmentName = variant.environmentName or "Environment"
	services_.MapService.UseEnvironment(environmentName)
	if variant.rareEnabled ~= false and rareKind == nil and os.time() - state.lastRareEventAt >= 3600 then
		rareKind = "golden"
	end
	if rareKind ~= nil then
		state.lastRareEventAt = os.time()
	end

	services_.CakeFieldService.ResetCake(composition, footprint, rareKind, biome)
	-- ⚠ REFRESH THE COARSE SAFETY NET *BEFORE* PLACING ANYONE ON THE CAKE.
	-- `ResetCake` writes the selected cake's full height but changes nothing collidable, and
	-- the only other caller of `UpdateHeights` is the 5 Hz clock in
	-- CakeSimulationSubs — which sits BELOW that Heartbeat's
	-- `roundSimulationEnabled()` early-return, and so does its accumulator. That
	-- gate is `match-started`, which `GameRoundService.CompleteStart` sets only
	-- AFTER `BeginMatch` (i.e. after this function) returns. So at a reserved-match
	-- start the 256 slabs are provably still their build pose (1-stud plates with
	-- their tops at `grid.origin.y`) for a FULL `1/collisionHz` after the lift
	-- below drops characters at cake height — nothing to stand on for 200 ms, on
	-- top of however long the client's cold EditableMesh pool build takes before
	-- its own columns exist. That window is the bug: players free-fall into the
	-- cake and `columnsRebuild` then closes 1024 solid columns around them.
	-- A freshly reset cake is near-flat, so the min-of-block slab lands within
	-- ~0.3 studs of the true surface: an exact floor at exactly the instant it is
	-- needed. Zero the accumulator too: the slabs are current as of right now, so
	-- the 5 Hz clock should start a fresh period rather than fire again instantly.
	services_.CakeCollisionService.UpdateHeights()
	state.simulationAccumulators.collision = 0
	services_.TreasureService.SpawnForCake()
	services_.MapService.ApplyBiome(biome)
	local topBand = composition[#composition]
	services_.MapService.SetCheckpointHeight(cakeCfg.grid.origin.y + topBand.top, topBand.footprint or footprint)
	services_.CakeCycleService.BeginEating()

	-- Lift characters out of the materialized cake, and carry checkpoint users
	-- with the plate when it jumps to the fresh top layer.
	local grid = cakeCfg.grid
	-- Two DIFFERENT heights, deliberately split (they used to be one `+ 3`):
	--   surfaceY = the crust. The "are they inside the new cake?" PREDICATE, so a
	--     player already standing on fresh crust is not re-hopped every new cake.
	--   liftY    = where we actually put them. `+ 3` was the HumanoidRootPart
	--     offset of an R15 rig, i.e. feet flush ON the crust with ZERO clearance —
	--     the wrong constant for a target that has no collider under it yet.
	local surfaceY = grid.origin.y + composition[#composition].top
	local liftY = surfaceY + cakeCfg.composition.liftClearanceStuds
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
		-- An ANCHORED root is owned by something that re-asserts its CFrame (the
		-- gym treadmill mount, BodySubs) — teleporting it just fights that loop for
		-- one tick. Let the owner carry the player instead.
		if root and not root.Anchored then
			local qx = math.max(math.abs(root.Position.X - grid.origin.x) - edgeX, 0)
			local qz = math.max(math.abs(root.Position.Z - grid.origin.z) - edgeZ, 0)
			if qx * qx + qz * qz <= liftR * liftR and root.Position.Y < surfaceY then
				-- ⚠ Zero the assembly first. A bare CFrame write KEEPS velocity, and
				-- during the arrival window there is no cake at all — every character
				-- is mid-fall from the spawn pad at up to terminal speed. Placed at
				-- cake height still carrying ~150 studs/s down, they punch straight
				-- through on the next physics step. (BodySubs.mountTreadmill already
				-- does this; the lift never did — that is the "sometimes".)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.CFrame = CFrame.new(root.Position.X, liftY, root.Position.Z)
			elseif services_.MapService.IsOverCheckpoint(root.Position) then
				local checkpoint = services_.MapService.GetCheckpointCFrame()
				if checkpoint then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
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

local function announceMiniBossStart()
	local fighters = loadedCakePlayers()
	beatCycle(
		fighters,
		nil,
		"miniboss-start",
		tostring(state.miniBoss and state.miniBoss.index or 0),
		tostring(state.miniBoss and state.miniBoss.model)
	)
	CakeCycleSubs.BroadcastCycle("miniboss-spawned")
end

--API
-- eating -> miniboss, at a flavour-ZONE boundary (features/cake-cycle.md).
-- `zoneIndex` is the zone the layer gate has just stepped INTO; that zone's
-- `bossModel` is the rig that bursts out of the cake to guard it. Every bite is
-- blocked until it dies, which is what makes a zone a real chapter break.
function CakeCycleSubs.BeginMiniBoss(zoneIndex: number): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, "BeginMiniBoss called before Start -- zone gate skipped")
		return false
	end
	if state.phase ~= "eating" then
		-- The boss/reward transition won the race for this scan tick. Not an
		-- error, but it must not be silent: a swallowed gate means a zone opened
		-- unguarded.
		Log.Once(SCOPE, "miniboss-late", `zone gate for zone #{zoneIndex} arrived in phase '{state.phase}' -- skipped`)
		return false
	end
	if not services_.CakeCycleService.BeginMiniBoss(CakeCycleSubs.BossPlayerCount(), zoneIndex) then
		return false
	end
	announceMiniBossStart()
	return true
end

--API
-- Starts the oldest boundary captured by QueueCrossedMiniBosses. A multi-zone
-- scan enters the first gate immediately; FinishMiniBoss chains the remainder
-- without reopening the already-cleared deeper zones between fights.
function CakeCycleSubs.BeginNextMiniBoss(): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, "BeginNextMiniBoss called before Start -- queued zone gate not started")
		return false
	end
	if state.phase ~= "eating" then
		Log.Once(SCOPE, "queued-miniboss-wrong-phase", `queued zone gate arrived in phase '{state.phase}' -- start deferred`)
		return false
	end
	if not services_.CakeCycleService.BeginNextMiniBoss(CakeCycleSubs.BossPlayerCount()) then
		return false
	end
	announceMiniBossStart()
	return true
end

--API
-- miniboss -> eating. The gate is down; the zone below is now edible.
function CakeCycleSubs.FinishMiniBoss(): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, "FinishMiniBoss called before Start -- ignored")
		return false
	end
	if state.phase ~= "miniboss" or state.miniBoss == nil then
		return false
	end
	local index = state.miniBoss.index
	-- Change phase before telemetry or remotes. CakeSubs finishes on the killing
	-- tap while Heartbeat has an hp<=0 backstop; guarding the state first keeps
	-- both callbacks from consuming two FIFO gates if they meet on one frame.
	services_.CakeCycleService.FinishMiniBoss()
	beatCycle(loadedCakePlayers(), nil, "miniboss-end", tostring(index), nil)
	CakeCycleSubs.BroadcastCycle("miniboss-defeated")
	local pending = services_.CakeCycleService.PendingMiniBossCount()
	if pending > 0 and not CakeCycleSubs.BeginNextMiniBoss() then
		Log.Warn(SCOPE, `{pending} crossed zone gate(s) remain queued after mini-boss #{index} -- cake stays locked from its finale`)
	end
	return true
end

--API
-- eating -> boss. CakeSimulationSubs calls this instead of
-- CakeCycleService.BeginBoss directly so the analytics beats stay in the
-- subscription layer (R3/R4).
function CakeCycleSubs.BeginBoss(playerCount: number): boolean
	if state == nil or services_ == nil then
		Log.Warn(SCOPE, "BeginBoss called before Start -- boss phase not started")
		return false
	end
	if not services_.CakeCycleService.BeginBoss(playerCount) then
		return false
	end
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
