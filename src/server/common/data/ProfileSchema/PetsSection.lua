--[[
	Profile section: pets — collection + equipped set (GDD §9).
	  owned    — { [petId: string] = copies } ; copies = pet level
	             (duplicates merge into upgrades automatically)
	  equipped — array of petIds (slot cap enforced by PetService)
]]

return {
	key = "pets",
	version = 1,
	defaults = {
		owned = {},
		equipped = {},
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		if type(section.owned) ~= "table" then
			section.owned = {}
		end
		for petId, copies in pairs(section.owned) do
			if type(copies) ~= "number" or copies ~= copies or copies == math.huge or copies < 1 then
				section.owned[petId] = 1
			else
				section.owned[petId] = math.floor(copies)
			end
		end
		if type(section.equipped) ~= "table" then
			section.equipped = {}
		end
		-- Equipped must reference owned pets.
		local cleaned = {}
		for _, petId in ipairs(section.equipped) do
			if section.owned[petId] then
				table.insert(cleaned, petId)
			end
		end
		section.equipped = cleaned
		return section
	end,
}
