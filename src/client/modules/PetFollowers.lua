--[[
	PetFollowers — floating pet companions for every player (GDD §9),
	rendered locally from the replicated "EquippedPets" attribute (csv of
	petIds). Simple primitive looks from PetConfig (placeholder for real
	models); cloned from templates built once at Init (R5).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared:WaitForChild("config"):WaitForChild("PetConfig"))

local PetFollowers = {}

local templates: { [string]: BasePart } = {}
local petsById: { [string]: any } = {}
local folder: Folder?
local clock = 0

-- [player] = { csv = string, parts = { BasePart } }
local followers: { [Player]: { csv: string, parts: { BasePart } } } = {}

function PetFollowers.Init()
	for _, def in ipairs(PetConfig.pets) do
		petsById[def.id] = def
	end

	local function makeTemplate(shape: string): BasePart
		local part
		if shape == "donut" then
			part = Instance.new("Part")
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(0.8, 1.8, 1.8)
		elseif shape == "cube" then
			part = Instance.new("Part")
			part.Size = Vector3.new(1.4, 1.4, 1.4)
		else
			part = Instance.new("Part")
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(1.6, 1.6, 1.6)
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		return part
	end
	templates.ball = makeTemplate("ball")
	templates.cube = makeTemplate("cube")
	templates.donut = makeTemplate("donut")

	folder = Instance.new("Folder")
	folder.Name = "PetFollowers"
	folder.Parent = workspace
end

local function rebuild(player: Player, csv: string)
	local entry = followers[player]
	if entry then
		for _, part in ipairs(entry.parts) do
			part:Destroy()
		end
	end
	entry = { csv = csv, parts = {} }
	followers[player] = entry
	if csv ~= "" then
		for petId in string.gmatch(csv, "[^,]+") do
			local def = petsById[petId]
			if def then
				local template = templates[def.look.shape] or templates.ball
				local part = template:Clone()
				part.Name = `{player.Name}_{petId}`
				part.Color = def.look.color
				part.Parent = folder
				table.insert(entry.parts, part)
			end
		end
	end
end

--API
-- Per-frame update (connected in BodySubsClient).
function PetFollowers.Step(dt: number)
	clock += dt
	for player, entry in pairs(followers) do
		if player.Parent == nil then
			for _, part in ipairs(entry.parts) do
				part:Destroy()
			end
			followers[player] = nil
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local csv = tostring(player:GetAttribute("EquippedPets") or "")
		local entry = followers[player]
		if not entry or entry.csv ~= csv then
			rebuild(player, csv)
			entry = followers[player]
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and #entry.parts > 0 then
			for k, part in ipairs(entry.parts) do
				local angle = math.pi * 0.75 + (k - 1) * 0.6
				local offset = root.CFrame * Vector3.new(math.sin(angle) * 4, 1.5, math.cos(angle) * 4)
				local bob = math.sin(clock * 2.2 + k * 1.7) * 0.4
				part.CFrame = CFrame.new(offset + Vector3.new(0, bob, 0), root.Position)
			end
		elseif #entry.parts > 0 then
			-- Dead/respawning: park followers out of sight instead of
			-- leaving them frozen over the corpse spot.
			for _, part in ipairs(entry.parts) do
				part.CFrame = CFrame.new(0, -500, 0)
			end
		end
	end
end

return PetFollowers
