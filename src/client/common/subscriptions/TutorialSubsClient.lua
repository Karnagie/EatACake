--[[
	TutorialSubsClient — the onboarding flow, client side (R4).
	Feature doc: docs/features/tutorial.md. Tuning: Shared.config.TutorialConfig.

	GAME PLACE ONLY (partition marker `GameUiData`, the BodySubsClient gate) —
	the lobby has no cake, no checkpoint and no upgrade computer to point at.
	The module is COMMON rather than game/ so the gate reports its own absence
	in the lobby console (R8) instead of vanishing silently.

	THE FLOW — five states, one `step` variable:
	  "slides"   the 4-panel comic. Plays on EVERY entry to the game place,
	             finished or not; SKIP is the only way out.
	  "eat"      the instruction popup. Dismissed by GOT IT *or* by the first
	             bite landing, whichever comes first.
	  "belly"    silent watch: the belly crossing TutorialConfig.bellyThreshold01.
	  "path"     the guidance BEAM (a clone of the authored HintBeam) runs from
	             the player to the checkpoint plate, and the TO CHECKPOINT
	             button breathes. Ends on ARRIVAL at the plate.
	  "upgrades" the world arrow points at the upgrade computer. Ends when the
	             UpgradeStation prompt fires — which is also the end of the
	             tutorial, so `TutorialComplete` goes to the server here.
	Steps 2-5 are skipped entirely for an account whose profile says `done`.

	WHY THE THRESHOLD IS LATCHED: the belly falls again the moment a gym drain
	starts (BodySubs resyncs ~8 Hz), so an un-latched test would blink the beam
	off at 89% while the player is still walking to the platform.

	R5: the beam is a CLONE of ReplicatedStorage.Assets.GuidanceTemplates.HintBeam.
	The two Attachments are Instance.new'd — an attachment is a positioning node,
	not a view object, and it must parent to instances (the live HumanoidRootPart,
	the moving plate) that no template can own.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local TutorialConfig = require(Shared:WaitForChild("config"):WaitForChild("TutorialConfig"))

local SCOPE = "Tutorial"

local TutorialSubsClient = {}

-- Resolve a named child to the BasePart a beam/arrow can anchor to. The
-- authored checkpoint pieces are Parts today, but `MapService` resolves them as
-- PVInstances, so a future re-model into a Model must not crash this feature —
-- it falls back to the model's first BasePart.
local function asBasePart(instance: Instance?): BasePart?
	if instance == nil then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function TutorialSubsClient.Start(data, modules)
	if data.GameUiData == nil then
		Log.Info(SCOPE, "game client partition absent -- onboarding flow skipped in lobby")
		return
	end
	local AppRoot = modules.AppRoot
	local player = Players.LocalPlayer
	local world = TutorialConfig.world
	local rComplete = Net.Remote("TutorialComplete")
	-- Optional (features/analytics.md). The whole guided flow is client-owned,
	-- so every one of its steps is invisible to the server except the last.
	local Analytics = modules.LocalAnalyticsService
	if Analytics == nil then
		Log.Warn(SCOPE, "LocalAnalyticsService missing -- slides/skip/hint beats will not be logged")
	end
	-- Each tutorial beat carries how long the player spent on the PREVIOUS
	-- one, which is what turns "they got past the slides" into "they stared at
	-- the slides for 40 seconds first".
	local lastBeatAt = os.clock()
	local function beat(stepKey: string, flowStep: string?)
		if Analytics == nil then
			return
		end
		local now = os.clock()
		Analytics.Tutorial(stepKey, math.floor((now - lastBeatAt) * 10) / 10)
		lastBeatAt = now
		if flowStep then
			Analytics.Flow(flowStep)
		end
	end

	-- The authored UpgradeStation prompt is what ends the flow; its NAME is
	-- already the contract UpgradesSubsClient opens the tree on.
	local upgradesUi = data.UpgradesUiData
	local promptName = upgradesUi and upgradesUi["config"] and upgradesUi["config"]["prompt-name"]
	if promptName == nil then
		Log.Warn(SCOPE, "UpgradesUiData config['prompt-name'] missing -- step 4 can never complete; tutorial will stay on the arrow")
	end

	-- ── state ───────────────────────────────────────────────────────────
	local step: string? = "slides"
	-- nil until TutorialUpdate lands. Tri-state on purpose: "not told yet" is
	-- NOT the same as "not done", and starting the hints on the assumption of
	-- `false` would flash them at a veteran who skipped the slides fast.
	local serverDone: boolean? = nil
	local wantSteps = false
	local completeSent = false

	local function push()
		AppRoot.Set({
			tutorial = {
				slides = step == "slides",
				hint = if step == "eat" then "eat" else nil,
				arrow = if step == "upgrades" then "upgrades" else nil,
				pulseCheckpoint = step == "path",
			},
		})
	end

	-- ── world guidance: the beam (step "path") ──────────────────────────
	local beam: Beam? = nil
	local beamPlayerAttachment: Attachment? = nil
	local beamTargetAttachment: Attachment? = nil

	local function checkpointChild(name: string): Instance?
		local map = Workspace:FindFirstChild(world.mapFolder)
		local checkpoint = map and map:FindFirstChild(world.checkpointFolder)
		return checkpoint and checkpoint:FindFirstChild(name) or nil
	end

	local function beamTemplate(): Beam?
		-- Place content (ADR-0007), so it can replicate LATE and must never be
		-- cached: resolve lazily every time, exactly like PetFollowers does.
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local folder = assets and assets:FindFirstChild(world.beamFolder)
		local template = folder and folder:FindFirstChild(world.beamName)
		return if template and template:IsA("Beam") then template else nil
	end

	local function clearBeam()
		if beam then
			beam:Destroy()
			beam = nil
		end
		if beamPlayerAttachment then
			beamPlayerAttachment:Destroy()
			beamPlayerAttachment = nil
		end
		if beamTargetAttachment then
			beamTargetAttachment:Destroy()
			beamTargetAttachment = nil
		end
	end

	-- Rebuilt (not repositioned) whenever a piece goes away: the HumanoidRootPart
	-- dies on every respawn and the plate is re-cloned with the map, so holding
	-- references across those events is the bug, not the fix.
	local function ensureBeam()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local plate = asBasePart(checkpointChild(world.plateName))
		if root == nil or plate == nil then
			clearBeam()
			if plate == nil then
				Log.GraceOnce(SCOPE, "tutorial-no-plate", TutorialConfig.resolveGraceSeconds, function()
					return asBasePart(checkpointChild(world.plateName)) == nil
				end, `workspace.{world.mapFolder}.{world.checkpointFolder}.{world.plateName} missing — the tutorial beam cannot point anywhere (step 3 degrades to the pulsing button alone)`)
			end
			return
		end
		-- Still wired to the same live parts? Then nothing to do.
		if beam ~= nil
			and beamPlayerAttachment ~= nil and beamPlayerAttachment.Parent == root
			and beamTargetAttachment ~= nil and beamTargetAttachment.Parent == plate
		then
			return
		end
		clearBeam()

		local template = beamTemplate()
		if template == nil then
			Log.GraceOnce(SCOPE, "tutorial-no-beam-template", TutorialConfig.resolveGraceSeconds, function()
				return beamTemplate() == nil
			end, `ReplicatedStorage.Assets.{world.beamFolder}.{world.beamName} missing — no guidance beam (step 3 degrades to the pulsing button alone). It is PLACE content, not in the repo.`)
			return
		end

		local from = Instance.new("Attachment")
		from.Name = world.clientFolderName .. "From"
		from.Position = TutorialConfig.beam.playerAttachmentOffset
		from.Parent = root

		local to = Instance.new("Attachment")
		to.Name = world.clientFolderName .. "To"
		-- Above the plate's TOP face, not its centre — the plate is a slab and
		-- the beam should ride over the surface the player walks onto.
		to.Position = Vector3.new(0, plate.Size.Y / 2, 0) + TutorialConfig.beam.targetAttachmentOffset
		to.Parent = plate

		local beamCfg = TutorialConfig.beam
		local clone = template:Clone()
		clone.Attachment0 = from
		clone.Attachment1 = to
		-- Bow the line upward so it reads as an aimed arc rather than a wall
		-- clipping through the loaf.
		clone.CurveSize0 = beamCfg.curveSize
		clone.CurveSize1 = beamCfg.curveSize
		-- Legibility overrides on the CLONE (the template stays as authored).
		-- Both are optional: nil defers to the template.
		if beamCfg.width ~= nil then
			clone.Width0 = beamCfg.width
			clone.Width1 = beamCfg.width
		end
		if beamCfg.color ~= nil then
			clone.Color = ColorSequence.new(beamCfg.color)
		end
		clone.Enabled = true
		clone.Parent = from

		beam, beamPlayerAttachment, beamTargetAttachment = clone, from, to
		Log.Info(SCOPE, "guidance beam attached (player -> checkpoint plate)")
	end

	-- ── step transitions ────────────────────────────────────────────────
	local function finish()
		if step == nil then
			return
		end
		beat("upgrades", "upgrades-open")
		step = nil
		clearBeam()
		push()
		if completeSent or serverDone == true then
			return
		end
		completeSent = true
		rComplete:FireServer()
		Log.Sum(SCOPE, "onboarding COMPLETE — TutorialComplete sent")
	end

	local function setStep(next: string?)
		if step == next then
			return
		end
		step = next
		if next ~= "path" then
			clearBeam()
		end
		push()
		-- One beat per state ENTERED, so the tutorial funnel mirrors the state
		-- machine exactly instead of being sprinkled across its callers.
		if next == "eat" then
			beat("eat", "eat-hint")
		elseif next == "belly" then
			beat("belly")
		elseif next == "path" then
			beat("path")
		elseif next == "upgrades" then
			-- Entering this state IS the arrival on the plate; the funnel's
			-- `upgrades` step belongs to the computer prompt, which is a
			-- separate act several studs later.
			beat("arrived", "checkpoint")
		end
		Log.Info(SCOPE, `step -> {tostring(next)}`)
	end

	-- Called when the slides close, and again when TutorialUpdate lands, so the
	-- two can arrive in either order without racing.
	local function beginStepsIfKnown()
		if not wantSteps or serverDone == nil then
			return
		end
		wantSteps = false
		if serverDone then
			Log.Info(SCOPE, "tutorial already completed on this account — slides only")
			setStep(nil)
		else
			setStep("eat")
		end
	end

	push()
	beat("slides", "slides")
	Log.Sum(SCOPE, "onboarding armed — showing the story slides")

	-- ── wiring ──────────────────────────────────────────────────────────
	Net.Update("TutorialUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			Log.Warn(SCOPE, "TutorialUpdate with a non-table payload — ignored")
			return
		end
		serverDone = payload.done == true
		Log.Info(SCOPE, `server says tutorial done = {serverDone}`)
		beginStepsIfKnown()
	end)

	-- New callback NAMES only: AppRoot.SetCallbacks merges by key and the last
	-- writer wins, so re-registering onEatDown/onReturnCheckpoint here would
	-- silently unplug eating or the checkpoint button.
	AppRoot.SetCallbacks({
		onTutorialSkip = function()
			if step ~= "slides" then
				return
			end
			-- The value is how long the comic was on screen before they left
			-- it: "skipped in 1.2s" and "skipped after 45s" are opposite
			-- findings about the same button.
			beat("skip", "slides-skip")
			wantSteps = true
			setStep(nil) -- hide the board immediately; the next step may need the server
			beginStepsIfKnown()
		end,
		onTutorialHintDismiss = function()
			if step == "eat" then
				-- Dismissed by BUTTON. The other exit (the first bite landing)
				-- goes through the StomachUpdate branch below, and telling them
				-- apart is telling "read the instructions" from "worked it out".
				if Analytics then
					Analytics.Flow("eat-hint-clear")
				end
				setStep("belly")
			end
		end,
		-- Read every frame by HintArrow (never through React state — see its
		-- header). Returns nil until the station replicates, which the arrow
		-- renders as "hidden", not as a marker stuck at the origin.
		onTutorialArrowTarget = function(): Vector3?
			local station = asBasePart(checkpointChild(world.upgradeStationName))
			if station == nil then
				return nil
			end
			return station.Position + TutorialConfig.arrow.targetOffset
		end,
	})

	-- Belly watch (steps "eat" -> "belly" -> "path"). Both payload shapes carry
	-- `fill`/`capacity`; only the per-bite one carries `layerId`, which is how
	-- the first BITE is told apart from a join/gym resync.
	Net.Update("StomachUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if step == "eat" and payload.layerId ~= nil then
			-- They worked it out without reading. Get out of the way.
			if Analytics then
				Analytics.Flow("eat-hint-clear")
			end
			setStep("belly")
			return
		end
		if step ~= "belly" then
			return
		end
		local capacity = tonumber(payload.capacity) or 0
		local fill = tonumber(payload.fill) or 0
		if capacity <= 0 then
			return
		end
		if fill / capacity >= TutorialConfig.bellyThreshold01 then
			setStep("path")
		end
	end)

	-- The tutorial's goal is the upgrade tree OPENING, so honour the prompt from
	-- any live step — not just from step 4.
	-- ⚠ The two zones do not coincide: the station's prompt is a 10-stud sphere
	-- with no line-of-sight requirement and sits ~3.5 studs from the loaf edge,
	-- so it lights up several studs back ONTO the cake — while `checkpointFar`
	-- stays true anywhere on the loaf by design (BodySubsClient). Gating on
	-- step == "upgrades" therefore dropped the completion of every player who
	-- pressed E on the way in, and their tutorial replayed forever.
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if step ~= nil and promptName ~= nil and prompt.Name == promptName then
			finish()
		end
	end)

	-- One throttled tick drives both world-facing steps. It is deliberately NOT
	-- per-frame: the beam's endpoints follow their parent parts by themselves,
	-- so this only has to notice pieces appearing, dying, or the player arriving.
	local accum = math.huge
	RunService.RenderStepped:Connect(function(dt)
		if step ~= "path" and step ~= "upgrades" then
			return
		end
		accum += dt
		if accum < TutorialConfig.resolveIntervalSeconds then
			return
		end
		accum = 0
		if step == "path" then
			ensureBeam()
			-- ARRIVAL. `checkpointFar` is BodySubsClient's plate-footprint test
			-- (it Starts first, alphabetically); reading it keeps one definition
			-- of "on the platform" instead of a second copy that could drift.
			if AppRoot.Get("checkpointFar") == false then
				setStep("upgrades")
			end
		end
	end)
end

return TutorialSubsClient
