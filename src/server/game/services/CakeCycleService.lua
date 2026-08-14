--[[
	CakeCycleService — cake lifecycle logic (GDD §9):
	  spawning -> eating -> (miniboss -> eating)* -> boss -> reward -> spawning ...

	Logic only (R2): state lives in CakeStateData; CakeSubs drives Step(dt)
	from Heartbeat, reacts to the returned events (fires remotes, rolls
	pets — R3 orchestration stays in the subscription).

	ZONES (2026-08-07). A cake is a SEQUENCE of flavour groups
	(`CakeConfig.layerGroups`), several layers deep each, and the boundary
	between two zones is a MINI-BOSS that has to be beaten before the next zone
	can be eaten. `RollComposition` decides the zones; `CakeSimulationSubs`
	spots the boundary crossing; the three MiniBoss functions below own the
	phase. features/cake-cycle.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local CakeCycleService = {}

local state -- CakeStateData
local cakeCfg -- CakeConfigData.cake
local roundState -- RoundStateData

local function currentVariant(): (string, any)
	local defaultId = cakeCfg.defaultVariantId or "cake-classic"
	local requestedId = roundState and roundState["cake-id"]
	local usedStudioOverride = false
	if requestedId == nil then
		local studioId = if RunService:IsStudio() then cakeCfg.studioVariantId else nil
		if type(studioId) == "string" and studioId ~= "" then
			requestedId = studioId
			usedStudioOverride = true
		else
			if studioId ~= nil then
				Log.Once(
					"CakeCycle",
					"malformed-studio-variant-override",
					"CakeConfig.studioVariantId must be a non-empty string or nil -- production default used"
				)
			end
			requestedId = defaultId
		end
	end
	local variants = cakeCfg.variants or {}
	local variant = variants[requestedId]
	if variant == nil then
		Log.Once(
			"CakeCycle",
			`unknown-variant-{tostring(requestedId)}`,
			`round cake '{tostring(requestedId)}' has no CakeConfig variant -- '{defaultId}' used`
		)
		requestedId = defaultId
		variant = variants[defaultId]
		usedStudioOverride = false
	end
	if variant == nil then
		Log.Once(
			"CakeCycle",
			"missing-default-variant",
			`CakeConfig.variants['{defaultId}'] is missing -- neutral classic tuning used`
		)
		variant = {}
	end
	if usedStudioOverride then
		Log.Once(
			"CakeCycle",
			"studio-variant-override",
			`Studio launch override active -- building '{requestedId}' (CakeConfig.studioVariantId)`
		)
	end
	return requestedId, variant
end

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
-- count and the difficulty/co-op scoop ramp (CakeConfig.composition header).
-- Selectable variants apply their own height and duration factors separately in
-- RollComposition; this function deliberately remains the match-size term only.
function CakeCycleService.CakeWork(playerCount: number): number
	local comp = cakeCfg.composition
	local players = math.max(1, playerCount or 1)
	local difficultyWork = difficultyConfig().workMultiplier or 1
	return difficultyWork * (1 + (comp.coopWork or 0) * (players - 1))
end

-- Draws `count` DISTINCT entries out of `pool` (array), in a random order.
-- Fewer than `count` available -> everything, shuffled. Fisher-Yates over a
-- copy so the shared config array is never reordered in place.
local function drawDistinct(pool, count: number)
	local bag = table.clone(pool)
	for i = #bag, 2, -1 do
		local j = math.random(i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	local drawn = {}
	for i = 1, math.min(count, #bag) do
		drawn[i] = bag[i]
	end
	return drawn
end

-- Splits `layerCount` design bands (top-down) into flavour ZONES.
--
-- The split is by LAYER COUNT (`composition.groups.layerShares`), and the
-- reason is measured rather than assumed. A bite clears to the band floor, so a
-- band's clear time goes as 1/scoop² and the deepest band costs ~16x the top
-- one — which says "split by cost". That holds for a FIXED eater and fails for
-- the run people play: the player buys tiers as they dig and the upgrade ramp
-- very nearly cancels the scoop ramp, so `tools/balance-model/pacing.py`
-- measures a FLAT ~1.21 min per layer across the whole cake. Splitting by cost
-- put 11 layers and 13.2 min into the opening zone; by count it is 3 layers and
-- ~4 min, which is the requirement. See the CakeConfig comment for the numbers.
--
-- Returns `zoneOf[k]` (zone index per top-down band k) and `zones`
-- (array of { id, nameKey, members, layers, gateFromPrevious }), zone 1 ==
-- the TOP of the cake. A variant may decouple visual colour boundaries from
-- mini-boss gates with `gateBoundaries`; an omitted entry preserves the classic
-- contract that every boundary is gated.
local function rollZones(layerCount: number, variant)
	local cfg = variant.groups or cakeCfg.composition.groups
	local pool = cfg.pool or cakeCfg.layerGroups
	local shares = cfg.layerShares
	local minLayers = math.max(1, cfg.minLayers or 1)
	local gateBoundaries = cfg.gateBoundaries

	if pool == nil or #pool == 0 then
		Log.Warn("CakeCycle", "CakeConfig.layerGroups is empty -- cake rolled as ONE zone of frosting only")
		return {}, {}
	end
	if type(shares) ~= "table" or #shares == 0 then
		Log.Once("CakeCycle", "no-layer-shares", "composition.groups.layerShares is missing -- zones split EVENLY instead")
		shares = {}
		for i = 1, math.max(1, cfg.count or 1) do
			shares[i] = 1 / math.max(1, cfg.count or 1)
		end
	end
	if #shares ~= (cfg.count or #shares) then
		Log.Once(
			"CakeCycle",
			"share-count-mismatch",
			`composition.groups.count ({tostring(cfg.count)}) != #layerShares ({#shares}) -- using the smaller`
		)
	end

	-- A zone needs `minLayers` bands, so a small cake gets fewer zones (and
	-- therefore fewer mini-bosses) rather than one-band zones.
	local zoneCount = math.max(1, math.min(cfg.count or #shares, #shares, #pool, math.floor(layerCount / minLayers)))
	local drawn
	if cfg.fixedOrder == true then
		drawn = {}
		for index = 1, zoneCount do
			drawn[index] = pool[index]
		end
	else
		drawn = drawDistinct(pool, zoneCount)
	end
	zoneCount = #drawn

	local shareSum = 0
	for z = 1, zoneCount do
		shareSum += math.max(0, shares[z] or 0)
	end
	if shareSum <= 0 then
		shareSum = zoneCount
		for z = 1, zoneCount do
			shares[z] = 1
		end
	end

	local zoneOf, zones = {}, {}
	local band = 1
	local target = 0
	for z = 1, zoneCount do
		target += (math.max(0, shares[z] or 0) / shareSum) * layerCount
		-- Never eat into what the zones BELOW need to reach `minLayers`.
		local remainingZones = zoneCount - z
		local maxTake = math.max(1, layerCount - (band - 1) - remainingZones * minLayers)
		local want = math.max(minLayers, math.floor(target - (band - 1) + 0.5))
		local taken = 0
		while band <= layerCount and taken < maxTake and taken < want do
			zoneOf[band] = z
			band += 1
			taken += 1
		end
		local groupDef = drawn[z]
		local gateFromPrevious = false
		if z > 1 then
			local configured = if type(gateBoundaries) == "table" then gateBoundaries[z - 1] else nil
			gateFromPrevious = if configured == nil then true else configured == true
		end
		zones[z] = {
			id = groupDef.id,
			nameKey = groupDef.nameKey,
			members = groupDef.members,
			layers = taken,
			radiusScale = if type(cfg.radiusScales) == "table" then cfg.radiusScales[z] or 1 else 1,
			gateFromPrevious = gateFromPrevious,
		}
	end
	-- Rounding leftovers join the DEEPEST zone (its share is the biggest, so
	-- one more band there is the smallest relative distortion).
	while band <= layerCount do
		zoneOf[band] = zoneCount
		zones[zoneCount].layers += 1
		band += 1
	end

	return zoneOf, zones
end

--API
-- Rolls a new cake: composition (bottom-up bands, each with its own optional
-- terrace footprint) + the widest loaf footprint + rare kind. The caller passes
-- everything to
-- CakeFieldService.ResetCake.
--
-- Bands are designed TOP-DOWN along the pacing curve (see the CakeConfig
-- .composition header): band k gets a `scoop` (bite-radius multiplier) that
-- shrinks geometrically with depth, a thickness that grows with it, and a
-- `density` (calories + belly fill per stud³) that keeps one bite worth the
-- same food anywhere in any cake. Classic random zones only own layer identity;
-- selectable variants may additionally declare height, duration and terraces.
--
-- Layer identity is now a run of ZONES (`rollZones`): `composition.groups.count`
-- flavour groups, in a random order, each several bands deep, walked with no
-- immediate repeat inside the zone. Every band carries `group` (1 = the TOP
-- zone) so the layer gate can spot a visual boundary crossing; the destination
-- zone's `gateFromPrevious` independently decides whether that crossing opens a
-- mini-boss.
function CakeCycleService.RollComposition(biome: string, playerCount: number)
	local comp = cakeCfg.composition
	local grid = cakeCfg.grid
	local footprint = comp.footprint
	local cakeId, variant = currentVariant()
	local heightScale = math.max(0.01, variant.heightScale or 1)
	local durationScale = math.max(0.01, variant.durationScale or 1)
	local durationWorkScale = math.max(0.01, variant.durationWorkScale or durationScale)

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
	local totalHeight = math.min(comp.maxTotalHeight * heightScale, grid.maxHeight - comp.coreThickness)

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

	-- ZONES: which flavour group each band belongs to (index 1 == TOP band).
	local zoneOf, zones = rollZones(layers, variant)
	local zoneCount = math.max(1, #zones)

	-- Layer identity: classic index 1 is frosting (it FLOWS, which keeps a
	-- stationary Auto-Eat player earning); fixed variants may replace that cap,
	-- with index `layers` still deepest. Every other band takes the next member of its
	-- zone's group, with no immediate repeat, so a 10-band zone cycles its
	-- variants instead of showing one flavour ten times.
	local useFrostingCap = not (variant.groups and variant.groups.useFrostingCap == false)
	local ids = {}
	local lastId = if useFrostingCap then "frosting" else ""
	if useFrostingCap then
		ids[1] = "frosting"
	end
	local firstIdentityBand = if useFrostingCap then 2 else 1
	for k = firstIdentityBand, layers do
		local zone = zones[zoneOf[k]]
		local members = zone and zone.members
		if members == nil or #members == 0 then
			ids[k] = lastId
		elseif #members == 1 then
			ids[k] = members[1]
			lastId = members[1]
		else
			local candidate
			repeat
				candidate = members[math.random(#members)]
			until candidate ~= lastId
			lastId = candidate
			ids[k] = candidate
		end
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
	local function scaledFootprint(scale: number)
		local safeScale = math.clamp(scale, 0.05, 1)
		return {
			hx = footprint.hx * safeScale,
			hz = footprint.hz * safeScale,
			corner = footprint.corner * safeScale,
		}
	end
	local function push(band)
		band.bottom = cursor
		band.top = cursor + band.thickness
		cursor = band.top
		band.thickness = nil
		table.insert(composition, band)
	end
	-- The core carries the DEEPEST zone's index on purpose: the layer gate
	-- reaches band #1 when everything edible is gone, and a different index
	-- there would fire a mini-boss one second before the Cake Guardian.
	push({
		id = "core",
		thickness = comp.coreThickness,
		scoop = 1,
		density = 1,
		group = zoneCount,
		footprint = footprint,
	})
	-- bottom-up: the DEEPEST designed band (k = layers) goes in first
	for k = layers, 1, -1 do
		local zone = zones[zoneOf[k]]
		local radiusScale = math.clamp((zone and zone.radiusScale) or 1, 0.05, 1)
		-- A terrace has area proportional to radiusScale^2. Shrinking its bite
		-- radius by the same scale cancels that geometric shortcut; the measured
		-- duration-work factor then stretches each band. Matching density
		-- compensation keeps total food per band at the classic progression depth.
		local scoop = scoops[k] * radiusScale / math.sqrt(durationWorkScale)
		local density = math.clamp(
			comp.refBandWeight / (thickness[k] * scoop * scoop * durationWorkScale),
			1,
			comp.maxDensity
		)
		push({
			id = ids[k],
			thickness = thickness[k],
			scoop = scoop,
			density = density,
			group = zoneOf[k] or zoneCount,
			footprint = scaledFootprint(radiusScale),
		})
	end

	-- Rare cakes (§5): golden / rainbow, announced server-wide by CakeSubs.
	local rareKind = nil
	if variant.rareEnabled ~= false then
		local roll = math.random()
		if roll < comp.rare.rainbow.chance then
			rareKind = "rainbow"
		elseif roll < comp.rare.rainbow.chance + comp.rare.golden.chance then
			rareKind = "golden"
		end
	end

	-- Payout scale for THIS cake: difficulty premium × per-head co-op payout.
	-- Stored here (not recomputed per bite) so it cannot drift as players leave.
	state.payoutScale = (difficultyConfig().caloriesMultiplier or 1)
		* (1 + (comp.coopCalories or 0) * (math.max(1, playerCount or 1) - 1))
	-- Gems from finds get the per-head term but NOT the difficulty premium — see
	-- CakeConfig.composition.coopFinds.
	state.findPayoutScale = (1 + (comp.coopFinds or 0) * (math.max(1, playerCount or 1) - 1))
		* (variant.findRewardMultiplier or 1)
	state.cakeId = cakeId

	-- The MINI-BOSS ROSTER of this cake: one distinct rig per GATED boundary.
	-- Visual terraces may deliberately leave a boundary open (rainbow's final
	-- indigo -> violet transition), so gate index and zone index are separate.
	-- Rolled here (once per cake) so the same rig cannot repeat inside a cake.
	local miniCfg = cakeCfg.cycle.miniBoss
	local gateCount = 0
	for z = 2, zoneCount do
		if zones[z].gateFromPrevious then
			gateCount += 1
		end
	end
	local rigs = drawDistinct((miniCfg and miniCfg.models) or {}, gateCount)
	local gateIndex = 0
	for z = 2, zoneCount do
		if zones[z].gateFromPrevious then
			gateIndex += 1
			zones[z].gateIndex = gateIndex
			zones[z].bossModel = rigs[gateIndex]
		end
	end
	state.zones = zones
	if type(state.pendingMiniBossZones) ~= "table" then
		state.pendingMiniBossZones = {}
	else
		table.clear(state.pendingMiniBossZones)
	end
	state.miniBossesDefeated = 0

	local zoneSummary = {}
	for z, zone in ipairs(zones) do
		local boundary = if z == 1 then "" elseif zone.gateFromPrevious then `[{tostring(zone.bossModel)}]` else "[open]"
		table.insert(zoneSummary, `{zone.id}x{zone.layers}{boundary}`)
	end
	Log.Sum(
		"CakeCycle",
		`cake '{cakeId}' rolled — {layers} layers, {math.floor(totalHeight)} edible studs, work {string.format("%.2f", work)}, duration target ×{string.format("%.2f", durationScale)} (work ×{string.format("%.2f", durationWorkScale)}), payout ×{string.format("%.2f", state.payoutScale)}, finds ×{string.format("%.2f", state.findPayoutScale)}`
	)
	Log.Sum("CakeCycle", `zones (top→bottom): {table.concat(zoneSummary, " → ")} — {gateCount} mini-boss gate(s) + the Cake Guardian`)
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
-- Records EVERY configured gate crossed by one authoritative layer scan. The
-- field may have moved across several zones since the previous 1 Hz scan (paid
-- clears and the Studio DebugClearLayer hook both do this), so comparing only
-- the previous/final destination would silently discard intermediate bosses.
-- Destination zones are queued top-to-bottom and de-duplicated against gates
-- already defeated, currently active, or already pending.
function CakeCycleService.QueueCrossedMiniBosses(previousZoneIndex: number, currentZoneIndex: number): number
	if type(previousZoneIndex) ~= "number" or type(currentZoneIndex) ~= "number" then
		Log.Warn(
			"CakeCycle",
			`cannot queue crossed gates from invalid zones '{tostring(previousZoneIndex)}' -> '{tostring(currentZoneIndex)}'`
		)
		return 0
	end
	local previous = math.floor(previousZoneIndex)
	local current = math.floor(currentZoneIndex)
	if current <= previous then
		return 0
	end

	local zones = state.zones or {}
	if current > #zones then
		Log.Warn("CakeCycle", `layer gate reached missing zone #{current} -- only known boundaries through #{#zones} can queue`)
		current = #zones
	end
	local pending = state.pendingMiniBossZones
	if type(pending) ~= "table" then
		Log.Warn("CakeCycle", "CakeStateData.pendingMiniBossZones missing -- recreating the gate queue")
		pending = {}
		state.pendingMiniBossZones = pending
	end

	-- Gate indexes are assigned sequentially at roll time. In production,
	-- `miniBossesDefeated == N` therefore means gates 1..N are complete.
	local scheduledThrough = math.max(0, math.floor(state.miniBossesDefeated or 0))
	if state.miniBoss and type(state.miniBoss.index) == "number" then
		scheduledThrough = math.max(scheduledThrough, math.floor(state.miniBoss.index))
	end
	for _, zoneIndex in ipairs(pending) do
		local pendingZone = zones[zoneIndex]
		if pendingZone and type(pendingZone.gateIndex) == "number" then
			scheduledThrough = math.max(scheduledThrough, math.floor(pendingZone.gateIndex))
		end
	end

	local added = 0
	for zoneIndex = math.max(2, previous + 1), current do
		local zone = zones[zoneIndex]
		if zone and zone.gateFromPrevious == true then
			local gateIndex = zone.gateIndex
			if type(gateIndex) ~= "number" or gateIndex < 1 then
				Log.Warn("CakeCycle", `crossed gated zone #{zoneIndex} has no valid gateIndex -- gate cannot be queued`)
			else
				gateIndex = math.floor(gateIndex)
				if gateIndex > scheduledThrough then
					table.insert(pending, zoneIndex)
					scheduledThrough = gateIndex
					added += 1
				end
			end
		end
	end
	if added > 1 then
		Log.Sum(
			"CakeCycle",
			`layer scan crossed zones #{previous + 1}-#{current} -- queued {added} mini-bosses in boundary order`
		)
	end
	return added
end

--API
function CakeCycleService.PendingMiniBossCount(): number
	local pending = state.pendingMiniBossZones
	return if type(pending) == "table" then #pending else 0
end

--API
-- Starts, then consumes, the oldest queued gate. Peek-before-start is
-- deliberate: malformed config leaves the gate pending and blocks the finale
-- instead of silently opening a zone whose boss could not be constructed.
function CakeCycleService.BeginNextMiniBoss(playerCount: number): boolean
	local pending = state.pendingMiniBossZones
	local zoneIndex = type(pending) == "table" and pending[1] or nil
	if type(zoneIndex) ~= "number" then
		return false
	end
	if not CakeCycleService.BeginMiniBoss(playerCount, zoneIndex) then
		Log.Warn("CakeCycle", `queued gate for zone #{zoneIndex} could not start -- it remains pending and blocks the finale`)
		return false
	end
	table.remove(pending, 1)
	return true
end

--API
-- eating -> miniboss. `zoneIndex` is the zone being ENTERED (>= 2). Its
-- independently assigned `gateIndex` controls HP growth and its `bossModel`
-- guards it. NO timer: a mini-boss is a GATE, not a race.
function CakeCycleService.BeginMiniBoss(playerCount: number, zoneIndex: number): boolean
	if state.phase ~= "eating" then
		Log.Once(
			"CakeCycle",
			`miniboss-wrong-phase-{state.phase}`,
			`zone gate #{tostring(zoneIndex)} cannot start in phase '{state.phase}' -- transition refused`
		)
		return false
	end
	local miniCfg = cakeCfg.cycle.miniBoss
	if miniCfg == nil then
		Log.Warn("CakeCycle", "CakeConfig.cycle.miniBoss is missing -- zone boundary passed without a mini-boss")
		return false
	end
	local zones = state.zones or {}
	local zone = zones[zoneIndex]
	if zone == nil then
		Log.Warn("CakeCycle", `zone gate requested for missing zone #{zoneIndex} -- boundary left open`)
		return false
	end
	if zone.gateFromPrevious ~= true then
		Log.Once(
			"CakeCycle",
			`ungated-zone-{zoneIndex}`,
			`zone #{zoneIndex} ('{tostring(zone.id)}') has no configured mini-boss boundary -- boundary left open`
		)
		return false
	end
	local gateIndex = zone.gateIndex
	if type(gateIndex) ~= "number" or gateIndex < 1 then
		Log.Warn("CakeCycle", `zone #{zoneIndex} is gated but has no gateIndex -- boundary left open`)
		return false
	end
	gateIndex = math.floor(gateIndex)
	local difficulty = difficultyConfig()
	local hp = math.max(
		1,
		math.ceil(
			miniCfg.tapsPerPlayer
				* math.max(1, playerCount)
				* (difficulty.bossHpMultiplier or 1)
				* (miniCfg.tapsGrowth or 1) ^ (gateIndex - 1)
		)
	)
	state.phase = "miniboss"
	state.phaseTimer = 0
	state.miniBoss = {
		hp = hp,
		maxHp = hp,
		index = gateIndex,
		zoneIndex = zoneIndex,
		model = zone and zone.bossModel,
		zoneKey = zone and zone.nameKey,
	}
	Log.Sum(
		"CakeCycle",
		`mini-boss #{gateIndex} — '{tostring(state.miniBoss.model)}' guards the '{tostring(zone and zone.id)}' zone, hp={hp}`
	)
	return true
end

--API
-- A tap on the mini-boss. Returns remaining hp (<= 0 means defeated this tap),
-- or nil when there is no live mini-boss.
function CakeCycleService.DamageMiniBoss(amount: number): number?
	local boss = state.miniBoss
	if state.phase ~= "miniboss" or boss == nil then
		return nil
	end
	boss.hp = math.max(0, boss.hp - math.max(1, math.floor(amount)))
	return boss.hp
end

--API
-- miniboss -> eating. The layer gate has ALREADY advanced into the new zone
-- (that is what opened this phase), so there is nothing to unlock here beyond
-- letting bites through again.
function CakeCycleService.FinishMiniBoss()
	state.miniBoss = nil
	state.miniBossesDefeated = (state.miniBossesDefeated or 0) + 1
	state.phase = "eating"
	state.phaseTimer = 0
end

--API
-- eating -> boss. HP scales with the current population.
function CakeCycleService.BeginBoss(playerCount: number): boolean
	if state.phase ~= "eating" then
		Log.Once(
			"CakeCycle",
			`boss-wrong-phase-{state.phase}`,
			`Cake Guardian cannot start in phase '{state.phase}' -- transition refused`
		)
		return false
	end
	local pending = CakeCycleService.PendingMiniBossCount()
	if pending > 0 then
		Log.Once(
			"CakeCycle",
			`boss-pending-gates-{state.cakeIndex}`,
			`Cake Guardian deferred -- {pending} crossed mini-boss gate(s) still pending for cake #{state.cakeIndex}`
		)
		return false
	end
	local difficulty = difficultyConfig()
	state.phase = "boss"
	state.miniBoss = nil
	state.phaseTimer = cakeCfg.cycle.bossDuration * (difficulty.bossDurationMultiplier or 1)
	local hp = math.max(
		1,
		math.ceil(cakeCfg.cycle.bossTapsPerPlayer * math.max(1, playerCount) * (difficulty.bossHpMultiplier or 1))
	)
	state.boss = { hp = hp, maxHp = hp }
	Log.Sum("CakeCycle", `boss phase — {cakeCfg.cycle.bossName}, hp={hp}, {state.phaseTimer}s limit`)
	return true
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
	state.miniBoss = nil
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
--   "boss-timeout"      boss timer expired (the round orchestrator records a loss)
--   "boss-defeated"     hp reached zero
--   "miniboss-defeated" a zone-gate mini-boss reached zero hp
--   "spawn-cake"        spawning countdown finished
function CakeCycleService.Step(dt: number): string?
	if state.phase == "boss" then
		state.phaseTimer -= dt
		if state.boss and state.boss.hp <= 0 then
			return "boss-defeated"
		end
		if state.phaseTimer <= 0 then
			return "boss-timeout"
		end
	elseif state.phase == "miniboss" then
		-- No timer by design (CakeConfig.cycle.miniBoss): it is a gate, not a
		-- race. The only way out is beating it.
		if state.miniBoss and state.miniBoss.hp <= 0 then
			return "miniboss-defeated"
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
