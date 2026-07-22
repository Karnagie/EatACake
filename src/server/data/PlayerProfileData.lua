--[[
	PlayerProfileData — runtime cache of loaded player profiles (R1: state
	lives in data modules only).

	profiles[userId]  -> the raw profile data table (Profile.Data). This is
	                     what services read and mutate directly. Changes are
	                     auto-saved by ProfileStore while the session is active.
	sessions[userId]  -> the ProfileStore Profile object (session handle).
	                     Only PersistenceService and subscriptions should
	                     touch this (e.g. FirstSessionTime for analytics).
	releasing[userId] -> transient flag: an INTENTIONAL pre-teleport session
	                     release is in flight (the lobby<->game handoff), so the
	                     "session-taken" kick in OnSessionEnd is suppressed — the
	                     player is being moved on purpose, not displaced. Set and
	                     cleared by PersistenceService.

	The profile table shape is defined by section files in data/ProfileSchema/.
	Never add profile fields anywhere else — see docs/recipes/add-profile-section.md.
]]

local PlayerProfileData = {}

PlayerProfileData.profiles = {} -- [userId: number] = profile data table
PlayerProfileData.sessions = {} -- [userId: number] = ProfileStore Profile object
PlayerProfileData.releasing = {} -- [userId: number] = true during an intentional pre-teleport release (see header)

function PlayerProfileData.Init()
	table.clear(PlayerProfileData.profiles)
	table.clear(PlayerProfileData.sessions)
	table.clear(PlayerProfileData.releasing)
end

--API
function PlayerProfileData.Get(userId: number)
	return PlayerProfileData.profiles[userId]
end

return PlayerProfileData
