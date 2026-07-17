--[[
	BodyMorphController — local, smooth body inflation for EVERY character
	(GDD §8): reads each player's replicated "StomachFill" attribute (0..1)
	and lerps the Humanoid scale NumberValues toward the morph targets.
	Runs on every client independently — zero network cost, always smooth.

	Also owns the bite squash & stretch impulse for the LOCAL character
	(§7.3): a quick height dip layered on top of the morph.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local BodyConfig = require(Shared:WaitForChild("config"):WaitForChild("BodyConfig"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local BodyMorphController = {}

-- [character] = { width, depth, height } current lerped scales.
local states: { [Model]: { width: number, depth: number, height: number } } = {}
local squashT = 0 -- local squash timer (seconds left)

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--API
-- Quick compress-and-release on the local character per bite.
function BodyMorphController.SquashImpulse()
	squashT = JuiceConfig.squash.time
end

--API
-- Per-frame update (connected in BodySubsClient).
function BodyMorphController.Step(dt: number)
	squashT = math.max(0, squashT - dt)
	local morph = BodyConfig.morph
	local alpha = math.min(1, morph.lerpSpeed * dt)
	local localCharacter = Players.LocalPlayer.Character

	-- Prune destroyed characters.
	for character in pairs(states) do
		if character.Parent == nil then
			states[character] = nil
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			continue
		end
		local width = humanoid:FindFirstChild("BodyWidthScale") :: NumberValue?
		local depth = humanoid:FindFirstChild("BodyDepthScale") :: NumberValue?
		local height = humanoid:FindFirstChild("BodyHeightScale") :: NumberValue?
		if not width or not depth or not height then
			-- R6 rig: no scale values — morph degrades gracefully (R8: say why).
			Log.Once("BodyMorph", `r6-{player.UserId}`, `{player.Name} has no Humanoid scale values (R6 rig?) — body morph skipped`)
			continue
		end

		local fill = tonumber(player:GetAttribute("StomachFill")) or 0
		local state = states[character]
		if not state then
			state = { width = width.Value, depth = depth.Value, height = height.Value }
			states[character] = state
		end
		state.width = lerp(state.width, lerp(morph.widthScale[1], morph.widthScale[2], fill), alpha)
		state.depth = lerp(state.depth, lerp(morph.depthScale[1], morph.depthScale[2], fill), alpha)
		local targetHeight = lerp(morph.heightScale[1], morph.heightScale[2], fill)
		if character == localCharacter and squashT > 0 then
			targetHeight *= JuiceConfig.squash.compress
			state.height = targetHeight -- squash snaps, release lerps back
		else
			state.height = lerp(state.height, targetHeight, alpha)
		end

		if math.abs(width.Value - state.width) > 0.005 then
			width.Value = state.width
		end
		if math.abs(depth.Value - state.depth) > 0.005 then
			depth.Value = state.depth
		end
		if math.abs(height.Value - state.height) > 0.005 then
			height.Value = state.height
		end
	end
end

return BodyMorphController
