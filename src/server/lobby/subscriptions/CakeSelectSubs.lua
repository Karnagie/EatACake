--[[
	CakeSelectSubs — cake catalogue domain, server side (R4). features/cake-select.md.

	The server owns TWO facts; the client only renders the answer it is pushed:
	  * WHICH cake is chosen — profile section `cakes.selected` (CakesSection).
	  * WHICH cakes are unlocked — DERIVED per push from the player's lifetime
	    `progress.cakesEaten` against each cake's `unlockRule`
	    (CakeSelectConfig). Entitlement is never stored, so there is no second
	    truth free to drift and no backfill: an account that has already eaten a
	    cake is entitled the moment this ships.

	LOBBY partition: cakes are picked in the hub, so the remote handler exists
	only there. The `cakes` SECTION is common (server/common/data/ProfileSchema)
	because the game place loads the same profile and must not drop the key.

	CakeSelectUpdate payload: { selected = cakeId, unlocked = { cakeId, ... } }
	⚠ `unlocked` is an ARRAY, never a map — RemoteEvent serialization stringifies
	numeric table keys. It is built by walking `CakeSelectConfig.order`, so the
	client gets catalogue order for free.

	SelectCake carries one argument: the cake id. Unlike TutorialComplete (whose
	flag only SUPPRESSES a tutorial), trusting this would GRANT content, so R6 is
	enforced in full — string, catalogue key, and unlocked FOR THIS ACCOUNT.
	Every rejection RE-PUSHES the authoritative state, so a desynced client is
	corrected rather than left believing its own lie — with ONE exception it
	cannot cover: if the profile is not loaded there is nothing to build a push
	from, so a tap in that (seconds-wide, pre-teleport) window leaves the client
	showing its optimistic guess until the next join replays PushInitialState.

	⚠ A rule this module does not recognise is treated as LOCKED and warned
	about, never silently granted — adding a rule kind to the catalogue means
	teaching `unlockedFor` about it.

	The queue remains cake-agnostic while the player configures it. At launch,
	LobbyQueue/Launch snapshots the leader's persisted choice into protocol-v2
	TeleportData; the game validates it as a playable CakeConfig variant. See
	features/cake-select.md and ADR-0020.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local CakeSelectConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeSelectConfig"))

local SCOPE = "CakeSelectSubs"

local CakeSelectSubs = {}

local profileData
local ProgressService
local uCakeSelect

-- The `cakes` section is materialised from CakesSection's defaults on load, so a
-- nil here is a SCHEMA wiring failure (section file missing / failed to require),
-- not a player state — one warn for the whole server, then read-only degrade.
local function cakesSection(profile)
	local section = profile.cakes
	if type(section) ~= "table" then
		Log.Once(
			SCOPE,
			"cakes-section-missing",
			`profile.cakes is missing (ProfileSchema/CakesSection did not load?) — selection cannot be read or written; everyone falls back to '{CakeSelectConfig.defaultId}'`
		)
		return nil
	end
	return section
end

-- Entitlement for ONE cake, as (unlocked, evaluated).
--
-- FAILS CLOSED on `unlocked`: an unknown rule, a "cakes-eaten" rule without its
-- threshold, or an unavailable ProgressService all mean LOCKED plus a warn (R8)
-- — never a silent grant.
--
-- ⚠ `evaluated` is why this returns two values instead of one, and the
-- distinction is load-bearing. "Locked because the player has not earned it" and
-- "locked because this build could not work out the answer" are the same answer
-- on the WIRE (render the card locked — harmless, self-heals next push) and very
-- different answers on the WRITE path: OnProfileLoaded persists its coercion
-- into an auto-saving profile, so treating a CONFIG error as a real lock would
-- silently destroy the stored pick of every player who chose that cake, and
-- reverting the config could not bring it back. Only an explicit
-- `evaluated = true, unlocked = false` may cause a write.
local function isUnlocked(cakeId: string, def, userId: number): (boolean, boolean)
	local rule = def.unlockRule
	if rule == "none" then
		return true, true
	end
	-- A teaser slot: recognised, always locked, and EVALUATED — "this cake does
	-- not exist yet" is a real answer, not a failure to compute one. That matters
	-- twice: it must not trip the unknown-rule warning below, and OnProfileLoaded
	-- must be allowed to coerce a stored selection that names it.
	if rule == "coming-soon" then
		return false, true
	end
	if rule == "cakes-eaten" then
		if ProgressService == nil then
			Log.Once(SCOPE, "progress-service-missing", "ProgressService unavailable — every 'cakes-eaten' cake stays LOCKED")
			return false, false
		end
		local required = def.unlockCakesEaten
		if type(required) ~= "number" then
			Log.Once(
				SCOPE,
				`rule-threshold-{cakeId}`,
				`'{cakeId}' uses unlockRule 'cakes-eaten' with no numeric unlockCakesEaten — treated as LOCKED`
			)
			return false, false
		end
		return ProgressService.CakesEaten(userId) >= required, true
	end
	Log.Once(
		SCOPE,
		`rule-unknown-{cakeId}`,
		`'{cakeId}': unknown unlockRule '{tostring(rule)}' — treated as LOCKED (teach {SCOPE} the rule before shipping it)`
	)
	return false, false
end

-- Returns the payload ARRAY and a membership set for validation. Allocates fresh
-- tables every call and mutates nothing, so replaying a push is free of
-- side effects.
local function unlockedFor(userId: number): ({ string }, { [string]: boolean })
	local list: { string } = {}
	local set: { [string]: boolean } = {}
	for _, cakeId in ipairs(CakeSelectConfig.order) do
		local def = CakeSelectConfig.cakes[cakeId]
		if def == nil then
			Log.Once(SCOPE, `order-orphan-{cakeId}`, `CakeSelectConfig.order lists '{cakeId}' with no .cakes entry — skipped`)
		elseif isUnlocked(cakeId, def, userId) then
			table.insert(list, cakeId)
			set[cakeId] = true
		end
	end
	return list, set
end

-- READ-ONLY coercion for the wire: a stored id that is not a catalogue key is
-- reported as the default rather than echoed back. Repairing the stored value is
-- OnProfileLoaded's job — a push must never mutate (it is replayed).
local function selectedFor(section): string
	local stored = section and section.selected
	if type(stored) == "string" and CakeSelectConfig.cakes[stored] ~= nil then
		return stored
	end
	return CakeSelectConfig.defaultId
end

local function push(player: Player, profile)
	local unlocked = unlockedFor(player.UserId)
	local selected = selectedFor(cakesSection(profile))
	uCakeSelect:FireClient(player, { selected = selected, unlocked = unlocked })
	Log.Info(SCOPE, `{player.Name}: selected '{selected}', unlocked {#unlocked}/{#CakeSelectConfig.order}`)
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load +
-- ClientReady. IDEMPOTENT — it reads and sends, it never writes — so the
-- teleport resync can replay it as often as it likes.
function CakeSelectSubs.PushInitialState(player: Player)
	if uCakeSelect == nil then
		Log.Warn(SCOPE, `PushInitialState({player.Name}) before Start ran — push dropped`)
		return
	end
	local profile = profileData.Get(player.UserId)
	if not profile then
		Log.Warn(SCOPE, `PushInitialState({player.Name}): profile not loaded — push dropped, the catalogue stays unrendered`)
		return
	end
	push(player, profile)
end

--API
-- Profile-loaded hook: PlayerLifecycleSubs calls this BEFORE anything is pushed,
-- so the client is never shown a selection the server is about to correct.
--
-- CakesSection.sanitize already coerces an UNKNOWN id at load, but it cannot
-- coerce a LOCKED one — a section only ever sees its own slice and can never
-- read `progress`. Entitlement is therefore repaired HERE, where it is known.
-- This is what covers a cake whose unlock rule is TIGHTENED after players have
-- already picked it.
function CakeSelectSubs.OnProfileLoaded(player: Player)
	if profileData == nil then
		Log.Warn(SCOPE, `OnProfileLoaded({player.Name}) before Start ran — stored selection NOT validated`)
		return
	end
	local profile = profileData.Get(player.UserId)
	if not profile then
		Log.Warn(SCOPE, `OnProfileLoaded({player.Name}): profile not loaded — stored selection NOT validated`)
		return
	end
	local section = cakesSection(profile)
	if section == nil then
		return -- cakesSection already warned (R8)
	end
	local stored = section.selected
	local def = if type(stored) == "string" then CakeSelectConfig.cakes[stored] else nil
	local reason
	if def == nil then
		reason = "is not a catalogue id"
	else
		local unlocked, evaluated = isUnlocked(stored, def, player.UserId)
		if not evaluated then
			-- Could not compute entitlement (unknown rule / bad threshold / no
			-- ProgressService). This is the ONE branch that must not write: the
			-- push path already renders the card locked for this session, which
			-- is recoverable, whereas overwriting `selected` here would autosave
			-- and permanently destroy a choice a config fix could not restore.
			Log.Warn(
				SCOPE,
				`{player.Name}: entitlement for stored selection '{tostring(stored)}' could NOT be evaluated — `
					.. `left untouched on the profile (it will render locked until the catalogue is fixed)`
			)
			return
		end
		if not unlocked then
			reason = "is no longer unlocked for this account"
		end
	end
	if reason == nil then
		return
	end
	section.selected = CakeSelectConfig.defaultId
	Log.Warn(SCOPE, `{player.Name}: stored selection '{tostring(stored)}' {reason} — coerced to '{CakeSelectConfig.defaultId}'`)
end

function CakeSelectSubs.Start(data, services)
	profileData = data.PlayerProfileData
	ProgressService = services.ProgressService
	uCakeSelect = Net.Update("CakeSelectUpdate")
	if ProgressService == nil then
		Log.Warn(SCOPE, "ProgressService missing — no 'cakes-eaten' cake can ever unlock (every account sees only the always-on cakes)")
	end

	-- ECHO THROTTLE. Every inbound SelectCake answers with an outbound push, so
	-- an unthrottled modded client turns one packet into two plus two fresh
	-- tables per call — this handler AMPLIFIES, which its neighbours (SettingsSubs)
	-- do not. Validation is never skipped, only the confirming echo, and only
	-- when one already went out moments ago; a real change always forces one
	-- through so an accepted pick is never left unconfirmed.
	local ECHO_MIN_INTERVAL = 0.25
	local lastEcho: { [number]: number } = {}
	local function echo(player: Player, profile, force: boolean?)
		local userId = player.UserId
		local now = os.clock()
		if not force and (now - (lastEcho[userId] or -math.huge)) < ECHO_MIN_INTERVAL then
			return
		end
		lastEcho[userId] = now
		push(player, profile)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastEcho[player.UserId] = nil
	end)

	Net.Remote("SelectCake").OnServerEvent:Connect(function(player, cakeId)
		local userId = player.UserId
		local profile = profileData.Get(userId)
		if not profile then
			-- Same window as TutorialSubs: a client-fired remote with no rate
			-- limit, and the profile-nil gap is seconds wide during the
			-- lobby→game handoff — keyed Once, not an unthrottled Warn, so a
			-- looping client cannot bury the boot report.
			Log.Once(SCOPE, `select-preload-{userId}`, `SelectCake({player.Name}): profile not loaded — selection NOT written`)
			return
		end
		-- R6: `cakeId` is whatever the client sent. Both rejections below are
		-- keyed per PLAYER (not per id — an exploiter can vary the id forever)
		-- and both RE-PUSH, so the client is resynced on every attempt even
		-- though only the first is logged.
		if type(cakeId) ~= "string" or CakeSelectConfig.cakes[cakeId] == nil then
			Log.Once(
				SCOPE,
				`select-unknown-{userId}`,
				`SelectCake({player.Name}): '{tostring(cakeId)}' is not a catalogue id — REJECTED, authoritative state re-pushed`
			)
			echo(player, profile)
			return
		end
		local _, unlockedSet = unlockedFor(userId)
		if not unlockedSet[cakeId] then
			Log.Once(
				SCOPE,
				`select-locked-{userId}`,
				`SelectCake({player.Name}): '{cakeId}' is LOCKED for this account — REJECTED, authoritative state re-pushed`
			)
			echo(player, profile)
			return
		end
		local section = cakesSection(profile)
		if section == nil then
			-- The schema is broken, but the client has ALREADY patched its
			-- mirror optimistically. Re-push so it falls back to what the server
			-- actually believes (selectedFor(nil) answers the default) rather
			-- than standing on a pick nothing stored.
			echo(player, profile)
			return -- cakesSection already warned (R8)
		end
		local changed = false
		if section.selected ~= cakeId then
			local previous = tostring(section.selected)
			section.selected = cakeId
			changed = true
			-- No explicit PersistenceService.Save: a PREFERENCE auto-saves while
			-- the session is live (P4/P5, ProfileStore autosave + the final save
			-- on leave). Losing it to a crash costs one re-pick, not currency —
			-- Save is reserved for Robux milestones.
			Log.Info(SCOPE, `{player.Name}: cake '{previous}' -> '{cakeId}'`)
		end
		-- Confirm, and repair a client that dropped an update. A real change
		-- FORCES the echo past the throttle: an accepted pick must never be
		-- left unconfirmed.
		echo(player, profile, changed)
	end)

	-- Config sanity (R8): the coercion target must exist and must be reachable by
	-- EVERY account, or a rejected selection would be replaced by another locked
	-- one and the player would end up with no cake at all.
	local defaultDef = CakeSelectConfig.cakes[CakeSelectConfig.defaultId]
	if defaultDef == nil then
		Log.Warn(SCOPE, `defaultId '{tostring(CakeSelectConfig.defaultId)}' has no .cakes entry — coercion has NO valid target`)
	elseif defaultDef.unlockRule ~= "none" then
		Log.Warn(SCOPE, `default cake '{CakeSelectConfig.defaultId}' has unlockRule '{tostring(defaultDef.unlockRule)}' (not "none") — a fresh account could have NO selectable cake`)
	end
	for cakeId in pairs(CakeSelectConfig.cakes) do
		if not table.find(CakeSelectConfig.order, cakeId) then
			Log.Warn(SCOPE, `'{cakeId}' is in .cakes but not in .order — it is unreachable and will never be pushed`)
		end
	end

	Log.Info(SCOPE, `cake catalogue armed (lobby place) — {#CakeSelectConfig.order} cake(s), default '{CakeSelectConfig.defaultId}'`)
end

return CakeSelectSubs
