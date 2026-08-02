--[[
	Analytics.Session — one player's instrumentation state, and the funnel
	engine that sits on top of it.

	A "session" here is the PLAYER'S session, not the server's. The game is
	two places (ADR-0009) and every lobby->game teleport ends the player on
	this server and starts them on a fresh one, so a naive per-server funnel
	would cut the initial player flow in half exactly where it gets
	interesting — the lobby half would end at "teleport started" and the game
	half would begin at "arrived" with no way to join them. The analytics
	session id is therefore MINTED in the lobby and CARRIED THROUGH the
	teleport payload, which is what makes `PlayerFlow` a single funnel from
	"joined" to "match won" across two servers.

	The flow itself is declared once in AnalyticsConfig.flowSteps and drives:

	  * `PlayerFlow`  — the custom funnel, keyed by the carried session id, so
	    it measures EVERY session including returning players.
	  * the built-in ONBOARDING funnel — lifetime, per player, de-duped by
	    Roblox and reported against D1/D7 retention. Only fired for the `new`
	    cohort: it is a first-session instrument by definition, and firing it
	    for veterans would double the budget for data Roblox throws away.
	  * `flow_step` — a custom event whose VALUE is the seconds spent on the
	    previous step. One event, every step, and it answers "where is it
	    slow" without a second funnel.
	  * `flow_stall` — the confusion signal. Each step carries a patience
	    budget; blowing it fires ONCE. This is the closest thing to "the
	    player is sitting there not knowing what to do" that telemetry can
	    honestly report.
	  * `flow_abandon` — they left mid-flow. Deliberately NOT fired when the
	    player is teleporting out: that is the flow continuing elsewhere, and
	    counting it as abandonment would make the healthiest path in the game
	    look like its worst leak.

	This state is WIRING, not game data (R1) — the same call PlayerLifecycleSubs
	makes about its own gate tables. Nothing here is authoritative, nothing is
	persisted, and losing all of it costs telemetry only.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))
local PlaceConfig = require(Shared:WaitForChild("config"):WaitForChild("PlaceConfig"))
local Sink = require(script.Parent:WaitForChild("Sink"))

local SCOPE = "Analytics"

local Session = {}

local sessions: { [number]: any } = {}
local profileData -- PlayerProfileData, for the first-session cohort
local visitSerial = 0

local FLOW = AnalyticsConfig.funnels.flow

function Session.Init(data)
	profileData = data and data.PlayerProfileData
	if profileData == nil then
		Log.Warn(SCOPE, "PlayerProfileData missing — every player will be reported in the 'unknown' cohort")
	end
end

-- ── cohort ──────────────────────────────────────────────────────────────
-- ProfileStore owns "is this their first ever session" natively
-- (SessionLoadCount), so nothing is persisted for it here. It resolves LATE:
-- PlayerAdded fires before the profile finishes loading, so the first beats
-- of the flow happen while the cohort is still unknown. Rather than guess,
-- the onboarding calls for those beats are held (see `pendingOnboarding`)
-- until the answer arrives.
--
-- ⚠ SessionLoadCount counts PROFILE loads, and a teleport is a load, so it
-- reads 2+ for a brand-new player arriving in the game place. That is why
-- the answer is carried across the handoff instead of recomputed there.
local function resolveCohort(session, player: Player): string?
	if session.cohort ~= nil then
		return session.cohort
	end
	if session.adoptedCohort ~= nil then
		session.cohort = session.adoptedCohort
		return session.cohort
	end
	local profile = profileData and profileData.sessions and profileData.sessions[player.UserId]
	local count = profile and profile.SessionLoadCount
	if type(count) ~= "number" then
		return nil -- still loading; ask again next beat
	end
	session.cohort = if count <= 1 then "new" else "returning"
	return session.cohort
end

-- ── lifecycle ───────────────────────────────────────────────────────────
--API
function Session.Begin(player: Player)
	local existing = sessions[player.UserId]
	if existing ~= nil then
		return existing
	end
	local now = os.clock()
	local session = {
		id = HttpService:GenerateGUID(false),
		place = PlaceConfig.current(),
		startedAt = now,
		joinedAtUnix = os.time(),
		cohort = nil,
		adoptedCohort = nil,
		platform = nil,
		fieldsCache = nil,
		difficulty = nil,
		roundId = nil,
		-- flow
		flowKey = nil,
		flowIndex = 0,
		flowAt = now,
		flowBase = 0, -- highest step index already logged BEFORE this server
		flowSeen = {},
		flowStalled = {},
		flowDone = false,
		pendingOnboarding = {},
		-- other funnels
		funnelSeen = {},
		visits = {},
	}
	sessions[player.UserId] = session
	Session.Adopt(player, session)
	return session
end

--API
function Session.Get(userId: number)
	return sessions[userId]
