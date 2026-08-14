--[[
	MiniBossView — the client-side visual of a ZONE-GATE CRUMB MONSTER
	(features/cake-cycle.md; "mini-boss" is its code/phase name everywhere, the
	player-facing word became CRUMB MONSTER on 2026-08-13). One bursts up
	through the cake every time the layer gate crosses from one flavour zone
	into the next, and the cake is inedible until it dies.

	⚠ Its billboard is a ZONE NAMEPLATE only — the world-space HP bar was
	removed 2026-08-13 with the Cake Monster's. Health has two better readouts
	already: the HUD's CakeBar, and §3 below (the rig's own SIZE).

	Purely cosmetic, exactly like BossView: hits are `EatAt` taps, HP arrives on
	`CakeCycleUpdate`. The server only ever names the RIG — every pose, scale and
	frame of the entrance is decided here.

	THE MODELS are place-authored rigs under `ReplicatedStorage.Assets.MiniBosses`
	(moved out of Workspace 2026-08-07, ADR-0007 content). They are R6 character
	rigs, so preparing a template STRIPS them down to a static prop: Humanoid,
	Animator, AnimSaves and the authoring CameraPart go, every part is anchored
	and made non-collidable/non-queryable. The authored folder is NEVER mutated
	(TreasureService's rule) — each entry is prepared as an unparented CLONE and
	cached, so the user can keep editing and saving the place.

	THE THREE THINGS IT DOES
	1. ENTRANCE — it starts `emergeDepthStuds` UNDER the freshly-cleared layer
	   floor, pitched back into the cake, and punches up through it in
	   `emergeSeconds`, overshooting and dropping back as it stands upright. That
	   is the "suddenly breaking through the top" beat; the crumb burst and the
	   camera punch are fired by CakeSubsClient at the same moment.
	2. IT STANDS STILL AND LOOKS AT YOU — no walking, no strafing. It only yaws,
	   at `faceTurnDegrees`/s, toward the LOCAL player. Client-side, so every
	   player is the one it is staring at. The rig's authored facing is measured
	   once (HumanoidRootPart LookVector) and cancelled out, so a rig authored
	   facing any direction still looks at you.
	3. SIZE IS THE HEALTH BAR — `scaleFull` (x4 a player) at full HP shrinking to
	   `scaleDead` (x0.5) at zero, then it pops in a burst of
	   `ReplicatedStorage.Assets.Vfx.MiniBossPoof`. `Model:ScaleTo` walks every
	   descendant, so it is applied on a THRESHOLD (and at most ~12 Hz), never
	   per frame on a 490-part rig.

	⚠ The pivot of an authored rig is arbitrary. On prepare the model's
	`WorldPivot` is re-seated (WITHOUT moving any part) to the CENTRE OF ITS
	FOOTPRINT AT ITS FEET with identity rotation, so `PivotTo(CFrame.new(spot) *
	yaw * pitch)` afterwards means "stand here, facing there, tipped back this
	far" — and the foot offset stays valid under `ScaleTo` because it scales with
	the model.

	Degrades loudly (R8): a missing folder, a missing rig or a missing VFX
	template each warn once and the fight still runs (no model = no visual, but
	the HP/announce/gating are server-side and unaffected).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CakeConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeConfig"))
local Log = require(Shared:WaitForChild("Log"))

local SCOPE = "MiniBossView"

local MiniBossView = {}

local cfg = CakeConfig.cycle.miniBoss
local origin = CakeConfig.grid.origin

-- Prepared, unparented templates keyed by rig name + the metrics measured off
-- them once (natural height, foot offset, authored yaw).
local templates: { [string]: { model: Model, height: number, yaw: number } } = {}
local poofTemplate: BasePart? = nil
local assetsChecked = false

local current: Model?
local currentMetrics
local nameGui: BillboardGui?

-- Animation state
local phase = "idle" -- "emerging" | "settling" | "idle"
local phaseClock = 0
local groundY = 0
local facingYaw = 0
local displayScale = 1
local targetScale = 1
local appliedScale = -1
local scaleClock = 0
local bobClock = 0
local currentHp01 = 1

local SCALE_APPLY_INTERVAL = 1 / 12
local SCALE_APPLY_EPSILON = 0.004

-- ── asset resolution ────────────────────────────────────────────────────

local function assetsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("MiniBosses")
	if folder == nil then
		if not assetsChecked then
			assetsChecked = true
			Log.Warn(
				SCOPE,
				"ReplicatedStorage.Assets.MiniBosses is MISSING -- zone-gate bosses will be invisible "
					.. "(the fight still works). Author the rigs there and SAVE the place; see features/cake-cycle.md"
			)
		end
		return nil
	end
	return folder :: Folder
end

-- Strips an authored character rig down to a static, scalable prop. Operates on
-- a CLONE — the authored library is never touched.
local function prepare(source: Instance): Model?
	if not source:IsA("Model") then
		Log.Warn(SCOPE, `mini-boss asset '{source.Name}' is a {source.ClassName}, not a Model -- skipped`)
		return nil
	end
	local model = source:Clone()

	-- Measure the authored facing BEFORE anything is stripped: HumanoidRootPart
	-- is the only thing that knows which way the rig was built to look.
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local authoredYaw = 0
	if root then
		local look = root.CFrame.LookVector
		authoredYaw = math.atan2(-look.X, -look.Z)
	else
		Log.Once(
			SCOPE,
			`no-hrp-{source.Name}`,
			`mini-boss rig '{source.Name}' has no HumanoidRootPart -- its authored facing is unknown, it may look sideways`
		)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
		elseif descendant:IsA("Humanoid") or descendant:IsA("BaseScript") or descendant:IsA("KeyframeSequence") then
			-- A Humanoid would fight ScaleTo and try to simulate; scripts on an
			-- authored rig are not ours to run; KeyframeSequences are editor data.
			descendant:Destroy()
		end
	end
	for _, junk in ipairs({ "AnimSaves", "CameraPart" }) do
		local child = model:FindFirstChild(junk)
		if child then
			child:Destroy()
		end
	end

	local boxCFrame, boxSize = model:GetBoundingBox()
	if boxSize.Y <= 0.01 then
		Log.Warn(SCOPE, `mini-boss rig '{source.Name}' has no volume -- skipped`)
		model:Destroy()
		return nil
	end
	-- Re-seat the pivot at the FEET, centred, unrotated. Assigning WorldPivot
	-- moves nothing; it only changes what PivotTo means afterwards.
	-- ⚠ CLEAR PrimaryPart FIRST. A Model with a PrimaryPart takes its pivot from
	-- THAT PART and ignores `WorldPivot` entirely, so on an R6 rig the pivot stays
	-- at the HumanoidRootPart — the hip. Measured in Studio 2026-08-07: the boss
	-- stood 6.4 studs SUNK INTO the cake, because `PivotTo(groundY)` was putting
	-- its hip on the crust, and `ScaleTo` grew it about the hip too, so the error
	-- scaled with HP. These rigs are static props here (the Humanoid is stripped
	-- above), so nothing else wants the PrimaryPart.
	model.PrimaryPart = nil
	local footCentre = Vector3.new(boxCFrame.Position.X, boxCFrame.Position.Y - boxSize.Y * 0.5, boxCFrame.Position.Z)
	model.WorldPivot = CFrame.new(footCentre)

	templates[source.Name] = { model = model, height = boxSize.Y, yaw = authoredYaw }
	return model
end

local function templateFor(name: string?)
	if name == nil or name == "" then
		return nil
	end
	local cached = templates[name]
	if cached then
		return cached
	end
	local folder = assetsFolder()
	if folder == nil then
		return nil
	end
	local source = folder:FindFirstChild(name)
	if source == nil then
		-- Not fatal, and not silent: the config names a rig the place does not
		-- have. Fall back to ANY rig in the folder so the gate still has a face.
		local fallback = folder:FindFirstChildWhichIsA("Model")
		Log.Once(
			SCOPE,
			`missing-rig-{name}`,
			`mini-boss rig '{name}' is not in ReplicatedStorage.Assets.MiniBosses -- `
				.. (if fallback then `using '{fallback.Name}' instead` else "no rig available, the gate will be invisible")
		)
		if fallback == nil then
			return nil
		end
		source = fallback
	end
	prepare(source)
	return templates[source.Name]
end

local function poof(): BasePart?
	if poofTemplate then
		return poofTemplate
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("Vfx")
	local template = vfx and vfx:FindFirstChild("MiniBossPoof")
	if template == nil or not template:IsA("BasePart") then
		Log.Once(
			SCOPE,
			"no-poof",
			"ReplicatedStorage.Assets.Vfx.MiniBossPoof is missing -- a beaten mini-boss will vanish with no burst"
		)
		return nil
	end
	poofTemplate = template :: BasePart
	return poofTemplate
end

-- ── name billboard ──────────────────────────────────────────────────────
-- ⚠ This used to be a NAMEPLATE + HP BAR. The bar was removed 2026-08-13
-- (user request, same call as the Cake Monster's): a crumb monster's health is
-- already the HUD's top-centre CakeBar, and it is ALSO its own size — the rig
-- shrinks from 4x a player to half of one as it dies (`scaleForHp`). Three
-- readouts of one number, one of them covering the monster.
-- What stays is the ZONE NAME, which is information nothing else carries:
-- this monster guards CHOCOLATE, and that is why you are fighting it.
local function buildNamePlate(host: BasePart, title: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "MiniBossName"
	gui.Size = UDim2.fromOffset(cfg.hpBarWidthPx or 300, 40)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 500

	local title_ = Instance.new("TextLabel")
	-- Full height now the bar is gone; it used to be the top half of the split.
	title_.Size = UDim2.fromScale(1, 1)
	title_.BackgroundTransparency = 1
	title_.Font = Enum.Font.FredokaOne
	title_.TextScaled = true
	title_.TextColor3 = Color3.new(1, 1, 1)
	title_.TextStrokeTransparency = 0.3
	title_.Text = title
	title_.Parent = gui

	gui.Parent = host
	-- `applyScale` rides this to hold the plate's world clearance above a rig
	-- whose height changes with HP.
	nameGui = gui
end

-- ── placement ───────────────────────────────────────────────────────────

local function scaleForHp(hp01: number): number
	local metrics = currentMetrics
	if metrics == nil then
		return 1
	end
	local wanted = (cfg.playerHeightStuds or 5)
		* ((cfg.scaleDead or 0.5) + ((cfg.scaleFull or 4) - (cfg.scaleDead or 0.5)) * math.clamp(hp01, 0, 1))
	return wanted / math.max(0.01, metrics.height)
end

-- One frame of placement: `lift` studs above the ground, `pitch` radians tipped
-- back. Yaw already includes the rig's authored-facing correction.
local function place(lift: number, pitch: number)
	local model = current
	local metrics = currentMetrics
	if model == nil or metrics == nil then
		return
	end
	model:PivotTo(
		CFrame.new(origin.x, groundY + lift, origin.z)
			* CFrame.Angles(0, facingYaw - metrics.yaw, 0)
			* CFrame.Angles(pitch, 0, 0)
	)
end

local function applyScale(force: boolean)
	local model = current
	if model == nil then
		return
	end
	if not force and math.abs(displayScale - appliedScale) < SCALE_APPLY_EPSILON then
		return
	end
	appliedScale = displayScale
	-- ScaleTo walks every descendant; pcall'd because an authored rig can carry
	-- something it refuses to scale, and a throw here would kill the render step.
	local ok, err = pcall(function()
		model:ScaleTo(math.max(0.01, displayScale))
	end)
	if not ok then
		Log.Once(SCOPE, "scale-failed", `Model:ScaleTo FAILED on the mini-boss rig -- size will not track HP: {err}`)
	end
	-- The billboard hangs off the HEAD in WORLD studs, so its clearance has to
	-- shrink with the boss or it drifts into the sky as the fight goes on.
	if nameGui and currentMetrics then
		nameGui.StudsOffsetWorldSpace = Vector3.new(0, currentMetrics.height * displayScale * 0.22, 0)
	end
end

-- ── API ─────────────────────────────────────────────────────────────────

--API
function MiniBossView.IsShown(): boolean
	return current ~= nil
end

--API
-- The world point the boss occupies — where CakeSubsClient throws the crumbs
-- and the camera punch on the breach, and where hit FX land.
function MiniBossView.Center(): Vector3
	local metrics = currentMetrics
	local half = if metrics then metrics.height * displayScale * 0.5 else 6
	return Vector3.new(origin.x, groundY + half, origin.z)
end

--API
-- Bring one up through the cake. `surfaceY` is the world Y of the freshly
-- cleared layer floor at the cake centre (nil = fall back to the cake base).
function MiniBossView.Show(modelName: string?, title: string, surfaceY: number?, hp: number?, maxHp: number?)
	if current then
		return
	end
	local metrics = templateFor(modelName)
	if metrics == nil then
		return
	end
	local model = metrics.model:Clone()
	current = model
	currentMetrics = metrics
	groundY = surfaceY or (origin.y + 1)
	currentHp01 = if hp and maxHp and maxHp > 0 then math.clamp(hp / maxHp, 0, 1) else 1
	targetScale = scaleForHp(currentHp01)
	displayScale = targetScale
	appliedScale = -1
	phase = "emerging"
	phaseClock = 0
	bobClock = 0
	scaleClock = 0

	-- Face the local player from the first frame — it should be looking at you
	-- the moment its head clears the crust, not spin to find you afterwards.
	facingYaw = MiniBossView.DesiredYaw() or 0

	-- The nameplate rides the HEAD so it clears the rig at any scale; its
	-- world-stud clearance is (re)computed inside applyScale, so build it FIRST.
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart")
	local host = (if head and head:IsA("BasePart") then head
		elseif root and root:IsA("BasePart") then root
		else model:FindFirstChildWhichIsA("BasePart", true)) :: BasePart?
	if host then
		buildNamePlate(host, title)
	else
		Log.Once(SCOPE, "no-hp-host", `mini-boss rig '{tostring(modelName)}' has no BasePart to hang the zone nameplate on`)
	end
	applyScale(true)
	place(-(cfg.emergeDepthStuds or 26) * displayScale, -1.15)
	model.Parent = workspace
	Log.Info(SCOPE, `mini-boss '{model.Name}' bursting out at y={string.format("%.1f", groundY)}, scale {string.format("%.2f", displayScale)}`)
end

--API
-- Yaw (radians) that points the rig at the local character. nil when there is
-- nobody to look at, in which case the current facing is kept.
function MiniBossView.DesiredYaw(): number?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil then
		return nil
	end
	local dx = root.Position.X - origin.x
	local dz = root.Position.Z - origin.z
	if dx * dx + dz * dz < 1e-4 then
		return nil
	end
	return math.atan2(-dx, -dz)
end

--API
-- ⚠ Still the HP sink even though the bar is gone (2026-08-13): SIZE is this
-- monster's health bar. `scaleForHp` walks the rig from 4x a player at full HP
-- down to half a player at zero, so dropping this call would freeze it at full
-- size and delete the only feedback the fight has left in the world.
function MiniBossView.SetHp(hp: number, maxHp: number)
	currentHp01 = math.clamp(hp / math.max(1, maxHp), 0, 1)
	targetScale = scaleForHp(currentHp01)
end

--API
-- `defeated` fires the poof; a plain hide (new cake, phase reset) does not.
function MiniBossView.Hide(defeated: boolean?)
	local model = current
	if model == nil then
		return
	end
	if defeated then
		local template = poof()
		if template then
			local burst = template:Clone()
			burst.CFrame = CFrame.new(MiniBossView.Center())
			burst.Parent = workspace
			for _, child in ipairs(burst:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					child:Emit(if child.Name == "Burst" then 70 else 12)
				elseif child:IsA("Light") then
					child.Enabled = true
				end
			end
			Debris:AddItem(burst, 3)
		end
	end
	model:Destroy()
	current = nil
	currentMetrics = nil
	nameGui = nil
	phase = "idle"
end

--API
-- Drives the entrance, the shrink and the stare. Called every frame from
-- CakeSubsClient's render step.
function MiniBossView.Step(dt: number)
	local model = current
	local metrics = currentMetrics
	if model == nil or metrics == nil then
		return
	end

	-- Turn toward the player at a fixed rate — it STANDS STILL, it just looks.
	local wanted = MiniBossView.DesiredYaw()
	if wanted ~= nil then
		local delta = (wanted - facingYaw + math.pi) % (math.pi * 2) - math.pi
		local step = math.rad(cfg.faceTurnDegrees or 220) * dt
		facingYaw += math.clamp(delta, -step, step)
	end

	-- Shrink toward the HP-driven size (smoothed, then applied on a threshold —
	-- ScaleTo is O(descendants) and these rigs carry ~490).
	displayScale += (targetScale - displayScale) * math.clamp(dt * 6, 0, 1)
	scaleClock += dt
	if scaleClock >= SCALE_APPLY_INTERVAL then
		scaleClock = 0
		applyScale(false)
	end

	phaseClock += dt
	bobClock += dt
	local depth = (cfg.emergeDepthStuds or 26) * displayScale
	local overshoot = (cfg.emergeOvershootStuds or 3.5) * displayScale
	if phase == "emerging" then
		local duration = math.max(0.05, cfg.emergeSeconds or 0.7)
		local t = math.clamp(phaseClock / duration, 0, 1)
		-- Fast out of the hole, easing as it tops out: 1-(1-t)^3.
		local eased = 1 - (1 - t) ^ 3
		place(-depth + (depth + overshoot) * eased, -1.15 * (1 - eased))
		if t >= 1 then
			phase = "settling"
			phaseClock = 0
		end
	elseif phase == "settling" then
		local duration = math.max(0.05, cfg.settleSeconds or 0.35)
		local t = math.clamp(phaseClock / duration, 0, 1)
		place(overshoot * (1 - t * t), 0)
		if t >= 1 then
			phase = "idle"
			phaseClock = 0
		end
	else
		local bob = math.abs(math.sin(bobClock * (cfg.bobSpeed or 2.2))) * (cfg.bobAmplitude or 0.35) * displayScale
		place(bob, 0)
	end
end

return MiniBossView
