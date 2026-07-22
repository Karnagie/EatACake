--[[
	ChunkDebris — pooled flying cake chunks (the "chunk ripped out" bite
	juice): a bite launches a few physical crumbs of the bitten layer's
	color that arc out and vanish. Fixed pool built ONCE at Init — zero
	Instance.new in the bite path (GDD §16.10).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local ChunkDebris = {}

local pool: { { part: Part, gen: number } } = {}
local cursor = 1

local PARK_CF = CFrame.new(0, -500, 0)

function ChunkDebris.Init()
	local cfg = JuiceConfig.chunks
	local folder = Instance.new("Folder")
	folder.Name = "ChunkDebris"

	for k = 1, cfg.poolSize do
		local part = Instance.new("Part")
		part.Name = `Chunk_{k}`
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Size = Vector3.new(1.2, 1.2, 1.2)
		part.CFrame = PARK_CF
		part.Parent = folder
		table.insert(pool, { part = part, gen = 0 })
	end
	folder.Parent = workspace
end

--API
-- Launches `count` chunks of `color` from `position` (bite point).
function ChunkDebris.Throw(position: Vector3, color: Color3, count: number)
	local cfg = JuiceConfig.chunks
	for _ = 1, count do
		local entry = pool[cursor]
		cursor = cursor % #pool + 1
		entry.gen += 1
		local gen = entry.gen
		local part = entry.part

		local s = cfg.sizeMin + math.random() * (cfg.sizeMax - cfg.sizeMin)
		part.Size = Vector3.new(s, s * (0.8 + math.random() * 0.4), s)
		part.Color = color
		part.CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5))
			* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
		part.Anchored = false
		local angle = math.random() * math.pi * 2
		part.AssemblyLinearVelocity = Vector3.new(
			math.cos(angle) * cfg.sideSpeed * math.random(),
			cfg.upSpeedMin + math.random() * (cfg.upSpeedMax - cfg.upSpeedMin),
			math.sin(angle) * cfg.sideSpeed * math.random()
		)
		part.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 12,
			(math.random() - 0.5) * 12,
			(math.random() - 0.5) * 12
		)

		task.delay(cfg.lifetime, function()
			if entry.gen == gen then -- not recycled since
				part.Anchored = true
				part.CFrame = PARK_CF
			end
		end)
	end
end

return ChunkDebris
