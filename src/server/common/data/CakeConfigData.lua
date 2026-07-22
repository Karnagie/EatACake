--[[
	CakeConfigData — server-side access point to the shared cake config
	(R1: services receive config through data modules, never require
	Shared.config directly) + server-only tuning: anti-cheat caps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CakeConfigData = {}

local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config")
CakeConfigData.cake = require(config:WaitForChild("CakeConfig"))
CakeConfigData.upgrades = require(config:WaitForChild("UpgradeConfig"))
CakeConfigData.body = require(config:WaitForChild("BodyConfig"))
CakeConfigData.pets = require(config:WaitForChild("PetConfig"))
CakeConfigData.treasures = require(config:WaitForChild("TreasureConfig"))

-- ── Anti-cheat (GDD §13): every remote handler validates against these ──
CakeConfigData.antiCheat = {
	-- Bites/sec token bucket: capacity + refill = eatSpeed stat * slack.
	biteRateSlack = 1.6,
	biteRateBurst = 4, -- extra tokens to absorb network jitter
	-- The bite point must be near the character (raycast distance check).
	maxBiteReachStuds = 18, -- + the player's bite radius
	-- The bite point must be near the actual surface (no biting mid-air
	-- or deep underground through spoofed positions).
	maxSurfaceDeltaStuds = 8,
	-- NOTE: no per-bite calorie cap — volume/layer/calories are computed
	-- entirely server-side from a position, so there is nothing to clamp.
}

return CakeConfigData
