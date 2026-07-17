--[[
	PetSubs — pets domain orchestration (R4, GDD §9): equip/unequip remote,
	collection pushes, the pet-reveal channel, and the "egg" reward kind
	(ADR-0002) so shop products / finds / daily rewards can grant rolls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "PetSubs"

local PetSubs = {}

local services_
local uPets, uPetRoll

--API
-- Collection + slots push.
function PetSubs.SendPets(player: Player)
	if uPets == nil then
		Log.Warn(SCOPE, `SendPets({player.Name}) before Start ran — push dropped`)
		return
	end
	local userId = player.UserId
	local collection = services_.PetService.Collection(userId)
	if collection == nil then
		Log.Warn(SCOPE, `SendPets({player.Name}): profile not loaded — push dropped`)
		return
	end
	uPets:FireClient(player, {
		collection = collection,
		slots = services_.StatsService.PetSlots(userId),
	})
	-- Followers replicate via a plain attribute: every client renders every
	-- player's equipped pets locally (PetFollowers), zero extra remotes.
	local equipped = {}
	for _, entry in ipairs(collection) do
		if entry.equipped then
			table.insert(equipped, entry.petId)
		end
	end
	player:SetAttribute("EquippedPets", table.concat(equipped, ","))
end

--API
-- One roll result -> the reveal UI (slot machine).
function PetSubs.SendRoll(player: Player, roll)
	if uPetRoll == nil then
		Log.Warn(SCOPE, `SendRoll({player.Name}) before Start ran — push dropped`)
		return
	end
	uPetRoll:FireClient(player, roll)
end

function PetSubs.Start(data, services)
	services_ = services
	uPets = Net.Update("PetsUpdate")
	uPetRoll = Net.Update("PetRollUpdate")

	Net.Remote("EquipPet").OnServerEvent:Connect(function(player, petId, equip)
		if type(petId) ~= "string" or type(equip) ~= "boolean" then
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			return
		end
		local ok, reason
		if equip then
			ok, reason = services.PetService.Equip(userId, petId, services.StatsService.PetSlots(userId))
		else
			ok, reason = services.PetService.Unequip(userId, petId)
		end
		if not ok then
			Log.Info(SCOPE, `{player.Name}: equip({petId}, {equip}) refused — {reason}`)
		end
		PetSubs.SendPets(player) -- resync either way (covers stale client UI)
	end)

	-- Reward kind "egg": { kind = "egg", eggType = "cycle"|"lucky"|"mega" }.
	RewardGrantSubs.Register("egg", function(player: Player, reward, source: string?)
		local roll = services.PetService.Roll(player.UserId, reward.eggType)
		if not roll then
			return nil -- profile not loaded
		end
		roll.source = source or "egg"
		PetSubs.SendRoll(player, roll)
		PetSubs.SendPets(player)
		return { kind = "egg", petId = roll.petId, rarity = roll.rarity }
	end)
end

return PetSubs
