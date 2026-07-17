--[[
	PetsSubsClient — pets domain consumer (R4, GDD §9): PetsUpdate feeds the
	AppRoot pets panel; PetRollUpdate triggers the reveal; equip clicks flow
	back through the EquipPet remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local PetsSubsClient = {}

function PetsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rEquip = Net.Remote("EquipPet")

	Net.Update("PetsUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		AppRoot.Set({ pets = payload })
	end)

	local revealCount = 0
	Net.Update("PetRollUpdate").OnClientEvent:Connect(function(roll)
		if type(roll) ~= "table" then
			return
		end
		revealCount += 1
		AppRoot.Set({ petReveal = roll, petRevealCount = revealCount })
		SoundPool.Play("fanfare", { pitchMult = 1.1 })
	end)

	AppRoot.SetCallbacks({
		onEquipPet = function(petId: string, equip: boolean)
			rEquip:FireServer(petId, equip)
		end,
		onDismissReveal = function()
			AppRoot.Set({ petReveal = false }) -- false = dismissed (nil won't overwrite)
		end,
	})
end

return PetsSubsClient
