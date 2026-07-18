--[[
	BallRollController — the "full belly makes you tumble like a ball", applied
	by EVERY client for EVERY character from the replicated "StomachFill"
	attribute (zero network cost). Once the (server-scaled) body is round/full
	enough (past BodyConfig.tumble.tumbleFill) the WHOLE visible body TUMBLES
	forward as you MOVE — and settles UPRIGHT when you stop.

	HOW (rig-agnostic): the tumble rotates the ROOT joint's STATIC offset — the
	one channel the Animator never overwrites:
	  * Motor6D rig  -> RootJoint.C0
	  * AnimationConstraint rig (layered-clothing avatars) -> the Root
	    constraint's Attachment0.CFrame
	The joint animation (walk/idle) still plays on top; only the whole-body
	orientation is offset. The HumanoidRootPart (physics / collision / camera)
	stays upright, so WalkSpeed and jump are UNTOUCHED — visual only.

	The BODY SIZE itself (getting big & fat) is the server-side morph in
	BodySubs — this module only rolls it. All tuning in BodyConfig.tumble (R1).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local BodyConfig = require(Shared:WaitForChild("config"):WaitForChild("BodyConfig"))

local SCOPE = "BallRollController"

local BallRollController = {}

local cfg = BodyConfig.tumble

type RollState = {
	kind: string, -- "motor" (Motor6D.C0) | "anim" (Attachment.CFrame)
	target: Instance, -- the Motor6D or the Attachment whose offset we rotate
	orig: CFrame, -- its rest offset (captured once — the Animator never touches it)
	lastXZ: Vector3,
	angle: number, -- accumulated tumble angle (radians)
	tumbling: boolean,
}

local states: { [Model]: RollState } = {}
local TWO_PI = math.pi * 2

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function findRootTarget(character: Model): (string?, Instance?, CFrame?)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "RootJoint" then
			return "motor", d, d.C0
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("AnimationConstraint") and d.Name == "Root" and d.Attachment0 then
			return "anim", d.Attachment0, d.Attachment0.CFrame
		end
	end
	return nil, nil, nil
end

-- -X on the joint offset pitches the body FORWARD (probed on the Root
-- Attachment0: +X tipped it backward). Same convention for both rig types.
local function applyRoll(state: RollState, angle: number)
	local off = state.orig * CFrame.Angles(-angle, 0, 0)
	if state.kind == "motor" then
		(state.target :: Motor6D).C0 = off
	else
		(state.target :: Attachment).CFrame = off
	end
end

local function restoreRoll(state: RollState)
	if state.target.Parent == nil then
		return
	end
	if state.kind == "motor" then
		(state.target :: Motor6D).C0 = state.orig
	else
		(state.target :: Attachment).CFrame = state.orig
	end
end

function BallRollController.Init()
	Log.Info(SCOPE, "ready — full-belly tumble-roll active")
end

--API
-- Per-frame update for every character (connected in BodySubsClient).
function BallRollController.Step(dt: number)
	-- Prune destroyed characters / rebuilt joints (restore first).
	for character, state in pairs(states) do
		if character.Parent == nil or state.target.Parent == nil then
			restoreRoll(state)
			states[character] = nil
		end
	end

	local span = math.max(1e-3, 1 - cfg.tumbleFill)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not hrp then
			continue
		end

		local fill = tonumber(player:GetAttribute("StomachFill")) or 0
		local tumble = math.clamp((fill - cfg.tumbleFill) / span, 0, 1)
		local state = states[character]

		if state == nil then
			if tumble <= 0 then
				continue -- not round enough — nothing to do
			end
			local kind, target, orig = findRootTarget(character)
			if not kind or not target or not orig then
				Log.Once(SCOPE, `noroot-{player.UserId}`, `{player.Name}: no root joint (Motor6D 'RootJoint' / AnimationConstraint 'Root') — tumble disabled`)
				continue
			end
			state = {
				kind = kind,
				target = target,
				orig = orig,
				lastXZ = Vector3.new(hrp.Position.X, 0, hrp.Position.Z),
				angle = 0,
				tumbling = false,
			}
			states[character] = state
		end

		-- Tumble forward by real distance while MOVING; settle UPRIGHT when
		-- stopped (or de-rounded) so a full body standing still never freezes
		-- head-down.
		local curXZ = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
		local dist = (curXZ - state.lastXZ).Magnitude
		state.lastXZ = curXZ
		local moving = dist > cfg.moveSpeedThreshold * math.max(dt, 1e-4)
		if tumble > 0.01 and moving then
			local maxStep = math.rad(cfg.spinMaxDegPerSec) * dt
			state.angle = (state.angle + math.min(dist / math.max(0.1, cfg.rollRadius), maxStep) * tumble) % TWO_PI
			applyRoll(state, state.angle)
			state.tumbling = true
		elseif state.tumbling then
			local a = if state.angle > math.pi then state.angle - TWO_PI else state.angle
			a = lerp(a, 0, math.min(1, cfg.unwindLerp * dt))
			if math.abs(a) < 0.02 then
				state.angle = 0
				restoreRoll(state)
				state.tumbling = false
			else
				state.angle = a % TWO_PI
				applyRoll(state, state.angle)
			end
		end
	end
end

return BallRollController