end

--API
function Session.All()
	return sessions
end

--API
function Session.End(player: Player)
	local session = sessions[player.UserId]
	sessions[player.UserId] = nil
	return session
end

--API
-- The client tells us what it is running on (touch vs mouse vs gamepad) and
-- how big its screen is. It is a segmentation field, never a gate, so an
-- unvalidated string from the client can do nothing worse than mislabel one
-- row of a breakdown — and Ingest bounds it anyway.
function Session.SetPlatform(player: Player, platform: string?)
	local session = sessions[player.UserId]
	if session and platform then
		session.platform = platform
		session.fieldsCache = nil
	end
end

--API
function Session.SetMatch(player: Player, roundId: string?, difficulty: string?)
	local session = sessions[player.UserId]
	if session == nil then
		return
	end
	session.roundId = roundId or session.roundId
	session.difficulty = difficulty or session.difficulty
end

-- ── teleport continuity ─────────────────────────────────────────────────
--API
-- Builds the block the lobby attaches to the launch TeleportData so the game
-- place can continue the SAME funnel session.
--
-- ⚠ It is an ARRAY of per-player entries, not a userId-keyed map: teleport
-- data is serialized and numeric keys come back as STRINGS (the warning in
-- Net.lua), which would turn a lookup into a silent miss and quietly split
-- every funnel in the game exactly where this code exists to stop that.
function Session.HandoffPayload(players: { Player }): { any }
	local entries = {}
	for _, player in ipairs(players) do
		local session = sessions[player.UserId]
		if session then
			table.insert(entries, {
				u = player.UserId,
				s = session.id,
				c = resolveCohort(session, player) or "unknown",
				i = session.flowIndex,
				p = session.platform,
				-- WALL time of the last step, so the destination can report an
				-- honest dwell for the first step it logs. Without it the
				-- teleport's own latency — one of the longest waits in the
				-- whole flow — is systematically reported as zero, because
				-- `os.clock()` restarts with the process on the new server.
				t = os.time() - math.floor(os.clock() - session.flowAt),
			})
		end
	end
	return entries
end

--API
-- Reads this player's entry back out of the arriving TeleportData. Anything
-- malformed simply leaves a fresh session in place — a split funnel is a
-- reporting problem, never a gameplay one, so nothing here may throw.
function Session.Adopt(player: Player, session)
	session = session or sessions[player.UserId]
	if session == nil then
		return false
	end
	local ok, joinData = pcall(player.GetJoinData, player)
	if not ok or type(joinData) ~= "table" then
		return false
	end
	local teleportData = joinData.TeleportData
	local entries = type(teleportData) == "table" and teleportData.analytics
	if type(entries) ~= "table" then
		return false
	end
	for _, entry in pairs(entries) do
		if type(entry) == "table" and entry.u == player.UserId then
			if type(entry.s) == "string" and entry.s ~= "" then
				session.id = entry.s
			end
			if entry.c == "new" or entry.c == "returning" then
				session.adoptedCohort = entry.c
				session.fieldsCache = nil
			end
			if type(entry.i) == "number" and entry.i > 0 then
				-- Steps already logged upstream. Suppressing them by INDEX
				-- (rather than shipping the whole seen-set) is enough because
				-- everything before "arrive" is lobby-only anyway.
				session.flowBase = math.floor(entry.i)
				session.flowIndex = math.max(session.flowIndex, session.flowBase)
			end
			if type(entry.p) == "string" then
				session.platform = entry.p
			end
			if type(entry.t) == "number" then
				-- Rebase the dwell clock onto the previous step's real time.
				-- `os.clock()` is per-process, so it cannot cross a teleport;
				-- the wall gap is converted back into this process's clock.
				local elapsed = math.max(0, os.time() - entry.t)
				session.flowAt = os.clock() - elapsed
			end
			Log.Info(SCOPE, `{player.Name}: adopted analytics session {session.id} (cohort {tostring(session.adoptedCohort)}, resuming after flow step {session.flowBase})`)
			return true
		end
	end
	return false
end

-- ── the flow ────────────────────────────────────────────────────────────
-- The cohort/platform/place triple, CACHED per session. It is read on every
-- event — including the bite path, which runs at eat-rate per player — and a
-- fresh three-element table per call is pure garbage. Rebuilt only when one of
-- its three inputs actually changes; the sink only ever reads it.
local function flowFields(session, player: Player): { any }
	local cohort = resolveCohort(session, player) or "unknown"
	local platform = session.platform or "unknown"
	local cached = session.fieldsCache
	if cached ~= nil and cached[1] == cohort and cached[2] == platform then
		return cached
	end
	cached = { cohort, platform, session.place }
	session.fieldsCache = cached
	return cached
end

