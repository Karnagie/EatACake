--[[
	ProfileSchema — declarative registry of profile sections (R1).

	Every ModuleScript child of this module defines ONE top-level section of
	the player profile. Files whose names start with "_" are skipped
	(templates, disabled sections).

	Section contract (see _TEMPLATE.lua for a fully commented example):
	{
		key        = "economy",   -- top-level field name in the profile table (required, unique)
		version    = 1,           -- current schema version of this section (>= 1)
		defaults   = {...},       -- deep-copied for new profiles; missing fields
		                          -- are filled in on load (reconcile)
		intKeySets = {...},       -- dot-paths (relative to the section) of tables
		                          -- whose keys are NUMBERS. DataStore JSON turns
		                          -- numeric keys into strings; these are converted
		                          -- back automatically on every load.
		migrations = {...},       -- [oldVersion] = function(section) -> section
		                          -- run sequentially to upgrade stored data
		sanitize   = nil,         -- optional function(section) -> section for
		                          -- last-resort coercion after migrate+reconcile
	}

	The key "__schema" is reserved (stores per-section versions inside the profile).

	This module is a pure registry: all application logic (migrate, reconcile,
	int-key normalization) lives in services/PersistenceService.lua (R2).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "ProfileSchema"

local RESERVED_KEYS = {
	["__schema"] = true,
}

local ProfileSchema = {}

ProfileSchema.sections = {} -- [key: string] = section definition table

function ProfileSchema.Init()
	table.clear(ProfileSchema.sections)
	local registered = {}
	for _, child in ipairs(script:GetChildren()) do
		if not child:IsA("ModuleScript") then
			continue
		end
		if string.sub(child.Name, 1, 1) == "_" then
			Log.Info(SCOPE, `{child.Name}: skipped (underscore prefix = template/disabled)`)
			continue
		end
		local ok, section = pcall(require, child)
		if not ok then
			Log.Warn(SCOPE, `{child.Name}: require FAILED — {section}`)
			continue
		end
		if type(section) ~= "table" or type(section.key) ~= "string" or type(section.defaults) ~= "table" then
			Log.Warn(SCOPE, `{child.Name}: INVALID section (requires key: string and defaults: table) — skipped`)
			continue
		end
		if RESERVED_KEYS[section.key] then
			Log.Warn(SCOPE, `{child.Name}: uses reserved key '{section.key}' — skipped`)
			continue
		end
		if ProfileSchema.sections[section.key] then
			Log.Warn(SCOPE, `{child.Name}: duplicate section key '{section.key}' — skipped`)
			continue
		end
		section.version = math.max(1, math.floor(tonumber(section.version) or 1))
		ProfileSchema.sections[section.key] = section
		table.insert(registered, `{section.key} v{section.version}`)
	end
	table.sort(registered)
	if #registered == 0 then
		Log.Warn(SCOPE, "NO sections registered — profiles will be empty tables")
	else
		Log.Sum(SCOPE, `{#registered} section(s) registered: {table.concat(registered, ", ")}`)
	end
end

return ProfileSchema
