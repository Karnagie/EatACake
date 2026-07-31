--[[
	PassOwnershipSubs — gamepass ownership resolution (COMMON: runs in BOTH the
	lobby and the game place).

	Gamepass PERKS (CaloriesMult, Capacity, AutoEat, AutoGym, PetSlots) are read
	from ShopData.passOwnership by StatsService. The ownership fetch must run on
	join in EVERY place, or a place would apply stale/empty perks.
	UserOwnsGamePassAsync is a cheap Roblox-side query (no DataStore).

	Writes ShopData.passOwnership directly (StatsService reads it directly, so
	the game needs no ShopService). ShopSubs (also COMMON since 2026-07-30) owns
	purchase + catalogue; here we re-push its catalogue once ownership resolves.

	`ApplyPerkAttributes` is exported because a gamepass bought MID-SESSION has
	to take effect without a rejoin: ShopSubs calls it from
	PromptGamePassPurchaseFinished. Before that, buying Auto-Eat flipped the
	shop cell to OWNED but never set the `AutoEat` attribute the client gates on,
	so a 399 R$ pass sat inert until the next place transition.

	R4: PlayerRemoving cleanup connected here; the join fetch is a
	PushInitialState hook (PlayerLifecycleSubs calls it after load + ClientReady).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "PassOwnership"

local PassOwnershipSubs = {}

local ShopData
-- COMMON, so present in both places — but resolved through the registry and
-- nil-tolerant, so a place that maps only one partition still boots (ADR-0014).
local ShopSubs
local PetSubs

-- A throttled UserOwnsGamePassAsync leaves the key UNSET, and every reader treats
-- absent as "does not own" — so one dropped call silently switches a paid perk off
-- for the WHOLE session (there is no periodic re-check). A full lobby teleports
-- MatchConfig.queue.maxPlayers players at once, which is 6 web calls each in one
-- burst, so the throttle is a normal event and not an edge case. Retry before
-- accepting a false.
local FETCH_ATTEMPTS = 3
local FETCH_BACKOFF = 1.5

local function ownsPassNow(userId: number, gamePassId: number): (boolean, boolean, string?)
	local lastErr: string? = nil
	for attempt = 1, FETCH_ATTEMPTS do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
		end)
		if ok then
			return true, owns == true, nil
		end
		lastErr = tostring(owns)
		if attempt < FETCH_ATTEMPTS then
			task.wait(FETCH_BACKOFF * attempt)
		end
	end
	return false, false, lastErr
end

local function applyOwnership(player: Player)
	local userId = player.UserId
	for key, def in pairs(ShopData.gamepasses) do
		if type(def.gamePassId) == "number" and def.gamePassId > 0 then
			local ok, owns, err = ownsPassNow(userId, def.gamePassId)
			if player.Parent ~= Players then
				return -- left mid-fetch; writing now would leak the runtime cache
			end
			if ok then
				local map = ShopData.passOwnership[userId]
				if map == nil then
					map = {}
					ShopData.passOwnership[userId] = map
				end
				map[key] = owns
			else
				-- R8: this is a PAID perk being switched off for the session, so it
				-- is a per-occurrence Warn, not a Log.Once — the count is the signal.
				Log.Warn(
					SCOPE,
					`UserOwnsGamePassAsync failed {FETCH_ATTEMPTS}x for '{key}' (user {userId}): {err}. `
						.. `The perk is OFF for this session — if this player owns it, they paid for nothing until they rejoin.`
				)
			end
		end
	end
	if player.Parent ~= Players then
		return
	end
	-- Perk attributes the CLIENT reads locally (auto-eat hold, HUD hints) — set
	-- in BOTH places so the game client sees them.
	local owned = ShopData.passOwnership[userId]
	local function ownsAny(...): boolean
		if owned == nil then
			return false
		end
		for _, key in ipairs({ ... }) do
			if owned[key] then
				return true
			end
		end
		return false
	end
	player:SetAttribute("AutoEat", ownsAny("autoeat", "vip"))
	player:SetAttribute("AutoGym", ownsAny("autogym", "vip"))
	-- Refresh the shop catalogue's `owned` flags now that ownership is known.
	if ShopSubs then
		ShopSubs.SendShop(player)
	end
	-- ...and the PETS payload, because `slots` is a gamepass perk too.
	-- PushInitialState hooks run synchronously in alphabetical order, and this one
	-- yields on its first UserOwnsGamePassAsync — so when PetSubs.SendPets runs,
	-- the ownership cache is still EMPTY and StatsService.PetSlots returns the base
	-- 3. Nothing re-pushed it, so a VIP buyer saw "3 / 3" on every join and
	-- "Equip Best" filled 3 of the 5 slots they paid 799 R$ for. The server-side
	-- limit was always correct; only the number the client was told was stale.
	if PetSubs then
		PetSubs.SendPets(player)
	else
		Log.Once(SCOPE, "petsubs-missing",
			"PetSubs is not in the subscriptions registry — pet SLOTS will stay at the "
				.. "pre-ownership value for this session (VIP/pass slot perks look unapplied).")
	end
end

--API
-- Re-derive the client-read perk attributes from the CURRENT ownership cache,
-- without re-querying Roblox. Called after a mid-session gamepass purchase.
function PassOwnershipSubs.ApplyPerkAttributes(player: Player)
	if ShopData == nil then
		Log.Warn(SCOPE, `ApplyPerkAttributes({player.Name}) before Start ran — perks not applied`)
		return
	end
	local owned = ShopData.passOwnership[player.UserId]
	local function ownsAny(...): boolean
		if owned == nil then
			return false
		end
		for _, key in ipairs({ ... }) do
			if owned[key] then
				return true
			end
		end
		return false
	end
	player:SetAttribute("AutoEat", ownsAny("autoeat", "vip"))
	player:SetAttribute("AutoGym", ownsAny("autogym", "vip"))
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function PassOwnershipSubs.PushInitialState(player: Player)
	-- UserOwnsGamePassAsync YIELDS per pass — never block the join push chain.
	task.spawn(applyOwnership, player)
end

function PassOwnershipSubs.Start(data, services, subscriptions)
	ShopData = data.ShopData
	ShopSubs = subscriptions.ShopSubs -- COMMON since 2026-07-30; present in both places
	PetSubs = subscriptions.PetSubs -- COMMON; owns the `slots` push (see applyOwnership)

	Players.PlayerRemoving:Connect(function(player)
		-- Drop the runtime ownership cache so it doesn't grow over the server's life.
		ShopData.passOwnership[player.UserId] = nil
	end)
end

return PassOwnershipSubs
