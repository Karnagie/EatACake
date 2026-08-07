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
	  ["station"]: authored world-sign contract read by UpgradeStationSubsClient
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
	-- The "N Available" sign over the checkpoint computer (2026-08-05, user
	-- request). PLACE-AUTHORED content (ADR-0007) — none of it is in the repo;
	-- MapService clones `ReplicatedStorage.Assets.Checkpoint` into
	-- `workspace.Map.Checkpoint`, so this is a path down that clone.
	-- ⚠ EVERY name here is resolved as an EXPLICIT CHAIN, never a recursive
	-- `FindFirstChild(name, true)`: `UpgradeStationBody` carries TWO BillboardGuis
	-- and BOTH of their TextLabels are named `Txt` (the other one is the static
	-- "Upgrades" nameplate). A recursive search silently relabels the nameplate.
	["station"] = {
		["map-folder"] = "Map",
		["checkpoint-folder"] = "Checkpoint",
		["body-name"] = "UpgradeStationBody",
		["gui-name"] = "AvailableGui",
		["label-name"] = "Txt",
		-- Locale key; `{n}` is the count of upgrades affordable right now.
		["label-key"] = "station-available",
		-- Nothing to sell -> the whole BillboardGui goes dark rather than
		-- advertising "0 Available", which reads as a broken station.
		["hide-when-zero"] = true,
		-- Re-resolve/refresh cadence. The COUNT only moves on UpgradesUpdate /
		-- CurrencyUpdate (calories are banked at the gym, not per bite), so this
		-- tick exists for the INSTANCE: the checkpoint replicates late and is
		-- re-cloned whenever MapService rebuilds the map.
		["refresh-seconds"] = 0.5,
		-- How long the sign may stay unresolved before it warns once (R8).
		["resolve-grace-seconds"] = 15,
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
