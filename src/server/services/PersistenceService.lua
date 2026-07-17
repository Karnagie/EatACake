--[[
	PersistenceService — schema-driven player profile persistence (R2: logic only).

	Built on ProfileStore (vendored: src/shared/lib/ProfileStore.luau), which
	provides session locking, periodic auto-save (~30s), retries and a final
	save on server shutdown — none of that is reimplemented here.

	What THIS service does on top:
	- Builds the profile template from ProfileSchema sections (single source
	  of truth: define a field once, it persists — no hand-maintained
	  whitelists).
	- On load, per section: run version migrations -> reconcile missing
	  fields from defaults -> normalize declared int-key sets (DataStore JSON
	  stringifies numeric keys) -> sanitize.
	- Manages the session lifecycle: kick on lock conflict, cleanup on
	  session end, critical saves.

	State lives in PlayerProfileData; config in PersistenceData; the schema
	in ProfileSchema (R1). See docs/features/persistence.md and ADR-0001.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ProfileStore = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("lib"):WaitForChild("ProfileStore"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Persistence"

local PersistenceService = {}

local profileData -- PlayerProfileData
local schemaData -- ProfileSchema
local configData -- PersistenceData

local store -- ProfileStore object

local function deepCopy(source: { [any]: any }): { [any]: any }
	local copy = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Fills keys missing in `target` from `defaults` (recursively for tables).
-- Existing values are never overwritten; wrong types are left for sanitize.
local function deepReconcile(target: { [any]: any }, defaults: { [any]: any })
	for key, defaultValue in pairs(defaults) do
		local current = target[key]
		if current == nil then
			if type(defaultValue) == "table" then
				target[key] = deepCopy(defaultValue)
			else
				target[key] = defaultValue
			end
		elseif type(current) == "table" and type(defaultValue) == "table" then
			deepReconcile(current, defaultValue)
		end
	end
end

-- Rebuilds the table at `path` (dot-separated, relative to `root`) converting
-- string keys back to numbers. DataStore JSON stringifies numeric keys; this
-- guarantees services can always index declared sets with numbers.
local function normalizeIntKeys(root: { [any]: any }, path: string)
	local node = root
	local segments = string.split(path, ".")
	for i = 1, #segments - 1 do
		node = node[segments[i]]
		if type(node) ~= "table" then
			return
		end
	end
	local lastKey = segments[#segments]
	local target = node[lastKey]
	if type(target) ~= "table" then
		return
	end
	local fixed = {}
	for key, value in pairs(target) do
		-- Strict integer match only: tonumber() alone would also convert
		-- "1e5"/"0x10"/"nan" (NaN would even error as a table index).
		if type(key) == "string" and string.match(key, "^%-?%d+$") then
			fixed[tonumber(key)] = value
		else
			fixed[key] = value
		end
	end
	node[lastKey] = fixed
end

-- Upgrades one stored section from its saved version to the current one.
local function migrateSection(sectionKey: string, section: { [any]: any }, definition: { [any]: any }, storedVersion: number)
	local version = storedVersion
	while version < definition.version do
		local migrate = definition.migrations and definition.migrations[version]
		if type(migrate) == "function" then
			local ok, result = pcall(migrate, section)
			if ok then
				if type(result) == "table" then
					section = result
				end
				Log.Info(SCOPE, `section '{sectionKey}': migrated v{version} -> v{version + 1}`)
			else
				Log.Warn(SCOPE, `section '{sectionKey}': migration v{version} -> v{version + 1} FAILED — {result}`)
				-- Continue: reconcile + sanitize below act as the safety net.
			end
		else
			-- Version was bumped without a migration step (P2 violation?).
			-- Old-shaped data gets stamped as current — log loudly.
			Log.Warn(SCOPE, `section '{sectionKey}': v{version} -> v{version + 1} has NO migration defined`)
		end
		version += 1
	end
	return section
end

-- Applies the full schema pipeline to a loaded profile data table:
-- migrate -> reconcile -> int-key normalize -> sanitize, per section.
-- Unknown fields (sections removed from the schema) are preserved untouched.
local function applySchema(dataTable: { [any]: any })
	if type(dataTable.__schema) ~= "table" then
		dataTable.__schema = {}
	end
	for sectionKey, definition in pairs(schemaData.sections) do
		local stored = dataTable[sectionKey]
		if type(stored) ~= "table" then
			dataTable[sectionKey] = deepCopy(definition.defaults)
			dataTable.__schema[sectionKey] = definition.version
		else
			local storedVersion = math.floor(tonumber(dataTable.__schema[sectionKey]) or 1)
			stored = migrateSection(sectionKey, stored, definition, storedVersion)
			dataTable[sectionKey] = stored
			deepReconcile(stored, definition.defaults)
			for _, path in ipairs(definition.intKeySets or {}) do
				normalizeIntKeys(stored, path)
			end
			if type(definition.sanitize) == "function" then
				local ok, result = pcall(definition.sanitize, stored)
				if ok and type(result) == "table" then
					dataTable[sectionKey] = result
				elseif not ok then
					Log.Warn(SCOPE, `section '{sectionKey}': sanitize FAILED — {result}`)
				end
			end
			-- NEVER downgrade the stamp: after an update ships, old servers
			-- keep running for a while. If an old server (lower section
			-- version) stamped its own version onto data already migrated by
			-- a new server, the migration would re-run later and corrupt it.
			dataTable.__schema[sectionKey] = math.max(storedVersion, definition.version)
		end
	end
end

local function buildTemplate(): { [any]: any }
	local template = { __schema = {} }
	for sectionKey, definition in pairs(schemaData.sections) do
		template[sectionKey] = deepCopy(definition.defaults)
		template.__schema[sectionKey] = definition.version
	end
	return template
end

function PersistenceService.Init(data)
	profileData = data.PlayerProfileData
	schemaData = data.ProfileSchema
	configData = data.PersistenceData

	store = ProfileStore.New(configData.storeName, buildTemplate())
	local mock = RunService:IsStudio() and configData.useMockInStudio
	if mock then
		store = store.Mock
		Log.Warn(SCOPE, "Studio MOCK store: nothing will persist this session (PersistenceData.useMockInStudio)")
	end

	ProfileStore.OnError:Connect(function(errorMessage, storeName, profileKey)
		Log.Warn(SCOPE, `DataStore error ({storeName}/{profileKey}): {errorMessage}`)
	end)

	-- Console transparency: the single most dangerous SILENT state is "no
	-- DataStore access" (unpublished place / Studio API access off) — the
	-- game runs fine but nothing persists. Report the resolved state loudly.
	task.spawn(function()
		while ProfileStore.DataStoreState == "NotReady" do
			task.wait(0.2)
		end
		local state = ProfileStore.DataStoreState
		if mock then
			Log.Sum(SCOPE, `store '{configData.storeName}' ready (MOCK mode)`)
		elseif state == "Access" then
			Log.Sum(SCOPE, `store '{configData.storeName}' ready — DataStore access OK, profiles will persist`)
		else
			Log.Warn(
				SCOPE,
				`store '{configData.storeName}': NO DataStore access ({state}) — profiles will NOT persist! (Studio: Game Settings -> Security -> Enable Studio Access to API Services, and publish the place)`
			)
		end
	end)
end

--API
-- Starts a session-locked profile session for the player. Yields.
-- Returns (profile data table, isNew) on success, nil if the player left or
-- the session could not be started (the player is kicked in that case).
-- isNew is true ONLY for a genuinely fresh profile (first session ever) —
-- never because of a failed read (safe for retention cohorts / first-join grants).
function PersistenceService.LoadProfile(player: Player): ({ [any]: any }?, boolean)
	local userId = player.UserId

	if store == nil then
		-- Init failed (bad store name / no DataStore access). Fail loudly
		-- instead of leaving the player in-game with no data.
		Log.Warn(SCOPE, `store unavailable — cannot load profile for {userId}`)
		if player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end

	local profile = store:StartSessionAsync(tostring(userId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		Log.Warn(SCOPE, `session NOT started for {player.Name} ({userId}) — lock conflict or DataStore failure; kicking`)
		if player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end

	profile:AddUserId(userId) -- GDPR association

	local schemaOk, schemaErr = pcall(applySchema, profile.Data)
	if not schemaOk then
		-- Poisoned profile (bad stored value crashed a migration/normalize).
		-- End the session so the lock is released, and fail loudly.
		Log.Warn(SCOPE, `schema apply FAILED for {userId} — {schemaErr}`)
		profile:EndSession()
		if player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end

	if player.Parent ~= Players then
		-- Player left while we were loading.
		profile:EndSession()
		return nil, false
	end

	profile.OnSessionEnd:Connect(function()
		profileData.profiles[userId] = nil
		profileData.sessions[userId] = nil
		-- Don't kick on server shutdown (ProfileStore ends sessions itself;
		-- "loaded on another server" would be a false message).
		if not ProfileStore.IsClosing and player.Parent == Players then
			player:Kick(configData.messages["session-taken"])
		end
	end)

	profileData.profiles[userId] = profile.Data
	profileData.sessions[userId] = profile

	if not profile:IsActive() then
		-- Session ended during load (OnSessionEnd may have fired before it
		-- was connected) — clean up manually.
		profileData.profiles[userId] = nil
		profileData.sessions[userId] = nil
		if player.Parent == Players then
			player:Kick(configData.messages["session-taken"])
		end
		return nil, false
	end

	local isNew = profile.SessionLoadCount == 1
	Log.Info(SCOPE, `profile loaded: {player.Name} ({userId}) — isNew={isNew}, session #{profile.SessionLoadCount}`)
	return profile.Data, isNew
end

--API
-- Immediate save for critical moments (e.g. right after granting a Robux
-- purchase). Routine saving is automatic — do NOT call this on a timer.
function PersistenceService.Save(userId: number)
	local session = profileData.sessions[userId]
	if session ~= nil and session:IsActive() then
		session:Save()
	end
end

--API
-- Ends the session (final save included) and clears the runtime cache.
-- Call exactly once when the player leaves.
function PersistenceService.Unload(userId: number)
	local session = profileData.sessions[userId]
	if session ~= nil then
		session:EndSession() -- OnSessionEnd clears PlayerProfileData
	end
end

--API
function PersistenceService.IsLoaded(userId: number): boolean
	return profileData.profiles[userId] ~= nil
end

return PersistenceService
