--[[
	GymService — mash-minigame session logic (GDD §8). R2: state lives in
	PlayerRuntimeData.gymSessions; the burn itself is StomachService's job
	(BodySubs orchestrates both).

	Anti-cheat (GDD §13): taps are counted SERVER-side per event, capped at
	gym.tapsPerSecondCap × duration; the result is computed from the server
	count, never from a client-reported total.
]]

local GymService = {}

local runtime -- PlayerRuntimeData
local bodyCfg

function GymService.Init(data)
	runtime = data.PlayerRuntimeData
	bodyCfg = data.CakeConfigData.body
end

--API
-- Starts a session. Returns false + reason when refused.
function GymService.StartSession(userId: number): (boolean, string?)
	local existing = runtime.gymSessions[userId]
	local now = os.clock()
	if existing then
		if now - existing.startedAt < bodyCfg.gym.duration + bodyCfg.gym.cooldown then
			return false, "already-active"
		end
		runtime.gymSessions[userId] = nil
	end
	runtime.gymSessions[userId] = { startedAt = now, taps = 0, lastTapAt = 0 }
	return true
end

--API
-- Registers one tap. Silently ignores taps beyond the per-second cap or
-- outside a session (the client UI can only desync, not profit).
function GymService.RegisterTap(userId: number)
	local session = runtime.gymSessions[userId]
	if not session then
		return
	end
	local now = os.clock()
	local elapsed = now - session.startedAt
	if elapsed > bodyCfg.gym.duration then
		return -- window over; FinishDue will close it
	end
	-- Cap: total taps may never exceed cap × elapsed (+1 burst allowance).
	if session.taps >= bodyCfg.gym.tapsPerSecondCap * elapsed + 1 then
		return
	end
	session.taps += 1
	session.lastTapAt = now
end

--API
-- True when the player's session window has expired and awaits payout.
function GymService.IsFinishDue(userId: number): boolean
	local session = runtime.gymSessions[userId]
	return session ~= nil and os.clock() - session.startedAt >= bodyCfg.gym.duration
end

--API
-- Closes the session and returns the mash bonus multiplier
-- (1.0 .. gym.maxBonus by tap count). nil = no session.
function GymService.FinishSession(userId: number): number?
	local session = runtime.gymSessions[userId]
	if not session then
		return nil
	end
	runtime.gymSessions[userId] = nil
	local t = math.clamp(session.taps / bodyCfg.gym.perfectTaps, 0, 1)
	return 1 + (bodyCfg.gym.maxBonus - 1) * t
end

return GymService
