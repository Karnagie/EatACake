
-- ── the actual verification run ─────────────────────────────────────────
local GridUtil = __REGISTRY["Shared.GridUtil"]
local CakeConfig = __REGISTRY["Shared.config.CakeConfig"]
local TreasureConfig = __REGISTRY["Shared.config.TreasureConfig"]
local TreasureService = __REGISTRY["__TreasureService"]

local SEED = __SEED__
math.randomseed(SEED)

local function rule() print(("-"):rep(76)) end

-- ── authored Items library (varied shapes, like a real Toolbox grab) ────
local function makeModel(name, parts, extras)
	local model = stub.newInstance("Model", name)
	for i, p in ipairs(parts) do
		local part = stub.newInstance("Part", `{name}_{i}`)
		part.Size = Vector3.new(p[1], p[2], p[3])
		part.Position = Vector3.new(p[4] or 0, p[5] or 0, p[6] or 0)
		part.CFrame = CFrame.new(part.Position)
		part.Parent = model
	end
	if extras then
		local host = model:GetChildren()[1]
		local decal = stub.newInstance("Decal", "Face")
		decal.Parent = host
		local emitter = stub.newInstance("ParticleEmitter", "Shine")
		emitter.Parent = host
		local light = stub.newInstance("PointLight", "Glow")
		light.Parent = host
	end
	return model
end

local items = stub.newInstance("Folder", "Items")
makeModel("Teapot", { { 3, 2, 3 }, { 1, 1, 1, 2, 0.5, 0 } }, true).Parent = items -- chunky + decal/emitter/light
makeModel("RollingPin", { { 1, 1, 8 } }).Parent = items -- long + thin
makeModel("Tray", { { 12, 0.4, 9 } }).Parent = items -- WIDE + FLAT (the clamp test)
makeModel("Whisk", { { 0.6, 7, 0.6 } }).Parent = items -- tall + thin
makeModel("Cupcake", { { 2.5, 2.5, 2.5 } }).Parent = items -- cube-ish
items.Parent = Workspace

-- ── cake state, bands exactly as CakeCycleService.RollComposition ───────
local grid = CakeConfig.grid
local comp = CakeConfig.composition

local function rollComposition(work)
	local layers = math.clamp(math.floor(comp.baseLayers * work ^ comp.layerExponent + 0.5), 2, comp.maxLayers)
	local scoopScale = (work / (layers / comp.baseLayers)) ^ -0.5
	local scoopTop = comp.scoopTop * scoopScale
	local scoopBottom = comp.scoopBottom * scoopScale
	local totalHeight = math.min(comp.maxTotalHeight, grid.maxHeight - comp.coreThickness)
	local scoops, weights, weightSum = {}, {}, 0
	for k = 0, layers - 1 do
		local f = if layers > 1 then k / (layers - 1) else 0
		local scoop = scoopTop * (scoopBottom / scoopTop) ^ f
		scoops[k + 1] = scoop
		local w = (scoopTop / scoop) ^ (2 * comp.thicknessExponent)
		weights[k + 1] = w
		weightSum += w
	end
	local thickness, thickSum = {}, 0
	for k = 1, layers do
		local jitter = 0.9 + math.random() * 0.2
		local t = math.max(comp.minLayerThickness, weights[k] / weightSum * totalHeight * jitter)
		thickness[k] = t
		thickSum += t
	end
	for k = 1, layers do thickness[k] *= totalHeight / thickSum end

	local composition, cursor = {}, 0
	local function push(band)
		band.bottom = cursor
		band.top = cursor + band.thickness
		cursor = band.top
		band.thickness = nil
		table.insert(composition, band)
	end
	push({ id = "core", thickness = comp.coreThickness, scoop = 1, density = 1 })
	for k = layers, 1, -1 do
		push({ id = "sponge", thickness = thickness[k], scoop = scoops[k], density = 1 })
	end
	return composition
end

