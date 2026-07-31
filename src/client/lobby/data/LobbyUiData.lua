--[[
	LobbyUiData -- lobby-only client configuration + transient UI state.

	Data shape:
	  ["match-config"]       : shared MatchConfig
	  ["matchmaking"]        : false | selector state table
	  ["bound-shop-parts"]   : { [BasePart] = true }
	  ["last-shop-open-at"]  : os.clock timestamp
	(The hex upgrade tree's config/state moved to the COMMON `UpgradesUiData`
	on 2026-07-26 — it has to work in the game place too.)

	Its presence is also the client partition marker AppRoot uses to enable
	lobby panels in lobby.project.json (and the combined development build).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("MatchConfig"))

local LobbyUiData = {
	["match-config"] = MatchConfig,
	["matchmaking"] = false,
	["bound-shop-parts"] = {} :: { [BasePart]: boolean },
	["last-shop-open-at"] = 0,
}

function LobbyUiData.Init()
	LobbyUiData["matchmaking"] = false
	table.clear(LobbyUiData["bound-shop-parts"])
	LobbyUiData["last-shop-open-at"] = 0
end

--API
function LobbyUiData.OpenMatch(state: { [string]: any })
	LobbyUiData["matchmaking"] = state
	return state
end

--API
function LobbyUiData.PatchMatch(patch: { [string]: any })
	local current = LobbyUiData["matchmaking"]
	if type(current) ~= "table" then
		return nil
	end
	for key, value in pairs(patch) do
		current[key] = value
	end
	return current
end


--API
function LobbyUiData.CloseMatch()
	LobbyUiData["matchmaking"] = false
end

return LobbyUiData
