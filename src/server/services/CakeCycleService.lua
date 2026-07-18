--[[
	CakeCycleService — cake lifecycle logic (GDD §9):
	  spawning -> eating -> boss -> reward -> spawning ...

	Logic only (R2): state lives in CakeStateData; CakeSubs drives Step(dt)
	from Heartbeat, reacts to the returned events (fires remotes, rolls
	pets — R3 orchestration stays in the subscription).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local CakeCycleService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake

function CakeCycleService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
end

--API
-- Rolls a new cake: composition (bottom-up bands) + the fixed loaf
-- footprint + rare kind. Pure roll — the caller passes everything to
-- CakeFieldService.ResetCake.
function CakeCycleService.RollComposition(biome: string, playerCount: number)
	local comp = cakeCfg.composition
	local grid = cakeCfg.grid
	local footprint = comp.footprint

	-- Middle layers: middleCountMin..Max from the pool, no immediate repeats.
	local middleCount = math.random(comp.middleCountMin, comp.middleCountMax)
	local middles = {}
	local lastId = nil
	for _ = 1, middleCount do
		local candidate
		repeat
			candidate = comp.middlePool[math.random(#comp.middlePool)]
		until candidate ~= lastId
		lastId = candidate
		table.insert(middles, candidate)
	end

	-- Thicknesses: roll raw, then scale middles so the total hits the
	-- rolled target height (clamped to the grid ceiling).
	local totalTarget = math.min(
		math.random(comp.totalHeight[1], comp.totalHeight[2]),
		grid.maxHeight
	)
	local frosting = math.random(comp.frostingThickness[1], comp.frostingThickness[2])
	local middleBudget = totalTarget - comp.coreThickness - frosting
	local raw = {}
	local rawSum = 0
	for k = 1, middleCount do
		raw[k] = math.random(comp.middleThickness[1], comp.middleThickness[2])
		rawSum += raw[k]
	end

	local composition = {}
	local cursor = 0
	local function push(id: string, thickness: number)
		table.insert(composition, { id = id, bottom = cursor, top = cursor + thickness })
		cursor += thickness
	end
	push("core", comp.coreThickness)
	for k = 1, middleCount do
		push(middles[k], raw[k] / rawSum * middleBudget)
	end
	push("frosting", frosting)

	-- Rare cakes (§5): golden / rainbow, announced server-wide by CakeSubs.
	local rareKind = nil
	local roll = math.random()
	if roll < comp.rare.rainbow.chance then
		rareKind = "rainbow"
	elseif roll < comp.rare.rainbow.chance + comp.rare.golden.chance then
		rareKind = "golden"
	end

	return composition, footprint, rareKind
end

--API
-- Calories multiplier of the current cake (rare cakes pay more).
function CakeCycleService.CakeCaloriesMult(): number
	local rare = state.rareKind and cakeCfg.composition.rare[state.rareKind]
	return rare and rare.caloriesMult or 1
end

--API
function CakeCycleService.Phase(): string
	return state.phase
end

--API
-- eating -> boss. HP scales with the current population.
function CakeCycleService.BeginBoss(playerCount: number)
	state.phase = "boss"
	state.phaseTimer = cakeCfg.cycle.bossDuration
	local hp = cakeCfg.cycle.bossTapsPerPlayer * math.max(1, playerCount)
	state.boss = { hp = hp, maxHp = hp }
	Log.Sum("CakeCycle", `boss phase — {cakeCfg.cycle.bossName}, hp={hp}, {cakeCfg.cycle.bossDuration}s limit`)
end

--API
-- A tap on the boss. Returns remaining hp (<= 0 means defeated this tap).
function CakeCycleService.DamageBoss(amount: number): number?
	local boss = state.boss
	if state.phase ~= "boss" or boss == nil then
		return nil
	end
	boss.hp = math.max(0, boss.hp - math.max(1, math.floor(amount)))
	return boss.hp
end

--API
-- boss -> reward (pet rolls happen in CakeSubs, then StartSpawning).
function CakeCycleService.BeginReward()
	state.phase = "reward"
	state.boss = nil
	state.phaseTimer = 0
end

--API
-- reward -> spawning (countdown to the next cake).
function CakeCycleService.StartSpawning()
	state.phase = "spawning"
	state.phaseTimer = cakeCfg.cycle.newCakeDelay
end

--API
-- Marks the freshly built cake as live.
function CakeCycleService.BeginEating()
	state.phase = "eating"
	state.phaseTimer = 0
end

--API
-- Advances timed phases. Returns an event string when a transition is due,
-- which the SUBSCRIPTION acts on (R3/R4):
--   "boss-timeout"  boss timer expired (auto-defeat — never block the loop)
--   "boss-defeated" hp reached zero
--   "spawn-cake"    spawning countdown finished
function CakeCycleService.Step(dt: number): string?
	if state.phase == "boss" then
		state.phaseTimer -= dt
		if state.boss and state.boss.hp <= 0 then
			return "boss-defeated"
		end
		if state.phaseTimer <= 0 then
			return "boss-timeout"
		end
	elseif state.phase == "spawning" then
		state.phaseTimer -= dt
		if state.phaseTimer <= 0 then
			return "spawn-cake"
		end
	end
	return nil
end

return CakeCycleService
