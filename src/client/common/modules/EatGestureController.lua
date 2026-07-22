--[[
	EatGestureController — the "player eats a piece" animation for the LOCAL
	character (wired from CakeSubsClient). Every accepted bite:
	  * rips a chunky piece of the EATEN LAYER out of the cake IN FRONT of you
	    (Play is handed the forward bite point + the layer),
	  * flies it up through your right HAND to your MOUTH along a two-arc path
	    (cake -> hand -> mouth), tumbling, then shrinks it away (eaten).

	Flight time is derived from the eat-rate stat so faster eating visibly
	chews faster ("скорость анимации зависит от скорости поедания").

	RIG-AGNOSTIC on purpose: it only reads part positions (Head / RightHand) and
	moves its OWN pooled parts — it never poses the character's joints. (This
	avatar's rig uses AnimationConstraints, not Motor6Ds, and the Animator
	overwrites any joint Transform every frame, so joint posing is unreliable;
	the flying piece IS the eating animation.)

	LOCAL only, matching the local-prediction bite juice (other players' bite FX
	aren't networked either). The body morph + tumble are what other players see.

	Pool built ONCE at Init (Instance.new only here, never in the bite path —
	same pattern as ChunkDebris). Feel/timing tuning in BodyConfig.eatGesture
	(R1); the piece geometry offsets are structural constants beside the code.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local BodyConfig = require(Shared:WaitForChild("config"):WaitForChild("BodyConfig"))

local SCOPE = "EatGestureController"

local EatGestureController = {}

local cfg = BodyConfig.eatGesture

local pool: { { part: BasePart, gen: number } } = {}
local cursor = 1
-- Active flights: { entry, gen, startClock, duration, origin, sizeVec }.
local active: { { entry: any, gen: number, startClock: number, duration: number, origin: Vector3, sizeVec: Vector3 } } = {}

local PARK_CF = CFrame.new(0, -500, 0)

-- Quadratic Bézier through a lifted midpoint (a clean arc from a -> b).
local function arc(a: Vector3, b: Vector3, lift: number, t: number): Vector3
	local mid = (a + b) * 0.5 + Vector3.new(0, lift, 0)
	local u = 1 - t
	return a * (u * u) + mid * (2 * u * t) + b * (t * t)
end

function EatGestureController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "EatPieces"
	for k = 1, math.max(1, cfg.poolSize) do
		local part = Instance.new("Part")
		part.Name = `EatPiece_{k}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Size = Vector3.new(cfg.pieceSize, cfg.pieceSize * 0.85, cfg.pieceSize)
		part.CFrame = PARK_CF
		part.Parent = folder
		table.insert(pool, { part = part, gen = 0 })
	end
	folder.Parent = workspace
	Log.Info(SCOPE, `eat-piece pool ready ({#pool} pieces)`)
end

-- Local character anchors (recomputed live each frame — the body moves).
local function handPosition(character: Model, root: BasePart): Vector3
	local hand = character:FindFirstChild("RightHand") -- R15
		or character:FindFirstChild("Right Arm") -- R6
	if hand and hand:IsA("BasePart") then
		return hand.Position
	end
	return (root.CFrame * CFrame.new(1.3, 0.4, -1.1)).Position
end

local function mouthPosition(character: Model, root: BasePart): Vector3
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return (head.CFrame * CFrame.new(0, -0.2, -0.9)).Position
	end
	return (root.CFrame * CFrame.new(0, 2.6, -0.8)).Position
end

--API
-- Kick off one flying piece from the forward bite point. Flight time is derived
-- from the eat-rate stat (faster eating -> shorter flight -> faster chewing).
function EatGestureController.Play(fromWorldPos: Vector3, layer, eatRate: number)
	local durationSeconds = math.clamp(cfg.baseDuration / math.max(0.25, eatRate or 1), cfg.minDuration, cfg.maxDuration)

	local entry = pool[cursor]
	if entry == nil then
		return -- pool never built (Init failed) — logged there, degrade silently
	end
	cursor = cursor % #pool + 1
	entry.gen += 1

	local part = entry.part
	local top = layer and layer.colors and layer.colors.top or Color3.fromRGB(240, 220, 220)
	part.Color = top:Lerp(Color3.new(1, 1, 1), cfg.tint) -- appetising glaze
	part.Material = (layer and layer.material) or Enum.Material.SmoothPlastic
	part.Transparency = (layer and layer.transparency) or 0 -- translucent jelly piece stays translucent
	part.Reflectance = (layer and layer.gloss) or 0
	local sizeVec = Vector3.new(cfg.pieceSize, cfg.pieceSize * 0.85, cfg.pieceSize)
	part.Size = sizeVec
	part.CFrame = CFrame.new(fromWorldPos)

	table.insert(active, {
		entry = entry,
		gen = entry.gen,
		startClock = os.clock(),
		duration = math.max(0.05, durationSeconds),
		origin = fromWorldPos,
		sizeVec = sizeVec,
	})
end

--API
-- Advance flights. Cheap: pool is tiny (<= poolSize).
function EatGestureController.Step(dt: number)
	if #active == 0 then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local handPos = (character and root) and handPosition(character, root) or nil
	local mouthPos = (character and root) and mouthPosition(character, root) or nil

	local now = os.clock()
	for i = #active, 1, -1 do
		local rec = active[i]
		local part = rec.entry.part
		if rec.entry.gen ~= rec.gen then
			table.remove(active, i) -- recycled by a newer bite
			continue
		end
		local t = (now - rec.startClock) / rec.duration
		if t >= 1 or handPos == nil or mouthPos == nil then
			part.CFrame = PARK_CF
			table.remove(active, i)
			continue
		end

		local pos: Vector3
		local hf = cfg.handFraction
		if t < hf then
			pos = arc(rec.origin, handPos, cfg.arcHeight, t / hf)
		else
			pos = arc(handPos, mouthPos, cfg.arcHeight * 0.4, (t - hf) / (1 - hf))
		end

		local spin = math.rad(cfg.tumbleDegPerSec) * (now - rec.startClock)
		-- Shrink away in the last stretch (bitten off at the mouth).
		local scale = if t > 0.82 then math.max(0.001, (1 - t) / 0.18) else 1
		part.Size = rec.sizeVec * scale
		part.CFrame = CFrame.new(pos) * CFrame.Angles(spin, spin * 0.7, spin * 0.3)
	end
end

return EatGestureController
