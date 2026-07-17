--[[
	Profile section: core — cross-feature basics (player settings).
	Feature-specific state belongs in that feature's own section file.

	Note: creation time, session count and "is new player" do NOT live here —
	ProfileStore provides them natively (Profile.FirstSessionTime,
	Profile.SessionLoadCount) via PlayerProfileData.sessions[userId].
]]

return {
	key = "core",
	version = 1,
	defaults = {
		settings = {
			["music-enabled"] = true,
			["sfx-enabled"] = true,
		},
	},
	intKeySets = {},
	migrations = {},
	sanitize = nil,
}
