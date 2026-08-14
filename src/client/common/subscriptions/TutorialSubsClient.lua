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
	  "belly"    silent watch: the player earning enough to afford their first
	             upgrade (TutorialConfig.burnPromptStat), with the belly hitting
	             TutorialConfig.bellyThreshold01 as the safety net.
	  "path"     the guidance BEAM (a clone of the authored HintBeam) runs from
	             the player to the checkpoint plate, and the TO CHECKPOINT
	             button breathes. Ends on ARRIVAL at the plate.
	  "upgrades" the world arrow points at the upgrade computer. It KEEPS
	             pointing while the tree is opened and browsed; the step (and the
	             tutorial) ends only when the player actually BUYS a tier, which
	             is when `TutorialComplete` goes to the server.
	Steps 2-5 are skipped entirely for an account whose profile says `done`.

	OPENING THE TREE FROM THE HUD DOES NOT BREAK ANY OF THIS (2026-08-13, user
	request). The game HUD grew an Upgrades button beside the station prompt
	(features/app-root.md). The flow needed one thing to already be true and one
	thing to be added:
	  * TRUE ALREADY — completion tests the STATE ("owns a tier") off
	    `UpgradesUpdate` from ANY live guided step, never a prompt transition, so a
	    tier bought through the HUD ends onboarding exactly like one bought at the
	    computer. Nothing about the exit was ever prompt-shaped.
	  * ADDED — the TUTORIAL funnel's `upgrades` step (with its dwell), which used
	    to ride the prompt alone. The player-flow `upgrades-open` step did not:
	    AnalyticsSubsClient polls the open PANEL and always reported it.
	The HUD open moves NO step, deliberately — see the two-openers block below.

	WHY THE LAST STEP ENDS ON A PURCHASE (2026-08-09, user request): opening the
	computer is not learning the loop — eat, burn, SPEND is. The prompt used to
	end the flow, so a player who pressed E, looked at the honeycomb and walked
	away had "completed" onboarding without ever buying anything, and the arrow
	that would have brought them back was already gone. The prompt now only moves
	the step (and fires the `upgrades-open` beat, which still means exactly what
	its name says); the purchase ends it. The two are separate events in the
	analytics catalog already — `upgrades-open` then `first-upgrade` — so the gap
	the change is meant to close is measured for free.

	WHY THE THRESHOLD IS LATCHED: the belly falls again the moment a gym drain
	starts (BodySubs resyncs ~8 Hz), so an un-latched test would blink the beam
	off at 89% while the player is still walking to the platform. The same is true
	of the affordability gate — banking SPENDS `stored`, so it un-affords itself.
	Both are one-way: `setStep` only ever moves forward.

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

	-- Step 3's gate (see TutorialConfig.burnPromptStat). Both modules are COMMON
	-- and load before subscriptions, so absence means a broken bootstrap, not a
	-- place split — warn and let the belly safety net carry the step (R8).
	local LocalStatsService = modules.LocalStatsService
	local LocalUpgradeTree = modules.LocalUpgradeTree
	local gateStat = TutorialConfig.burnPromptStat
	if LocalStatsService == nil or LocalUpgradeTree == nil then
		Log.Warn(SCOPE, "LocalStatsService/LocalUpgradeTree missing -- step 3 cannot test upgrade affordability; it will advance on the belly threshold alone")
	elseif type(gateStat) ~= "string" or gateStat == "" then
		Log.Warn(SCOPE, "TutorialConfig.burnPromptStat missing -- step 3 will advance on the belly threshold alone")
		gateStat = nil
	end

	-- The authored UpgradeStation prompt is what ends the flow; its NAME is
	-- already the contract UpgradesSubsClient opens the tree on.
	local upgradesUi = data.UpgradesUiData
	local promptName = upgradesUi and upgradesUi["config"] and upgradesUi["config"]["prompt-name"]
	if promptName == nil then
		Log.Warn(SCOPE, "UpgradesUiData config['prompt-name'] missing -- the last step can never be ENTERED (and UpgradesSubsClient cannot open the tree either, so nothing can be bought): the tutorial will never finish")
	end

	-- ── state ───────────────────────────────────────────────────────────
	local step: string? = "slides"
	-- nil until TutorialUpdate lands. Tri-state on purpose: "not told yet" is
	-- NOT the same as "not done", and starting the hints on the assumption of
	-- `false` would flash them at a veteran who skipped the slides fast.
	local serverDone: boolean? = nil
	local wantSteps = false
	local completeSent = false

	-- The two world-facing steps, i.e. the ones the beam is drawn for.
	local function isBeamStep(value: string?): boolean
		return value == "path" or value == "upgrades"
	end

	local function push()
		AppRoot.Set({
			tutorial = {
				slides = step == "slides",
				hint = if step == "eat" then "eat" else nil,
				pulseCheckpoint = step == "path",
			},
		})
	end

	-- ── world guidance: the beam (steps "path" AND "upgrades") ──────────
	-- ONE mechanism for both world-facing steps (user request, 2026-08-09): the
	-- flow used to switch to a screen-space HintArrow for the last step, so the
	-- player was taught to follow a line and then asked to follow something else.
	-- Only the DESTINATION changes — plate, then computer.
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

	-- Which authored piece the beam points at, for the step we are on. Resolved
	-- LAZILY every tick (place content replicates late) and never cached.
	local function beamTarget(): (BasePart?, string, string, number)
		if step == "upgrades" then
			return asBasePart(checkpointChild(world.upgradeStationName)),
				world.upgradeStationName,
				"upgrade computer",
				TutorialConfig.beam.stationExtraHeight or 0
		end
		return asBasePart(checkpointChild(world.plateName)), world.plateName, "checkpoint plate", 0
	end

	-- Rebuilt (not repositioned) whenever a piece goes away OR the step changes
	-- its destination: the HumanoidRootPart dies on every respawn and the
	-- checkpoint is re-cloned with the map, so holding references across those
	-- events is the bug, not the fix.
	local function ensureBeam()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local target, targetName, targetLabel, extraHeight = beamTarget()
		if root == nil or target == nil then
			clearBeam()
			if target == nil then
				-- R8: without this the step shows NOTHING and says nothing. The
				-- key is per-target so a missing plate and a missing computer are
				-- reported separately.
				Log.GraceOnce(SCOPE, `tutorial-no-target-{targetName}`, TutorialConfig.resolveGraceSeconds, function()
					return (select(1, beamTarget())) == nil
				end, `workspace.{world.mapFolder}.{world.checkpointFolder}.{targetName} missing — the tutorial beam cannot point at the {targetLabel} (that step shows no guidance at all)`)
			end
			return
		end
		-- Still wired to the same live parts? Then nothing to do.
		if beam ~= nil
			and beamPlayerAttachment ~= nil and beamPlayerAttachment.Parent == root
			and beamTargetAttachment ~= nil and beamTargetAttachment.Parent == target
		then
			return
		end
		clearBeam()

		local template = beamTemplate()
		if template == nil then
			Log.GraceOnce(SCOPE, "tutorial-no-beam-template", TutorialConfig.resolveGraceSeconds, function()
				return beamTemplate() == nil
			end, `ReplicatedStorage.Assets.{world.beamFolder}.{world.beamName} missing — no guidance beam at all (steps 4 and 5 degrade to the pulsing button alone). It is PLACE content, not in the repo.`)
			return
		end

		local beamCfg = TutorialConfig.beam
		local from = Instance.new("Attachment")
		from.Name = world.clientFolderName .. "From"
		from.Position = beamCfg.playerAttachmentOffset
		from.Parent = root

		local to = Instance.new("Attachment")
		to.Name = world.clientFolderName .. "To"
		-- Above the target's TOP face, not its centre: the plate is a slab the
		-- player walks onto, and the computer is a prop they stand beside.
		to.Position = Vector3.new(0, target.Size.Y / 2 + extraHeight, 0) + beamCfg.targetAttachmentOffset
		to.Parent = target

		local clone = template:Clone()
		clone.Attachment0 = from
		clone.Attachment1 = to
		-- STRAIGHT: curveSize 0 draws the direct line the player should walk.
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
		Log.Info(SCOPE, `guidance beam attached (player -> {targetLabel})`)
	end

	-- ── step transitions ────────────────────────────────────────────────
	-- Called on the FIRST upgrade purchase (see the UpgradesUpdate watch below).
	-- No client beat: the tutorial funnel's `done` step and the `tutorial-done`
	-- flow step are both fired SERVER-side off `TutorialComplete` (TutorialSubs),
	-- and Ingest refuses a client asserting a step the server owns.
	local function finish()
		if step == nil then
			return
		end
		-- WHICH step it ended on is worth a line (R8). Completion has always been
		-- allowed from any live guided step, but until 2026-08-13 the only way to
		-- reach the tree was a prompt at the station, so it was ALWAYS `upgrades`
		-- in practice. The HUD button removed that coupling, and one cohort can now
		-- finish without ever standing on the plate: an Auto-Gym / VIP owner banks
		-- calories anywhere on the cake (BodySubs' auto burn), so they can buy from
		-- step `belly`. Their funnel legitimately shows no `checkpoint` step — the
		-- beats are NOT back-filled, because asserting "reached the checkpoint" for
		-- a player who never did would corrupt the one thing the funnel measures.
		local endedOn = step
		step = nil
		clearBeam()
		push()
		if completeSent or serverDone == true then
			return
		end
		completeSent = true
		rComplete:FireServer()
		Log.Sum(SCOPE, `onboarding COMPLETE (first upgrade bought, from step '{endedOn}') — TutorialComplete sent`)
		if endedOn ~= "upgrades" then
			Log.Info(
				SCOPE,
				`onboarding ended from '{endedOn}', not '{"upgrades"}' — the tree was opened from the HUD before the `
					.. "checkpoint was reached (expected for Auto-Gym/VIP owners, who bank calories without a gym trip). "
					.. "The `checkpoint`/`arrived` beats are deliberately NOT reported: they were not earned."
			)
		end
	end

	local function setStep(next: string?)
		if step == next then
			return
		end
		step = next
		-- Leaving the beam steps tears the line down; MOVING BETWEEN them (path
		-- -> upgrades) also clears it, because the destination attachment has to
		-- be re-parented to the new target — `ensureBeam` rebuilds on the next
		-- tick against whatever `beamTarget()` now returns.
		clearBeam()
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

	-- ── step 3's gate: "you can afford your first upgrade" ──────────────
	-- Belly snapshot, kept because the two halves of the gate ride different
	-- remotes: `fill`/`stored` come on StomachUpdate (every bite), the BANKED
	-- balance on CurrencyUpdate (AppRoot state), the owned tiers on
	-- UpgradesUpdate (LocalStatsService).
	local lastFill, lastCapacity, lastStored = 0, 0, 0

	-- Would the trip we are about to send them on leave them able to buy the gate
	-- stat's next tier? Before the first gym visit EVERY calorie they have earned
	-- is unbanked, so the honest test is the post-burn balance:
	-- `calories + floor(stored × gymEff)` — the exact figure GymService will bank.
	local function canAffordGateStat(): boolean
		if LocalStatsService == nil or LocalUpgradeTree == nil or gateStat == nil then
			return false
		end
		local banked = tonumber(AppRoot.Get("calories")) or 0
		local afterBurn = banked + math.floor(lastStored * LocalStatsService.GymEfficiency())
		-- nil = the config no longer has this stat; fall through to the belly net
		-- rather than treating a typo as "gate satisfied" and skipping the step.
		return LocalUpgradeTree.CanAffordNext(LocalStatsService.Levels(), afterBurn, gateStat) == true
	end

	local function evaluateBurnPrompt()
		if step ~= "belly" then
			return
		end
		if canAffordGateStat() then
			setStep("path")
			return
		end
		-- SAFETY NET (TutorialConfig.bellyThreshold01): a player who cannot eat and
		-- has not been told where to go is the worst state a first session reaches.
		if lastCapacity > 0 and lastFill / lastCapacity >= TutorialConfig.bellyThreshold01 then
			Log.Info(
				SCOPE,
				`belly reached {math.floor(TutorialConfig.bellyThreshold01 * 100)}% before '{tostring(gateStat)}' was affordable — advancing step 3 on the safety net`
			)
			setStep("path")
		end
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
		-- ⚠ `onTutorialArrowTarget` was removed on 2026-08-09 together with the
		-- screen-space HintArrow: the last step draws the same world BEAM as the
		-- one before it, so there is no per-frame target callback any more.
	})

	-- Belly watch (steps "eat" -> "belly" -> "path"). Both payload shapes carry
	-- `fill`/`capacity`/`stored`; only the per-bite one carries `layerId`, which
	-- is how the first BITE is told apart from a join/gym resync.
	Net.Update("StomachUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		-- Snapshot BEFORE the step logic: a missing field keeps the last known
		-- value rather than zeroing the gate.
		lastFill = tonumber(payload.fill) or lastFill
		lastCapacity = tonumber(payload.capacity) or lastCapacity
		lastStored = tonumber(payload.stored) or lastStored
		if step == "eat" and payload.layerId ~= nil then
			-- They worked it out without reading. Get out of the way.
			if Analytics then
				Analytics.Flow("eat-hint-clear")
			end
			setStep("belly")
			-- deliberately NO return: with the 2026-08-05 belly curve a single
			-- opening bite can already be worth the first upgrade, and making the
			-- player wait for the NEXT push to be told so is a visible stall.
		end
		evaluateBurnPrompt()
	end)

	-- ── the tree opened, and the tree was BOUGHT from ───────────────────
	-- Opening moves the step; only a purchase ends the flow.
	-- ⚠ The two zones do not coincide: the station's prompt is a 10-stud sphere
	-- with no line-of-sight requirement and sits ~3.5 studs from the loaf edge,
	-- so it lights up several studs back ONTO the cake — while `checkpointFar`
	-- stays true anywhere on the loaf by design (BodySubsClient). So the prompt
	-- is honoured from ANY live step: a player who presses E on the way in must
	-- still get the arrow (and, before this change, still got their completion —
	-- gating that on step == "upgrades" once made the tutorial replay forever).
	-- ⚠ "any LIVE step" means any GUIDED step — never "slides". The comic plays
	-- for everyone, including accounts that finished onboarding years ago, and
	-- the station prompt is a keyboard press the comic does not swallow. Without
	-- this test a veteran who taps E while the comic is up would be handed a
	-- first-session arrow, and a purchase would dismiss the comic under them.
	local function guidedStepRunning(): boolean
		return step ~= nil and step ~= "slides"
	end

	-- ⚠ TWO OPENERS since 2026-08-13 (features/app-root.md): the station prompt
	-- and the game HUD's Upgrades button. They are deliberately NOT equivalent to
	-- onboarding, and that asymmetry is the whole point of this block:
	--   * the PROMPT proves the player is AT the station, so it MOVES the step;
	--   * the HUD BUTTON is reachable from anywhere — including step "eat" with an
	--     empty balance — so it moves NOTHING. Advancing on it would tear down the
	--     eat popup and run the beam to a computer across the cake for a player who
	--     has not eaten yet, and whose calories are all still unbanked (they cannot
	--     buy anything, which is exactly why the run-scoped tree does not break the
	--     loop the button opens a second door into).
	-- Both must still REPORT — but measure before believing which half was at
	-- risk. Verified live 2026-08-13 by recording the `AnalyticsBeat` remote:
	--   * the PLAYER-FLOW step `upgrades-open` and the `upgrades` funnel's `open`
	--     step were ALREADY opener-agnostic. `AnalyticsSubsClient` polls
	--     `AppRoot.GetOpenPanel()` and fires both when it turns "Upgrades",
	--     whatever opened it. (`Flow` is `once`-deduped, so the call inside
	--     `beat` below is a harmless no-op whenever that poll wins the race —
	--     which it does. It stays as the belt to that sub's braces.)
	--   * the TUTORIAL funnel's own `upgrades` step is the one that rode the
	--     prompt alone, and it is the one that carries the DWELL — how long the
	--     player stood at the station before opening anything. Without this a
	--     player who buys through the HUD leaves a hole between `arrived` and
	--     `done` in the onboarding funnel that reads as a drop-off.
	-- Reported once, and only from the step the funnel expects it in, so an early
	-- HUD open can never assert step 5 out of order.
	local treeOpenedBeat = false
	local function reportTreeOpened()
		if treeOpenedBeat or step ~= "upgrades" then
			return
		end
		treeOpenedBeat = true
		beat("upgrades", "upgrades-open")
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if not guidedStepRunning() or promptName == nil or prompt.Name ~= promptName then
			return
		end
		-- setStep FIRST so the "arrived" beat cannot be reported after the
		-- "opened the computer" one.
		setStep("upgrades")
		reportTreeOpened()
	end)

	-- The purchase watch. `UpgradesUpdate` is the ONLY channel that carries owned
	-- tiers to the client and its payload is byte-identical for a join snapshot,
	-- a successful buy and a refused-buy resync — so this tests the STATE ("owns
	-- at least one tier"), not a transition. That is the robust reading here:
	-- `RunResetSubs` zeroes every tier on each profile load (ADR-0013) and the
	-- server sends every configured id zero-filled, so the first push of a run is
	-- provably all-zeros for veterans and newcomers alike, and a player who
	-- somehow already owns a tier should not be nagged by an arrow.
	-- ⚠ Client subs Start alphabetically, so this handler runs one step AHEAD of
	-- UpgradesSubsClient's on the same remote — hence reading the payload here
	-- rather than LocalStatsService, which has not been fed yet.
	local seenLevels = false
	Net.Update("UpgradesUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.levels) ~= "table" then
			-- R8: this remote is ANOTHER feature's contract (features/upgrades.md
			-- owns it). If its shape ever changes, the tutorial's only exit stops
			-- firing and the player keeps the arrow forever with nothing on the
			-- console to say why. Warn once rather than returning silently.
			Log.Once(
				SCOPE,
				"tutorial-upgrades-shape",
				"UpgradesUpdate carried no `levels` table -- the tutorial can no longer see a purchase and will never finish"
			)
			return
		end
		local owned = false
		for _, level in pairs(payload.levels) do
			if type(level) == "number" and level >= 1 then
				owned = true
				break
			end
		end
		local isFirstPush = not seenLevels
		seenLevels = true
		if not owned or not guidedStepRunning() then
			return
		end
		if isFirstPush then
			-- They already owned tiers before the flow could point at any. Normal
			-- if `runCfg.resetOnLoad` is off (ADR-0013 is opt-out-able); a symptom
			-- of a failed run reset if it is on. Either way suppressing is right —
			-- but say WHICH completion this was, so the two are not confused.
			Log.Info(SCOPE, "first UpgradesUpdate already reports owned tiers -- onboarding suppressed instead of pointing at a purchase already made")
		else
			-- BACKSTOP for the HUD opener: you cannot buy a tier without the tree
			-- being open, so a real purchase proves the open even if the 0.5 s tick
			-- never sampled it (open + buy + close inside one interval). No-ops when
			-- the tick or the prompt already reported, and keeps `upgrades-open`
			-- strictly before the server's `tutorial-done`.
			reportTreeOpened()
		end
		finish()
	end)

	-- One throttled tick drives both world-facing steps. It is deliberately NOT
	-- per-frame: the beam's endpoints follow their parent parts by themselves,
	-- so this only has to notice pieces appearing, dying, or the player arriving.
	-- BOTH beam steps tick here now (the last step draws a beam too, so it is no
	-- longer a state with nothing to do). Still throttled, not per-frame: the
	-- beam's endpoints follow their parent parts by themselves, so this only has
	-- to notice pieces appearing, dying, the destination changing, or the player
	-- arriving.
	local accum = math.huge
	RunService.RenderStepped:Connect(function(dt)
		if not isBeamStep(step) then
			return
		end
		accum += dt
		if accum < TutorialConfig.resolveIntervalSeconds then
			return
		end
		accum = 0
		ensureBeam()
		-- ARRIVAL. `checkpointFar` is BodySubsClient's plate-footprint test
		-- (it Starts first, alphabetically); reading it keeps one definition
		-- of "on the platform" instead of a second copy that could drift.
		if step == "path" and AppRoot.Get("checkpointFar") == false then
			setStep("upgrades")
		end
		-- The tree may have been opened from the HUD button, which fires no
		-- ProximityPrompt event. Reading AppRoot's own `openPanel` is how this sub
		-- already learns a fact another sub owns (`checkpointFar`, one line up),
		-- and for the same reason: ONE definition of "the tree is open", not a
		-- second copy that can drift from UpgradesSubsClient's modal state.
		-- Checked AFTER the arrival test so a player who opened the tree while
		-- walking is reported the instant they land, not one tick later.
		if AppRoot.GetOpenPanel() == "Upgrades" then
			reportTreeOpened()
		end
	end)
end

return TutorialSubsClient
