--[[
	PlayerControlData -- client input-lock configuration and runtime state (R1).

	Shape:
	  reasons             -- stable reason ids used by independent subscriptions
	  teleport-attribute  -- server-written Player attribute watched by the client
	  locks               -- [reason] = true while that feature owns a control lock
	  controls            -- lazily resolved PlayerModule controls handle
	  controls-disabled   -- last state successfully applied to that handle

	A reason set prevents one modal from re-enabling movement while another
	feature (notably a cross-place teleport handoff) still requires it disabled.
]]

local PlayerControlData = {}

PlayerControlData.reasons = {
	teleport = "teleport-handoff",
	upgrades = "upgrade-overlay",
}
PlayerControlData["teleport-attribute"] = "Teleporting"
PlayerControlData.locks = {}
PlayerControlData.controls = nil
PlayerControlData["controls-disabled"] = false

function PlayerControlData.Init()
	PlayerControlData.locks = {}
	PlayerControlData.controls = nil
	PlayerControlData["controls-disabled"] = false
end

return PlayerControlData
