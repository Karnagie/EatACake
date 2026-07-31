--[[
	ProgressService — lifetime stats over profile section `progress` (GDD §9).

	⚠ REBIRTH REMOVED (2026-07-26, by request). `RebirthCost` / `ApplyRebirth`
	are gone with the rest of the system (docs/flow/2026-07-26_cake-pacing-
	rebalance.md). The profile still CARRIES `progress.rebirths` (always 0) so
	no schema version bump / migration was needed, and `GetRebirths` still reads
	it for the leaderstat. Progression now lives in the persistent upgrade tree
	and the difficulty ladder instead.

	Biomes were unlocked by rebirth level; with no rebirths every cake uses the
	FIRST biome (`biomes[1]`). `BiomeFor` keeps its signature so the cake-spawn
	path is unchanged and re-introducing an unlock rule stays a one-liner.
]]

local ProgressService = {}

local profileData
local cakeCfg -- CakeConfigData.cake (biomeOrder)

-- Fallback only if the shared config never resolves (never crash a spawn).
local DEFAULT_BIOME = "factory"

function ProgressService.Init(data)
	profileData = data.PlayerProfileData
	cakeCfg = data.CakeConfigData and data.CakeConfigData.cake
end

local function progress(userId: number)
	local profile = profileData.profiles[userId]
	return profile and profile.progress
end

--API
-- Increments a lifetime stat (lifetimeCalories, cakesEaten, findsCollected).
function ProgressService.AddStat(userId: number, key: string, amount: number)
	local section = progress(userId)
	if section and type(section[key]) == "number" then
		section[key] += amount
	end
end

--API
-- How many DISTINCT buried-find kinds this player has ever dug up. The set, not
-- the count of pickups — a countable collection is what gives a long run a goal
-- (features/treasures.md).
function ProgressService.CountFindKinds(userId: number): number
	local section = progress(userId)
	if section == nil or type(section.foundKinds) ~= "table" then
		return 0
	end
	local n = 0
	for _ in pairs(section.foundKinds) do
		n += 1
	end
	return n
end

--API
-- Records that this player has now dug up `findId` at least once. Returns TRUE
-- only the FIRST time — that return value IS the "new discovery!" moment
-- (features/treasures.md). Safe to call on every collect.
function ProgressService.MarkFindDiscovered(userId: number, findId: string): boolean
	local section = progress(userId)
	if section == nil or type(findId) ~= "string" then
		return false
	end
	if type(section.foundKinds) ~= "table" then
		section.foundKinds = {}
	end
	if section.foundKinds[findId] then
		return false
	end
	section.foundKinds[findId] = true
	return true
end

--API
-- Always 0 now that rebirth is removed; kept for the leaderstat + summary.
function ProgressService.GetRebirths(userId: number): number?
	local section = progress(userId)
	return section and section.rebirths
end

--API
-- Biome for a rebirth level. Rebirth is gone, so this is always the first
-- biome; the argument is kept so callers (CakeCycleSubs) need no change.
function ProgressService.BiomeFor(_rebirths: number): string
	local order = cakeCfg and cakeCfg.biomeOrder
	if type(order) == "table" and order[1] ~= nil then
		return order[1]
	end
	return DEFAULT_BIOME
end

--API
-- Snapshot for the client (HUD stats + leaderboards).
function ProgressService.Summary(userId: number)
	local section = progress(userId)
	if not section then
		return nil
	end
	return {
		rebirths = section.rebirths,
		lifetimeCalories = section.lifetimeCalories,
		cakesEaten = section.cakesEaten,
		findsCollected = section.findsCollected,
		findKindsFound = ProgressService.CountFindKinds(userId),
		biggestBelly = section.biggestBelly,
		biome = ProgressService.BiomeFor(section.rebirths),
	}
end

return ProgressService
