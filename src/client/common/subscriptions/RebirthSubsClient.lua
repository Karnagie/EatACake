--[[
	RebirthSubsClient — rebirth domain consumer (R4, GDD §9): RebirthUpdate
	feeds the AppRoot rebirth panel; the confirm button fires DoRebirth.

	The fanfare follows the rebirth COUNT going up in the update, not the button
	— a refused rebirth (not enough calories, profile not loaded) must stay
	silent (docs/features/audio.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local RebirthSubsClient = {}

function RebirthSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rRebirth = Net.Remote("DoRebirth")

	-- nil until the first push (the join snapshot is a state, not a rebirth).
	local lastRebirths: number? = nil

	Net.Update("RebirthUpdate").OnClientEvent:Connect(function(summary)
		if type(summary) ~= "table" then
			return
		end
		AppRoot.Set({ rebirth = summary })
		local rebirths = tonumber(summary.rebirths)
		if rebirths ~= nil then
			if lastRebirths ~= nil and rebirths > lastRebirths then
				SoundPool.Play("rebirth")
			end
			lastRebirths = rebirths
		end
	end)

	AppRoot.SetCallbacks({
		onDoRebirth = function()
			rRebirth:FireServer()
		end,
	})
end

return RebirthSubsClient
