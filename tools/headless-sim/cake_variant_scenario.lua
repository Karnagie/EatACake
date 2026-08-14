-- SELECTABLE CAKE VARIANT scenario: the real composition + field services must
-- build the rainbow pyramid without changing the classic cake contract.

local GridUtil = __REGISTRY["Shared.GridUtil"]
local CakeConfig = __REGISTRY["Shared.config.CakeConfig"]
local MatchConfig = __REGISTRY["Shared.config.MatchConfig"]
local CakeStateData = __REGISTRY["__CakeStateData"]
local CakeConfigData = __REGISTRY["__CakeConfigData"]
local CakeCycleService = __REGISTRY["__CakeCycleService"]
local CakeFieldService = __REGISTRY["__CakeFieldService"]
local CakeCycleSubs = __REGISTRY["__CakeCycleSubs"]
local CakeSimulationSubs = __REGISTRY["__CakeSimulationSubs"]

local failures, checks = 0, 0
local function check(label: string, ok: boolean, detail: string?)
	checks += 1
	if ok then
		print(`  ok    {label}{detail and (" — " .. detail) or ""}`)
	else
		failures += 1
		print(`  FAIL  {label}{detail and (" — " .. detail) or ""}`)
	end
end

local function near(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 1e-6)
end

local roundState = {
	["match-config"] = MatchConfig,
	["difficulty"] = MatchConfig.round.directJoinDifficulty,
	["cake-id"] = "cake-classic",
}

CakeStateData.Init()
CakeCycleService.Init({
	CakeStateData = CakeStateData,
	CakeConfigData = CakeConfigData,
	RoundStateData = roundState,
})
CakeFieldService.Init({ CakeStateData = CakeStateData, CakeConfigData = CakeConfigData })

