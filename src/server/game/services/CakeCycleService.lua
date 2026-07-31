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
local roundState -- RoundStateData

local function difficultyConfig()
	local matchConfig = roundState and roundState["match-config"]
	local difficulty = roundState and roundState["difficulty"]
	local config = matchConfig and matchConfig.difficulties[difficulty]
	if config == nil then
		Log.Once("CakeCycle", "missing-difficulty", `round difficulty '{tostring(difficulty)}' has no MatchConfig tuning -- neutral multipliers used`)
		return {}
	end
	return config
end

function CakeCycleService.Init(data)
	state = data.CakeStateData
	cakeCfg = data.CakeConfigData.cake
	roundState = data.RoundStateData
end

--API
-- How much EATING WORK this cake is worth: difficulty × co-op. Drives the layer
-- count and the scoop ramp (CakeConfig.composition header) — and nothing else,
-- so a bigger cake is never a taller one.
function CakeCycleService.CakeWork(playerCount: number): number
	local comp = cakeCfg.composition
	local players = math.max(1, playerCount or 1)
	local difficultyWork = difficultyConfig().workMultiplier or 1
	return difficultyWork * (1 + (comp.coopWork or 0) * (players - 1))
end

--API
-- Rolls a new cake: composition (bottom-up bands) + the fixed loaf
-- footprint + rare kind. Pure roll — the caller passes everything to
-- CakeFieldService.ResetCake.
--
-- Bands are designed TOP-DOWN along the pacing curve (see the CakeConfig
-- .composition header): band k gets a `scoop` (bite-radius multiplier) that
-- shrinks geometrically with depth, a thickness that grows with it, and a
-- `density` (calories + belly fill per stud³) that keeps one bite worth the
-- same food anywhere in any cake. Layer IDENTITY stays random — the pacing
-- lives on the band, so a chocolate layer near the top can no longer wreck the
-- opening minutes.
function CakeCycleService.RollComposition(biome: string, playerCount: number)
	local comp = cakeCfg.composition
	local grid = cakeCfg.grid
	local footprint = comp.footprint

	local work = CakeCycleService.CakeWork(playerCount)
	local layers = math.clamp(
		math.floor(comp.baseLayers * work ^ comp.layerExponent + 0.5),
		2,
		comp.maxLayers
	)
	-- Work the layer cap could not absorb becomes SMALLER scoops (a denser cake).
	-- Clear time scales with the bite AREA, hence the square root.
	local scoopScale = (work / (layers / comp.baseLayers)) ^ -0.5
	local scoopTop = comp.scoopTop * scoopScale
	local scoopBottom = comp.scoopBottom * scoopScale
	local totalHeight = math.min(comp.maxTotalHeight, grid.maxHeight - comp.coreThickness)

	-- Per-band scoop + thickness WEIGHT (thickness follows the scoop ramp).
	local scoops, weights, weightSum = {}, {}, 0
	for k = 0, layers - 1 do
		local f = if layers > 1 then k / (layers - 1) else 0
		local scoop = scoopTop * (scoopBottom / scoopTop) ^ f
		scoops[k + 1] = scoop
		local w = (scoopTop / scoop) ^ (2 * comp.thicknessExponent)
		weights[k + 1] = w
		weightSum += w
	end

	-- Layer identity: random from the pool, no immediate repeats. Index 1 is
	-- the TOP (always frosting), index `layers` the deepest.
	local ids = { "frosting" }
	local lastId = "frosting"
	for k = 2, layers do
		local candidate
		repeat
			candidate = comp.middlePool[math.random(#comp.middlePool)]
		until candidate ~= lastId
		lastId = candidate
		ids[k] = candidate
	end

	-- Thicknesses (top-down), jittered then RENORMALISED so the cake is exactly
	-- `totalHeight` tall whatever the jitter and the min-thickness floor did.
	local thickness, thickSum = {}, 0
	for k = 1, layers do
		local jitter = 0.9 + math.random() * 0.2
		local t = math.max(comp.minLayerThickness, weights[k] / weightSum * totalHeight * jitter)
		thickness[k] = t
		thickSum += t
	end
	local renorm = totalHeight / thickSum
	for k = 1, layers do
		thickness[k] *= renorm
	end

	local composition = {}
	local cursor = 0
	local function push(band)
		band.bottom = cursor
		band.top = cursor + band.thickness
		cursor = band.top
		band.thickness = nil
		table.insert(composition, band)
	end
	push({ id = "core", thickness = comp.coreThickness, scoop = 1, density = 1 })
	-- bottom-up: the DEEPEST designed band (k = layers) goes in first
	for k = layers, 1, -1 do
		local scoop = scoops[k]
		local density = math.clamp(comp.refBandWeight / (thickness[k] * scoop * scoop), 1, comp.maxDensity)
		push({ id = ids[k], thickness = thickness[k], scoop = scoop, density = density })
	end

	-- Rare cakes (§5): golden / rainbow, announced server-wide by CakeSubs.
	local rareKind = nil
	local roll = math.random()
	if roll < comp.rare.rainbow.chance then
		rareKind = "rainbow"
	elseif roll < comp.rare.rainbow.chance + comp.rare.golden.chance then
		rareKind = "golden"
	end

	-- Payout scale for THIS cake: difficulty premium × per-head co-op payout.
	-- Stored here (not recomputed per bite) so it cannot drift as players leave.
	state.payoutScale = (difficultyConfig().caloriesMultiplier or 1)
		* (1 + (comp.coopCalories or 0) * (math.max(1, playerCount or 1) - 1))
	-- Gems from finds get the per-head term but NOT the difficulty premium — see
	-- CakeConfig.composition.coopFinds.
	state.findPayoutScale = 1 + (comp.coopFinds or 0) * (math.max(1, playerCount or 1) - 1)

	Log.Sum(
		"CakeCycle",
		`cake rolled — {layers} layers, {math.floor(totalHeight)} studs, work {string.format("%.2f", work)}, scoop {string.format("%.2f", scoopTop)}→{string.format("%.2f", scoopBottom)}, payout ×{string.format("%.2f", state.payoutScale)}`
	)
	return composition, footprint, rareKind
end

--API
-- A find's reward descriptor with this cake's per-head find payout applied.
-- Returns a COPY — the caller is handed `TreasureConfig.finds[n].reward`, which
-- is shared by every spawn of that find for the life of the server, so scaling it
-- in place would compound on the config itself.
-- Only `gems` is scaled: finds pay gems only (features/treasures.md), and a kind
-- with no amount is passed through untouched rather than silently dropped.
function CakeCycleService.ScaleFindReward(reward)
	if type(reward) ~= "table" then
		return reward
	end
	local scale = state.findPayoutScale or 1
	if scale == 1 or reward.kind ~= "gems" or type(reward.amount) ~= "number" then
		return reward
	end
	local scaled = table.clone(reward)
	scaled.amount = math.max(1, math.floor(reward.amount * scale))
	return scaled
end

--API
-- Calories multiplier of the current cake: rare-cake bonus × this cake's payout
-- scale (difficulty premium × per-head co-op payout, fixed at RollComposition).
function CakeCycleService.CakeCaloriesMult(): number
	local rare = state.rareKind and cakeCfg.composition.rare[state.rareKind]
	return (rare and rare.caloriesMult or 1) * (state.payoutScale or 1)
end

--API
function CakeCycleService.Phase(): string
	return state.phase
end

--API
-- eating -> boss. HP scales with the current population.
function CakeCycleService.BeginBoss(playerCount: number)
	local difficulty = difficultyConfig()
	state.phase = "boss"
	state.phaseTimer = cakeCfg.cycle.bossDuration * (difficulty.bossDurationMultiplier or 1)
	local hp = math.max(
		1,
		math.ceil(cakeCfg.cycle.bossTapsPerPlayer * math.max(1, playerCount) * (difficulty.bossHpMultiplier or 1))
	)
	state.boss = { hp = hp, maxHp = hp }
	Log.Sum("CakeCycle", `boss phase — {cakeCfg.cycle.bossName}, hp={hp}, {state.phaseTimer}s limit`)
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
--   "boss-timeout"  boss timer expired (the round orchestrator records a loss)
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
