--[[
	CakeStateData — ALL runtime state of the shared per-server cake
	(R1: no state outside data modules). Owned/mutated by CakeFieldService
	and CakeCycleService; replicated by CakeSubs.

	Data shape:
	  field         buffer (u16 heights, GridUtil layout), allocated in Init
	  footprint     rounded-rect loaf { hx, hz, corner } in cells
	  composition   array bottom-up: { { id, bottom, top } } (studs)
	  floorUnits    core-top height in u16 units — the absolute cake floor
	  activeBandIndex  index into composition of the current TOP edible band
	                   (layer gate): bites can't dig below this band's bottom
	  activeFloorUnits bottom of the active band in u16 units — the layer-gate
	                   bite clamp (== floorUnits when the gate is disabled or
	                   only the core remains). Advances as layers are eaten.
	  cakeIndex     increments per cake (clients drop stale deltas)
	  rareKind      nil | "golden" | "rainbow"
	  biome         current biome id (CakeConfig.biomeOrder[1] since 2026-07-26)
	  phase         "eating" | "boss" | "reward" | "spawning"
	  phaseTimer    seconds left in a timed phase (boss / spawning)
	  boss          { hp, maxHp } during the boss phase
	  pendingPetRolls  { [userId] = { petId, rarity } } — the squishy each player
	                   is fighting the boss FOR (pre-rolled when the boss phase
	                   opens so the HUD can show it), committed on a win
	  progress      0..1 eaten fraction (1 Hz scan)
	  edibleVolume  studs^3 of edible cake at spawn (progress denominator)

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
CakeStateData.floorUnits = 0
-- Layer gate (features/cake-sim.md): the top edible band and its floor. Set
-- by CakeFieldService.ResetCake, advanced by ScanStats as layers are eaten.
CakeStateData.activeBandIndex = 0
CakeStateData.activeFloorUnits = 0
CakeStateData.cakeIndex = 0
CakeStateData.rareKind = nil :: string?
-- Calorie payout scale of the CURRENT cake: difficulty premium × per-head co-op
-- payout, fixed once at RollComposition so it cannot drift as players leave
-- (CakeCycleService.CakeCaloriesMult, features/cake-cycle.md).
CakeStateData.payoutScale = 1
-- GEM payout scale of the CURRENT cake: per-head co-op term only, no difficulty
-- premium (CakeCycleService.ScaleFindReward, CakeConfig.composition.coopFinds).
CakeStateData.findPayoutScale = 1
CakeStateData.biome = "factory"
CakeStateData.phase = "spawning"
CakeStateData.phaseTimer = 0
CakeStateData.boss = nil :: { hp: number, maxHp: number }?
CakeStateData.progress = 0
CakeStateData.edibleVolume = 0

-- Hourly Cake Event (GDD §12.2): unix time of the last forced rare cake.
CakeStateData.lastRareEventAt = 0

-- The squishy each player is FIGHTING FOR, decided when the boss phase opens and
-- shown in the boss HUD (features/cake-cycle.md, features/pets.md):
--   { [userId] = { petId: string, rarity: string } }
-- Committed on a win by granting exactly this petId, so the prize on screen is
-- the prize you get. NOT owned yet — this is a pending intent, which is why it
-- lives in runtime state and not in the profile. Cleared on win, loss, and on
-- every new cake.
CakeStateData.pendingPetRolls = {} :: { [number]: { petId: string, rarity: string } }

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
--   height, radiusCells, topUnits, bottomUnits, exposure (0..1, MONOTONIC),
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
