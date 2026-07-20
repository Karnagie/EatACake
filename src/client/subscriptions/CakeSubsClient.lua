--[[
	CakeSubsClient — the cake domain on the client (R4):
	  * CakeSnapshot/CakeDelta -> LocalCakeField mirror, renderer refresh
	  * CakeCycleUpdate -> boss view, HUD cycle state, announcements
	  * input: tap/HOLD to eat the cake DIRECTLY IN FRONT of you (aim by
	    turning/walking — no pointer/pixel aiming); auto-repeat at the eat-rate
	    stat; local bite prediction + full bite juice (§7.3) + the eat gesture
	    (EatGestureController) fire instantly, the server delta reconciles after
	  * full belly: stop eating (mirror the server block) + a slow self-probe
	    so a capacity increase unsticks it
	  * render step: renderer lerp, slump loop volume, camera shake, eat gesture
	  * walk-crunch + step cracks, treasure FX (landing cracks + the
	    fresh-cake ceremony live in CakeFeelSubsClient)

	Hold ownership: on touch, the ORIGINATING finger owns the hold, so a second
	finger (jump button, camera drag) neither starts a rival hold nor cancels it.
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
	local CakeWaxShell = modules.CakeWaxShell
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local CameraShake = modules.CameraShake
	local ComboMeter = modules.ComboMeter
	local EatGestureController = modules.EatGestureController
	local BossView = modules.BossView
	local LocalStatsService = modules.LocalStatsService
	local ChunkDebris = modules.ChunkDebris
	local AppRoot = modules.AppRoot

	local player = Players.LocalPlayer
	local rEatAt = Net.Remote("EatAt")

	CakeRenderer.Setup(LocalCakeField)
	CakeWaxShell.Setup(LocalCakeField)

	local eating = false
	local lastBiteAt = 0
	local cyclePhase = "spawning"
	local trackedTouch: InputObject? = nil -- the finger that owns the eat-hold
	local profileLive = false -- first StomachUpdate = server accepts our bites
	local isFull = false -- belly at capacity: eating is blocked (server + here)
	local lastFullCueAt = 0
	local lastLockCueAt = 0 -- layer gate: debounce the "eat the top layer first" cue
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
		-- OnSnapshot can YIELD (lazy mesh-pool build). If a newer snapshot
		-- was applied while we yielded, ITS handler owns phase/HUD state —
		-- never overwrite it with this stale meta.
		local current = LocalCakeField.Meta()
		if current ~= nil and current.cakeIndex ~= meta.cakeIndex then
			Log.Info(SCOPE, `snapshot #{meta.cakeIndex} superseded by #{current.cakeIndex} during rebuild — state writes skipped`)
			return
		end
		cyclePhase = meta.phase or "eating"
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
		-- Layer gate: keep the prediction/lock floor in sync between snapshots.
		if type(payload.activeBandIndex) == "number" then
			LocalCakeField.SetActiveBand(payload.activeBandIndex)
		end
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
	-- It also carries fill/capacity — mirror the "full = can't eat" state so
	-- the client stops firing (and predicting phantom craters) the instant the
	-- belly tops out, matching the server's authoritative block.
	Net.Update("StomachUpdate").OnClientEvent:Connect(function(payload)
		profileLive = true
		if type(payload) == "table" then
			local fill = tonumber(payload.fill)
			local capacity = tonumber(payload.capacity)
			if fill and capacity and capacity > 0 then
				isFull = fill >= capacity
			end
		end
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
	-- You eat the cake DIRECTLY IN FRONT of you (not where you tap): the
	-- surface a few studs ahead along the character's facing, snapped to the
	-- field. nil when you're facing off the loaf (nothing in front to eat) —
	-- turn/walk to aim. The forward reach grows a little with bite radius and
	-- stays well inside the server's reach cap (antiCheat.maxBiteReachStuds).
	local function computeBitePoint(root: BasePart): Vector3?
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 1e-3 then
			-- Degenerate facing (looking straight up/down): use any horizontal.
			local right = root.CFrame.RightVector
			flat = Vector3.new(right.X, 0, right.Z)
			if flat.Magnitude < 1e-3 then
				return nil
			end
		end
		-- Close in front of you (~half the old distance — the cake was tearing
		-- off too far ahead); still grows a touch with bite radius.
		local reach = 3 + LocalStatsService.BiteRadius() * 0.25
		local ahead = root.Position + flat.Unit * reach
		return LocalCakeField.SurfacePoint(ahead.X, ahead.Z)
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

		-- Belly full = can't eat (the server drops these too): skip the phantom
		-- prediction/gesture and cue softly. But do NOT hard-block forever —
		-- PROBE at a slow cadence: still fire the occasional EatAt so the block
		-- self-clears the instant we're eligible again (a capacity upgrade /
		-- gamepass raises the cap → the server accepts → its StomachUpdate
		-- resets isFull). A genuinely-full belly just no-ops server-side.
		if isFull then
			local now = os.clock()
			if now - lastFullCueAt > 0.6 then
				lastFullCueAt = now
				SoundPool.Play("uiClick", { pitchMult = 0.65 })
				local probe = computeBitePoint(root)
				if probe then
					rEatAt:FireServer(probe)
				end
			end
			return
		end

		local point = computeBitePoint(root)
		if not point then
			return
		end

		-- Layer gate: you must finish the current TOP layer before the next
		-- unlocks. If the surface directly ahead is already eaten down to the
		-- active-band floor, this bite would try to dig into the still-locked
		-- layer beneath — cue "eat the top layer first" and skip it (the server
		-- clamps to this floor too; here it's the instant, local nudge). The
		-- cue only fires for HELD input, so passive Auto-Eat never nags.
		if CakeConfig.layerGate.enabled then
			local activeFloor = LocalCakeField.ActiveFloorStuds()
			if activeFloor and LocalCakeField.ActiveBandIndex() >= 2
				and point.Y - CakeConfig.grid.origin.y <= activeFloor + CakeConfig.layerGate.lockEpsilon
			then
				if eating then
					local now = os.clock()
					if now - lastLockCueAt > CakeConfig.layerGate.cueInterval then
						lastLockCueAt = now
						SoundPool.Play("uiClick", { pitchMult = 0.55 })
						pushAnnounce("layer-locked")
					end
				end
				return
			end
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
			-- Eat gesture: rip this layer's piece out of the cake in front and
			-- fly it hand -> mouth. Speed tracks the eat-rate stat. LOCAL only,
			-- like the rest of this bite's juice.
			EatGestureController.Play(point, layer, LocalStatsService.EatRate())
		end
	end

	-- ── Input: hold to eat ──────────────────────────────────────────────
	-- Hold anywhere to keep eating the cake IN FRONT of you (aim by turning /
	-- walking, not by tapping a spot). Touch tracks the ORIGINATING finger so
	-- a second finger (jump button, camera drag) neither starts a rival hold
	-- nor cancels this one.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			eating = true
		elseif input.UserInputType == Enum.UserInputType.Touch and trackedTouch == nil then
			trackedTouch = input
			eating = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			eating = false
		elseif input == trackedTouch then
			trackedTouch = nil
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
		CakeWaxShell.Step(dt, footPos) -- always-visible wax coating that cracks underfoot
		EatGestureController.Step(dt) -- advance the local flying eat pieces
		SoundPool.PushSlumpEnergy(LocalCakeField.DrainAvalanche())
		SoundPool.Step(dt)
		ParticlePool.Step(dt)
		BossView.Step(dt)

		-- Walk crunch (§7.2): footstep-cadence crust sound + crumb puffs while
		-- moving on the cake — the crust must FEEL crunchy. The wax-film cracks
		-- themselves follow the foot continuously in CakeRenderer.Step (the
		-- underfoot reveal), so there is no per-step crack draw here.
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

	-- Landing crust cracks + the fresh-cake first-crack ceremony (§7.1)
	-- live in CakeFeelSubsClient — ONE Landed handler owns landings.
end

return CakeSubsClient