local function drainPendingOnboarding(session, player: Player)
	if #session.pendingOnboarding == 0 then
		return
	end
	local cohort = resolveCohort(session, player)
	if cohort == nil then
		return -- still unknown; try again on the next beat
	end
	local queued = session.pendingOnboarding
	session.pendingOnboarding = {}
	if cohort ~= "new" then
		return -- veteran: Roblox would de-dupe these away anyway
	end
	for _, item in ipairs(queued) do
		Sink.Onboarding(player, item.index, item.name)
	end
end

-- Held beats are drained BEFORE the current one is sent, so the lifetime
-- onboarding funnel receives its steps in order on the beat where the cohort
-- finally resolves (it is a progression funnel; out-of-order steps read as a
-- player who skipped the middle).
local function onboard(session, player: Player, index: number, name: string)
	local cohort = resolveCohort(session, player)
	if cohort == nil then
		if #session.pendingOnboarding < 8 then
			table.insert(session.pendingOnboarding, { index = index, name = name })
		else
			Log.Once(
				SCOPE,
				`onboard-backlog-{player.UserId}`,
				`{player.Name}: profile still unloaded after 8 flow beats — later onboarding steps are being dropped `
					.. `(the PlayerFlow funnel is unaffected; only the lifetime onboarding funnel loses them)`
			)
		end
		return
	end
	drainPendingOnboarding(session, player)
	if cohort == "new" then
		Sink.Onboarding(player, index, name)
	end
end

--API
-- Records one beat of the initial player flow. Idempotent per session: the
-- second call for a step is dropped, which is what makes it safe to fire
-- these from wherever the truth actually is (a remote handler, a physics
-- scan, a UI callback) without every caller having to remember whether it
-- already happened.
function Session.Flow(player: Player, stepKey: string): boolean
	local session = sessions[player.UserId]
	if session == nil then
		-- Never silent (R8): the only way here is a domain sub firing a beat
		-- before AnalyticsSubs.Start armed, or after the player left — both
		-- ordering bugs that would otherwise just show as a missing funnel.
		Log.Once(SCOPE, `no-session-{player.UserId}`, `{player.Name}: flow beat '{stepKey}' arrived with no analytics session — dropped (fired before Start, or after the player left?)`)
		return false
	end
	local step = AnalyticsConfig.FlowStep(stepKey)
	local index = AnalyticsConfig.FlowIndex(stepKey)
	if step == nil or index == nil then
		Log.Once(SCOPE, `bad-flow-{stepKey}`, `unknown flow step '{stepKey}' — NOT logged (add it to AnalyticsConfig.flowSteps)`)
		return false
	end
	if session.flowSeen[stepKey] or index <= session.flowBase then
		return false
	end
	session.flowSeen[stepKey] = true

	local now = os.clock()
	local dwell = math.max(0, now - session.flowAt)
	session.flowAt = now
	session.flowKey = stepKey
	session.flowIndex = math.max(session.flowIndex, index)
	if index >= #AnalyticsConfig.flowSteps then
		session.flowDone = true
	end

	local fields = flowFields(session, player)
	-- The DWELL is the value: one event name answers "how long did each step
	-- take" for all 31 steps at once, which no amount of extra event names
	-- could buy inside the 100-name budget.
	Sink.Custom(player, "flow-step", math.floor(dwell * 10) / 10, { stepKey, fields[1], session.place }, {
		tier = "critical",
	})
	Sink.Funnel(player, FLOW.name, session.id, index, step.name, fields)

	-- The onboarding funnel is lifetime and first-session-only. While the
	-- cohort is still unresolved the call is HELD rather than guessed at.
	onboard(session, player, index, step.name)

	Log.Info(SCOPE, `{player.Name}: flow {index}/{#AnalyticsConfig.flowSteps} '{stepKey}' (+{string.format("%.1f", dwell)}s)`)
	return true
end

--API
-- Emits `flow_stall` for anyone who has sat on the same step past its
-- patience budget. Called from the sink tick, never per frame.
function Session.CheckStalls(now: number)
	for userId, session in pairs(sessions) do
		local key = session.flowKey
		if key ~= nil and not session.flowDone and not session.flowStalled[key] then
			local step = AnalyticsConfig.FlowStep(key)
			local budget = step and step.stallSeconds
			if budget ~= nil and now - session.flowAt >= budget then
				session.flowStalled[key] = true
				local player = Players:GetPlayerByUserId(userId)
				if player then
					Sink.Custom(player, "flow-stall", math.floor(now - session.flowAt), {
						key,
						session.cohort or "unknown",
						session.place,
					}, { tier = "critical" })
					Log.Info(SCOPE, `{player.Name}: STALLED on flow step '{key}' for {math.floor(now - session.flowAt)}s`)
				end
			end
		end
	end
end

