--[[
	GameUiData -- game-client partition marker.

	Game-only UI/input subscriptions check for this module in the merged data
	registry. The combined development project maps both GameUiData and
	LobbyUiData; each published project maps only its own marker.
]]

local GameUiData = {
	["enabled"] = true,
}

return GameUiData
