--[[
	LobbyMapService — builds the lobby HUB scene (lobby place only, R2 logic).

	Clones ReplicatedStorage.Assets.LobbyEnvironment (place-authored — a human /
	Studio MCP authors the hub; code only CLONES it by name, ADR-0007) into
	workspace.LobbyMap. If the asset is absent, warns once (R8) and drops a bare
	baseplate + SpawnLocation so players don't fall through the void.

	Build() is called from LobbySubs.Start — mirrors MapService.Build <-
	CakeSubs.Start in the game place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "LobbyMap"
local ASSET_NAME = "LobbyEnvironment"

local LobbyMapService = {}

function LobbyMapService.Init(data)
	-- No config deps yet; kept for bootstrap symmetry / future lobby map config.
end

--API
-- Clones the authored lobby hub into workspace. Idempotent (rebuilds cleanly).
function LobbyMapService.Build(): Folder
	-- The place file ships a default Baseplate + SpawnLocation — remove them so
	-- the authored scene owns the ground (mirrors MapService.Build).
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local stray = workspace:FindFirstChild(name)
		if stray then
			stray:Destroy()
		end
	end
	local existing = workspace:FindFirstChild("LobbyMap")
	if existing then
		existing:Destroy()
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(ASSET_NAME)

	local map = Instance.new("Folder")
	map.Name = "LobbyMap"

	if template and (template:IsA("Model") or template:IsA("Folder")) then
		local clone = template:Clone()
		clone.Parent = map
		Log.Sum(SCOPE, `lobby scene CLONED from ReplicatedStorage.Assets.{ASSET_NAME}`)
	else
		-- R8: authored scene missing — degrade gracefully, never leave a void.
		Log.Warn(SCOPE, `ReplicatedStorage.Assets.{ASSET_NAME} missing or not a Model/Folder — author the lobby hub there (ADR-0007). Dropping a bare baseplate so players don't fall.`)
		local base = Instance.new("Part")
		base.Name = "LobbyBaseplate"
		base.Anchored = true
		base.Size = Vector3.new(512, 4, 512)
		base.Position = Vector3.new(0, 0, 0)
		base.Color = Color3.fromRGB(70, 60, 90)
		base.Parent = map
	end

	-- Guarantee at least one SpawnLocation (the authored scene may add its own).
	if map:FindFirstChildWhichIsA("SpawnLocation", true) == nil then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "LobbySpawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Position = Vector3.new(0, 3, 0)
		spawn.Parent = map
	end

	map.Parent = workspace
	return map
end

return LobbyMapService