local function runCake(label, work, library)
	if library then
		items.Parent = Workspace
	else
		items.Parent = nil
	end

	local size = grid.size
	local state = {
		field = buffer.create(size * size * 2),
		footprint = comp.footprint,
		composition = rollComposition(work),
		floorUnits = 0,
		activeBandIndex = 0,
		activeFloorUnits = 0,
		cakeIndex = 1,
		edibleVolume = 0,
		treasures = {},
	}
	state.floorUnits = GridUtil.StudsToUnits(state.composition[1].top)
	local topStuds = state.composition[#state.composition].top
	local cellArea = grid.cell * grid.cell
	local cells = {}
	for z = 0, size - 1 do
		for x = 0, size - 1 do
			if GridUtil.InCake(size, state.footprint, x, z) then
				GridUtil.WriteHeight(state.field, GridUtil.Index(size, x, z), GridUtil.StudsToUnits(topStuds))
				state.edibleVolume += (topStuds - state.composition[1].top) * cellArea
				table.insert(cells, { x = x, z = z })
			end
		end
	end
	state.activeBandIndex = #state.composition
	state.activeFloorUnits = GridUtil.StudsToUnits(state.composition[#state.composition].bottom)

	rule()
	print(`CAKE "{label}" — work {string.format("%.2f", work)}, library {tostring(library)}`)
	print(`  {#state.composition - 1} edible bands, {string.format("%.0f", topStuds)} studs tall, volume {string.format("%.0f", state.edibleVolume)} studs^3`)
	local thin, thick = math.huge, 0
	for i = 2, #state.composition do
		local t = state.composition[i].top - state.composition[i].bottom
		thin, thick = math.min(thin, t), math.max(thick, t)
	end
	print(`  band thickness {string.format("%.1f", thin)} … {string.format("%.1f", thick)} studs`)

	TreasureService.Init({
		CakeStateData = state,
		CakeConfigData = { cake = CakeConfig, treasures = TreasureConfig },
	})
	flushLog()
	TreasureService.SpawnForCake()
	flushLog()

	-- placement sanity
	local heights, minBottom, maxTop = {}, math.huge, 0
	local outOfLoaf = 0
	for _, find in ipairs(state.treasures) do
		table.insert(heights, find.height)
		minBottom = math.min(minBottom, GridUtil.UnitsToStuds(find.bottomUnits))
		maxTop = math.max(maxTop, GridUtil.UnitsToStuds(find.topUnits))
		local r = find.radiusCells
		for _, d in ipairs({ { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
			if not GridUtil.InCake(size, state.footprint, find.x + d[1], find.z + d[2]) then
				outOfLoaf += 1
				break
			end
		end
	end
	table.sort(heights)
	print(`  finds {#state.treasures} · height min {string.format("%.2f", heights[1])} / med {string.format("%.2f", heights[math.ceil(#heights / 2)])} / max {string.format("%.2f", heights[#heights])} studs`)
	print(`  deepest bottom {string.format("%.2f", minBottom)} (core top {string.format("%.2f", state.composition[1].top)}) · highest top {string.format("%.2f", maxTop)} (surface {string.format("%.1f", topStuds)})`)
	print(`  finds whose footprint leaves the loaf: {outOfLoaf} (want 0)`)

	local visible, emitting = 0, 0
	for _, find in ipairs(state.treasures) do
		for _, t in ipairs(find.alphaTargets) do
			if t.Transparency < 0.999 then visible += 1 end
		end
		for _, e in ipairs(find.emitters) do
			if e.Enabled then emitting += 1 end
		end
	end
	print(`  at spawn: {visible} visible surfaces (want 0) · {emitting} live emitters (want 0)`)

	-- ── mow the cake band by band ───────────────────────────────────────
	local fakeChar = stub.newInstance("Model", "Char")
	local hrp = stub.newInstance("Part", "HumanoidRootPart")
	hrp.Name = "HumanoidRootPart"
	hrp.Parent = fakeChar
	playersList = { { UserId = 1, Character = fakeChar } }
	local loadedIds = { [1] = true }

	local revealBand, freeBand = {}, {}
	local collectedCount, revealedCount, flightOk = 0, 0, 0

	for bandIndex = #state.composition, 2, -1 do
		local band = state.composition[bandIndex]
		state.activeBandIndex = bandIndex
		state.activeFloorUnits = GridUtil.StudsToUnits(band.bottom)
		local floor = GridUtil.StudsToUnits(band.bottom)
		for i = #cells, 2, -1 do
			local j = math.random(i)
			cells[i], cells[j] = cells[j], cells[i]
		end
		for n, c in ipairs(cells) do
			local i = GridUtil.Index(size, c.x, c.z)
			if GridUtil.ReadHeight(state.field, i) > floor then
				GridUtil.WriteHeight(state.field, i, floor)
			end
			if n % 25 == 0 or n == #cells then
				local wx, wz = GridUtil.CellToWorld(grid, c.x, c.z)
				hrp.Position = Vector3.new(wx, grid.origin.y + band.bottom, wz)
				hrp.CFrame = CFrame.new(hrp.Position)
				local _near, revealed, collected = TreasureService.Tick(loadedIds, 0.5)
				for _, find in ipairs(revealed) do
					revealedCount += 1
					revealBand[find] = bandIndex
				end
				for _, entry in ipairs(collected) do
					collectedCount += 1
					freeBand[entry.find] = bandIndex
					if entry.find.model == nil then flightOk += 1 end
				end
			end
		end
	end

	-- DRAIN: freed finds are dealt one per cascade beat, so the last few of a
	-- swept layer land after the mowing stops. The real game has the boss phase
	-- + newCakeDelay (~60 s) for exactly this; give the sim the same grace or it
	-- reports a harness artifact as a stranded find.
	for _ = 1, 200 do
		local _n, _r, collected = TreasureService.Tick(loadedIds, 0.5)
		for _, entry in ipairs(collected) do
			collectedCount += 1
			freeBand[entry.find] = 2
			if entry.find.model == nil then flightOk += 1 end
		end
	end

	print(`  revealed {revealedCount}/{#state.treasures} · collected {collectedCount}/{#state.treasures} · flight finished+destroyed {flightOk}`)

	local spans, histogram, sum = {}, {}, 0
	for find, rb in pairs(revealBand) do
		local fb = freeBand[find]
		if fb then
			local layers = rb - fb + 1
			table.insert(spans, layers)
			histogram[layers] = (histogram[layers] or 0) + 1
			sum += layers
		end
	end
	table.sort(spans)
	print(`  LAYERS TO UNCOVER — mean {string.format("%.2f", sum / math.max(1, #spans))} · median {spans[math.ceil(#spans / 2)] or 0}`)
	local keys = {}
	for k in pairs(histogram) do table.insert(keys, k) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		print(`    {k} layer(s): {string.format("%2d", histogram[k])} finds {("#"):rep(histogram[k])}`)
	end
	flushLog()
	return #state.treasures - collectedCount
end

-- ONE scenario per process: TreasureService caches its prepared library in
-- module-level state, so running several cakes in one process would re-prepare
-- already-prepared templates (not a thing that happens in the real server).
local SCENARIO = "__SCENARIO__"
local stranded
if SCENARIO == "easy" then
	stranded = runCake("solo easy", 1.0, true)
elseif SCENARIO == "hard" then
	stranded = runCake("4p hard", 2.2 * 2.5, true)
else
	stranded = runCake("no library (fallback orbs)", 1.0, false)
end

rule()
print(if stranded == 0 then "PASS — every find was dug out and collected" else `FAIL — {stranded} stranded find(s)`)
