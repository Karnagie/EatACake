--[[
	LocalUpgradeTree — upgrades hex-tree view-model (R2, logic only). Expands
	UpgradeTreeConfig + replicated levels + calories into the positioned NODES
	the HexTreeOverlay renders. Pure derivation; the server validates every
	purchase from UpgradeConfig (never trusts this).

	Node states: locked / available (next buy) / owned / category / back / logo.
	Every stat and category node also carries an `icon` (a Theme.Icons registry
	NAME from UpgradeTreeConfig.icons) — the glyph is what identifies the node for
	a player who does not read the label; HexNode switches to its icon-first
	layout whenever one is present.
	Sub-tree tiers are PACKED into a tight spiral blob (HexUtil.Spiral) — hexes
	touch, no connectors. Each node also carries `detail` (name / description /
	status / cost) for the tap-to-open panel, and category nodes carry a `badge`
	when an affordable upgrade sits inside. Positions are Scale (0..1) of the
	square canvas; the overlay scales it once to the viewport.

	It also owns the AFFORDABILITY predicates (`AffordableCount` / `AnyAffordable`
	/ `CanAffordNext`) — one definition, shared by the category "!" BADGE, the Buy
	button's `detail.affordable`, the world "N AVAILABLE" sign over the upgrade
	station (UpgradeStationSubsClient) and the onboarding gate (TutorialSubsClient).
	They also drive `node.pulse` — the breathing hex (HexNode) that says "you can
	buy this RIGHT NOW": an affordable tier, and any category holding one (the
	same fact as its "!" badge, in a second channel).
	⚠ They do NOT drive the gold `available` STATE. A hex is gold when it is the
	next UNLOCKED tier (`owned == tier - 1`), priced but not necessarily payable —
	that is deliberate, since a tier has to show its price before you can afford
	it — so GOLD HEXES >= the sign's N, always. What the shared predicate buys is
	the one-way guarantee that matters: the sign can never promise a purchase the
	Buy button then refuses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HexUtil = require(ReplicatedStorage.Shared.HexUtil)
local Log = require(ReplicatedStorage.Shared.Log)
local UpgradeConfig = require(ReplicatedStorage.Shared.config.UpgradeConfig)
local UpgradeTreeConfig = require(ReplicatedStorage.Shared.config.UpgradeTreeConfig)

local SCOPE = "LocalUpgradeTree"

-- Registry NAMES per node (UpgradeTreeConfig.icons — the reasoning for each
-- choice lives there). Read-ONLY locals, never `ICONS.stats = ICONS.stats or {}`:
-- that writes into the shared config table, which would throw outright the day
-- someone `table.freeze`s it the way Theme freezes its sections. Tolerant of a
-- config with no icons block, so an older UpgradeTreeConfig still builds a tree —
-- just without glyphs, and HexNode falls back to its text-only cut.
local ICONS = UpgradeTreeConfig.icons or {}
local ICON_STATS = ICONS.stats or {}
local ICON_CATEGORIES = ICONS.categories or {}

local LocalUpgradeTree = {}

local locale

function LocalUpgradeTree.Init(data)
	locale = data.LocaleData
end

--API
-- How many upgrades could the player buy RIGHT NOW? Cheap (9 stats), pure.
--
-- Counts STATS whose next tier is affordable — the subset of the tree's gold
-- `available` hexes the player can actually pay for right now (gold means UNLOCKED,
-- not affordable — see the module header). It deliberately does NOT count a greedy
-- spending SEQUENCE (buy the cheapest, then see what the freed-up tier unlocks):
-- that answers a different question, and a world label promising "7 available" over
-- a tree the player can only buy 3 things from is a lie they can see.
function LocalUpgradeTree.AffordableCount(levels: { [string]: number }?, calories: number?): number
	local owned = levels or {}
	local balance = calories or 0
	local count = 0
	for id, def in pairs(UpgradeConfig.upgrades) do
		local nextTier = def.tiers[(owned[id] or 0) + 1]
		if nextTier ~= nil and nextTier.cost <= balance then
			count += 1
		end
	end
	return count
end

--API
-- Is ANY stat's next tier already affordable?
function LocalUpgradeTree.AnyAffordable(levels: { [string]: number }?, calories: number?): boolean
	return LocalUpgradeTree.AffordableCount(levels, calories) > 0
end

--API
-- Could the player afford ONE named stat's next tier at this balance?
-- A MAXED stat returns true: there is nothing left to save up for, so a caller
-- gating on "can they buy this yet?" must not wait forever.
-- An UNKNOWN id returns nil (and warns once) rather than a boolean — config drift
-- must not silently read as "yes, go ahead"; the caller picks the safe branch.
function LocalUpgradeTree.CanAffordNext(
	levels: { [string]: number }?,
	calories: number?,
	statId: string
): boolean?
	local def = UpgradeConfig.upgrades[statId]
	if def == nil then
		Log.Once(SCOPE, "badaffordstat-" .. tostring(statId), `CanAffordNext('{tostring(statId)}') — no such upgrade in UpgradeConfig`)
		return nil
	end
	local nextTier = def.tiers[((levels or {})[statId] or 0) + 1]
	if nextTier == nil then
		return true
	end
	return nextTier.cost <= (calories or 0)
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
				icon = ICON_CATEGORIES[cat.id],
				title = locale.T(def.nameKey),
				status = locale.T("hex-open"),
				clickable = true,
				badge = canBuy,
				-- "This branch holds something you can buy right now" — the same
				-- fact the "!" badge carries, said in MOTION so it survives a squint
				-- and reaches a player who never reads the labels (HexNode `pulse`).
				-- ONE predicate feeding both channels: they cannot disagree.
				pulse = canBuy,
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
			icon = ICONS.back,
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
				-- AFFORDABLE, not merely unlocked — see the module header: gold means
				-- "the next tier, priced", and a tier has to show its price before the
				-- player can afford it. Only this narrower set breathes, and it is the
				-- same set the green Buy button accepts.
				local affordable = owned == tier - 1 and calories >= tierDef.cost
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
					-- Every tier of a stat wears the SAME glyph; the roman numeral in
					-- the title is what separates them. A per-tier glyph would make one
					-- stat's wedge read as five unrelated upgrades.
					icon = ICON_STATS[statId],
					title = `{locale.T(`hex-name-{statId}`)} {roman(tier)}`,
					status = status,
					clickable = true,
					pulse = affordable,
					statId = statId,
					detail = {
						title = `{locale.T(def.nameKey)} {roman(tier)}`,
						desc = locale.T(def.descKey),
						statusLine = statusLine,
						buyText = if state == "available"
							then locale.T("price-calories", { n = fmt(tierDef.cost) })
							else nil,
						affordable = affordable,
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