print("\n[1] classic remains the baseline")
math.randomseed(__SEED__)
local classicComposition, classicFootprint, classicRare = CakeCycleService.RollComposition("factory", 1)
local classicLayers = #classicComposition - 1
local classicTop = classicComposition[#classicComposition].top
check("classic cake id", CakeStateData.cakeId == "cake-classic")
check("classic edible height is 170", near(classicTop - classicComposition[1].top, 170, 0.01), tostring(classicTop))
check("classic radius is 31.1 cells", near(classicFootprint.corner, 31.1))
check("classic environment/wax/crust contract",
	CakeConfig.variants["cake-classic"].environmentName == "Environment"
		and CakeConfig.variants["cake-classic"].waxEnabled == true
		and CakeConfig.variants["cake-classic"].crustEnabled == true)
check("classic keeps its legacy uniform non-rigid dent",
	CakeConfig.variants["cake-classic"].useLayerSquishMultiplier == false)
local classicGates = 0
for zone = 2, #CakeStateData.zones do
	local def = CakeStateData.zones[zone]
	if def.gateFromPrevious == true then
		classicGates += 1
	end
	check(`classic boundary {zone - 1} is gated by default`,
		def.gateFromPrevious == true and def.gateIndex == zone - 1 and type(def.bossModel) == "string")
end
check("classic gates every visual boundary", classicGates == #CakeStateData.zones - 1)
local sourceReward = { kind = "gems", amount = 25 }
local classicReward = CakeCycleService.ScaleFindReward(sourceReward)
check("classic solo find reward is unchanged", classicReward.amount == 25)
check("reward source is never mutated", sourceReward.amount == 25)

print("\n[2] rainbow composition is a fixed widening pyramid")
roundState["cake-id"] = "cake-rainbow"
math.randomseed(__SEED__)
local rainbowComposition, rainbowFootprint, rainbowRare = CakeCycleService.RollComposition("factory", 1)
local rainbowLayers = #rainbowComposition - 1
local rainbowTop = rainbowComposition[#rainbowComposition].top
local rainbowVariant = CakeConfig.variants["cake-rainbow"]
check("same work/layer count as classic", rainbowLayers == classicLayers,
	`classic {classicLayers}, rainbow {rainbowLayers}`)
check("rainbow edible height is exactly 204", near(rainbowTop - rainbowComposition[1].top, 204, 0.01), tostring(rainbowTop))
check("base radius stays inside the 64-cell field", near(rainbowFootprint.corner, 31.1))
check("duration contract is 1.5x", near(rainbowVariant.durationScale, 1.5))
check("measured duration work is 1.75x", near(rainbowVariant.durationWorkScale, 1.75))
check("rainbow environment is Environment1", rainbowVariant.environmentName == "Environment1")
check("selectable rainbow never rolls the unrelated rare modifier", rainbowRare == nil)
check("rainbow cake id is distinct from rareKind", CakeStateData.cakeId == "cake-rainbow")

local expectedIds = {
	"rainbow-red",
	"rainbow-orange",
	"rainbow-yellow",
	"rainbow-green",
	"rainbow-blue",
	"rainbow-indigo",
	"rainbow-violet",
}
local expectedScales = { 0.72, 0.76, 0.81, 0.87, 0.94, 0.97, 1.00 }
local expectedCounts = { 7, 5, 4, 4, 3, 3, 3 }
local counts, zoneFootprints, zoneTops = {}, {}, {}
local topDownGroups = {}
local previousGroup = nil
for index = #rainbowComposition, 2, -1 do
	local band = rainbowComposition[index]
	counts[band.group] = (counts[band.group] or 0) + 1
	zoneFootprints[band.group] = band.footprint
	zoneTops[band.group] = math.max(zoneTops[band.group] or 0, band.top)
	if band.group ~= previousGroup then
		table.insert(topDownGroups, band.group)
		previousGroup = band.group
	end
end
check("exactly seven contiguous ROYGBIV groups", #topDownGroups == 7)
local rainbowGates = 0
for zone = 1, 7 do
	local def = CakeStateData.zones[zone]
	check(`zone {zone} identity`, def ~= nil and def.id == expectedIds[zone], def and def.id or "missing")
	check(`zone {zone} radius scale`, def ~= nil and near(def.radiusScale, expectedScales[zone]))
	check(`zone {zone} solo/easy layer count`, counts[zone] == expectedCounts[zone], tostring(counts[zone]))
	check(`zone {zone} footprint matches its scale`, zoneFootprints[zone] ~= nil
		and near(zoneFootprints[zone].corner, CakeConfig.composition.footprint.corner * expectedScales[zone], 1e-5))
	if zone > 1 then
		check(`zone {zone} is wider than zone {zone - 1}`,
			zoneFootprints[zone].corner > zoneFootprints[zone - 1].corner)
		if def and def.gateFromPrevious then
			rainbowGates += 1
			check(`gated boundary into zone {zone} has a distinct indexed rig`,
				def.gateIndex == rainbowGates and type(def.bossModel) == "string")
		end
	end
end
check("rainbow uses exactly the five authored mini-boss gates", rainbowGates == 5)
check("indigo-to-violet boundary is deliberately ungated",
	CakeStateData.zones[7].gateFromPrevious == false
		and CakeStateData.zones[7].gateIndex == nil
		and CakeStateData.zones[7].bossModel == nil)
for position, group in ipairs(topDownGroups) do
	check(`top-down group #{position} stays contiguous`, group == position, tostring(group))
end

local rainbowLayer = CakeConfig.layers["rainbow-red"]
check("rainbow material is regular opaque SmoothPlastic",
	rainbowLayer.material == Enum.Material.SmoothPlastic and rainbowLayer.transparency == 0)
check("rainbow layers opt into a heavy configured squish",
	rainbowVariant.useLayerSquishMultiplier == true and (rainbowLayer.squishMult or 0) >= 2.5)
check("soft terraces hold their pyramid shape", rainbowLayer.flowRate == 0 and rainbowLayer.repose == math.huge)

print("\n[3] real field reset materializes every terrace")
CakeFieldService.ResetCake(rainbowComposition, rainbowFootprint, rainbowRare, "factory")
local _, meta = CakeFieldService.Snapshot()
check("snapshot carries the selected cake id", meta.cakeId == "cake-rainbow")
check("snapshot disables wax and brittle crust", meta.waxEnabled == false and meta.crustEnabled == false)
check("snapshot retains per-band footprints", meta.composition[#meta.composition].footprint ~= nil)

local field = CakeStateData.field
local size = CakeConfig.grid.size
local function heightAt(x: number, z: number): number
	return GridUtil.UnitsToStuds(GridUtil.ReadHeight(field, GridUtil.Index(size, x, z)))
end
for zone = 1, 7 do
	local footprint = zoneFootprints[zone]
	local upper = if zone > 1 then zoneFootprints[zone - 1] else nil
	local foundX, foundZ = nil, nil
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			if GridUtil.InCake(size, footprint, x, z)
				and (upper == nil or not GridUtil.InCake(size, upper, x, z))
			then
				foundX, foundZ = x, z
				break
			end
		end
		if foundX ~= nil then break end
	end
	local actual = if foundX ~= nil then heightAt(foundX, foundZ) else -1
	check(`zone {zone} has an exposed terrace surface`, foundX ~= nil and near(actual, zoneTops[zone], 0.35),
		`height {string.format("%.2f", actual)}, expected {string.format("%.2f", zoneTops[zone])}`)
end
check("outside the widest base is empty", heightAt(0, 0) == 0)

CakeCycleService.BeginEating()
check("fifth configured gate uses gate index five even though it enters zone six",
	CakeCycleService.BeginMiniBoss(1, 6) == true
		and CakeStateData.miniBoss ~= nil
		and CakeStateData.miniBoss.index == 5
		and CakeStateData.miniBoss.zoneIndex == 6)
CakeCycleService.FinishMiniBoss()
check("ungated violet boundary cannot accidentally start a sixth mini-boss",
	CakeCycleService.BeginMiniBoss(1, 7) == false and CakeCycleService.Phase() == "eating")

print("\n[4] finds pay 1.5x gems without compounding")
local rainbowReward = CakeCycleService.ScaleFindReward(sourceReward)
check("rainbow solo 25 gems -> 37 (one final floor)", rainbowReward.amount == 37, tostring(rainbowReward.amount))
check("source reward still unchanged after rainbow scale", sourceReward.amount == 25)
math.randomseed(__SEED__)
CakeCycleService.RollComposition("factory", 4)
local coopReward = CakeCycleService.ScaleFindReward(sourceReward)
check("rainbow four-player 25 gems -> 107", coopReward.amount == 107, tostring(coopReward.amount))
check("scaling does not mutate or compound", sourceReward.amount == 25 and rainbowReward.amount == 37)

print("\n[5] combined Studio Play uses the configured rainbow override")
local RunService = game:GetService("RunService")
local originalIsStudio = RunService.IsStudio
RunService.IsStudio = function() return true end
roundState["cake-id"] = nil
math.randomseed(__SEED__)
CakeCycleService.RollComposition("factory", 1)
check("Studio fallback starts rainbow", CakeStateData.cakeId == CakeConfig.studioVariantId)
local configuredStudioId = CakeConfig.studioVariantId
CakeConfig.studioVariantId = "cake-coming-soon"
math.randomseed(__SEED__)
CakeCycleService.RollComposition("factory", 1)
check("invalid Studio fallback returns to classic", CakeStateData.cakeId == CakeConfig.defaultVariantId)
CakeConfig.studioVariantId = nil
math.randomseed(__SEED__)
CakeCycleService.RollComposition("factory", 1)
check("nil Studio override restores classic testing", CakeStateData.cakeId == CakeConfig.defaultVariantId)
CakeConfig.studioVariantId = 123
math.randomseed(__SEED__)
CakeCycleService.RollComposition("factory", 1)
check("malformed Studio override safely restores classic", CakeStateData.cakeId == CakeConfig.defaultVariantId)
CakeConfig.studioVariantId = configuredStudioId
RunService.IsStudio = originalIsStudio
roundState["cake-id"] = "cake-rainbow"

print("\n[6] real subscriptions preserve every gate in a multi-zone scan")
local heartbeatCallback = nil
RunService.Heartbeat.Connect = function(_, callback)
	heartbeatCallback = callback
end

local mapHeights = {}
local collectedNext = {}
local grantCalls, progressCalls, discoveryCalls, saveCalls, analyticsCalls = 0, 0, 0, 0, 0
local gameRoundSubs = {
	IsActive = function() return true end,
	IsStarted = function() return true end,
	ExpectedCount = function() return 1 end,
	Participants = function() return game:GetService("Players"):GetPlayers() end,
	IsParticipant = function() return true end,
}
local mapService = {
	Build = function() end,
	UseEnvironment = function() end,
	ApplyBiome = function() end,
	SetCheckpointHeight = function(height, footprint)
		table.insert(mapHeights, { height = height, footprint = footprint })
	end,
	IsOverCheckpoint = function() return false end,
	GetCheckpointCFrame = function() return nil end,
}
local collisionService = {
	BuildParts = function() end,
	UpdateHeights = function() end,
}
local treasureService = {
	Tick = function()
		local collected = collectedNext
		collectedNext = {}
		return {}, {}, collected
	end,
	FindCounts = function() return 0, 0 end,
	SpawnForCake = function() end,
}
local persistenceService = {
	IsLoaded = function() return true end,
	Save = function() saveCalls += 1 end,
}
local progressService = {
	BiomeFor = function() return "factory" end,
	AddStat = function() progressCalls += 1 end,
	MarkFindDiscovered = function()
		discoveryCalls += 1
		return true
	end,
}
local cycleServices = {
	CakeCycleService = CakeCycleService,
	CakeFieldService = CakeFieldService,
	CakeCollisionService = collisionService,
	MapService = mapService,
	TreasureService = treasureService,
	PersistenceService = persistenceService,
	ProgressService = progressService,
	PetService = { Roll = function() return nil end },
}
local analyticsSubs = {
	Flow = function() analyticsCalls += 1 end,
	Funnel = function() analyticsCalls += 1 end,
	Event = function() analyticsCalls += 1 end,
}
local rewardGrantSubs = {
	Grant = function(_, reward)
		grantCalls += 1
		return { kind = reward.kind, amount = reward.amount }
	end,
}
local subscriptionData = {
	CakeStateData = CakeStateData,
	CakeConfigData = CakeConfigData,
	RoundStateData = { ["round-active"] = true },
}
local subscriptionSet = {
	CakeCycleSubs = CakeCycleSubs,
	GameRoundSubs = gameRoundSubs,
	RewardGrantSubs = rewardGrantSubs,
	AnalyticsSubs = analyticsSubs,
}
CakeCycleSubs.Start(subscriptionData, cycleServices, subscriptionSet)
CakeSimulationSubs.Start(subscriptionData, cycleServices, subscriptionSet)
check("real simulation subscription captured Heartbeat", type(heartbeatCallback) == "function")

local function resetRainbowField()
	math.randomseed(__SEED__)
	local composition, footprint, rareKind = CakeCycleService.RollComposition("factory", 1)
	CakeFieldService.ResetCake(composition, footprint, rareKind, "factory")
	CakeCycleService.BeginEating()
	for key in pairs(CakeStateData.simulationAccumulators) do
		CakeStateData.simulationAccumulators[key] = 0
	end
	return composition
end

local gateComposition = resetRainbowField()
for _ = 1, #gateComposition - 1 do
	local removed = CakeFieldService.ClearActiveBand()
	check("debug-style multi-clear removed one edible band", removed > 0)
end
heartbeatCallback(1)
local gateZones = {}
if CakeStateData.miniBoss then
	table.insert(gateZones, CakeStateData.miniBoss.zoneIndex)
end
check("first crossed gate starts before the final destination",
	CakeStateData.phase == "miniboss" and CakeStateData.miniBoss.zoneIndex == 2)
check("remaining crossed gates stay queued in order",
	#CakeStateData.pendingMiniBossZones == 4
		and CakeStateData.pendingMiniBossZones[1] == 3
		and CakeStateData.pendingMiniBossZones[4] == 6)
check("Cake Guardian is deferred while crossed gates remain", CakeStateData.boss == nil)

while CakeStateData.phase == "miniboss" do
	CakeCycleService.DamageMiniBoss(1000000)
	CakeCycleSubs.FinishMiniBoss()
	if CakeStateData.miniBoss then
		table.insert(gateZones, CakeStateData.miniBoss.zoneIndex)
	end
end
check("all five gated zones are consumed FIFO",
	#gateZones == 5
		and gateZones[1] == 2
		and gateZones[2] == 3
		and gateZones[3] == 4
		and gateZones[4] == 5
		and gateZones[5] == 6)
check("gate queue drains before finale", #CakeStateData.pendingMiniBossZones == 0 and CakeStateData.phase == "eating")
heartbeatCallback(1)
check("Cake Guardian starts only after pending gates resolve", CakeStateData.phase == "boss" and CakeStateData.boss ~= nil)

print("\n[7] one-boundary behaviour and Studio find safety stay intact")
local singleComposition = resetRainbowField()
for _ = 1, CakeStateData.zones[1].layers do
	local removed = CakeFieldService.ClearActiveBand()
	check("single-boundary setup removed one top-zone band", removed > 0)
end
heartbeatCallback(1)
check("one crossed boundary starts its usual gate immediately",
	CakeStateData.phase == "miniboss"
		and CakeStateData.miniBoss.zoneIndex == 2
		and #CakeStateData.pendingMiniBossZones == 0)
CakeCycleService.DamageMiniBoss(1000000)
CakeCycleSubs.FinishMiniBoss()
check("single gate returns directly to eating", CakeStateData.phase == "eating" and CakeStateData.miniBoss == nil)

local testPlayer = __newPlayer(99001, "DebugTester")
local fakeFind = {
	def = {
		id = "debug-find",
		nameKey = "find-debug",
		rarity = "rare",
		color = Color3.fromRGB(255, 0, 255),
		reward = { kind = "gems", amount = 87 },
	},
}
local beforeRemoteCalls = #__REMOTE_CALLS
CakeStateData.debugSuppressFindRewards = true
collectedNext = { { player = testPlayer, find = fakeFind, position = Vector3.new(0, 10, 0) } }
local beforeMutation = { grantCalls, progressCalls, discoveryCalls, saveCalls, analyticsCalls }
heartbeatCallback(0.5)
local debugCollectionCall = nil
for index = beforeRemoteCalls + 1, #__REMOTE_CALLS do
	local call = __REMOTE_CALLS[index]
	if call.name == "TreasureUpdate" and call.args[1].event == "collected" then
		debugCollectionCall = call
		break
	end
end
check("debug-collected find keeps its visual remote", debugCollectionCall ~= nil)
check("debug-collected find omits the fake reward popup",
	debugCollectionCall ~= nil and debugCollectionCall.args[1].reward == nil)
check("debug-collected find performs no profile or analytics mutations",
	grantCalls == beforeMutation[1]
		and progressCalls == beforeMutation[2]
		and discoveryCalls == beforeMutation[3]
		and saveCalls == beforeMutation[4]
		and analyticsCalls == beforeMutation[5])

CakeStateData.phase = "spawning"
CakeStateData.boss = nil
CakeCycleSubs.SpawnNewCake(1)
check("fresh cake resets Studio find suppression", CakeStateData.debugSuppressFindRewards == false)

local productionBefore = { grantCalls, progressCalls, discoveryCalls, saveCalls, analyticsCalls }
collectedNext = { { player = testPlayer, find = fakeFind, position = Vector3.new(0, 10, 0) } }
heartbeatCallback(0.5)
check("normal cake still grants a collected find",
	grantCalls == productionBefore[1] + 1
		and progressCalls == productionBefore[2] + 1
		and discoveryCalls == productionBefore[3] + 1
		and saveCalls == productionBefore[4] + 1
		and analyticsCalls > productionBefore[5])
__removePlayer(testPlayer)

flushLog()
print(`\n{checks - failures}/{checks} selectable-cake variant checks passed`)
if failures > 0 then
	error(`{failures} selectable-cake variant check(s) failed`)
end
