--[[
	LobbyMapService — builds the lobby HUB scene (lobby place only, R2 logic).

	Clones ReplicatedStorage.Assets.LobbyEnvironment (place-authored — a human /
	Studio MCP authors the hub; code only CLONES it by name, ADR-0007) into
	workspace.LobbyMap. The map container and spawn are authored templates too;
	if any required asset is absent, the existing Workspace is preserved (R5/R8).

	Before the clone enters Workspace, legacy scripts under each direct
	GroupToucher are destroyed and the old ChestStatus visual name is normalized
	to WaitingStatus. All authored names come from LobbyQueueData/MatchConfig.

	Build() is called from LobbySubs.Start — mirrors MapService.Build <-
	CakeSubs.Start in the game place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "LobbyMap"

local LobbyMapService = {}
local lobbyQueueData

function LobbyMapService.Init(data)
	lobbyQueueData = data.LobbyQueueData
	if lobbyQueueData == nil or lobbyQueueData["queue-config"] == nil then
		Log.Warn(SCOPE, "LobbyQueueData['queue-config'] missing -- the lobby map path contract is unavailable")
	end
end

local function isTextGui(instance: Instance?): boolean
	return instance ~= nil
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function normalizeQueueClone(clone: Instance, queue_config): boolean
	local touchers = clone:FindFirstChild(queue_config.touchersFolderName)
	if touchers == nil then
		Log.Warn(SCOPE, `{clone.Name}.{queue_config.touchersFolderName} missing -- queue pads cannot be sanitized or bound`)
		return false
	end

	local model_count = 0
	local usable_count = 0
	local removed_script_count = 0
	local invalid_models = {}
	for _, queue_model in ipairs(touchers:GetChildren()) do
		if queue_model:IsA("Model") then
			model_count += 1
			local toucher = queue_model:FindFirstChild(queue_config.toucherName)
			local usable = true
			if toucher == nil or not toucher:IsA("BasePart") then
				Log.Warn(SCOPE, `{queue_model:GetFullName()}.{queue_config.toucherName} missing or not a BasePart -- queue pad is unusable`)
				usable = false
			else
				for _, descendant in ipairs(toucher:GetDescendants()) do
					if descendant:IsA("BaseScript") then
						descendant.Disabled = true
						descendant:Destroy()
						removed_script_count += 1
					end
				end
			end

			local visual = queue_model:FindFirstChild(queue_config.visualName)
			if visual == nil then
				Log.Warn(SCOPE, `{queue_model:GetFullName()}.{queue_config.visualName} missing -- queue pad is unusable`)
				usable = false
			else
				local waiting_status = visual:FindFirstChild(queue_config.waitingStatusName)
				local legacy_status = visual:FindFirstChild(queue_config.legacyStatusName)
				if legacy_status and waiting_status then
					legacy_status:Destroy()
					Log.Info(SCOPE, `removed duplicate legacy {queue_config.legacyStatusName} from {queue_model.Name}`)
				elseif legacy_status then
					legacy_status.Name = queue_config.waitingStatusName
					waiting_status = legacy_status
					Log.Info(SCOPE, `normalized {queue_config.legacyStatusName} -> {queue_config.waitingStatusName} in {queue_model.Name}`)
				end

				local player_count = visual:FindFirstChild(queue_config.playerCountName)
				local count_text = player_count and player_count:FindFirstChild(queue_config.textName)
				local status_text = waiting_status and waiting_status:FindFirstChild(queue_config.textName)
				if not isTextGui(count_text) or not isTextGui(status_text) then
					Log.Warn(SCOPE, `{queue_model:GetFullName()} label contract incomplete -- {queue_config.playerCountName}/{queue_config.waitingStatusName}.{queue_config.textName} must be text GUI objects`)
					usable = false
				end
			end
			if usable then
				usable_count += 1
			else
				table.insert(invalid_models, queue_model)
			end
		end
	end
	for _, invalid_model in ipairs(invalid_models) do
		invalid_model:Destroy()
	end

	if model_count == 0 then
		Log.Warn(SCOPE, `{touchers:GetFullName()} has no direct Model children -- no lobby queues can bind`)
	end
	if removed_script_count > 0 then
		Log.Info(SCOPE, `destroyed {removed_script_count} legacy BaseScript(s) inside cloned queue touchers`)
	end
	if usable_count == 0 then
		Log.Warn(SCOPE, `{touchers:GetFullName()} has no complete queue pad contract -- current Workspace will be preserved`)
		return false
	end
	return true
end

--API
-- Clones the authored lobby hub into workspace. Idempotent (rebuilds cleanly).
function LobbyMapService.Build(): Folder?
	local queue_config = lobbyQueueData and lobbyQueueData["queue-config"]
	if queue_config == nil then
		Log.Warn(SCOPE, "Build skipped: LobbyQueueData['queue-config'] is missing")
		return nil
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(queue_config.environmentName)
	local container_template = assets and assets:FindFirstChild(queue_config.mapContainerName)
	if template == nil or not (template:IsA("Model") or template:IsA("Folder")) then
		Log.Warn(SCOPE, `ReplicatedStorage.Assets.{queue_config.environmentName} missing or invalid -- existing Workspace preserved; lobby queues cannot bind (ADR-0007)`)
		return nil
	end
	if container_template == nil or not container_template:IsA("Folder") then
		Log.Warn(SCOPE, `ReplicatedStorage.Assets.{queue_config.mapContainerName} missing or not a Folder -- existing Workspace preserved; lobby queues cannot bind (ADR-0007)`)
		return nil
	end
	if #container_template:GetChildren() > 0 then
		Log.Warn(SCOPE, `ReplicatedStorage.Assets.{queue_config.mapContainerName} must be empty -- existing Workspace preserved; remove authored children`)
		return nil
	end
	local spawn_template = template:FindFirstChild(queue_config.spawnName, true)
	if spawn_template == nil or not spawn_template:IsA("SpawnLocation") then
		Log.Warn(SCOPE, `{template:GetFullName()}.{queue_config.spawnName} missing or not a SpawnLocation -- existing Workspace preserved; lobby queues cannot bind`)
		return nil
	end
	if not spawn_template.Anchored or not spawn_template.Neutral then
		Log.Warn(SCOPE, `{spawn_template:GetFullName()} must be authored Anchored + Neutral -- existing Workspace preserved`)
		return nil
	end

	local map = container_template:Clone()
	map.Name = queue_config.mapName
	local clone = template:Clone()
	if not normalizeQueueClone(clone, queue_config) then
		clone:Destroy()
		map:Destroy()
		return nil
	end
	clone.Parent = map

	-- Cleanup starts only after every required authored template passed preflight
	-- and cloned, so a malformed update cannot destroy the current working map.
	local existing = workspace:FindFirstChild(queue_config.mapName)
	if existing then
		existing:Destroy()
	end
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local existing_spawn = workspace:FindFirstChild("SpawnLocation")
	if existing_spawn then
		existing_spawn:Destroy()
	end

	map.Parent = workspace
	Log.Sum(SCOPE, `lobby scene CLONED from ReplicatedStorage.Assets.{queue_config.environmentName}`)
	return map
end

return LobbyMapService
