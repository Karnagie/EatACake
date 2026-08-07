--[[
	PersistenceService — schema-driven player profile persistence (R2: logic only).

	Built on ProfileStore (vendored: src/shared/lib/ProfileStore.luau), which
	provides session locking, periodic auto-save (~300s; first ~150s after a
	profile loads are skipped), retries and a final
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

	- Delivers ProfileStore MESSAGES to the owning session (see below).

	State lives in PlayerProfileData; config in PersistenceData; the schema
	in ProfileSchema (R1). See docs/features/persistence.md and ADR-0001.

	MESSAGES — writing to a profile whose owner is NOT on this server.
	`SendMessage(userId, message)` queues a JSON table onto that profile through
	ProfileStore's `MessageAsync`; it is delivered to the owner's active session
	wherever it is (immediately if that is this server, on their next load
	otherwise) and survives them being offline entirely. That is the ONLY way to
	pay someone who is not here without touching DataStoreService directly (P5),
	and it is what the referral reward rides (features/referrals.md).
	`RegisterMessageHandler(name, handler)` installs a receiver, once, at
	subscription Start time: LoadProfile attaches every registered handler to the
	new session before publishing it. A handler is `(player, message, processed)`
	and MUST call `processed()` once it has actually applied the message —
	unprocessed messages are re-delivered on the next load, which is the property
	that makes the reward survive a crash (at the price of a possible double
	delivery if the server dies between applying and saving).
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
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

-- Cross-session message receivers, registered once at Start (see the header).
-- Ordered so the boot log and delivery order are reproducible.
local messageHandlers: { { name: string, fn: (Player, { [string]: any }, () -> ()) -> () } } = {}

export type LoadOptions = {
	deadline: number?,
	cancel: (() -> boolean)?,
	kickOnFailure: boolean?,
}

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
	-- Work on a copy. A migration is allowed to mutate before throwing; touching
	-- Profile.Data directly would make EndSession save that half-migrated shape.
	local working = deepCopy(section)
	local version = storedVersion
	while version < definition.version do
		local migrate = definition.migrations and definition.migrations[version]
		if type(migrate) == "function" then
			local ok, result = pcall(migrate, working)
			if ok then
				if type(result) == "table" then
					working = result
				elseif result ~= nil then
					error(`section '{sectionKey}': migration v{version} -> v{version + 1} returned {typeof(result)}, expected table or nil`)
				end
				Log.Info(SCOPE, `section '{sectionKey}': migrated v{version} -> v{version + 1}`)
			else
				error(`section '{sectionKey}': migration v{version} -> v{version + 1} FAILED — {result}`)
			end
		else
			error(`section '{sectionKey}': v{version} -> v{version + 1} has NO migration defined (P2)`)
		end
		version += 1
	end
	return working
end

-- Applies the full schema pipeline to a loaded profile data table:
-- migrate -> reconcile -> int-key normalize -> sanitize, per section.
-- Unknown fields (sections removed from the schema) are preserved untouched.
local function applySchema(dataTable: { [any]: any })
	-- The whole pipeline is transactional in memory. On any migration/sanitize
	-- failure Profile.Data stays byte-for-byte at its loaded shape, so the
	-- subsequent EndSession cannot persist a partial upgrade or false stamp.
	local working = deepCopy(dataTable)
	if type(working.__schema) ~= "table" then
		working.__schema = {}
	end
	for sectionKey, definition in pairs(schemaData.sections) do
		local stored = working[sectionKey]
		if type(stored) ~= "table" then
			working[sectionKey] = deepCopy(definition.defaults)
			working.__schema[sectionKey] = definition.version
		else
			local storedVersion = math.floor(tonumber(working.__schema[sectionKey]) or 1)
			stored = migrateSection(sectionKey, stored, definition, storedVersion)
			deepReconcile(stored, definition.defaults)
			for _, path in ipairs(definition.intKeySets or {}) do
				normalizeIntKeys(stored, path)
			end
			if type(definition.sanitize) == "function" then
				local ok, result = pcall(definition.sanitize, stored)
				if ok and type(result) == "table" then
					stored = result
				elseif not ok then
					error(`section '{sectionKey}': sanitize FAILED — {result}`)
				elseif result ~= nil then
					error(`section '{sectionKey}': sanitize returned {typeof(result)}, expected table or nil`)
				end
			end
			working[sectionKey] = stored
			-- NEVER downgrade the stamp: after an update ships, old servers
			-- keep running for a while. If an old server (lower section
			-- version) stamped its own version onto data already migrated by
			-- a new server, the migration would re-run later and corrupt it.
			working.__schema[sectionKey] = math.max(storedVersion, definition.version)
		end
	end

	table.clear(dataTable)
	for key, value in pairs(working) do
		dataTable[key] = value
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
-- Teleport recovery may provide a deadline/generation cancel callback and
-- disable this function's kick so its bounded recovery owner handles failure.
-- isNew is true ONLY for a genuinely fresh profile (first session ever) —
-- never because of a failed read (safe for retention cohorts / first-join grants).
function PersistenceService.LoadProfile(player: Player, options: LoadOptions?): ({ [any]: any }?, boolean)
	local userId = player.UserId
	local deadline = if type(options) == "table" and type(options.deadline) == "number"
		then options.deadline
		else nil
	local externalCancel = if type(options) == "table" and type(options.cancel) == "function"
		then options.cancel
		else nil
	local kickOnFailure = type(options) ~= "table" or options.kickOnFailure ~= false
	local cancelErrorLogged = false
	local function shouldCancel(): boolean
		if player.Parent ~= Players then
			return true
		end
		if deadline ~= nil and os.clock() >= deadline then
			return true
		end
		if externalCancel ~= nil then
			local ok, cancelOrError = pcall(externalCancel)
			if not ok then
				if not cancelErrorLogged then
					cancelErrorLogged = true
					Log.Warn(SCOPE, `load cancellation callback FAILED for {userId}: {cancelOrError}; cancelling load`)
				end
				return true
			end
			return cancelOrError == true
		end
		return false
	end

	if store == nil then
		-- Init failed (bad store name / no DataStore access). Fail loudly
		-- instead of leaving the player in-game with no data.
		Log.Warn(SCOPE, `store unavailable — cannot load profile for {userId}`)
		if kickOnFailure and player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end

	local profile = store:StartSessionAsync(tostring(userId), {
		Cancel = shouldCancel,
	})

	if profile == nil then
		local reason = if shouldCancel() then "cancelled/deadline reached" else "lock conflict or DataStore failure"
		Log.Warn(SCOPE, `session NOT started for {player.Name} ({userId}) — {reason}`)
		if kickOnFailure and player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end
	if shouldCancel() then
		profile:EndSession()
		Log.Info(SCOPE, `session load cancelled after acquisition for {player.Name} ({userId}); released without publishing`)
		return nil, false
	end

	profile:AddUserId(userId) -- GDPR association

	local schemaOk, schemaErr = pcall(applySchema, profile.Data)
	if not schemaOk then
		-- Poisoned profile (bad stored value crashed a migration/normalize).
		-- End the session so the lock is released, and fail loudly.
		Log.Warn(SCOPE, `schema apply FAILED for {userId} — {schemaErr}`)
		profile:EndSession()
		if kickOnFailure and player.Parent == Players then
			player:Kick(configData.messages["load-failed"])
		end
		return nil, false
	end

	if shouldCancel() then
		-- Player left, the deadline expired, or the recovery generation was
		-- invalidated while schema work ran. Never publish this late session.
		profile:EndSession()
		Log.Info(SCOPE, `session load cancelled before publish for {player.Name} ({userId})`)
		return nil, false
	end

	profile.OnSessionEnd:Connect(function()
		profileData.profiles[userId] = nil
		profileData.sessions[userId] = nil
		-- Intentional release (pre-teleport lobby<->game handoff): the player is
		-- being moved to another place ON PURPOSE — consume the flag and DON'T
		-- kick. A genuine displacement by another server never sets this.
		local intentional = profileData.releasing[userId]
		profileData.releasing[userId] = nil
		-- Don't kick on server shutdown (ProfileStore ends sessions itself;
		-- "loaded on another server" would be a false message).
		if not ProfileStore.IsClosing and not intentional and player.Parent == Players then
			player:Kick(configData.messages["session-taken"])
		end
	end)

	profileData.profiles[userId] = profile.Data
	profileData.sessions[userId] = profile
	-- Fresh (or re-acquired) session: discard every prior handoff marker.
	profileData.released[userId] = nil
	profileData.releaseCandidates[userId] = nil
	profileData.releaseNonces[userId] = nil
	profileData.releaseVerifying[userId] = nil

	if not profile:IsActive() then
		-- Session ended during load (OnSessionEnd may have fired before it
		-- was connected) — clean up manually.
		profileData.profiles[userId] = nil
		profileData.sessions[userId] = nil
		if kickOnFailure and player.Parent == Players then
			player:Kick(configData.messages["session-taken"])
		end
		return nil, false
	end

	-- Cross-session messages, attached only once the session is PUBLISHED above:
	-- MessageHandler replays the whole queued backlog immediately (each on its own
	-- task), and a handler that pays the player would otherwise run against a
	-- profile no service can see yet. Attaching after `profileData.profiles` is
	-- set makes `PlayerProfileData.Get(userId)` valid inside every handler.
	for _, handler in ipairs(messageHandlers) do
		profile:MessageHandler(function(message, processed)
			if type(message) ~= "table" then
				-- Consume it: a malformed message is not going to become valid on the
				-- next load, and leaving it queued replays this warn forever.
				Log.Warn(SCOPE, `message for {userId} was {typeof(message)}, not a table — dropped`)
				processed()
				return
			end
			local ok, err = pcall(handler.fn, player, message, processed)
			if not ok then
				-- Deliberately NOT processed: a throwing handler has not applied the
				-- message, and re-delivery on the next load is the whole point of the
				-- queue (R8 — say so, don't swallow it).
				Log.Warn(SCOPE, `{handler.name} message handler FAILED for {userId} — {err}; message stays queued`)
			end
		end)
	end

	local isNew = profile.SessionLoadCount == 1
	Log.Info(SCOPE, `profile loaded: {player.Name} ({userId}) — isNew={isNew}, session #{profile.SessionLoadCount}`)
	return profile.Data, isNew
end

--API
-- Installs a receiver for cross-session messages (see the module header). Call
-- from a subscription's Start — handlers are attached to a session at LOAD time,
-- so one registered after a player's profile loaded never sees that session.
-- `handler(player, message, processed)` must call `processed()` once the message
-- has been applied, or it is re-delivered on the player's next load.
function PersistenceService.RegisterMessageHandler(name: string, handler: (Player, { [string]: any }, () -> ()) -> ())
	if type(handler) ~= "function" then
		Log.Warn(SCOPE, `RegisterMessageHandler('{tostring(name)}') ignored — handler is not a function`)
		return
	end
	table.insert(messageHandlers, { name = name, fn = handler })
	Log.Info(SCOPE, `message handler registered: {name} ({#messageHandlers} total)`)
end

--API
-- YIELDS. Queues `message` onto ANOTHER player's profile — they need not be on
-- this server, or online at all. Returns whether the queue write committed.
-- ⚠ This is a write to a profile this server does not own: it can only APPEND a
-- message, never mutate their data. Everything the message does happens inside
-- the receiving session, through a registered handler.
function PersistenceService.SendMessage(userId: number, message: { [string]: any }): boolean
	if store == nil then
		Log.Warn(SCOPE, `SendMessage({userId}) dropped — profile store unavailable`)
		return false
	end
	if type(message) ~= "table" then
		Log.Warn(SCOPE, `SendMessage({userId}) dropped — message must be a table`)
		return false
	end
	local ok, result = pcall(function()
		return store:MessageAsync(tostring(userId), message)
	end)
	if not ok then
		Log.Warn(SCOPE, `SendMessage({userId}) FAILED — {result}`)
		return false
	end
	if result ~= true then
		-- ProfileStore returns false only when the server is closing; it retries
		-- DataStore errors internally. Either way the caller must not assume the
		-- message landed.
		Log.Warn(SCOPE, `SendMessage({userId}) did not commit (server closing?) — message NOT queued`)
		return false
	end
	return true
end

--API
-- Immediate save for critical moments (e.g. right after granting a Robux
-- purchase). Routine saving is automatic — do NOT call this on a timer.
function PersistenceService.Save(userId: number)
	if profileData.releaseNonces[userId] ~= nil then
		Log.Once(SCOPE, `save-during-release-{userId}`, `Save({userId}) ignored while an intentional release is in flight`)
		return
	end
	local session = profileData.sessions[userId]
	if session ~= nil and session:IsActive() then
		session:Save()
	end
end

--API
-- Save and WAIT (bounded) for the write to commit. Returns true only if a save
-- actually landed.
--
-- `Save` is fire-and-forget: ProfileStore's `Profile:Save()` is a `task.spawn`,
-- so it returns before anything reaches the DataStore. That is fine for
-- gameplay state, which the autosave will pick up — and NOT fine on the money
-- path, where the caller has to decide whether to tell Roblox the receipt was
-- granted. Telling it too early means a hard crash in that window consumes the
-- receipt with the grant only ever having existed in memory: Robux taken,
-- nothing delivered, and no retry because Roblox already saw PurchaseGranted.
--
-- Caveat inherited from ProfileStore: `OnAfterSave` is shared by every
-- concurrent save of this profile, so "a save committed" is what this proves,
-- not "MY save committed". That is the guarantee the receipt path needs — any
-- committed write carries the already-mutated `Data`, including the grant.
function PersistenceService.SaveAndWait(userId: number, timeoutSeconds: number?): boolean
	if profileData.releaseNonces[userId] ~= nil then
		Log.Once(SCOPE, `save-wait-during-release-{userId}`, `SaveAndWait({userId}) refused while an intentional release is in flight`)
		return false
	end
	local session = profileData.sessions[userId]
	if session == nil or not session:IsActive() then
		Log.Warn(SCOPE, `SaveAndWait({userId}): no active session — nothing was persisted`)
		return false
	end
	local saved = false
	local conn
	conn = session.OnAfterSave:Connect(function()
		saved = true
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end)
	session:Save()
	local deadline = os.clock() + (timeoutSeconds or 10)
	while not saved and os.clock() < deadline do
		task.wait(0.2)
	end
	if conn then
		conn:Disconnect()
	end
	if not saved then
		Log.Warn(SCOPE, `SaveAndWait({userId}) timed out — the write did not confirm in time`)
	end
	return saved
end

--API
-- Ends the session (final save included) and clears the runtime cache.
-- Call exactly once when the player leaves.
--
-- `intentional` = true marks a DELIBERATE release — the pre-teleport handoff to
-- another place in the same universe. It flags PlayerProfileData.releasing so
-- OnSessionEnd suppresses the "session-taken" kick (the player is being moved
-- on purpose). Routine leave (PlayerRemoving) omits it. The flag is only set
-- while the session is still active, so OnSessionEnd is guaranteed to consume it.
function PersistenceService.Unload(userId: number, intentional: boolean?)
	local session = profileData.sessions[userId]
	if session ~= nil then
		if intentional and session:IsActive() then
			profileData.releasing[userId] = true
			profileData.released[userId] = nil
			profileData.releaseCandidates[userId] = nil
			profileData.releaseVerifying[userId] = nil
			local releaseNonce = HttpService:GenerateGUID(false)
			profileData.releaseNonces[userId] = releaseNonce
			session.RobloxMetaData["teleport-release-nonce"] = releaseNonce
			-- OnSessionEnd fires before the ending write commits, and OnAfterSave is
			-- shared by every concurrent save. Therefore OnAfterSave only unlocks a
			-- read-back attempt. VerifyReleased is the safe signal: it requires this
			-- unique nonce and a nil persisted session lock in the same stored version.
			local conn
			conn = session.OnAfterSave:Connect(function()
				if not session:IsActive() then
					-- OnAfterSave is shared by every save. This is only a candidate;
					-- VerifyReleased read-backs the persisted nonce + cleared lock before
					-- TeleportSubs may move the player.
					profileData.releaseCandidates[userId] = true
					if conn then
						conn:Disconnect()
					end
				end
			end)
		end
		session:EndSession() -- OnSessionEnd clears PlayerProfileData (+ releasing)
	end
end

--API
function PersistenceService.IsLoaded(userId: number): boolean
	return profileData.profiles[userId] ~= nil
end

--API
-- True once an INTENTIONAL pre-teleport release's ending save has COMMITTED
-- (on-disk lock cleared). This — not IsLoaded — is the safe signal that the
-- destination place can load fresh data. Used by TeleportSubs before TeleportAsync.
function PersistenceService.IsReleased(userId: number): boolean
	return profileData.released[userId] == true
end

--API
-- Yields. Confirms that the exact ending save for this handoff committed by
-- reading the profile through ProfileStore and requiring BOTH the release nonce
-- and a nil persisted session lock. A generic OnAfterSave alone is ambiguous
-- when an autosave/manual save overlaps EndSession.
function PersistenceService.VerifyReleased(userId: number): boolean
	if profileData.released[userId] == true then
		return true
	end
	local expectedNonce = profileData.releaseNonces[userId]
	if expectedNonce == nil or profileData.releaseCandidates[userId] ~= true then
		return false
	end
	if profileData.releaseVerifying[userId] == expectedNonce then
		return false
	end
	if store == nil then
		Log.Warn(SCOPE, `release verification for {userId} skipped: profile store unavailable`)
		return false
	end
	profileData.releaseVerifying[userId] = expectedNonce

	local ok, viewOrError = pcall(function()
		return store:GetAsync(tostring(userId))
	end)
	if profileData.releaseVerifying[userId] == expectedNonce then
		profileData.releaseVerifying[userId] = nil
	end
	-- This read may finish after TeleportSubs timed out and recovered the player,
	-- or even after a newer handoff began. Never let an old read prove a new
	-- generation's release.
	if profileData.releaseNonces[userId] ~= expectedNonce then
		return false
	end
	if not ok then
		Log.Warn(SCOPE, `release verification read FAILED for {userId}: {viewOrError}`)
		return false
	end
	local view = viewOrError
	if view == nil then
		Log.Warn(SCOPE, `release verification read returned nil for {userId}`)
		return false
	end
	local metadata = view.RobloxMetaData
	local persistedNonce = type(metadata) == "table" and metadata["teleport-release-nonce"] or nil
	if view.Session == nil and persistedNonce == expectedNonce then
		profileData.released[userId] = true
		Log.Info(SCOPE, `intentional release verified for {userId}`)
		return true
	end
	return false
end

--API
function PersistenceService.ClearReleaseState(userId: number)
	profileData.releasing[userId] = nil
	profileData.released[userId] = nil
	profileData.releaseCandidates[userId] = nil
	profileData.releaseNonces[userId] = nil
	profileData.releaseVerifying[userId] = nil
end

return PersistenceService
