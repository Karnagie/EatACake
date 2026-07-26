--[[
	EconomySubsClient — currency consumer (R4).
	CurrencyUpdate ({ calories, gems }) -> AppRoot HUD pills.

	GEMS get a pickup cue, calories do NOT: calories tick on every bite (many
	a second), so a cue there would be a drone. The first push is the join
	snapshot, not a gain — it must stay silent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local EconomySubsClient = {}

function EconomySubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local lastGems: number? = nil

	Net.Update("CurrencyUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" then
			local gems = tonumber(payload.gems) or 0
			local gained = lastGems ~= nil and gems > lastGems
			lastGems = gems
			AppRoot.Set({
				calories = tonumber(payload.calories) or 0,
				gems = gems,
			})
			-- AFTER the state push: an error in the cue must never cost the HUD its
			-- update for the rest of the session (a throwing OnClientEvent handler
			-- stays connected and throws again on every push).
			if gained then
				SoundPool.Play("gemGain") -- throttled in AudioConfig
			end
		end
	end)
end

return EconomySubsClient
