--[[
	Profile section: upgrades — tiers OWNED per upgrade id (GDD §10).
	`levels[id]` = number of hexagon TIERS bought (0 = none, #tiers = maxed).
	Ids, tier values and costs live in Shared/config/UpgradeConfig; the hex-tree
	layout in Shared/config/UpgradeTreeConfig. UpgradeService clamps on purchase;
	StatsService clamps on read; sanitize only repairs corrupt values.

	v2 migration: v1 stored linear LEVELS (0..oldCap, up to 40); v2 stores TIER
	counts (0..5). Rescale proportionally so returning players keep ~their power
	instead of a level-40 save reading as maxed-everything (or an empty reset).

	The fat-burn stats (burnSpeed/burnPerTap/instantBurn) are NEW fields with a
	default of 0 — reconcile fills them for existing profiles, so no version bump
	or migration is needed (P2). Every consumer treats a missing id as tier 0.
]]

return {
	key = "upgrades",
	version = 2,
	defaults = {
		levels = {
			capacity = 0,
			biteRadius = 0,
			biteDepth = 0,
			eatSpeed = 0,
			gymEff = 0,
			burnSpeed = 0,
			burnPerTap = 0,
			instantBurn = 0,
			runSpeed = 0,
		},
	},
	intKeySets = {},
	migrations = {
		[1] = function(section)
			-- Old per-stat linear caps -> new uniform tier count.
			local oldCaps = {
				capacity = 40,
				biteRadius = 18,
				biteDepth = 40,
				eatSpeed = 40,
				gymEff = 30,
				runSpeed = 15,
			}
			-- Mirrors #tiers in UpgradeConfig at migration time (all stats = 5);
			-- self-contained on purpose — historical migrations don't import live
			-- config. Any later tier-count change needs its own migration.
			local newMax = 5
			local levels = section.levels
			if type(levels) ~= "table" then
				levels = {} -- corrupt store (levels not a table) — start clean
			end
			for id, oldCap in pairs(oldCaps) do
				local lvl = tonumber(levels[id]) or 0
				if lvl ~= lvl or lvl < 0 then
					lvl = 0
				end
				levels[id] = math.clamp(math.floor(lvl / oldCap * newMax + 0.5), 0, newMax)
			end
			section.levels = levels
			return section
		end,
	},
	sanitize = function(section)
		if type(section.levels) ~= "table" then
			section.levels = {} -- corrupt store — reconcile refills the defaults
		end
		for id, level in pairs(section.levels) do
			if type(level) ~= "number" or level ~= level or level == math.huge or level < 0 then
				section.levels[id] = 0
			else
				section.levels[id] = math.floor(level)
			end
		end
		return section
	end,
}
