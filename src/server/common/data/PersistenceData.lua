--[[
	PersistenceData — configuration for the persistence layer (R1).
	Logic lives in services/PersistenceService.lua.
]]

local PersistenceData = {}

-- DataStore name. No version suffix needed: schema versioning is per-section
-- (see data/ProfileSchema/). Change this ONLY to intentionally wipe all data.
PersistenceData.storeName = "PlayerProfiles"

-- When true, Studio play tests use ProfileStore.Mock (nothing is written to
-- live DataStore keys). Keep false if you want Studio sessions to persist.
PersistenceData.useMockInStudio = false

-- Player-facing kick messages. When a localization system is added to the
-- project, route these through it.
PersistenceData.messages = {
	["load-failed"] = "Failed to load your data. Please rejoin.",
	["session-taken"] = "Your data was loaded on another server. Please rejoin.",
}

return PersistenceData
