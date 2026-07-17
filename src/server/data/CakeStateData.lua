--[[
	CakeStateData — ALL runtime state of the shared per-server cake
	(R1: no state outside data modules). Owned/mutated by CakeFieldService
	and CakeCycleService; replicated by CakeSubs.

	Data shape:
	  field         buffer (u16 heights, GridUtil layout), allocated in Init
	  footprint     rounded-rect loaf { hx, hz, corner } in cells
	  composition   array bottom-up: { { id, bottom, top } } (studs)
	  floorUnits    core-top height in u16 units — bites clamp here
	  cakeIndex     increments per cake (clients drop stale deltas)
	  rareKind      nil | "golden" | "rainbow"
	  biome         current biome id (from rebirth progression)
	  phase         "eating" | "boss" | "reward" | "spawning"
	  phaseTimer    seconds left in a timed phase (boss / spawning)
	  boss          { hp, maxHp } during the boss phase
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
CakeStateData.cakeIndex = 0
CakeStateData.rareKind = nil :: string?
CakeStateData.biome = "factory"
CakeStateData.phase = "spawning"
CakeStateData.phaseTimer = 0
CakeStateData.boss = nil :: { hp: number, maxHp: number }?
CakeStateData.progress = 0
CakeStateData.edibleVolume = 0

-- Hourly Cake Event (GDD §12.2): unix time of the last forced rare cake.
CakeStateData.lastRareEventAt = 0

CakeStateData.settleQueue = {} :: { number }
CakeStateData.settleQueued = {} :: { [number]: boolean }
CakeStateData.netDirty = {} :: { [number]: boolean }
CakeStateData.netDirtyList = {} :: { number }
CakeStateData.repairCursor = 0

-- Collision: 8x8 invisible parts owned by CakeCollisionService.
CakeStateData.collisionParts = {} :: { BasePart }

-- Treasures of the current cake: array of
-- { def, x, z, revealUnits, state = "buried"|"spawned"|"collected"|"gone",
--   part: BasePart? } — see TreasureService.
CakeStateData.treasures = {}

function CakeStateData.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CakeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("CakeConfig"))
	local size = CakeConfig.grid.size
	CakeStateData.field = buffer.create(size * size * 2)
end

return CakeStateData
