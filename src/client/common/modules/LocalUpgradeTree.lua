--[[
	LocalUpgradeTree — upgrades hex-tree view-model (R2, logic only). Expands
	UpgradeTreeConfig + replicated levels + calories into the positioned NODES
	the HexTreeOverlay renders. Pure derivation; the server validates every
	purchase from UpgradeConfig (never trusts this).

	Node states: locked / available (next buy) / owned / category / back / logo.
	Sub-tree tiers are PACKED into a tight spiral blob (HexUtil.Spiral) — hexes
	touch, no connectors. Each node also carries `detail` (name / description /
	status / cost) for the tap-to-open panel, and category nodes carry a `badge`
	when an affordable upgrade sits inside. Positions are Scale (0..1) of the
	square canvas; the overlay scales it once to the viewport.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HexUtil = require(ReplicatedStorage.Shared.HexUtil)
local Log = require(ReplicatedStorage.Shared.Log)
local UpgradeConfig = require(ReplicatedStorage.Shared.config.UpgradeConfig)
local UpgradeTreeConfig = require(ReplicatedStorage.Shared.config.UpgradeTreeConfig)

local SCOPE = "LocalUpgradeTree"

local LocalUpgradeTree = {}

local locale

function LocalUpgradeTree.Init(data)
	locale = data.LocaleData
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local function roman(n: number): string
	return ROMAN[n] or tostring(n)
end

local function fmt(n: number): string
	local text = tostring(math.floor(n or 0))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- Pack a sub-tree's stats into a dense honeycomb blob around the centre: each
-- stat gets an angular SECTOR (so its tiers form one connected wedge-clump,
-- readable), tiers ordered nearest-first (tier 1 touches the centre). Returns
-- per-stat ordered cell lists { [statIndex] = { {q,r}, ... } }.
local function packSectors(needs): { { { q: number, r: number } } }
	local n = #needs
	local base = -math.pi / 2 -- sector 1 centred on "up"
	local perStat
	local radius = 1
	while true do
		local cells = {}
		for q = -radius, radius do
			for r = -radius, radius do
				local s = -q - r
				local dist = (math.abs(q) + math.abs(r) + math.abs(s)) / 2
				if not (q == 0 and r == 0) and dist <= radius then
					local px, py = HexUtil.ToPixel(1, q, r)
					table.insert(cells, { q = q, r = r, dist = dist, angle = math.atan2(py, px) })
				end
			end
		end
		perStat = {}
		for i = 1, n do
			perStat[i] = {}
		end
		for _, c in ipairs(cells) do
			local best, bestDelta
			for i = 1, n do
				local center = base + (i - 1) * (2 * math.pi / n)
				-- shortest angular distance to this sector's centre
				local delta = math.abs(((c.angle - center + math.pi) % (2 * math.pi)) - math.pi)
				if bestDelta == nil or delta < bestDelta then
					bestDelta, best = delta, i
				end
			end
			table.insert(perStat[best], c)
		end
		local enough = true
		for i = 1, n do
			if #perStat[i] < needs[i] then
				enough = false
				break
			end
		end
		if enough then
			break
		end
		radius += 1
	end
	local result = {}
	for i = 1, n do
		table.sort(perStat[i], function(a, b)
			if a.dist ~= b.dist then
				return a.dist < b.dist
			end
			return a.angle < b.angle
		end)
		local taken = {}
		for k = 1, needs[i] do
			taken[k] = perStat[i][k]
		end
		result[i] = taken
	end
	return result
end

-- Owned tiers across a category's stats, the total, and whether at least one
-- next tier is BOTH available and affordable (drives the category badge).
local function categoryInfo(catId: string, levels, calories: number): (number, number, boolean)
	local owned, total, canBuy = 0, 0, false
	for _, def in pairs(UpgradeConfig.upgrades) do
		if def.category == catId then
			local lvl = math.min(levels[def.id] or 0, #def.tiers)
			owned += lvl
			total += #def.tiers
			local next_ = def.tiers[lvl + 1]
			if next_ and calories >= next_.cost then
				canBuy = true
			end
		end
	end
	return owned, total, canBuy
end

--API
-- Node model for one tree id ("root" | category id). levels = { [statId] =
-- ownedTiers }, calories = current balance (for badges + Buy affordability).
function LocalUpgradeTree.BuildTree(treeId: string, levels, calories: number)
	levels = levels or {}
	calories = calories or 0

	local nodes = {}
	local function addNode(q, r, node)
		node.q, node.r = q, r
		table.insert(nodes, node)
	end

	if treeId == "root" then
		local root = UpgradeTreeConfig.trees.root
		addNode(root.logo.q, root.logo.r, {
			key = "logo",
			kind = "logo",
			state = "owned",
			title = locale.T("hex-logo"),
			status = "",
			clickable = false,
		})
		for _, cat in ipairs(root.categories) do
			local def = UpgradeConfig.categories[cat.id]
			if def == nil then
				-- R8: config drift — degrade (skip) loudly, don't crash the render.
				Log.Once(SCOPE, "badcat-" .. cat.id, `category '{cat.id}' missing from UpgradeConfig.categories — skipped`)
				continue
			end
			local owned, total, canBuy = categoryInfo(cat.id, levels, calories)
			addNode(cat.q, cat.r, {
				key = `cat:{cat.id}`,
				kind = "category",
				state = "category",
				title = locale.T(def.nameKey),
				status = locale.T("hex-open"),
				clickable = true,
				badge = canBuy,
				action = { type = "open", id = cat.id },
				detail = {
					title = locale.T(def.nameKey),
					desc = locale.T("hex-open-desc"),
					statusLine = locale.T("hex-progress", { owned = owned, total = total }),
				},
			})
		end
	else
		local sub = UpgradeTreeConfig.trees[treeId]
		if sub == nil then
			Log.Once(SCOPE, "badtree-" .. tostring(treeId), `unknown tree id '{treeId}' — empty model`)
			return { nodes = {}, nodeWidth = 0.1, nodeHeight = 0.1 }
		end
		-- Back at the centre; each stat packed into its own wedge-clump around it.
		addNode(0, 0, {
			key = "back",
			kind = "back",
			state = "back",
			title = locale.T("hex-back"),
			status = "",
			clickable = true,
			action = { type = "back" },
		})
		-- Skip any stat with no UpgradeConfig entry (config drift) — loudly (R8),
		-- so packSectors never indexes a nil def.
		-- Only show OWNED tiers + the available one + the next locked one
		-- (owned+2); the rest appear as you buy. Count per stat drives packing.
		local stats, counts = {}, {}
		for _, statId in ipairs(sub.stats) do
			local def = UpgradeConfig.upgrades[statId]
			if def then
				table.insert(stats, statId)
				table.insert(counts, math.min((levels[statId] or 0) + 2, #def.tiers))
			else
				Log.Once(SCOPE, "badstat-" .. statId, `stat '{statId}' has no UpgradeConfig.upgrades entry — skipped`)
			end
		end
		local packed = packSectors(counts)
		for si, statId in ipairs(stats) do
			local def = UpgradeConfig.upgrades[statId]
			local owned = levels[statId] or 0
			for tier = 1, counts[si] do
				local cell = packed[si][tier]
				local tierDef = def.tiers[tier]
				local state, status, statusLine
				if owned >= tier then
					state = "owned"
					status = ""
					statusLine = if tier == #def.tiers then locale.T("hex-tip-max") else locale.T("hex-owned")
				elseif owned == tier - 1 then
					state = "available"
					status = fmt(tierDef.cost)
					statusLine = ""
				else
					state = "locked"
					status = ""
					statusLine = locale.T("hex-tip-locked")
				end
				addNode(cell.q, cell.r, {
					key = `{statId}:{tier}`,
					kind = "tier",
					state = state,
					title = `{locale.T(`hex-name-{statId}`)} {roman(tier)}`,
					status = status,
					clickable = true,
					statId = statId,
					detail = {
						title = `{locale.T(def.nameKey)} {roman(tier)}`,
						desc = locale.T(def.descKey),
						statusLine = statusLine,
						buyText = if state == "available"
							then locale.T("price-calories", { n = fmt(tierDef.cost) })
							else nil,
						affordable = state == "available" and calories >= tierDef.cost,
						state = state,
					},
				})
			end
		end
	end

	-- Auto-fit: unit-grid pixels, then normalise the bounding box into the square
	-- canvas (uniform scale, centred) so any tree fills the view.
	local hexW, hexH = HexUtil.Dimensions(1)
	local fill = UpgradeTreeConfig.hex.nodeFill
	local pad = UpgradeTreeConfig.hex.pad
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, node in ipairs(nodes) do
		local px, py = HexUtil.ToPixel(1, node.q, node.r)
		node.px, node.py = px, py
		minX, maxX = math.min(minX, px - hexW / 2), math.max(maxX, px + hexW / 2)
		minY, maxY = math.min(minY, py - hexH / 2), math.max(maxY, py + hexH / 2)
	end
	local spanX = math.max(maxX - minX, 1e-3)
	local spanY = math.max(maxY - minY, 1e-3)
	local usable = 1 - 2 * pad
	local scale = math.min(usable / spanX, usable / spanY)
	local cx = (minX + maxX) / 2
	local cy = (minY + maxY) / 2
	for _, node in ipairs(nodes) do
		node.cx = 0.5 + (node.px - cx) * scale
		node.cy = 0.5 + (node.py - cy) * scale
	end

	return {
		nodes = nodes,
		nodeWidth = hexW * fill * scale,
		nodeHeight = hexH * fill * scale,
	}
end

return LocalUpgradeTree
