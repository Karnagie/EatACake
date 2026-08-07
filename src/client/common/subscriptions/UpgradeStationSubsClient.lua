--[[
	UpgradeStationSubsClient — the "N Available" sign over the checkpoint's
	upgrade computer (R4). Feature doc: docs/features/upgrades.md; authored
	contract + tuning: `UpgradesUiData["station"]`.

	It answers, from across the cake, the one question the ProximityPrompt cannot:
	"is it worth walking over there yet?". The count is the number of stats whose
	NEXT tier the player can already pay for, through the one shared predicate
	(LocalUpgradeTree.AffordableCount) that the tree's own Buy button and category
	badge use — so the sign can never promise a purchase the tree then refuses.
	⚠ It is NOT the number of GOLD hexes: gold means "next unlocked tier", priced
	but not necessarily payable, so gold hexes >= this number. See the
	LocalUpgradeTree header.

	GAME PLACE ONLY (`GameUiData` marker): the checkpoint is game-place scenery.
	The module is COMMON rather than game/ so its absence in the lobby is REPORTED
	(R8) instead of silently vanishing.

	SPLIT OUT of UpgradesSubsClient on purpose (R7): that file already owns the
	modal (blur, camera freeze, movement lock, world-prompt disabling) at ~250
	lines, and the world sign shares nothing with it but the feature name.

	WHY IT POLLS INSTEAD OF LISTENING. The count moves on exactly two updates —
	`UpgradesUpdate` (tiers) and `CurrencyUpdate` (balance) — but both are consumed
	by OTHER subscriptions that write the values into AppRoot, and client subs
	Start alphabetically: `UpgradeStationSubsClient` connects BEFORE
	`UpgradesSubsClient`, so a handler here would run on the same remote one step
	AHEAD of the state it needs and render the previous tier forever. Reading
	AppRoot on a slow tick has no such ordering hazard, and the same tick is
	needed anyway for the INSTANCE: `workspace.Map.Checkpoint` is a server-side
	clone of place content (ADR-0007) that replicates late.

	⚠ Resolution is an EXPLICIT CHAIN, never `FindFirstChild(name, true)`.
	`UpgradeStationBody` carries two BillboardGuis whose TextLabels are BOTH named
	`Txt`; a recursive search relabels the static "Upgrades" nameplate instead,
	with no error and no warning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "UpgradeStation"

local UpgradeStationSubsClient = {}

function UpgradeStationSubsClient.Start(data, modules)
	if data.GameUiData == nil then
		Log.Info(SCOPE, "game client partition absent -- upgrade-station sign skipped in lobby")
		return
	end
	local upgradesData = data.UpgradesUiData
	local station = upgradesData and upgradesData["station"]
	if type(station) ~= "table" then
		Log.Warn(SCOPE, "UpgradesUiData['station'] missing -- the upgrade station sign will never update")
		return
	end
	local locale = data.LocaleData
	local AppRoot = modules.AppRoot
	local LocalUpgradeTree = modules.LocalUpgradeTree
	if locale == nil or AppRoot == nil or LocalUpgradeTree == nil then
		Log.Warn(SCOPE, "LocaleData/AppRoot/LocalUpgradeTree missing -- the upgrade station sign will never update")
		return
	end

	local mapFolder = station["map-folder"]
	local checkpointFolder = station["checkpoint-folder"]
	local bodyName = station["body-name"]
	local guiName = station["gui-name"]
	local labelName = station["label-name"]
	local labelKey = station["label-key"]
	local hideWhenZero = station["hide-when-zero"] ~= false
	local refreshSeconds = tonumber(station["refresh-seconds"]) or 0.5
	local graceSeconds = tonumber(station["resolve-grace-seconds"]) or 15
	-- Iterate the KEY NAMES and index the config, never a table built from the
	-- locals: a table constructor given a nil value simply has no key, so `pairs`
	-- would skip exactly the case this guard exists for (a key deleted or renamed
	-- in UpgradesUiData) and `FindFirstChild(nil)` would throw from the tick
	-- instead of warning once.
	for _, key in ipairs({ "map-folder", "checkpoint-folder", "body-name", "gui-name", "label-name", "label-key" }) do
		local value = station[key]
		if type(value) ~= "string" or value == "" then
			Log.Warn(SCOPE, `UpgradesUiData['station']['{key}'] is not a name -- the upgrade station sign will never update`)
			return
		end
	end

	local gui: BillboardGui? = nil
	local label: TextLabel? = nil
	-- Last values WRITTEN, so the tick touches the instance only on a real change
	-- (a per-tick property write on a BillboardGui is pure churn). Cleared on
	-- re-resolve: a freshly cloned sign starts from whatever it was authored with.
	local lastText: string? = nil
	local lastEnabled: boolean? = nil

	-- Never cached across a rebuild: `Map` is a clone the server can replace, and
	-- holding a dead reference would freeze the sign on a stale number.
	local function resolve(): boolean
		if label ~= nil and label.Parent == gui and gui ~= nil and gui.Parent ~= nil then
			return true
		end
		gui, label, lastText, lastEnabled = nil, nil, nil, nil
		local map = Workspace:FindFirstChild(mapFolder)
		local checkpoint = map and map:FindFirstChild(checkpointFolder)
		local body = checkpoint and checkpoint:FindFirstChild(bodyName)
		local foundGui = body and body:FindFirstChild(guiName)
		if foundGui == nil or not foundGui:IsA("BillboardGui") then
			return false
		end
		local foundLabel = foundGui:FindFirstChild(labelName)
		if foundLabel == nil or not foundLabel:IsA("TextLabel") then
			return false
		end
		gui, label = foundGui, foundLabel
		Log.Info(SCOPE, `available-upgrades sign resolved ({mapFolder}.{checkpointFolder}.{bodyName}.{guiName}.{labelName})`)
		return true
	end

	local function refresh()
		if not resolve() then
			-- Place content replicates late (R8: a deferred re-check, never a
			-- blocking wait) — and the generated fallback checkpoint carries no
			-- BillboardGui at all, so a missing sign must degrade, not stall.
			Log.GraceOnce(SCOPE, "station-sign-missing", graceSeconds, function()
				return not resolve()
			end, `workspace.{mapFolder}.{checkpointFolder}.{bodyName}.{guiName}.{labelName} missing — the upgrade station will not show how many upgrades are affordable (the ProximityPrompt still opens the tree). It is PLACE content, not in the repo — see docs/features/upgrades.md.`)
			return
		end
		local count = LocalUpgradeTree.AffordableCount(AppRoot.Get("upgrades"), AppRoot.Get("calories"))
		-- "0 Available" reads as a broken station, so the whole board goes dark.
		local enabled = count > 0 or not hideWhenZero
		if enabled ~= lastEnabled then
			(gui :: BillboardGui).Enabled = enabled
			lastEnabled = enabled
		end
		if not enabled then
			return
		end
		local text = locale.T(labelKey, { n = count })
		if text ~= lastText then
			(label :: TextLabel).Text = text
			lastText = text
		end
	end

	refresh()

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < refreshSeconds then
			return
		end
		accum = 0
		refresh()
	end)
end

return UpgradeStationSubsClient
