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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "ProgressService"

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
		return
	end
	if section ~= nil then
		-- A typo'd key, or a field reconcile did not fill, silently stops
		-- counting a stat that something downstream depends on — `lifetimeGems`
		-- feeds a public leaderboard (R8: never return silently from a failure).
		Log.Once(SCOPE, `unknown-stat-{tostring(key)}`, `progress.{tostring(key)} is not a number -- that lifetime stat is NOT being counted`)
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
-- Lifetime cakes FINISHED — the counter CakeCycleSubs increments on a boss win.
-- Exposed as the NUMBER, not only as a flag, because the lobby cake catalogue
-- compares it against each cake's own `unlockCakesEaten` threshold
-- (features/cake-select.md); a bare flag would silently unlock a cake whose
-- threshold was later raised.
function ProgressService.CakesEaten(userId: number): number
	local section = progress(userId)
	if section == nil or type(section.cakesEaten) ~= "number" then
		return 0
	end
	return section.cakesEaten
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
-- Records how long a finished cake took, in MILLISECONDS. Keeps the BEST
-- (smallest) value ever, so it is safe to call on every clear; 0 in the profile
-- means "never finished a cake" and is what the leaderboard treats as no score
-- (docs/features/leaderboards.md).
-- Returns true only when this run became the player's new record.
function ProgressService.RecordCakeTime(userId: number, millis: number): boolean
	local section = progress(userId)
	if section == nil or type(millis) ~= "number" or millis ~= millis or millis <= 0 or millis == math.huge then
		return false
	end
	local value = math.floor(millis)
	local best = section.bestCakeMillis
	if type(best) ~= "number" or best <= 0 or value < best then
		section.bestCakeMillis = value
		return true
	end
	return false
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
-- ⚠ The three GLOBAL leaderboards read their value straight off this table by
-- the `statKey` in `GlobalLeaderboardData.boards` — renaming a field here
-- silently empties a board (docs/features/leaderboards.md).
function ProgressService.Summary(userId: number)
	local section = progress(userId)
	if not section then
		return nil
	end
	return {
		rebirths = section.rebirths,
		lifetimeCalories = section.lifetimeCalories,
		lifetimeGems = section.lifetimeGems,
		cakesEaten = section.cakesEaten,
		bestCakeMillis = section.bestCakeMillis,
		findsCollected = section.findsCollected,
		findKindsFound = ProgressService.CountFindKinds(userId),
		biggestBelly = section.biggestBelly,
		biome = ProgressService.BiomeFor(section.rebirths),
	}
end

return ProgressService
