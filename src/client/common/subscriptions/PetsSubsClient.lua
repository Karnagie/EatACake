--[[
	PetsSubsClient — pets domain consumer (R4, GDD §9): PetsUpdate feeds the
	AppRoot pets panel; PetRollUpdate triggers the reveal; equip clicks flow
	back through the EquipPet remote.

	The reveal cue is RARITY-TIERED (AudioConfig.hatchByRarity): a legendary
	must not sound like a common, or the roll has no stakes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local AudioConfig = require(Shared:WaitForChild("config"):WaitForChild("AudioConfig"))

local SCOPE = "PetsSubsClient"

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
		local rarity = if type(roll.rarity) == "string" then roll.rarity else nil
		local cue = rarity and AudioConfig.hatchByRarity[rarity] or nil
		if cue == nil then
			-- A new rarity with no hatch cue would silently fall back to the
			-- common one and read as a worthless roll (R8).
			Log.Once(SCOPE, `no-hatch-cue-{tostring(rarity)}`, `rarity '{tostring(rarity)}' has no AudioConfig.hatchByRarity entry — falling back to the common hatch cue`)
			cue = "hatchCommon"
		end
		SoundPool.Play(cue)
	end)

	AppRoot.SetCallbacks({
		onEquipPet = function(petId: string, equip: boolean)
			rEquip:FireServer(petId, equip)
			SoundPool.Play("petEquip", { pitchMult = if equip then 1 else 0.8 })
		end,
		onDismissReveal = function()
			AppRoot.Set({ petReveal = false }) -- false = dismissed (nil won't overwrite)
		end,
	})
end

return PetsSubsClient
