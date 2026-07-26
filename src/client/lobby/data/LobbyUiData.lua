--[[
	LobbyUiData -- lobby-only client configuration + transient UI state.

	Data shape:
	  ["match-config"]       : shared MatchConfig
	  ["matchmaking"]        : false | selector state table
	  ["bound-shop-parts"]   : { [BasePart] = true }
	  ["last-shop-open-at"]  : os.clock timestamp
	  ["upgrades-config"]    : authored names/tuning for UpgradesSubsClient
	  ["upgrades-state"]     : open/modal runtime state and cloned blur reference

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
	["upgrades-config"] = {
		["prompt-name"] = "UpgradeStation",
		["close-action-name"] = "CloseUpgradeTree",
		["blur-size"] = 18,
		["blur-template-name"] = "UpgradeTreeBlur",
	},
	["upgrades-state"] = {
		["open"] = false,
		["disabled-prompts"] = {} :: { ProximityPrompt },
		["saved-camera-type"] = nil :: Enum.CameraType?,
		["blur"] = nil :: BlurEffect?,
	},
}

function LobbyUiData.Init()
	LobbyUiData["matchmaking"] = false
	table.clear(LobbyUiData["bound-shop-parts"])
	LobbyUiData["last-shop-open-at"] = 0
	LobbyUiData["upgrades-state"] = {
		["open"] = false,
		["disabled-prompts"] = {} :: { ProximityPrompt },
		["saved-camera-type"] = nil,
		["blur"] = nil,
	}
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
