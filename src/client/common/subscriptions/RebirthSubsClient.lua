--[[
	RebirthSubsClient — rebirth domain consumer (R4, GDD §9): RebirthUpdate
	feeds the AppRoot rebirth panel; the confirm button fires DoRebirth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local RebirthSubsClient = {}

function RebirthSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rRebirth = Net.Remote("DoRebirth")

	Net.Update("RebirthUpdate").OnClientEvent:Connect(function(summary)
		if type(summary) ~= "table" then
			return
		end
		AppRoot.Set({ rebirth = summary })
	end)

	AppRoot.SetCallbacks({
		onDoRebirth = function()
			rRebirth:FireServer()
			SoundPool.Play("fanfare", { pitchMult = 0.9 })
		end,
	})
end

return RebirthSubsClient
