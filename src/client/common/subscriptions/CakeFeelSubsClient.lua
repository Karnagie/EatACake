--[[
	CakeFeelSubsClient — per-layer FEEL under your feet (R4, GDD §5).

	Every layer must feel different the moment you step on it:
	  * jumpMult   — sponge trampoline jumps high, caramel barely lets go
	                 (client-owned Humanoid jump props; WalkSpeed stays
	                 SERVER-authoritative in BodySubs — never touched here)
	  * bounce     — landing restitution: hard falls on bouncy layers throw
	                 you back up (capped by feel.bounceMaxUp)
	  * crust cracks — landings crack the crust skin (CakeRenderer.CrackAt
	                 draws into the layer texture). The FIRST crack of every
	                 fresh cake is the big ceremony (§7.1) — owned HERE, the
	                 single Landed handler (walking-step cracks live with the
	                 walk-crunch cadence in CakeSubsClient).

	Wiring state only: base jump values per character, last fall speed,
	the applied layer, the fresh-crust flag. All tuning in CakeConfig (R1).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "CakeFeelSubsClient"

local CakeFeelSubsClient = {}

function CakeFeelSubsClient.Start(data, modules)
	local LocalCakeField = modules.LocalCakeField
	local CakeRenderer = modules.CakeRenderer
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local CameraShake = modules.CameraShake
	local LocalEatState = modules.LocalEatState -- flat-while-eating gate (Task 4)

	local feelCfg = CakeConfig.feel
	local gridCfg = CakeConfig.grid

	local player = Players.LocalPlayer
	local humanoid: Humanoid? = nil
	local root: BasePart? = nil
	local baseJumpPower = 50
	local baseJumpHeight = 7.2
	local appliedLayerId: string? = nil
	local appliedEating = false -- last eating state the jump was applied for (Task 4)
	local lastFallSpeed = 0 -- studs/s downward, tracked pre-landing
	local pollAccum = 0
	local crustFresh = false -- first crack of a fresh cake = the ceremony

	Net.Update("CakeSnapshotUpdate").OnClientEvent:Connect(function(_, meta)
		if type(meta) == "table" then
			crustFresh = (meta.progress or 0) <= 0.02 -- landed on a fresh crust?
		end
	end)

	-- Layer def + surface point under the character, nil when off the cake.
	local function layerUnderFeet(): (any?, Vector3?)
		if root == nil then
			return nil, nil
		end
		local point = LocalCakeField.SurfacePoint(root.Position.X, root.Position.Z)
		if point == nil or math.abs(root.Position.Y - point.Y) > feelCfg.onCakeYTolerance then
			return nil, nil
		end
		return LocalCakeField.LayerAtStuds(point.Y - gridCfg.origin.y), point
	end

	local function applyJump(layer)
		if humanoid == nil then
			return
		end
		local mult = (layer and layer.jumpMult) or 1
		-- Flat while eating (Task 4): cap the jump to ~normal so a sponge/jelly
		-- super-jump doesn't launch you mid-eat (straight-line movement).
		if LocalEatState.Get() then
			mult = math.min(mult, feelCfg.jumpMultCapWhileEating)
		end
		if humanoid.UseJumpPower then
			humanoid.JumpPower = baseJumpPower * mult
		else
			humanoid.JumpHeight = baseJumpHeight * mult
		end
	end

	local function onLanded()
		local impact = lastFallSpeed
		lastFallSpeed = 0
		local layer, point = layerUnderFeet()
		if layer == nil or point == nil then
			return
		end
		-- Crust crack: CrackAt draws only when the surface really is crust.
		if impact >= feelCfg.crackMinImpact and CakeRenderer.CrackAt(point, "land") then
			local color = CakeRenderer.PaletteColor(point.Y - gridCfg.origin.y)
			if crustFresh then
				-- The signature first-crack ceremony of a fresh cake (§7.1).
				crustFresh = false
				SoundPool.Play("crustCrack")
				CameraShake.Impulse(JuiceConfig.camera.crustCrackAmp)
				for k = 1, 6 do -- radial shard ring
					local angle = k / 6 * math.pi * 2
					ParticlePool.Burst(
						point + Vector3.new(math.cos(angle) * 4, 1, math.sin(angle) * 4),
						color,
						JuiceConfig.particles.shardsPerCrack // 2
					)
				end
			else
				SoundPool.Play("crustCrack", { volumeMult = 0.7, pitchMult = 1.1 })
				ParticlePool.Burst(point + Vector3.new(0, 0.5, 0), color, JuiceConfig.particles.shardsPerCrack // 2)
			end
		end
		-- Trampoline layers: throw the character back up. SUPPRESSED while eating
		-- (Task 4) — no bounce mid-eat so movement stays a straight line.
		local eatingNow = feelCfg.noBounceWhileEating and LocalEatState.Get()
		if layer.bounce and impact >= feelCfg.bounceMinImpact and root ~= nil and not eatingNow then
			local v = root.AssemblyLinearVelocity
			local up = math.min(impact * layer.bounce, feelCfg.bounceMaxUp)
			root.AssemblyLinearVelocity = Vector3.new(v.X, up, v.Z)
			SoundPool.Play(layer.sfx, { pitchMult = 1.3 })
			CameraShake.Impulse(0.15)
		end
	end

	local function hookCharacter(character: Model)
		local h = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 10) :: Humanoid?
		if player.Character ~= character then
			return -- superseded by a fast respawn while waiting — never
			-- overwrite the NEW character's hook with this stale one
		end
		if h == nil then
			Log.Warn(SCOPE, "character without Humanoid — layer feel disabled for this life")
			return
		end
		local r = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			or character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if player.Character ~= character then
			return
		end
		if r == nil then
			Log.Warn(SCOPE, "character without HumanoidRootPart — layer feel disabled for this life")
			return
		end
		humanoid = h
		root = r
		baseJumpPower = h.JumpPower
		baseJumpHeight = h.JumpHeight
		appliedLayerId = nil
		appliedEating = false -- fresh character: re-apply the jump on the first poll
		lastFallSpeed = 0
		h.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed then
				onLanded()
			end
		end)
	end

	player.CharacterAdded:Connect(function(character)
		task.spawn(hookCharacter, character)
	end)
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterRemoving:Connect(function()
		humanoid = nil
		root = nil
		appliedLayerId = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		if root == nil or humanoid == nil then
			return
		end
		-- Fall speed must be sampled BEFORE the landing zeroes it.
		local vy = root.AssemblyLinearVelocity.Y
		if vy < -1 then
			lastFallSpeed = -vy
		end
		pollAccum += dt
		if pollAccum < feelCfg.surfacePollSeconds then
			return
		end
		pollAccum = 0
		local layer = layerUnderFeet()
		local id = layer and layer.id or nil
		-- Re-apply jump on a layer change OR when eating starts/stops (the eating
		-- gate caps the jump — Task 4), so stepping onto sponge mid-eat stays flat
		-- and releasing the EAT button restores the spring.
		local nowEating = LocalEatState.Get()
		if id ~= appliedLayerId or nowEating ~= appliedEating then
			appliedLayerId = id
			appliedEating = nowEating
			applyJump(layer)
		end
	end)
end

return CakeFeelSubsClient
