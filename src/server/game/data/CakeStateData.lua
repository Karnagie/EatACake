--[[
	CakeStateData — ALL runtime state of the shared per-server cake
	(R1: no state outside data modules). Owned/mutated by CakeFieldService
	and CakeCycleService; replicated by CakeSubs.

	Data shape:
	  field         buffer (u16 heights, GridUtil layout), allocated in Init
	  footprint     { hx, hz, corner } in cells — the rounded-rect SDF GridUtil
	                .InCake tests. All THREE equal == a DISC of that radius,
	                which is what ships (round cake, see CakeConfig)
	  composition   array bottom-up: { { id, bottom, top, scoop, density,
	                group, footprint } } (studs). `group` = the flavour ZONE this band
	                belongs to, 1 == the TOP zone (features/cake-cycle.md)
	  zones         the ZONE ROSTER of this cake, top-down:
	                { { id, nameKey, members, layers, radiusScale,
	                    gateFromPrevious, gateIndex?, bossModel? } }.
	                Gated destinations receive a sequential gateIndex and one
	                distinct bossModel; visual-only boundaries receive neither.
	                Rolled by CakeCycleService.RollComposition.
	  floorUnits    core-top height in u16 units — the absolute cake floor
	  activeBandIndex  index into composition of the current TOP edible band
	                   (layer gate): bites can't dig below this band's bottom
	  activeFloorUnits bottom of the active band in u16 units — the layer-gate
	                   bite clamp (== floorUnits when the gate is disabled or
	                   only the core remains). Advances as layers are eaten.
	  cakeIndex     increments per cake (clients drop stale deltas)
	  cakeId        selectable variant id (`cake-classic` / `cake-rainbow`)
	  rareKind      nil | "golden" | "rainbow" (random modifier, distinct from cakeId)
	  biome         current biome id (CakeConfig.biomeOrder[1] since 2026-07-26)
	  phase         "eating" | "miniboss" | "boss" | "reward" | "spawning"
	  phaseTimer    seconds left in a timed phase (boss / spawning). A
	                mini-boss is UNTIMED — it is a gate, not a race
	  boss          { hp, maxHp } during the boss phase
	  miniBoss      { hp, maxHp, index, zoneIndex, model, zoneKey } during the
	                miniboss phase — the zone-boundary gate
	  pendingMiniBossZones  FIFO of crossed gated destination-zone indexes that
	                        still need their mini-boss, in top-to-bottom order
	  miniBossesDefeated  how many gates this cake has already given up
	  debugSuppressFindRewards  Studio DebugClearLayer safety latch for this cake;
	                            reveal/collect visuals continue, profile writes do not
	  progress      0..1 eaten fraction (1 Hz scan)
	  edibleVolume  studs^3 of edible cake at spawn (progress denominator)
	  cakeStartedAt os.clock when the CURRENT cake was spawned — the start of
	                the SPEEDRUN clock (features/leaderboards.md)
	  cakeStartRoster  { [userId] = true } of everyone present at that spawn.
	                Only they get a time when the cake is cleared: a player who
	                joined an endless-mode cake half-eaten did not run it

	  settleQueue / settleQueued — FIFO + membership set of settle-dirty cells
	  netDirty / netDirtyList    — set + list of cells awaiting network flush
	  (both FIFOs use head/tail cursors owned by CakeFieldService)
	  repairCursor  rotating index for loss self-healing packets
]]

local CakeStateData = {}

