--[[
	CakeSubsClient — the cake domain on the client (R4):
	  * CakeSnapshot/CakeDelta -> LocalCakeField mirror, renderer refresh
	  * CakeCycleUpdate -> boss + ZONE-GATE mini-boss views, HUD cycle state,
	    announcements
	  * input: PC = hold the mouse ANYWHERE; TOUCH = the dedicated on-screen EAT
	    button only (AppRoot EatButton, NOT any finger — the joystick never eats,
	    Task 3). Either way you eat the cake DIRECTLY IN FRONT of you (aim by
	    turning/walking — no pointer/pixel aiming); auto-repeat at the eat-rate
	    stat; local bite prediction + full bite juice (§7.3) + the eat gesture
	    (EatGestureController) fire instantly, the server delta reconciles after
	  * full belly: stop eating (mirror the server block) + a slow self-probe
	    so a capacity increase unsticks it
	  * render step: renderer lerp, slump loop volume, camera shake, eat gesture
	  * walk-crunch + step cracks, treasure FX (landing cracks + the
	    fresh-cake ceremony live in CakeFeelSubsClient)

	Touch eating is driven ONLY by the dedicated EAT button (AppRoot EatButton →
	onEatDown/onEatUp), never by a raw finger — so the movement joystick and
	camera drag can't trigger eating (Task 3). PC still holds the mouse anywhere.
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
local TreasureConfig = require(Shared:WaitForChild("config"):WaitForChild("TreasureConfig"))

local SCOPE = "CakeSubsClient"

local CakeSubsClient = {}

function CakeSubsClient.Start(data, modules)
	if data.GameUiData == nil then
		Log.Info(SCOPE, "game client partition absent -- cake rendering/input skipped in lobby")
		return
	end
	local LocalCakeField = modules.LocalCakeField
	local CakeRenderer = modules.CakeRenderer
	local CakeWaxShell = modules.CakeWaxShell
	local CakeWrapper = modules.CakeWrapper -- textured outer wall hiding the ungenerated bulk (Task 2)
	local SoundPool = modules.SoundPool
	local ParticlePool = modules.ParticlePool
	local CameraShake = modules.CameraShake
	local ComboMeter = modules.ComboMeter
	local EatGestureController = modules.EatGestureController
	local BossView = modules.BossView
	local MiniBossView = modules.MiniBossView -- zone-gate boss (features/cake-cycle.md)
	local LocalStatsService = modules.LocalStatsService
	local ChunkDebris = modules.ChunkDebris
	local AppRoot = modules.AppRoot
	local LocalEatState = modules.LocalEatState -- flat-while-eating gate (Task 4)
	local PlayerControlService = modules.PlayerControlService
	local FloatingNumbers = modules.FloatingNumbers
	local FoodBurst = modules.FoodBurst -- celebration confetti (features/food-burst.md)
	local LocaleData = data.LocaleData

	local player = Players.LocalPlayer
	local rEatAt = Net.Remote("EatAt")
	if MiniBossView == nil then
		-- The gate is SERVER-side, so the fight still works and still blocks the
		-- cake — the player just gets no monster to look at. Never silent (R8).
		Log.Warn(SCOPE, "MiniBossView module missing -- zone-gate mini-bosses will be invisible (the fight still gates the cake)")
	end
	if FoodBurst == nil then
		-- Cosmetic only: the cheer banner, the chime and the camera punch all
		-- still fire, the celebration just loses its confetti. Never silent (R8).
		Log.Warn(SCOPE, "FoodBurst module missing -- layer/monster celebrations will have no food confetti")
	end
	local controlGateReady = PlayerControlService ~= nil and type(PlayerControlService.IsLocked) == "function"
	if not controlGateReady then
		Log.Warn(SCOPE, "PlayerControlService.IsLocked missing -- cake input disabled to avoid unsafe handoff prediction")
	end
	local function inputLocked(): boolean
		if not controlGateReady then
			return true
		end
		local ok, lockedOrError = pcall(PlayerControlService.IsLocked)
		if not ok then
			Log.Once(SCOPE, "control-gate-failed", `PlayerControlService.IsLocked FAILED -- cake input disabled: {lockedOrError}`)
			return true
		end
		return lockedOrError == true
	end

	-- ── Burial rescue ───────────────────────────────────────────────────
	-- The cake is only COLLIDABLE once this client's columns are built, but the
	-- character is placed at cake height before that (the spawn pad on join, the
	-- server's new-cake lift) — so it can end up UNDER the surface, and
	-- `columnsRebuild` then closes 1024 solid columns around it.
	--
	-- ⚠ This used to be called from exactly ONE place, right after a snapshot's
	-- rebuild. A reserved match broadcasts ONE snapshot per ~35-minute session, so
	-- that single check was the only recovery the game had: if it was voided (no
	-- character yet, a control lock held, or the burial happened later — a
	-- respawn, a walk back from the checkpoint) the player stayed inside the cake
	-- for the whole match. It is now armed three ways: after a rebuild, on every
	-- fresh character, and on a slow dwell-gated timer.
	-- Config + rationale in `CakeConfig.render.collision.buriedRescue*`.

	-- The world Y of the SOLID surface the character is standing in/on, or nil if
	-- there is none there.
	--
	-- ⚠ This asks the COLLISION COLUMNS, not the field. The two are deliberately
	-- different: `render.collision.riseRate` holds a column BELOW the field while
	-- refilling cake oozes back, which is the "you stay buried, jump out" feel. A
	-- field-based test therefore reads a big depth during exactly that feel, and a
	-- rescue driven by it would teleport the player to the full refilled height —
	-- the punt the rise cap exists to prevent. The column top is what the
	-- character is physically inside, which is the only thing "buried" can mean.
	-- It also covers the rim ring, where the field says nothing (`SurfacePoint`
	-- nil outside the footprint) but a column can stand at FULL cake height
	-- because `CakeRenderer.colTarget` averages only the IN-cake cells of its
	-- block. That ring used to be an unrecoverable trap.
	local function solidTopAt(root: BasePart): number?
		if CakeRenderer.ColumnTopAt == nil then
			Log.Once(SCOPE, "column-top-missing", "CakeRenderer.ColumnTopAt missing -- burial rescue falls back to the field surface")
			local surface = LocalCakeField.SurfacePoint(root.Position.X, root.Position.Z)
			return if surface ~= nil then surface.Y else nil
		end
		return CakeRenderer.ColumnTopAt(root.Position.X, root.Position.Z)
	end

	-- How deep the character is inside solid cake, or nil when it is not.
	local function buriedDepth(root: BasePart): number?
		local top = solidTopAt(root)
		if top == nil then
			return nil
		end
		local depth = top - root.Position.Y
		return if depth >= CakeConfig.render.collision.buriedRescueStuds then depth else nil
	end

	local function liftOut(root: BasePart, depth: number, why: string)
		local cfg = CakeConfig.render.collision
		-- `buriedDepth` proved a solid top exists; re-read it so the lift lands on
		-- the CURRENT top rather than on a stale one.
		local top = solidTopAt(root) or (root.Position.Y + depth)
		-- Zero the assembly: a bare CFrame write keeps velocity, and a character
		-- being lifted is usually one that has been falling.
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(root.Position.X, top + cfg.buriedRescueLift, root.Position.Z)
		Log.Warn(SCOPE, `local character was {math.floor(depth)} studs INSIDE the cake ({why}) — lifted onto the surface`)
	end

	-- Snapshot path: the rebuild has just made the cake solid, so a character
	-- under it is buried NOW — no dwell, lift immediately.
	local function rescueBuriedLocal()
		if inputLocked() then
			return -- a teleport handoff owns the character; never yank it mid-flight
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			return -- no character yet; the timed watchdog below owns this case now
		end
		local depth = buriedDepth(root)
		if depth ~= nil then
			liftOut(root, depth, "join/load race")
		end
	end

	-- Timed watchdog: the safety net for every burial the snapshot path cannot
	-- see. Dwell-gated so it can NEVER undo the deliberate "refilling cake buries
	-- you, jump out" feel (`render.collision.riseRate`) — that state resolves in a
	-- jump; staying buried for `buriedRescueDwellSeconds` straight does not.
	local buriedSince: number? = nil
	local rescuePollClock = 0
	local function watchdogStep(dt: number, root: BasePart?)
		local cfg = CakeConfig.render.collision
		rescuePollClock += dt
		if rescuePollClock < cfg.buriedRescuePollSeconds then
			return
		end
		rescuePollClock = 0
		if root == nil then
			buriedSince = nil
			return
		end
		if inputLocked() then
			-- SKIP this tick, do not forfeit: unlike the old one-shot path, a lock
			-- held right now costs nothing — we re-check in half a second. But a
			-- lock that never clears silently disables the last safety net (R8).
			if buriedSince ~= nil then
				Log.Once(SCOPE, "watchdog-locked", "burial watchdog is holding off: a movement lock is held while the character is buried")
			end
			return
		end
		local depth = buriedDepth(root)
		if depth == nil then
			buriedSince = nil
			return
		end
		buriedSince = (buriedSince or 0) + cfg.buriedRescuePollSeconds
		if buriedSince >= cfg.buriedRescueDwellSeconds then
			buriedSince = nil
			liftOut(root, depth, `buried for {cfg.buriedRescueDwellSeconds}s`)
		end
	end

	-- A fresh character was not on the cake while its columns went stale, so the
	-- rate-limited rise has nothing to protect: snap them to truth before it
	-- lands, then re-check. Without this a respawn onto a refilled centre rests on
	-- the coarse server slab (the MIN of its 6x6-stud block) several studs under
	-- its own surface.
	local function armFreshCharacter(character: Model)
		buriedSince = nil
		-- Snap immediately (no root needed), then re-snap and re-check once the
		-- character has had time to land. ⚠ No blocking WaitForChild here (R8):
		-- on a slow client it would delay the snap by up to its timeout, which is
		-- the very window this exists to close. If the root is still missing at the
		-- re-check the timed watchdog owns the case.
		CakeRenderer.SnapCollisionNow()
		task.delay(CakeConfig.render.collision.freshCharacterSnapSeconds, function()
			if player.Character ~= character then
				return -- died again; that life's own arming handles it
			end
			CakeRenderer.SnapCollisionNow()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root == nil then
				Log.Once(SCOPE, "fresh-character-no-root", "fresh character had no HumanoidRootPart at the spawn re-check -- the timed watchdog covers it")
				return
			end
			local depth = buriedDepth(root)
			if depth ~= nil and not inputLocked() then
				liftOut(root, depth, "respawn onto stale collision")
			end
		end)
	end
	player.CharacterAdded:Connect(armFreshCharacter)
	-- ⚠ Arm the character that ALREADY exists too. LocalBootstrap requires ~40
	-- modules before this subscription Starts, so on a slow client life #1 has
	-- already spawned and CharacterAdded will never fire for it — and life #1 on
	-- the join is precisely the reported symptom.
	if player.Character then
		armFreshCharacter(player.Character)
	end

	CakeRenderer.Setup(LocalCakeField)
	CakeWaxShell.Setup(LocalCakeField)
	CakeWrapper.Setup(LocalCakeField)

	local eating = false
	local lastBiteAt = 0
	local cyclePhase = "spawning"
	local lastCuedPhase = cyclePhase -- phase-ENTRY cues fire once per transition
	local profileLive = false -- first StomachUpdate = server accepts our bites
	local isFull = false -- belly at capacity: eating is blocked (server + here)
	local lastFullCueAt = 0
	local lastLockCueAt = 0 -- layer gate: debounce the "eat the top layer first" cue
	-- When the last CELEBRATION started (layer cleared / Cake Monster down).
	-- A layer FINISHES exactly while you are mowing its floor, which is also
	-- when the locked cue wants to fire — so the nag used to stomp the
	-- celebration within one frame (seen in playtest). The celebration wins,
	-- and since it became a full splash the same applies to find banners.
	local lastCelebrationAt = -math.huge
	-- ⚠ Set BELOW from the celebration banner's own Duration, so the window can
	-- never end up shorter than the splash it protects. It used to be a bare
	-- 2.5 that happened to exceed the 2.4 s banner by a tenth — anyone tuning
	-- the splash to 3 s would have silently reinstated the playtest bug.
	local LAYER_CLEAR_PRIORITY_SECONDS
	-- Which zone gate's ENTRANCE has already been played (nil = not in a gate).
	-- Keyed on the gate index rather than a boolean so the three gates of one
	-- cake each get their own breach, and cleared on every exit.
	local miniBossCuedGate: number? = nil
	-- Spots where a buried find is close enough to the surface to glint through
	-- the icing. Keyed by find+position so a new cake's finds never collide with
	-- a stale entry; cleared when the crown breaks through (see TreasureUpdate)
	-- AND wholesale on a new cake — a find left in the server's `loaded` state
	-- when the cake resets never sends its `revealed`, so its marker would sit
	-- here forever, glinting a spot on the NEXT cake that holds nothing and
	-- eating the `maxMarkers` budget that real finds need.
	local nearMarkers: { [string]: { x: number, z: number, color: Color3 } } = {}
	local markersCakeIndex: number? = nil
	local glintClock = 0
	local lastComboSent = 1
	local announceSeq = 0

	-- Single source for both banner lifetimes (Theme.*.Duration).
	local KitTheme = require(Shared:WaitForChild("UIKit"):WaitForChild("Theme"))
	local ANNOUNCE_SECONDS = KitTheme.AnnounceBanner.Duration
	local CELEBRATION_SECONDS = KitTheme.CelebrationBanner.Duration
	-- The nag/find banners must not stomp a celebration that is still playing.
	LAYER_CLEAR_PRIORITY_SECONDS = math.max(2.5, CELEBRATION_SECONDS)

	-- True while a layer/monster celebration owns the screen. Lower-value
	-- banners check this instead of pushing over it — the "eat the top layer
	-- first" nag already had to (it fires in the same frame the layer ends), and
	-- since the celebration became a full splash a rare FIND lands in exactly
	-- the same window: you mow the last cells of a band and uncover something at
	-- once, which is routine rather than rare.
	local function celebrationOwnsScreen(): boolean
		return os.clock() - lastCelebrationAt <= LAYER_CLEAR_PRIORITY_SECONDS
	end

	local function pushAnnounce(key: string)
		announceSeq += 1
		local seq = announceSeq
		-- Retires any celebration splash still on screen: the two banners share
		-- the top of the screen and one must always win outright.
		AppRoot.Set({ announceKey = key, celebration = false })
		task.delay(ANNOUNCE_SECONDS, function()
			if announceSeq == seq then
				AppRoot.Set({ announceKey = false })
			end
		end)
	end

	-- CELEBRATION (features/food-burst.md): the big splash + a burst of food.
	-- `kind` selects the cheer list ("layer" / "monster"), `subKey` is the
	-- optional factual second line, `count` how many sprites to launch.
	--
	-- ⚠ It shares `announceSeq` with pushAnnounce ON PURPOSE. The two banners
	-- occupy the same beat and must never overlap: a plain announce arriving
	-- mid-celebration has to be able to retire the splash, and vice versa, which
	-- one shared sequence number gives for free.
	local function pushCelebration(kind: string, fallbackKey: string, subKey: string?)
		announceSeq += 1
		local seq = announceSeq
		-- Arms the priority window for BOTH beats — the single writer. Setting it
		-- in the `layer-cleared` branch instead left the Cake Monster's splash,
		-- the bigger of the two, unprotected from the nag and the find banners.
		lastCelebrationAt = os.clock()
		-- The phrase is rolled HERE, once, and travels as a KEY: the HUD
		-- re-renders ~14x/second while the splash is up, and rolling inside the
		-- render would deal a new phrase on every bite.
		-- ⚠ LocaleData is treated as optional everywhere else in this file
		-- (the bootstrap pcalls each data Init and KEEPS GOING), and a throw
		-- here would abort the rest of the CakeCycleUpdate handler — including
		-- the AppRoot.Set that carries phase, timer, finds and monster HP.
		local cheerKey = fallbackKey
		if LocaleData ~= nil and type(LocaleData.RollCheer) == "function" then
			cheerKey = LocaleData.RollCheer(kind, fallbackKey)
		else
			Log.Once(SCOPE, "cheer-no-locale", "LocaleData.RollCheer missing — celebrations use the fixed fallback line")
		end
		AppRoot.Set({
			-- On the fallback path the cheer can BE the subtitle's key; showing
			-- one sentence stacked on itself is worse than showing it once.
			celebration = { cheerKey = cheerKey, subKey = if subKey ~= cheerKey then subKey else nil, seq = seq },
			announceKey = false,
		})
		if FoodBurst ~= nil then
			FoodBurst.Fire(kind)
		end
		task.delay(CELEBRATION_SECONDS, function()
			if announceSeq == seq then
				AppRoot.Set({ celebration = false })
			end
		end)
	end

	-- ── Sync ────────────────────────────────────────────────────────────
	Net.Update("CakeSnapshotUpdate").OnClientEvent:Connect(function(buf, meta)
		if typeof(buf) ~= "buffer" or type(meta) ~= "table" then
			Log.Warn(SCOPE, "malformed snapshot payload — dropped")
			return
		end
		-- Drop stale glint spots BEFORE the yielding rebuild below (the supersede
		-- guard can early-return past it). Guarded on cakeIndex, NOT unconditional:
		-- `near` fires once per find, and a mid-cake snapshot resend (a joining
		-- player) would otherwise wipe still-valid markers permanently.
		if meta.cakeIndex ~= markersCakeIndex then
			markersCakeIndex = meta.cakeIndex
			table.clear(nearMarkers)
		end
		LocalCakeField.ApplySnapshot(buf, meta)
		CakeWrapper.OnSnapshot() -- pick this cake's wall texture (before the renderer rebuild yields)
		CakeRenderer.OnSnapshot() -- ends in columnsRebuild(): the cake is collidable NOW
		rescueBuriedLocal() -- ...so this is the first moment a fall-through is recoverable
		-- OnSnapshot can YIELD (lazy mesh-pool build). If a newer snapshot
		-- was applied while we yielded, ITS handler owns phase/HUD state —
		-- never overwrite it with this stale meta.
		local current = LocalCakeField.Meta()
		if current ~= nil and current.cakeIndex ~= meta.cakeIndex then
			Log.Info(SCOPE, `snapshot #{meta.cakeIndex} superseded by #{current.cakeIndex} during rebuild — state writes skipped`)
			return
		end
		cyclePhase = meta.phase or "eating"
		-- A fresh cake can never have a live gate; drop any rig still standing
		-- (no poof — it was not beaten, the cake was replaced under it).
		if MiniBossView ~= nil and cyclePhase ~= "miniboss" then
			miniBossCuedGate = nil
			if MiniBossView.IsShown() then
				MiniBossView.Hide(false)
			end
		end
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
		if cyclePhase ~= lastCuedPhase then
			lastCuedPhase = cyclePhase
			if cyclePhase == "spawning" then
				SoundPool.Play("newCake") -- the next cake is on its way in
			end
		end
		-- Layer gate: keep the prediction/lock floor in sync between snapshots.
		if type(payload.activeBandIndex) == "number" then
			LocalCakeField.SetActiveBand(payload.activeBandIndex)
		end
		-- ── ZONE GATE (features/cake-cycle.md) ──────────────────────────
		-- A mini-boss bursts UP THROUGH the cake when the layer gate crosses
		-- into the next flavour zone. Same tap, different target: the cake is
		-- off the menu until it is beaten.
		if MiniBossView ~= nil then
			local mini = if type(payload.miniBoss) == "table" then payload.miniBoss else nil
			if cyclePhase == "miniboss" and mini ~= nil then
				-- ⚠ The entrance juice is latched on the GATE INDEX — i.e. on the
				-- phase transition — NOT on `MiniBossView.IsShown()`. Gating it on
				-- the view's success looks equivalent and is not: `Show` no-ops
				-- when the rig cannot be resolved (no `Assets.MiniBosses` in a
				-- fresh clone, a renamed rig, a template harvest into a new game),
				-- `IsShown()` then stays false forever, and since this update
				-- repeats at 1 Hz for a fight that is UNTIMED BY DESIGN the player
				-- would take a boss sting, a 0.55 camera punch (trauma is
				-- ADDITIVE, so it never decays back) and 100 particles EVERY
				-- SECOND until they tapped the gate down.
				if miniBossCuedGate ~= mini.index then
					miniBossCuedGate = mini.index
					-- THE BREACH: crust blows out in a ring around the hole it
					-- came through, the camera takes a punch, and the boss sting
					-- plays. The view owns the rig; the juice belongs here with
					-- the rest of the bite/layer FX.
					local origin = CakeConfig.grid.origin
					local surface = LocalCakeField.SurfacePoint(origin.x, origin.z)
					SoundPool.Play("bossAppear")
					CameraShake.Impulse(0.55)
					local burstY = (surface and surface.Y) or (origin.y + 1)
					for step = 0, 9 do
						local angle = step * math.pi / 5
						ParticlePool.Burst(
							Vector3.new(origin.x + math.cos(angle) * 9, burstY + 2, origin.z + math.sin(angle) * 9),
							Color3.fromRGB(255, 236, 200),
							10
						)
					end
				end
				-- Retried every update on purpose: it is a FindFirstChild + a
				-- Log.Once when the folder is missing, so a late-replicating
				-- Assets tree still gets its boss instead of an invisible fight.
				if not MiniBossView.IsShown() then
					local origin = CakeConfig.grid.origin
					local surface = LocalCakeField.SurfacePoint(origin.x, origin.z)
					local zoneName = if type(mini.zoneKey) == "string" and LocaleData ~= nil
						then LocaleData.T(mini.zoneKey)
						else ""
					MiniBossView.Show(mini.model, zoneName, surface and surface.Y, mini.hp, mini.maxHp)
				end
				MiniBossView.SetHp(mini.hp, mini.maxHp)
			else
				-- Defeated (the usual exit) or wiped by a new cake / phase reset.
				-- The win sting is keyed on the ANNOUNCE + the latch, not on
				-- IsShown, so a gate fought without a visible rig still resolves
				-- audibly.
				local defeated = payload.announce == "miniboss-defeated"
				if MiniBossView.IsShown() then
					MiniBossView.Hide(defeated)
				end
				if defeated and miniBossCuedGate ~= nil then
					SoundPool.Play("bossDefeat")
					CameraShake.Impulse(0.3)
				end
				miniBossCuedGate = nil
			end
		end
		if cyclePhase == "boss" then
			if not BossView.IsShown() then
				BossView.Show()
				SoundPool.Play("bossAppear")
			end
			-- ⚠ No BossView.SetHp: the Cake Monster's world-space HP bar was
			-- removed 2026-08-13 (features/cake-cycle.md). Its health reaches
			-- the player through the HUD's CakeBar, fed by the AppRoot.Set at
			-- the bottom of this handler — `payload.boss` is still carried.
		else
			if BossView.IsShown() then
				BossView.Hide()
				-- A boss fight can be LOST — the win sting must not score a defeat.
				SoundPool.Play(if payload.announce == "match-lost" then "bossLost" else "bossDefeat")
				ParticlePool.Burst(
					Vector3.new(CakeConfig.grid.origin.x, CakeConfig.grid.origin.y + 8, CakeConfig.grid.origin.z),
					Color3.fromRGB(255, 120, 160),
					24
				)
			end
		end
		-- ── the two CELEBRATION beats (features/food-burst.md) ────────────
		-- Both take the big splash + a burst of food instead of the plain
		-- announce line, so `celebrated` suppresses pushAnnounce below: two
		-- banners in one frame stomp each other.
		local celebrated = false
		if payload.announce == "cake-cleared" then
			SoundPool.Play("cakeCleared")
			-- The Cake Monster is down. Biggest burst in the game, hardest
			-- punch, and the cheer keeps `cake-cleared` as its SUBTITLE — the
			-- phrase carries the feeling, that line carries the squishy.
			CameraShake.Impulse(0.42)
			pushCelebration("monster", "cake-cleared", "cake-cleared")
			celebrated = true
		elseif payload.announce == "miniboss-defeated" then
			-- A ZONE GATE beaten. It gets the SAME treatment as the finale (user
			-- request 2026-08-13) — splash, cheer, confetti — at the middle of
			-- the three sizes, because it happens ~4x a cake. The defeat sting
			-- and the poof already fired in the MiniBossView block above; the
			-- camera punch belongs with the celebration, not with the view.
			CameraShake.Impulse(0.32)
			pushCelebration("crumb", "miniboss-defeated")
			celebrated = true
		elseif payload.announce == "layer-cleared" then
			-- A whole layer gone: chime, a soft punch and a ring of crumbs kicked
			-- up around the eater. The rhythm beat of the whole session.
			SoundPool.Play("layerCleared")
			CameraShake.Impulse(0.22)
			pushCelebration("layer", "layer-cleared")
			celebrated = true
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for step = 0, 7 do
					local angle = step * math.pi / 4
					ParticlePool.Burst(
						root.Position + Vector3.new(math.cos(angle) * 7, -2, math.sin(angle) * 7),
						Color3.fromRGB(255, 236, 200),
						7
					)
				end
			end
		elseif payload.announce and string.find(payload.announce, "rare-cake", 1, true) then
			SoundPool.Play("rareCake")
		end
		if not celebrated and type(payload.announce) == "string" then
			pushAnnounce(payload.announce)
		end
		AppRoot.Set({ cake = {
			phase = cyclePhase,
			progress = payload.progress or 0,
			timer = payload.timer,
			boss = payload.boss,
			biome = payload.biome,
			rareKind = payload.rareKind,
			finds = payload.finds, -- per-cake find goal for the HUD bar
			-- The zone gate's HP, so the top-centre bar becomes its health bar
			-- (features/cake-cycle.md). nil in every other phase.
			miniBoss = if type(payload.miniBoss) == "table" then payload.miniBoss else nil,
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
				local nowFull = fill >= capacity
				if nowFull and not isFull then
					SoundPool.Play("gulp") -- topped out: one swallow, not one per bite
				end
				isFull = nowFull
			end
		end
	end)

	-- ── Treasure FX ─────────────────────────────────────────────────────
	-- Two beats, both worth selling (the finds ARE the reward loop of a
	-- 40-minute cake): the CROWN breaking the surface, and the item popping
	-- free. Loudness scales with the find's rarity (TreasureConfig.rarityFx).
	local function rarityFx(rarity: string?)
		return TreasureConfig.rarityFx[rarity or "common"] or TreasureConfig.rarityFx.common
	end
	local function rewardText(reward): string?
		if type(reward) ~= "table" or LocaleData == nil then
			return nil
		end
		local amount = tonumber(reward.amount)
		if reward.kind == "gems" and amount then
			return LocaleData.T("label-gems-n", { n = math.floor(amount) })
		elseif reward.kind == "boost" then
			return LocaleData.T("label-boost")
		elseif reward.kind == "egg" then
			return LocaleData.T(if reward.eggType == "lucky" then "label-egg-epic" else "label-egg")
		end
		return nil
	end

	Net.Update("TreasureUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or typeof(payload.position) ~= "Vector3" then
			return
		end
		local color = if typeof(payload.color) == "Color3" then payload.color else Color3.fromRGB(255, 240, 160)
		local fx = rarityFx(payload.rarity)

		if payload.event == "near" then
			-- Something is just under the icing here. Remember the spot; the
			-- render step glints the SURFACE above it until the crown breaks
			-- through. This is what turns mowing into "dig THERE".
			nearMarkers[payload.findId .. tostring(payload.position)] = {
				x = payload.position.X,
				z = payload.position.Z,
				color = color,
			}
		elseif payload.event == "revealed" then
			-- A crown just broke through: a puff of crumbs off the top of it and
			-- a soft "something's here" chime, so the dig has a payoff BEFORE the
			-- item is free.
			ParticlePool.Burst(payload.position, color, math.floor(fx.burst * 0.5))
			SoundPool.Play("treasureSpawn")
			CameraShake.Impulse(fx.shake * 0.4)
			nearMarkers[payload.findId .. tostring(payload.position)] = nil
		elseif payload.event == "collected" then
			local mine = payload.byUserId == player.UserId
			-- A find you have NEVER dug up before is a one-off moment: treat it
			-- as at least rare no matter what it actually is, so the first berry
			-- lands and the fortieth does not.
			local firstEver = mine and payload.firstEver == true
			if firstEver then
				fx = TreasureConfig.rarityFx.rare
			end
			-- The pop: a fat burst at the hole, plus a ring of crumbs for the
			-- rarer finds. Everyone sees it (shared cake); the collector also
			-- gets the shake, the chime and the floating reward.
			ParticlePool.Burst(payload.position, color, mine and fx.burst or math.floor(fx.burst * 0.45))
			if fx.ring then
				for step = 0, 5 do
					local angle = step * math.pi / 3
					ParticlePool.Burst(
						payload.position + Vector3.new(math.cos(angle) * 4, 0.5, math.sin(angle) * 4),
						color,
						6
					)
				end
			end
			SoundPool.Play(if mine then fx.sound else "treasureSpawn")
			if mine then
				CameraShake.Impulse(fx.shake)
				local text = rewardText(payload.reward)
				if text and FloatingNumbers ~= nil then
					FloatingNumbers.Show(payload.position + Vector3.new(0, 3, 0), text, 1, color)
				end
				-- Only rare+ finds earn a banner — 40 finds a cake, so a banner
				-- per find would be pure noise. A FIRST-EVER discovery always
				-- does, and outranks the rarity banner.
				-- ⚠ Not while a celebration owns the screen: uncovering a find on
				-- the last bite of a layer is routine, and a one-line "EPIC
				-- FIND!" replacing a 2.4 s splash mid-slam — while its confetti
				-- is still in the air — reads as a bug. The find's own ring,
				-- shake and floating number above still fire.
				if celebrationOwnsScreen() then
					Log.Info(SCOPE, "find banner held back — a layer/monster celebration is on screen")
				elseif firstEver then
					pushAnnounce("find-new")
				elseif fx.ring and payload.rarity then
					pushAnnounce(`find-{payload.rarity}`)
				end
			end
		end
	end)

	-- ── The bite ────────────────────────────────────────────────────────
	-- You eat the cake DIRECTLY IN FRONT of you (not where you tap): the
	-- surface a few studs ahead along the character's facing, snapped to the
	-- field. nil when you're facing off the loaf (nothing in front to eat) —
	-- turn/walk to aim. The forward reach grows a little with bite radius and
	-- stays well inside the server's reach cap (antiCheat.maxBiteReachStuds).
	-- The point then SEARCHES FORWARD for cake still standing above the active
	-- floor, so running head-on into a layer wall bites the wall instead of the
	-- crater floor you are stood in (CakeConfig.aim).
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
		flat = flat.Unit
		local aim = CakeConfig.aim
		-- Just in front of you, scaled to the EFFECTIVE scoop on this band (the
		-- pacing curve: a wide spoonful of icing, a small chip of dense core).
		-- ⚠ It must stay under the front bite's own radius + the beneath bite's,
		-- or the two craters stop touching and every pass leaves an un-eaten RING
		-- around the eater — which the densest cakes (smallest scoops) would hit.
		local scooped = LocalCakeField.ScoopedRadius(LocalStatsService.BiteRadius())
		local reach = math.max(aim.minReachStuds, scooped * aim.reachMult)
		local origin = root.Position
		local function sampleAt(distance: number): Vector3?
			return LocalCakeField.SurfacePoint(origin.X + flat.X * distance, origin.Z + flat.Z * distance)
		end

		local nominal = sampleAt(reach)
		-- RUNNING HEAD-ON INTO A LAYER WALL (CakeConfig.aim): the nominal point is
		-- the floor of the crater you are standing in, so a bite there removes
		-- nothing AND the layer gate below reads it as "already eaten to the floor
		-- here" and skips the bite outright. Step forward to the nearest cake still
		-- standing above the active floor so the scoop centres on the WALL. When
		-- there is already cake at the nominal point — the normal "mow across the
		-- top surface" case — this returns immediately and nothing changes.
		local activeFloor = LocalCakeField.ActiveFloorStuds()
		if activeFloor == nil then
			return nominal
		end
		local standing = activeFloor + CakeConfig.layerGate.lockEpsilon
		local originY = CakeConfig.grid.origin.y
		if nominal ~= nil and nominal.Y - originY > standing then
			return nominal
		end
		-- The un-eaten-RING contract above still holds, and NOT because the probe is
		-- short: the march stops at the FIRST point above the floor, so everything
		-- between the eater and the bite point is already cleared. There is no cake
		-- left in the gap to strand, however far it walked. (The cap is about
		-- reach/latency and staying far inside the server's anti-cheat range —
		-- worst case here is ~15 studs vs the server's 18 + biteRadius.)
		local step = math.max(0.25, aim.stepStuds)
		local maxReach = math.max(reach, scooped + aim.probeStuds)
		local distance = step
		while distance <= maxReach do
			local candidate = sampleAt(distance)
			if candidate ~= nil and candidate.Y - originY > standing then
				return candidate
			end
			distance += step
		end
		-- Nothing ahead stands above the floor: keep the nominal point so the
		-- caller's layer-gate branch still fires its "eat the top layer first" cue.
		return nominal
	end

	local function doBite()
		if inputLocked() then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not LocalCakeField.HasCake() then
			return
		end

		if cyclePhase == "miniboss" then
			-- The zone gate takes the SAME tap the cake does; the server routes it
			-- (CakeSubs). Position is our own root, so it is always in reach and
			-- carries no aim information the server would have to trust.
			rEatAt:FireServer(root.Position)
			if MiniBossView ~= nil and MiniBossView.IsShown() then
				local at = MiniBossView.Center()
				ParticlePool.Burst(
					at + Vector3.new((math.random() - 0.5) * 4, (math.random() - 0.5) * 4, (math.random() - 0.5) * 4),
					Color3.fromRGB(255, 210, 120),
					6
				)
			end
			SoundPool.Play("bossHit")
			CameraShake.Impulse(0.1)
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
			SoundPool.Play("bossHit")
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
				SoundPool.Play("blocked")
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
					if
						now - lastLockCueAt > CakeConfig.layerGate.cueInterval
						and now - lastCelebrationAt > LAYER_CLEAR_PRIORITY_SECONDS
					then
						lastLockCueAt = now
						-- SILENT ON PURPOSE (user req): the layer gate refuses a
						-- bite you take constantly while clearing a layer, so a
						-- refusal sound here turned into a stutter of buzzes. The
						-- banner alone carries it. Do NOT add SoundPool.Play back —
						-- the full-belly refusal above is a different, rare event
						-- and keeps its cue.
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
				SoundPool.Play("shatter")
			end
			CameraShake.Impulse(JuiceConfig.camera.biteShakeAmp * (0.6 + intensity))
			-- Eat gesture: rip this layer's piece out of the cake in front and
			-- fly it hand -> mouth. Speed tracks the eat-rate stat. LOCAL only,
			-- like the rest of this bite's juice.
			EatGestureController.Play(point, layer, LocalStatsService.EatRate())
			-- A chew layered over the fast per-bite crumbles. Throttled in
			-- AudioConfig, so it keeps a slow mouth rhythm at any eat-rate.
			SoundPool.Play("chew")
		end
	end

	-- ── Input: hold to eat ──────────────────────────────────────────────
	-- TOUCH: eating comes ONLY from the dedicated EAT button (below) — never a
	-- raw finger, so the movement joystick / camera drag can't eat (Task 3). The
	-- button's press primitive is finger-aware (refcounts touches), so onEatUp
	-- fires only when the LAST finger lifts, including a drag-off release — no
	-- stuck-on eating, no need to correlate a single finger here.
	-- Optional (features/analytics.md). The EAT button's HOLD LENGTH is the
	-- clearest measure of how the core verb is actually used — a screen full
	-- of half-second taps and a screen full of ten-second holds are different
	-- games, and only the client can tell them apart.
	local Analytics = modules.LocalAnalyticsService
	local eatHoldStartedAt: number? = nil

	AppRoot.SetCallbacks({
		onEatDown = function()
			if inputLocked() then
				eating = false
				LocalEatState.Set(false)
				-- A press that the input lock swallowed: they tried to eat and
				-- the game did nothing visible. Counted as a dead press.
				if Analytics then
					Analytics.Press("EatButton/Locked", true)
				end
				return
			end
			eating = true
			eatHoldStartedAt = os.clock()
			-- A tap can begin and end within one frame; fire ONE bite right now so
			-- a tap always lands ≥1 bite, then let the Heartbeat auto-repeat the
			-- hold at the eat-rate cadence.
			lastBiteAt = os.clock()
			doBite()
		end,
		onEatUp = function()
			eating = false
			if Analytics and eatHoldStartedAt ~= nil then
				Analytics.Hold("EatButton", math.floor((os.clock() - eatHoldStartedAt) * 10) / 10)
			end
			eatHoldStartedAt = nil
		end,
	})
	-- PC: hold the mouse ANYWHERE (no joystick to clash with). Aim by turning /
	-- walking, not by tapping a spot.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not inputLocked() then
			eating = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			eating = false
		end
	end)

	RunService.Heartbeat:Connect(function()
		local locked = inputLocked()
		if locked then
			eating = false
		end
		-- Auto-Eat pass (server sets the attribute): always chewing.
		local activelyEating = not locked and (eating or player:GetAttribute("AutoEat") == true)
		-- Flat-while-eating gate (Task 4) = ACTIVE hold/tap only, NOT Auto-Eat —
		-- so an Auto-Eat pass owner keeps the (toned) per-layer bounce/jump feel
		-- while just running around; they only go flat when they actively hold EAT.
		LocalEatState.Set(not locked and eating)
		if activelyEating then
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
		local footPos = nil -- CLOSE to the surface: cosmetic squish/wax
		local scanCentre = nil -- collision-scan centre: the character's raw XZ
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			-- ⚠ The scan centre is the character's POSITION, not its surface point.
			-- It used to be the surface point, which is nil off the footprint — so
			-- the collision scan went dead at the checkpoint, at the gym, and in the
			-- rim ring where a column stands at full cake height over out-of-cake
			-- XZ. Columns went stale exactly where the player was about to return.
			scanCentre = root.Position
			local surfacePoint = LocalCakeField.SurfacePoint(root.Position.X, root.Position.Z)
			-- Only the near-surface case gets the cosmetic underfoot squish/wax.
			if surfacePoint and math.abs(root.Position.Y - surfacePoint.Y) < CakeConfig.feel.onCakeYTolerance then
				footPos = surfacePoint
			end
		end
		watchdogStep(dt, root)
		CakeRenderer.Step(dt, footPos, scanCentre)
		CakeWaxShell.Step(dt, footPos) -- always-visible wax coating that cracks underfoot
		-- Textured outer wall hiding the cake below the current + next rendered
		-- layers — but only in editable mode; the parts fallback draws the whole cake
		-- as keycap columns, which the wall would just occlude.
		if CakeRenderer.Impl() == "editable" then
			CakeWrapper.Step(dt)
		else
			CakeWrapper.Hide()
		end
		EatGestureController.Step(dt) -- advance the local flying eat pieces
		SoundPool.PushSlumpEnergy(LocalCakeField.DrainAvalanche())
		SoundPool.Step(dt)
		ParticlePool.Step(dt)
		BossView.Step(dt)
		if MiniBossView ~= nil then
			MiniBossView.Step(dt) -- entrance, the stare, and the HP-driven shrink
		end
		if FoodBurst ~= nil then
			FoodBurst.Step(dt) -- celebration confetti; a no-op while nothing is live
		end

		-- GLINT: a slow shimmer on the cake SURFACE directly above every find
		-- that is nearly uncovered. It never shows the item itself (that would be
		-- an x-ray and would delete the dig) — only that this SPOT is worth
		-- eating. Pooled bursts, so zero allocation; capped so a swept layer
		-- can't flood the particle budget.
		glintClock += dt
		if glintClock >= JuiceConfig.findGlint.interval then
			glintClock = 0
			local shown = 0
			for _, marker in pairs(nearMarkers) do
				if shown >= JuiceConfig.findGlint.maxMarkers then
					break
				end
				local surface = LocalCakeField.SurfacePoint(marker.x, marker.z)
				if surface then
					ParticlePool.Burst(
						surface + Vector3.new(0, JuiceConfig.findGlint.liftStuds, 0),
						marker.color,
						JuiceConfig.findGlint.particles
					)
					shown += 1
				end
			end
		end

		-- Walk crunch (§7.2): footstep-cadence crust sound + crumb puffs while
		-- moving on the cake — the crust must FEEL crunchy. The wax-film cracks
		-- themselves follow the foot continuously in CakeRenderer.Step (the
		-- underfoot reveal), so there is no per-step crack draw here.
		if footPos and root then
			local crunch = JuiceConfig.walkCrunch
			local velocity = root.AssemblyLinearVelocity
			local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
			local now = os.clock()
			-- `crunch.biteSuppressSeconds`: the crunch reuses the BITE sample, and a
			-- bite drops the column under you — the settle drift alone trips
			-- `minSpeed`, so one click used to fire the bite plus two crunches.
			local biting = now - lastBiteAt < crunch.biteSuppressSeconds
			if not biting and speed >= crunch.minSpeed and now - lastCrunchAt >= crunch.interval then
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
