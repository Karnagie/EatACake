--[[
	PlayerRuntimeData — per-player RUNTIME state (never persisted):
	  biteTokens   — { [userId] = { tokens, lastRefill } } anti-cheat token
	                 bucket for EatAt (refill = eat rate * slack)
	  gymSessions  — { [userId] = { startedAt, taps, lastTapAt } } live mash
	                 sessions (GymService logic operates on these)
	  lastAutoBurn — { [userId] = unix } auto-gym pacing
	  lastMorphFill— { [userId] = number } last replicated StomachFill attr
	                 (BodySubs skips redundant attribute writes)

	Entries are cleared on PlayerRemoving (PlayerLifecycleSubs).
]]

local PlayerRuntimeData = {}

PlayerRuntimeData.biteTokens = {} :: { [number]: { tokens: number, lastRefill: number } }
PlayerRuntimeData.gymSessions = {} :: { [number]: { startedAt: number, taps: number, lastTapAt: number } }
PlayerRuntimeData.lastAutoBurn = {} :: { [number]: number }
PlayerRuntimeData.lastMorphFill = {} :: { [number]: number }

--API
function PlayerRuntimeData.Clear(userId: number)
	PlayerRuntimeData.biteTokens[userId] = nil
	PlayerRuntimeData.gymSessions[userId] = nil
	PlayerRuntimeData.lastAutoBurn[userId] = nil
	PlayerRuntimeData.lastMorphFill[userId] = nil
end

return PlayerRuntimeData
