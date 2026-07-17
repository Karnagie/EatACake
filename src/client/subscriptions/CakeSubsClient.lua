--[[
	CakeSubsClient — the cake domain on the client (R4):
	  * CakeSnapshot/CakeDelta -> LocalCakeField mirror, renderer refresh
	  * CakeCycleUpdate -> boss view, HUD cycle state, announcements
	  * input: tap/hold ANYWHERE near the cake = eat (§7.6 zero precision);
	    auto-repeat at the eat-rate stat; local bite prediction + full bite
	    juice (§7.3) fire instantly, the server delta reconciles after
	  * render step: renderer lerp, slump loop volume, camera shake
	  * landing crust crack (§7.1), treasure FX

	Mobile-first: touch position is tracked from Began/Moved; desktop uses
	the mouse location. No pixel-hunting: a miss falls back to the surface
	point in front of the character.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local JuiceConfig = require(Shared:WaitForChild("config"):WaitForChild("JuiceConfig"))

local SCOPE = "CakeSubsClient"

local CakeSubsClient = {}

function CakeSubsClient.Start(data, modules)
	local LocalCakeField = modules.LocalCakeField
	local CakeRenderer = modules.CakeRenderer
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local CameraShake = modules.CameraShake
	local ComboMeter = modules.ComboMeter
	local BodyMorphController = modules.BodyMorphController
	local BossView = modules.BossView
	local LocalStatsService = modules.LocalStatsService
	local ChunkDebris = modules.ChunkDebris
	local AppRoot = modules.AppRoot

	local player = Players.LocalPlayer
	local rEatAt = Net.Remote("EatAt")

	CakeRenderer.Setup(LocalCakeField)

	local eating = false
	local lastBiteAt = 0
	local crustCracked = true -- until the first snapshot says "fresh cake"
	local cyclePhase = "spawning"
	local touchPos: Vector2? = nil
	local trackedTouch: InputObject? = nil -- the finger that owns eat-hold/aim
	local profileLive = false -- first StomachUpdate = server accepts our bites
	local lastComboSent = 1
	local announceSeq = 0

	-- Single source for the banner lifetime (Theme.AnnounceBanner.Duration).
	local ANNOUNCE_SECONDS = require(Shared:WaitForChild("UIKit"):WaitForChild("Theme")).AnnounceBanner.Duration

	local function pushAnnounce(key: string)
		announceSeq += 1
		local seq = announceSeq
		AppRoot.Set({ announceKey = key })
		task.delay(ANNOUNCE_SECONDS, function()
			if announceSeq == seq then
				AppRoot.Set({ announceKey = false })
			end
		end)
	end

	-- ── Sync ────────────────────────────────────────────────────────────
	Net.Update("CakeSnapshotUpdate").OnClientEvent:Connect(function(buf, meta)
		if typeof(buf) ~= "buffer" or type(meta) ~= "table" then
			Log.Warn(SCOPE, "malformed snapshot payload — dropped")
			return
		end
		LocalCakeField.ApplySnapshot(buf, meta)
		CakeRenderer.OnSnapshot()
		cyclePhase = meta.phase or "eating"
		crustCracked = (meta.progress or 0) > 0.02 -- landed on a fresh crust?
		AppRoot.Set({ cake = {
			phase = cyclePhase,
			progress = meta.progress or 0,
			biome = meta.biome,
			rareKind = meta.rareKind,
		} })
		Log.Info(SCOPE, `snapshot: cake #{meta.cakeIndex}, biome={meta.biome}, rare={meta.rareKind or "no"}`)
	end)

	Net.Update("CakeDeltaUpdate").OnClientEvent:Connect(function(cakeIndex, buf)
		if type(cakeIndex) == "number" and typeof(buf) == "buffer" then
			LocalCakeField.ApplyDelta(cakeIndex, buf)
		end
	end)

	Net.Update("CakeCycleUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		cyclePhase = payload.phase or cyclePhase
		if cyclePhase == "boss" then
			if not BossView.IsShown() then
				BossView.Show()
				SoundPool.Play("fanfare", { pitchMult = 0.8 })
			end
			if payload.boss then
				BossView.SetHp(payload.boss.hp, payload.boss.maxHp)
			end
		else
			if BossView.IsShown() then
				BossView.Hide()
				ParticlePool.Burst(
					Vector3.new(CakeConfig.grid.origin.x, CakeConfig.grid.origin.y + 8, CakeConfig.grid.origin.z),
					Color3.fromRGB(255, 120, 160),
					24
				)
			end
		end
		if payload.announce == "cake-cleared" then
			SoundPool.Play("fanfare")
		elseif payload.announce and string.find(payload.announce, "rare-cake", 1, true) then
			SoundPool.Play("fanfare", { pitchMult = 1.2 })
		end
		if type(payload.announce) == "string" then
			pushAnnounce(payload.announce)
		end
		AppRoot.Set({ cake = {
			phase = cyclePhase,
			progress = payload.progress or 0,
			timer = payload.timer,
			boss = payload.boss,
			biome = payload.biome,
			rareKind = payload.rareKind,
			announce = payload.announce,
		} })
	end)

	-- First stomach push = profile loaded server-side; prediction may start.
	Net.Update("StomachUpdate").OnClientEvent:Connect(function()
		profileLive = true
	end)

	-- ── Treasure FX ─────────────────────────────────────────────────────
	Net.Update("TreasureUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
			return
		end
		if payload.event == "spawned" then
			ParticlePool.Burst(payload.position, Color3.fromRGB(255, 240, 160), 10)
			SoundPool.Play("uiClick", { pitchMult = 1.3 })
		elseif payload.event == "collected" then
			local mine = payload.byUserId == player.UserId
			ParticlePool.Burst(payload.position, Color3.fromRGB(140, 230, 255), mine and 18 or 8)
			if mine then
				SoundPool.Play("coinBurst")
			end
		end
	end)

	-- ── The bite ────────────────────────────────────────────────────────
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include

	local function refreshRaycastFilter()
		local list = {}
		-- Prefer the renderer's own columns (exact visual tops); the coarse
		-- server slabs stay as a fallback for the EditableMesh path.
		local cakeColumns = workspace:FindFirstChild("CakeColumns")
		if cakeColumns then
			table.insert(list, cakeColumns)
		end
		local collision = workspace:FindFirstChild("CakeCollision")
		if collision then
			table.insert(list, collision)
		else
			-- Legitimately late (server builds it in CakeSubs.Start) — warn
			-- only if it STILL isn't there after the grace period (R8).
			Log.GraceOnce(SCOPE, "cake-collision-folder", 10, function()
				return workspace:FindFirstChild("CakeCollision") == nil
			end, "workspace.CakeCollision never appeared — pointer aim degraded to char-forward bites")
		end
		raycastParams.FilterDescendantsInstances = list
	end

	-- The bite target: pointer ray vs the cake, else the surface right in
	-- front of the character. Clamped into server reach.
	-- ⚠ Coordinate spaces differ per input: InputObject.Position (touch) is
	-- GUI-inset space → ScreenPointToRay; GetMouseLocation is inset-free →
	-- ViewportPointToRay. Mixing them skews mobile aim up by the topbar.
	local function computeBitePoint(root: BasePart): Vector3?
		local camera = workspace.CurrentCamera
		local ray
		if touchPos then
			ray = camera:ScreenPointToRay(touchPos.X, touchPos.Y)
		else
			local m = UserInputService:GetMouseLocation()
			ray = camera:ViewportPointToRay(m.X, m.Y)
		end
		refreshRaycastFilter()
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, raycastParams)
		local candidate = hit and hit.Position or nil
		if candidate == nil then
			candidate = root.Position + root.CFrame.LookVector * 5
		end
		-- Clamp horizontally into reach so legit taps never get dropped.
		local dx = candidate.X - root.Position.X
		local dz = candidate.Z - root.Position.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		local maxDist = 14 + LocalStatsService.BiteRadius() * 0.5
		if dist > maxDist then
			local scale = maxDist / dist
			candidate = Vector3.new(root.Position.X + dx * scale, candidate.Y, root.Position.Z + dz * scale)
		end
		return LocalCakeField.SurfacePoint(candidate.X, candidate.Z)
	end

	local function doBite()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not LocalCakeField.HasCake() then
			return
		end

		if cyclePhase == "boss" then
			rEatAt:FireServer(root.Position)
			local origin = CakeConfig.grid.origin
			ParticlePool.Burst(
				Vector3.new(origin.x, origin.y + 10 + math.random() * 6, origin.z),
				Color3.fromRGB(255, 90, 120),
				5
			)
			SoundPool.Play("blorp", { pitchMult = 1.2 })
			CameraShake.Impulse(0.12)
			return
		end
		if cyclePhase ~= "eating" then
			return
		end

		local point = computeBitePoint(root)
		if not point then
			return
		end
		rEatAt:FireServer(point)

		-- No prediction/FX until the server confirms it accepts our bites
		-- (first StomachUpdate): predicting while the profile still loads
		-- carves phantom craters the server never made.
		if not profileLive then
			return
		end

		local removed, layer = LocalCakeField.PredictBite(
			point.X, point.Z, LocalStatsService.BiteRadius(), LocalStatsService.BiteDepth()
		)
		if removed and removed > 0 and layer then
			local combo = ComboMeter.RegisterBite()
			local intensity = ComboMeter.Intensity()
			if combo ~= lastComboSent then
				lastComboSent = combo
				AppRoot.Set({ combo = { value = combo, intensity = intensity } })
			end
			SoundPool.PlayBite(layer.sfx, combo)
			local surfaceH = point.Y - CakeConfig.grid.origin.y
			local biteColor = CakeRenderer.PaletteColor(surfaceH)
			ParticlePool.Burst(
				point + Vector3.new(0, 1, 0),
				biteColor,
				JuiceConfig.particles.crumbsPerBite + math.floor(intensity * 6)
			)
			-- The ripped-out chunk: physical crumbs arc out of the crater.
			ChunkDebris.Throw(
				point + Vector3.new(0, 0.8, 0),
				biteColor,
				JuiceConfig.chunks.perBite + math.floor(intensity * 2)
			)
			if layer.shatterFx then
				ParticlePool.Burst(point + Vector3.new(0, 1.5, 0), layer.colors.top, JuiceConfig.particles.shardsPerCrack)
				SoundPool.Play("crack")
			end
			CameraShake.Impulse(JuiceConfig.camera.biteShakeAmp * (0.6 + intensity))
			BodyMorphController.SquashImpulse()
		end
	end

	-- ── Input: hold to eat ──────────────────────────────────────────────
	-- Touch tracks the ORIGINATING InputObject: a second finger (jump
	-- button, camera drag) must neither hijack the aim nor cancel the hold.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			eating = true
		elseif input.UserInputType == Enum.UserInputType.Touch and trackedTouch == nil then
			trackedTouch = input
			touchPos = Vector2.new(input.Position.X, input.Position.Y)
			eating = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == trackedTouch then
			touchPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			eating = false
		elseif input == trackedTouch then
			trackedTouch = nil
			touchPos = nil
			eating = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		-- Auto-Eat pass (server sets the attribute): always chewing.
		if eating or player:GetAttribute("AutoEat") == true then
			local now = os.clock()
			if now - lastBiteAt >= 1 / math.max(0.5, LocalStatsService.EatRate()) then
				lastBiteAt = now
				doBite()
			end
		end
		-- Combo lapse: the HUD badge must drop back to hidden.
		if lastComboSent > 1 and ComboMeter.Current() == 1 then
			lastComboSent = 1
			AppRoot.Set({ combo = { value = 1, intensity = 0 } })
		end
	end)

	-- ── Render step ─────────────────────────────────────────────────────
	local lastCrunchAt = 0
	RunService.RenderStepped:Connect(function(dt)
		local footPos = nil
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local surfacePoint = LocalCakeField.SurfacePoint(root.Position.X, root.Position.Z)
			if surfacePoint and math.abs(root.Position.Y - surfacePoint.Y) < 7 then
				footPos = surfacePoint
			end
		end
		CakeRenderer.Step(dt, footPos)
		SoundPool.PushSlumpEnergy(LocalCakeField.DrainAvalanche())
		SoundPool.Step(dt)
		ParticlePool.Step(dt)
		BossView.Step(dt)

		-- Walk crunch (§7.2): footstep-cadence crust sound + crumb puffs
		-- while moving on the cake — the crust must FEEL crunchy.
		if footPos and root then
			local crunch = JuiceConfig.walkCrunch
			local velocity = root.AssemblyLinearVelocity
			local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
			local now = os.clock()
			if speed >= crunch.minSpeed and now - lastCrunchAt >= crunch.interval then
				lastCrunchAt = now
				local surfaceH = footPos.Y - CakeConfig.grid.origin.y
				local layer = LocalCakeField.LayerAtStuds(surfaceH)
				if layer then
					SoundPool.Play(layer.sfx, { volumeMult = crunch.volumeMult, pitchMult = crunch.pitchMult })
					ParticlePool.Burst(footPos, CakeRenderer.PaletteColor(surfaceH), crunch.particles)
				end
			end
		end
	end)

	RunService:BindToRenderStep("CakeCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local offset = CameraShake.Step(dt)
		if offset ~= CFrame.identity then
			workspace.CurrentCamera.CFrame *= offset
		end
	end)

	-- ── Crust crack on landing (§7.1) ───────────────────────────────────
	local function hookCharacter(character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			Log.Warn(SCOPE, "character without Humanoid — crust-crack hook skipped")
			return
		end
		humanoid.StateChanged:Connect(function(_, new)
			if new ~= Enum.HumanoidStateType.Landed or crustCracked then
				return
			end
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end
			local surfacePoint = LocalCakeField.SurfacePoint(root.Position.X, root.Position.Z)
			if surfacePoint and math.abs(root.Position.Y - surfacePoint.Y) < 8 then
				crustCracked = true
				SoundPool.Play("crustCrack")
				CameraShake.Impulse(JuiceConfig.camera.crustCrackAmp)
				local color = CakeRenderer.PaletteColor(surfacePoint.Y - CakeConfig.grid.origin.y)
				for k = 1, 6 do -- radial shard ring
					local angle = k / 6 * math.pi * 2
					ParticlePool.Burst(
						surfacePoint + Vector3.new(math.cos(angle) * 4, 1, math.sin(angle) * 4),
						color,
						JuiceConfig.particles.shardsPerCrack / 2
					)
				end
			end
		end)
	end
	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
end

return CakeSubsClient
