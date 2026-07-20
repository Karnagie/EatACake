--[[
	GymService — fat-burn session math (GDD §8, reworked). R2: session state
	lives in PlayerRuntimeData.gymSessions; writing the belly + banking calories
	is orchestrated by BodySubs (it owns the profile + economy services).

	The model (the user's spec): pressing the gym prompt starts a session that
	captures the belly's START fill/stored as the BASELINE and LOCKS gymEff. A
	single burn progress `burned01` runs 0..1; at burned01 = 1 the baseline is
	fully burned and ALL captured stored has banked. Progress advances two ways:
	  * PASSIVE — `burnSpeed` (fraction/sec) × dt every server tick
	  * per TAP — `burnPerTap` (fraction) per registered tap
	`instantBurn` seeds burned01 at StartSession (a slice removed on press; the
	final tier seeds 1.0 = whole belly instantly). Each step reports the drain's
	OWN delta (dFill/dStored) and BodySubs SUBTRACTS it from the current belly —
	so a bite taken mid-session (the cake edge is reachable from the gym) survives
	instead of being clobbered by a baseline overwrite. Banking is monotone: we
	track the integer banked-so-far and hand BodySubs the DELTA each step, so the
	total is exactly floor(startStored × gymEff) with no drift or double-count
	(gymEff is fixed at start, so it can't be nudged mid-burn).

	Anti-cheat (GDD §13): taps are counted SERVER-side and capped at
	tapsPerSecondCap × elapsed. Note there is no economic exploit in fast tapping
	— taps only drain the player's OWN belly (a bounded pool); banking can never
	exceed startStored × gymEff however fast the taps arrive. The cap just bounds
	per-tick work and keeps pacing honest.
]]

local GymService = {}

local runtime -- PlayerRuntimeData
local bodyCfg

function GymService.Init(data)
	runtime = data.PlayerRuntimeData
	bodyCfg = data.CakeConfigData.body
end

-- Resolve the session's current burned01, advance the banked-so-far marker, and
-- return the step result BodySubs applies. Reports the drain's OWN delta this
-- step (dFill/dStored) rather than absolute belly values — BodySubs SUBTRACTS
-- them from the CURRENT belly, so a bite taken mid-session (you can reach the
-- cake edge from the gym) isn't clobbered by a baseline overwrite.
local function apply(session)
	local b = math.clamp(session.burned01, 0, 1)
	session.burned01 = b
	local remain = 1 - b
	local newFill = session.startFill * remain
	local newStored = session.startStored * remain
	-- Never negative — burned01 only rises, so lastFill/lastStored only fall.
	local dFill = math.max(0, session.lastFill - newFill)
	local dStored = math.max(0, session.lastStored - newStored)
	session.lastFill = newFill
	session.lastStored = newStored
	-- gymEff is LOCKED at StartSession (no mid-burn re-read), so bankTarget is
	-- monotone in b and the integer delta sums to exactly floor(startStored ×
	-- gymEff) — no drift, no double-count.
	local bankTarget = math.floor(session.startStored * session.gymEff * b)
	local bankDelta = bankTarget - session.bankedInt
	session.bankedInt = bankTarget
	return {
		burned01 = b,
		dFill = dFill, -- belly VOLUME to remove THIS step (drain's own contribution)
		dStored = dStored, -- unbanked calories to remove THIS step
		bankDelta = bankDelta, -- integer calories to credit THIS step
		bankedTotal = bankTarget, -- integer calories banked across the session so far
		complete = b >= 1,
	}
end

--API
-- Opens a session from the belly baseline, seeding burned01 with `instantBurn01`
-- (the instant-burn upgrade). Returns the initial step result (the instant-burn
-- slice as dFill/dStored/bankDelta) — BodySubs applies it and, if `complete`,
-- ends the session (final instant-burn tier clears everything on press).
function GymService.StartSession(userId: number, startFill: number, startStored: number, instantBurn01: number, gymEff: number)
	local sf = math.max(0, startFill)
	local ss = math.max(0, startStored)
	local session = {
		startFill = sf,
		startStored = ss,
		gymEff = gymEff, -- locked in at start (banking is stable to mid-burn upgrade buys)
		burned01 = math.clamp(instantBurn01 or 0, 0, 1),
		pendingTaps = 0,
		tapsTotal = 0,
		bankedInt = 0,
		lastFill = sf, -- belly BEFORE the instant-burn slice (apply computes its delta)
		lastStored = ss,
		startedAt = os.clock(),
	}
	runtime.gymSessions[userId] = session
	return apply(session)
end

--API
-- Registers one tap (accumulated into pendingTaps, consumed on the next Advance).
-- Silently ignores taps outside a session or beyond the per-second cap — the
-- client UI can only desync, never profit (see the anti-cheat note above).
function GymService.RegisterTap(userId: number)
	local session = runtime.gymSessions[userId]
	if not session then
		return
	end
	local elapsed = os.clock() - session.startedAt
	if session.tapsTotal >= bodyCfg.gym.tapsPerSecondCap * elapsed + 2 then
		return -- over the cap (+2 burst allowance)
	end
	session.tapsTotal += 1
	session.pendingTaps += 1
end

--API
-- Advances the session by `dt` seconds: passive burnSpeed drain + any pending
-- taps × burnPerTap. Returns the step result (dFill/dStored/bankDelta/complete),
-- or nil when there is no session. gymEff is captured at StartSession, not here.
function GymService.Advance(userId: number, dt: number, burnSpeed: number, burnPerTap: number)
	local session = runtime.gymSessions[userId]
	if not session then
		return nil
	end
	session.burned01 += burnSpeed * dt + session.pendingTaps * burnPerTap
	session.pendingTaps = 0
	return apply(session)
end

--API
function GymService.HasSession(userId: number): boolean
	return runtime.gymSessions[userId] ~= nil
end

--API
-- Ends the session (belly stays at its already-drained state). Idempotent.
function GymService.EndSession(userId: number)
	runtime.gymSessions[userId] = nil
end

return GymService