CakeStateData.field = nil :: buffer?
CakeStateData.footprint = { hx = 1, hz = 1, corner = 1 }
-- Bite-torn cells wait here before they may settle (the "chunk ripped
-- out, then it slowly oozes" feel): array of { i, dueAt (os.clock) }.
CakeStateData.delayedSettle = {} :: { { i: number, dueAt: number } }
CakeStateData.composition = {}
-- Flavour ZONE roster of the current cake, top-down (see the header). Empty
-- until the first RollComposition.
CakeStateData.zones = {} :: { any }
CakeStateData.floorUnits = 0
-- Layer gate (features/cake-sim.md): the top edible band and its floor. Set
-- by CakeFieldService.ResetCake, advanced by ScanStats as layers are eaten.
CakeStateData.activeBandIndex = 0
CakeStateData.activeFloorUnits = 0
CakeStateData.cakeIndex = 0
CakeStateData.cakeId = "cake-classic"
CakeStateData.rareKind = nil :: string?
-- Calorie payout scale of the CURRENT cake: difficulty premium × per-head co-op
-- payout, fixed once at RollComposition so it cannot drift as players leave
-- (CakeCycleService.CakeCaloriesMult, features/cake-cycle.md).
CakeStateData.payoutScale = 1
-- GEM payout scale of the CURRENT cake: per-head co-op term × selectable-variant
-- multiplier, no difficulty premium (CakeCycleService.ScaleFindReward).
CakeStateData.findPayoutScale = 1
CakeStateData.biome = "factory"
CakeStateData.phase = "spawning"
CakeStateData.phaseTimer = 0
CakeStateData.boss = nil :: { hp: number, maxHp: number }?
-- The ZONE-BOUNDARY gate (features/cake-cycle.md): a mini-boss bursts out of
-- the cake when the layer gate crosses from one flavour zone into the next and
-- blocks every bite until it is beaten. UNTIMED on purpose.
CakeStateData.miniBoss = nil :: { hp: number, maxHp: number, index: number, zoneIndex: number, model: string?, zoneKey: string? }?
-- A 1 Hz scan can observe several already-flattened zones at once. Keep every
-- gated destination here until its boss has been fought; CakeCycleService owns
-- queue mutation and CakeCycleSubs owns the cross-service transitions.
CakeStateData.pendingMiniBossZones = {} :: { number }
CakeStateData.miniBossesDefeated = 0
-- Studio-only safety latch armed by DebugClearLayer. TreasureService still
-- consumes/reveals finds for visual QA, while CakeSimulationSubs suppresses all
-- reward, progress, discovery, analytics, and save mutations until a new cake.
CakeStateData.debugSuppressFindRewards = false
CakeStateData.progress = 0
CakeStateData.edibleVolume = 0

-- SPEEDRUN clock of the current cake (features/leaderboards.md). Stamped by
-- CakeCycleSubs.SpawnNewCake and read once, at the boss win. os.clock is
-- monotonic and is what the rest of the round code already measures with.
CakeStateData.cakeStartedAt = 0
CakeStateData.cakeStartRoster = {} :: { [number]: boolean }

-- Hourly Cake Event (GDD §12.2): unix time of the last forced rare cake.
CakeStateData.lastRareEventAt = 0

CakeStateData.settleQueue = {} :: { number }
CakeStateData.settleQueued = {} :: { [number]: boolean }
CakeStateData.netDirty = {} :: { [number]: boolean }
CakeStateData.netDirtyList = {} :: { number }
CakeStateData.repairCursor = 0

-- One-Heartbeat scheduling clocks (CakeSimulationSubs). Runtime only.
CakeStateData.simulationAccumulators = {
	settle = 0,
	net = 0,
	collision = 0,
	treasure = 0,
	scan = 0,
	cycle = 0,
}

-- Collision: net.collisionGrid² invisible safety-net parts (16x16) owned by CakeCollisionService.
CakeStateData.collisionParts = {} :: { BasePart }

-- Treasures of the current cake: array of
-- { def, x, z, model: Instance?, parts: { BasePart }, sparkle: ParticleEmitter?,
--   height, radiusCells, footprint, topUnits, bottomUnits, exposure (0..1, MONOTONIC),
--   state = "buried"|"loaded"|"revealed"|"collected" } — see TreasureService.
-- The model is a CLONE of the authored ReplicatedStorage.Assets.Items library,
-- parented into workspace.CakeFinds at cake spawn and hidden (alpha 1) until
-- the surface nears it.
CakeStateData.treasures = {}

function CakeStateData.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CakeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("CakeConfig"))
	local size = CakeConfig.grid.size
	CakeStateData.field = buffer.create(size * size * 2)
	for key in pairs(CakeStateData.simulationAccumulators) do
		CakeStateData.simulationAccumulators[key] = 0
	end
end

return CakeStateData
