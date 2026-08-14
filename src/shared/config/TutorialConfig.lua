--[[
	TutorialConfig -- the onboarding flow's tuning + authored-instance contract
	(ADR-0004: shared game config; features/tutorial.md is the feature doc).

	Loaded by BOTH places: the client sub reads the whole thing, the server sub
	reads only `analyticsBeat`. Nothing here is per-player state — the flag that
	says "this account finished the tutorial" lives in the `tutorial` profile
	section (P1).
]]

local TutorialConfig = {}

-- Story panels, in reading order (top-left, top-right, bottom-left,
-- bottom-right). NAMES, not asset ids: components resolve through
-- `Theme.Icon` (kit iron rule 2). Ids live in src/shared/UIKit/Icons.lua.
TutorialConfig.slideIcons = {
	"TutorialSlide1",
	"TutorialSlide2",
	"TutorialSlide3",
	"TutorialSlide4",
}

-- Step 3 ("go burn it off") fires when the player can afford their FIRST REAL
-- UPGRADE — not when the belly meter looks full (user request, 2026-08-05).
-- Rationale: "your stomach is full" is a punishment cue, and it arrives at the
-- moment the game stops responding to the button it just taught. "You have
-- earned a bigger bite, go and collect it" is the same walk with a reward at the
-- end of it, and it puts the player at the upgrade station holding exactly
-- enough calories to buy something — so their first trip to the checkpoint ends
-- in a purchase instead of a chore.
--
-- ⚠ The calories are UNBANKED at this point. A player who has never been to the
-- gym has `economy.calories == 0` and everything they earned sitting in
-- `stomach.stored`; the gate therefore tests `calories + floor(stored × gymEff)`,
-- which is exactly what the trip they are being sent on will pay out
-- (GymService banks `floor(startStored × gymEff)`).
-- ⚠ This stat's tier-1 cost is load-bearing — see the comment on
-- `UpgradeConfig.upgrades.biteRadius`. A full base belly of frosting is worth
-- ~612 calories against a 450 cost, so the gate opens ~74% of the way through
-- the very first belly.
TutorialConfig.burnPromptStat = "biteRadius"

-- SAFETY NET for the step above, not the trigger. If the gate somehow cannot
-- open — a re-priced `biteRadius`, a low-calorie biome, an already-maxed stat —
-- the player would sit at a full belly that refuses to eat with no guidance at
-- all, which is the worst state the first session can reach. Crossing this
-- fraction advances the step regardless.
-- Also read by BodySubs for the `belly-full` analytics beat: one definition of
-- "the belly is effectively full", so the funnel and the guidance can't disagree
-- about when that happened.
-- LATCHED, never re-armed: the belly falls again the moment the gym drain starts
-- (~8 Hz resync pushes), and a beam that blinked off at 89% while the player
-- walked would read as a bug.
TutorialConfig.bellyThreshold01 = 0.90

-- World contract (place-authored; ADR-0007 — none of this is in the repo).
-- `workspace.Map` is MapService's clone of ReplicatedStorage.Assets.
TutorialConfig.world = {
	mapFolder = "Map",
	checkpointFolder = "Checkpoint",
	-- The beam's two destinations: the checkpoint plate for step 4 ("go burn it
	-- off"), the upgrade computer for step 5 ("now spend it"). Since 2026-08-09
	-- BOTH steps draw the same beam — there is no arrow in the flow any more.
	plateName = "CheckpointPlate",
	upgradeStationName = "UpgradeStationBody",
	-- Authored Beam cloned for the guidance line (R5: clone, never create).
	beamFolder = "GuidanceTemplates",
	beamName = "HintBeam",
	-- Folder the client parks its own instances in, so nothing it makes is ever
	-- confused with authored content.
	clientFolderName = "TutorialGuidance",
}

-- Beam geometry + legibility overrides, applied to the CLONE only — the
-- authored template in ReplicatedStorage is never modified (R5).
--
-- STRAIGHT and WHITE (user request, 2026-08-09): `curveSize = 0` makes the beam
-- a direct line from the player to the target instead of the lobbed arc it used
-- to draw, and the colour is plain white.
--
-- ⚠ `width` stays overridden. The authored template is a 3-stud line, and this
-- game's guidance run is 80+ studs across a pastel sky over a near-white loaf:
-- measured in Studio, 3 studs renders as a hairline that is not findable on
-- screen at all. Width is the only lever left now that the hue is white, so do
-- not drop it too. Set any of the three to nil to defer to the template.
TutorialConfig.beam = {
	playerAttachmentOffset = Vector3.new(0, 1.5, 0), -- on the HumanoidRootPart
	-- Above the destination's top face. The upgrade computer is taller than the
	-- plate, so step 5 adds `stationExtraHeight` on top of this.
	targetAttachmentOffset = Vector3.new(0, 4.0, 0),
	stationExtraHeight = 2.0,
	curveSize = 0,
	width = 7,
	color = Color3.new(1, 1, 1),
}

-- Retry cadence for authored instances that replicate LATE (R8: never a
-- blocking WaitForChild in feature flow — re-check on a tick and warn once via
-- Log.GraceOnce if they truly never arrive).
TutorialConfig.resolveIntervalSeconds = 0.5
TutorialConfig.resolveGraceSeconds = 12

-- Player-flow beat recorded when the whole guided flow completes. Must be a
-- key in AnalyticsConfig.flowSteps or it only warns (features/analytics.md).
TutorialConfig.analyticsBeat = "tutorial-done"

return TutorialConfig
