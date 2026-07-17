--[[
	ComboMeter — the eat combo (GDD §7.5): grows +1 step every `growEvery`
	seconds of continuous eating up to `max`; a pause > `resetAfter` resets.
	FX-ONLY by design: drives pitch, particles, shake and number size —
	never calories (a server-validated combo isn't worth the surface).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JuiceConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("JuiceConfig")
)

local ComboMeter = {}

local combo = 1
local eatingSince = 0 -- 0 = not in a chain
local lastBiteAt = 0

--API
-- Registers a bite. Returns the current combo step (1..max).
function ComboMeter.RegisterBite(): number
	local now = os.clock()
	if now - lastBiteAt > JuiceConfig.combo.resetAfter then
		eatingSince = now
	end
	lastBiteAt = now
	combo = math.min(JuiceConfig.combo.max, 1 + math.floor((now - eatingSince) / JuiceConfig.combo.growEvery))
	return combo
end

--API
-- Current combo (resets lazily when the chain lapsed).
function ComboMeter.Current(): number
	if os.clock() - lastBiteAt > JuiceConfig.combo.resetAfter then
		combo = 1
		eatingSince = 0
	end
	return combo
end

--API
-- 0..1 intensity for FX scaling (saturation, particle counts).
function ComboMeter.Intensity(): number
	return (ComboMeter.Current() - 1) / math.max(1, JuiceConfig.combo.max - 1)
end

return ComboMeter