--API
-- Called on leave. `handedOff` is true when the player is mid-teleport, in
-- which case the flow is continuing on the destination server and this is
-- emphatically NOT an abandonment.
function Session.ReportExit(player: Player, handedOff: boolean)
	local session = sessions[player.UserId]
	if session == nil then
		return
	end
	if not handedOff and not session.flowDone and session.flowKey ~= nil then
		Sink.Custom(player, "flow-abandon", session.flowIndex, {
			session.flowKey,
			session.cohort or "unknown",
			session.place,
		}, { tier = "critical" })
	end
end

-- ── the other funnels ───────────────────────────────────────────────────
--API
-- Starts a new attempt at a recurring funnel (a shop visit, a gym session, a
-- queue). Returns the funnelSessionId. Roblox uses it to tell one attempt
-- from the next, so a player who opens the shop five times is five attempts,
-- not one attempt with five step-1s.
function Session.BeginVisit(player: Player, funnelKey: string, explicitId: string?): string?
	local session = sessions[player.UserId]
	if session == nil then
		return nil
	end
	visitSerial += 1
	local id = explicitId or `{player.UserId}-{funnelKey}-{visitSerial}`
	session.visits[funnelKey] = id
	session.funnelSeen[funnelKey] = {}
	return id
end

--API
-- One step of any catalog funnel. The session id comes from the funnel's
-- declared `session` mode, so callers never have to know which funnels are
-- one-per-session and which recur.
function Session.Funnel(player: Player, funnelKey: string, stepKey: string): boolean
	local session = sessions[player.UserId]
	if session == nil then
		return false
	end
	local funnel = AnalyticsConfig.funnels[funnelKey]
	if funnel == nil then
		Log.Once(SCOPE, `bad-funnel-{funnelKey}`, `unknown funnel '{funnelKey}' — NOT logged (add it to AnalyticsConfig.funnels)`)
		return false
	end
	local index, stepName
	for position, step in ipairs(funnel.steps) do
		if step.key == stepKey then
			index, stepName = position, step.name
			break
		end
	end
	if index == nil then
		Log.Once(SCOPE, `bad-step-{funnelKey}-{stepKey}`, `unknown step '{stepKey}' in funnel '{funnelKey}' — NOT logged`)
		return false
	end

	-- Landing on a recurring funnel's FIRST step opens a new attempt. Without
	-- this rule the seen-set from the player's first shop visit would suppress
	-- every step of their second, third and fortieth — the funnel would show
	-- one visit per session and the conversion rate would be nonsense. It is
	-- done here, once, rather than by asking every caller to remember a
	-- BeginVisit call it will eventually forget.
	if funnel.session == "visit" and funnel.steps[1] ~= nil and funnel.steps[1].key == stepKey then
		Session.BeginVisit(player, funnelKey)
	end

	local seen = session.funnelSeen[funnelKey]
	if seen == nil then
		seen = {}
		session.funnelSeen[funnelKey] = seen
	end
	if seen[stepKey] then
		-- Roblox ignores a repeated step but still charges it against the
		-- rate limit, so the repeat is refused HERE where it is free.
		return false
	end
	seen[stepKey] = true

	local sessionId
	if funnel.session == "flow" then
		sessionId = session.id
	elseif funnel.session == "round" then
		sessionId = session.roundId or session.id
	else
		sessionId = session.visits[funnelKey]
		if sessionId == nil then
			-- A mid-funnel step with no attempt open (the player was already
			-- in the shop when this server started instrumenting them, say).
			-- Open one rather than dropping the step.
			sessionId = Session.BeginVisit(player, funnelKey)
			seen = session.funnelSeen[funnelKey]
			seen[stepKey] = true
		end
	end

	return Sink.Funnel(player, funnel.name, sessionId or session.id, index, stepName, {
		resolveCohort(session, player) or "unknown",
		session.platform or "unknown",
		session.difficulty or session.place,
	})
end

--API
-- The cohort/platform/place triple every custom event wants for its
-- breakdowns, resolved for one player. Returns "unknown" rather than nil so
-- a missing answer is a visible bucket instead of an absent field.
function Session.Fields(player: Player): { any }
	local session = sessions[player.UserId]
	if session == nil then
		return { "unknown", "unknown", PlaceConfig.current() }
	end
	return flowFields(session, player)
end

--API
function Session.Cohort(player: Player): string
	local session = sessions[player.UserId]
	if session == nil then
		return "unknown"
	end
	return resolveCohort(session, player) or "unknown"
end

--API
-- Nudges any held onboarding calls once the profile lands. Cheap, and it
-- keeps the first three beats of a brand-new player's funnel from being lost
-- to a race with the DataStore.
function Session.OnProfileLoaded(player: Player)
	local session = sessions[player.UserId]
	if session then
		drainPendingOnboarding(session, player)
	end
end

return Session
