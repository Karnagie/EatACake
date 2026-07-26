--[[
	PlayerRuntimeData — per-player RUNTIME state (never persisted):
	  biteTokens   — { [userId] = { tokens, lastRefill } } anti-cheat token
	                 bucket for EatAt (refill = eat rate * slack)
	  gymSessions  — { [userId] = { startFill, startStored, gymEff, burned01,
	                 pendingTaps, tapsTotal, bankedInt, lastFill, lastStored,
	                 startedAt } } live fat-burn sessions (GymService operates on
	                 these; gymEff is locked at start, lastFill/lastStored track
	                 the drain's own contribution)
	  lastAutoBurn — { [userId] = unix } auto-gym pacing
	  lastMorphFill— { [userId] = number } last replicated StomachFill attr
	                 (BodySubs skips redundant attribute writes)

	  returnCooldown -- { [userId] = os.clock timestamp } checkpoint debounce

	Entries are cleared on PlayerRemoving (PlayerLifecycleSubs).
]]

local PlayerRuntimeData = {}

PlayerRuntimeData.biteTokens = {} :: { [number]: { tokens: number, lastRefill: number } }
PlayerRuntimeData.gymSessions = {} :: {
	[number]: {
		startFill: number,
		startStored: number,
		gymEff: number,
		burned01: number,
		pendingTaps: number,
		tapsTotal: number,
		bankedInt: number,
		lastFill: number,
		lastStored: number,
		startedAt: number,
	},
}
PlayerRuntimeData.lastAutoBurn = {} :: { [number]: number }
PlayerRuntimeData.lastMorphFill = {} :: { [number]: number }
PlayerRuntimeData.returnCooldown = {} :: { [number]: number }

--API
function PlayerRuntimeData.Clear(userId: number)
	PlayerRuntimeData.biteTokens[userId] = nil
	PlayerRuntimeData.gymSessions[userId] = nil
	PlayerRuntimeData.lastAutoBurn[userId] = nil
	PlayerRuntimeData.lastMorphFill[userId] = nil
	PlayerRuntimeData.returnCooldown[userId] = nil
end

return PlayerRuntimeData
