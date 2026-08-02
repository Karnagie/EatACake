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

-- Step 3 fires at this belly fraction. LATCHED, never re-armed: the belly
-- falls again the moment the gym drain starts (~8 Hz resync pushes), and a
-- beam that blinked off at 89% while the player walked would read as a bug.
TutorialConfig.bellyThreshold01 = 0.90

-- World contract (place-authored; ADR-0007 — none of this is in the repo).
-- `workspace.Map` is MapService's clone of ReplicatedStorage.Assets.
TutorialConfig.world = {
	mapFolder = "Map",
	checkpointFolder = "Checkpoint",
	-- Step 3's beam destination and step 4's arrow target.
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
-- ⚠ `width` and `color` exist because the authored beam is a 3-stud WHITE line,
-- and this game's guidance run is 80+ studs across a pastel sky over a
-- near-white loaf: measured in Studio, the authored settings render as a
-- hairline that is not findable on screen at all. Width 7 + the candy-magenta
-- the EAT button already uses (the one hue in the palette that no part of the
-- scene shares) is what makes it read. Set either to nil to defer to whatever
-- the template is authored with.
TutorialConfig.beam = {
	playerAttachmentOffset = Vector3.new(0, 1.5, 0), -- on the HumanoidRootPart
	targetAttachmentOffset = Vector3.new(0, 4.0, 0), -- above the plate's top face
	curveSize = 12,
	width = 7,
	color = Color3.fromRGB(255, 60, 200),
}

-- Step 4's arrow sits above the upgrade computer, not inside it.
TutorialConfig.arrow = {
	targetOffset = Vector3.new(0, 5.0, 0),
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
