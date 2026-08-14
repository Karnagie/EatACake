--[[
	Profile section: cakes — which cake the player has CHOSEN in the lobby
	(catalogue: src/shared/config/CakeSelectConfig.lua).
	  selected — a CakeSelectConfig id ("cake-classic" | "cake-rainbow"); the
	             card the lobby grid renders as picked.

	It lives in the COMMON partition, so the lobby and the game place both load
	it and the choice is not run-scoped — it survives the teleport and rejoins.

	⚠ There is deliberately NO `unlocked` set here. Entitlement is DERIVED at
	push time from `progress.cakesEaten` against the cake's `unlockRule`, which
	keeps ONE source of truth and means existing accounts need no backfill: a
	player who has already eaten a cake is entitled the moment this ships.
	A mirrored set would be a second truth free to drift — and `sanitize` could
	not maintain it anyway, because PersistenceService hands each section ONLY
	its own slice (this file can never read `progress`). A stored selection that
	is no longer entitled is therefore corrected where entitlement IS known (the
	cake-select subscription), never here.

	P3 N/A — cake ids are strings end to end (config keys, stored value, remote
	payloads); nothing in this section is number-keyed, so `intKeySets` is empty.
	P2 N/A — this is a brand-new section: PersistenceService materialises a
	missing section from `defaults` on load, so existing profiles need neither a
	version bump nor a migration anywhere; `migrations` is empty.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local CakeSelectConfig = require(Shared:WaitForChild("config"):WaitForChild("CakeSelectConfig"))

local SCOPE = "ProfileSchema"

return {
	key = "cakes",
	version = 1,
	defaults = {
		-- Not a second hardcoded "cake-classic": the catalogue owns what a fresh
		-- profile starts on, and sanitize coerces to that exact same value.
		selected = CakeSelectConfig.defaultId,
	},
	intKeySets = {},
	migrations = {},
	sanitize = function(section)
		-- Reconcile has already filled `selected`, so a value that is not a
		-- catalogue key means a hand-edited/corrupted profile or a cake retired
		-- from the catalogue. Either way the only safe answer is the default —
		-- and it is worth a line in the console, since silently resetting a
		-- player's choice is exactly the kind of quiet bug R8 exists to prevent.
		if type(section.selected) ~= "string" or CakeSelectConfig.cakes[section.selected] == nil then
			Log.Once(
				SCOPE,
				`cakes-unknown-selected-{tostring(section.selected)}`,
				`section 'cakes': stored selection '{tostring(section.selected)}' is not in CakeSelectConfig.cakes — reset to '{CakeSelectConfig.defaultId}'`
			)
			section.selected = CakeSelectConfig.defaultId
		end
		return section
	end,
}
