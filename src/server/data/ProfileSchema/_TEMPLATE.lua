--[[
	Profile section TEMPLATE — copy this file, rename it (PascalCase, e.g.
	EconomySection.lua), fill in the fields, delete unused ones and these
	comments. Files starting with "_" are ignored by the registry.

	Register new persistent state ONLY through section files like this one.
	Full guide: docs/recipes/add-profile-section.md
]]

return {
	-- Top-level field name in the profile table. Unique across all sections.
	-- Services read it as: profileData.Get(userId).myFeature
	key = "myFeature",

	-- Bump this when the section shape changes, and add a migration below.
	version = 1,

	-- Deep-copied into new profiles. On load, missing fields are filled in
	-- from here automatically (reconcile) — adding a new field with a default
	-- requires NO migration. NOTE: reconcile fills missing KEYS only; it will
	-- not fix wrong value types — use sanitize for that.
	defaults = {
		counter = 0,
		flags = {},
		-- claimed = {}, -- example of a number-keyed set, declared below
	},

	-- Dot-paths (relative to this section) of tables whose keys are NUMBERS,
	-- e.g. { [level: number] = true }. DataStore JSON stringifies numeric
	-- keys ("1", "2", ...); paths listed here are converted back to numbers
	-- on every load, so services can always index them with numbers.
	-- Nested paths are supported: "stats.perLevel".
	intKeySets = {
		-- "claimed",
	},

	-- Sequential upgrades for stored data: [oldVersion] = function(section).
	-- A profile stored at version N runs migrations[N], [N+1], ... up to
	-- version - 1. Each function mutates and/or returns the section table.
	-- Migrations run BEFORE reconcile, so old fields are still intact.
	migrations = {
		-- [1] = function(section)
		-- 	section.counter = section.oldCounter or 0 -- renamed in v2
		-- 	section.oldCounter = nil
		-- 	return section
		-- end,
	},

	-- Optional last line of defense, runs after migrate + reconcile +
	-- int-key normalization. Coerce invalid values here (wrong types,
	-- out-of-range numbers). Return the section table.
	sanitize = nil,
	-- sanitize = function(section)
	-- 	if type(section.counter) ~= "number" or section.counter < 0 then
	-- 		section.counter = 0
	-- 	end
	-- 	return section
	-- end,
}
