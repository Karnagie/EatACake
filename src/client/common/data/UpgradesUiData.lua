--[[
	UpgradesUiData — authored names + modal runtime state for the hex upgrade
	tree (UpgradesSubsClient, features/upgrades.md).

	COMMON on purpose (2026-07-26). This block used to live in `LobbyUiData`,
	which made the whole tree lobby-only — and since the published lobby has no
	authored `UpgradeStation` prompt, the tree was reachable from NOWHERE. The
	tree is the calorie sink the whole match pacing is built around (you buy a
	tier at the checkpoint after each belly run), so it has to exist in the GAME
	place too.

	Shape:
	  ["config"] : authored names/tuning read by UpgradesSubsClient
	  ["state"]  : open flag, cloned blur, saved camera type, prompts it disabled
]]

local UpgradesUiData = {
	["config"] = {
		-- World ProximityPrompt that also opens the tree where one is authored
		-- (the game checkpoint "computer"; the HUD button is the guaranteed
		-- entry point). Opening a menu is LOCAL UI — no server round-trip.
		["prompt-name"] = "UpgradeStation",
		["close-action-name"] = "CloseUpgradeTree",
		["blur-size"] = 18,
		["blur-template-name"] = "UpgradeTreeBlur",
	},
	["state"] = {
		["open"] = false,
		["disabled-prompts"] = {} :: { ProximityPrompt },
		["saved-camera-type"] = nil :: Enum.CameraType?,
		["blur"] = nil :: BlurEffect?,
	},
}

function UpgradesUiData.Init()
	UpgradesUiData["state"] = {
		["open"] = false,
		["disabled-prompts"] = {} :: { ProximityPrompt },
		["saved-camera-type"] = nil,
		["blur"] = nil,
	}
end

return UpgradesUiData
