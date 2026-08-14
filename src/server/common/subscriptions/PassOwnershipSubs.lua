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

	⚠ ATTRIBUTES ARE ONLY ONE OF THE THREE WAYS A PERK REACHES A PLAYER, and the
	other two also have to be re-run on a mid-session purchase (2026-08-13 — the
	shop is now openable from the GAME HUD, so buying a pass mid-run is a normal
	act, not a lobby-only one):
	  READ per use   — CaloriesMult / GemsMult / EatRate / Capacity are read out
	                   of StatsService at the moment they are needed, so they
	                   need nothing. This is most of them.
	  PUSHED once    — `slots` rides PetsUpdate and `capacity` rides
	                   StomachUpdate. Both are snapshots: nothing re-sends them,
	                   so a VIP buyer kept seeing "3 / 3" squishy slots and an
	                   un-doubled belly bar until the next place transition.
	  APPLIED once   — WalkSpeed is written onto the Humanoid.
	So `ApplyPerkAttributes` re-pushes the pets payload and hands the
	applied/pushed family to `BoostSubs.Apply`, which already exists to re-derive
	exactly that set (bite mirror + RefreshBody + SendStomach) and is documented
	idempotent. Same routine runs on JOIN, where the ordering hazard is the same
	one the PetSubs note below describes: this hook YIELDS on its first
	UserOwnsGamePassAsync, so every other PushInitialState — BoostSubs' included —
	has already run against an EMPTY ownership cache.

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
-- Also COMMON. It owns the re-derivation of every value that is PUSHED or
-- APPLIED once rather than read per use (see the header) — R3: a subscription
-- reached through the registry, never a service→service call.
local BoostSubs

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

local function ownsAny(userId: number, ...): boolean
	local owned = ShopData.passOwnership[userId]
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

-- Perk attributes the CLIENT reads locally (auto-eat hold, HUD hints) — set in
-- BOTH places so the game client sees them.
local function writePerkAttributes(player: Player)
	local userId = player.UserId
	player:SetAttribute("AutoEat", ownsAny(userId, "autoeat", "vip"))
	player:SetAttribute("AutoGym", ownsAny(userId, "autogym", "vip"))
end

-- Re-send / re-apply the perk values that do NOT re-derive themselves (header).
-- Split out because BOTH entry points need it: the join fetch (which resolves
-- ownership after every other PushInitialState has already run) and a
-- mid-session purchase.
local function pushDerivedPerks(player: Player)
	-- `slots` is a gamepass perk carried on the PetsUpdate snapshot.
	if PetSubs then
		PetSubs.SendPets(player)
	else
		Log.Once(SCOPE, "petsubs-missing",
			"PetSubs is not in the subscriptions registry — pet SLOTS will stay at the "
				.. "pre-ownership value for this session (VIP/pass slot perks look unapplied).")
	end
	-- Humanoid WalkSpeed + the StomachUpdate capacity the HUD belly bar draws.
	-- BoostSubs is the single owner of that re-derivation (it exists because a
	-- timed boost moves the same three values) and its Apply is idempotent, so
	-- a pass purchase reuses it rather than growing a second copy here.
	if BoostSubs then
		BoostSubs.Apply(player)
	else
		Log.Once(SCOPE, "boostsubs-missing",
			"BoostSubs is not in the subscriptions registry — a pass that changes CAPACITY or "
				.. "WALK SPEED will not reach the player until the next place transition.")
	end
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
				-- ⚠ NEVER downgrade a runtime `true` back to `false`. This loop
				-- YIELDS (3 attempts × up to 4.5 s per throttled pass, 6 passes),
				-- and `ShopSubs.PromptGamePassPurchaseFinished` writes the truth
				-- into this SAME table via ShopService.SetPassOwned. A purchase that
				-- completes inside the fetch window is not visible to
				-- UserOwnsGamePassAsync yet (it is eventually consistent), so a
				-- blind write would turn the paid perk OFF for the rest of the
				-- session — attributes cleared, `slots`/capacity re-pushed un-perked
				-- and the shop cell flipped back to unowned. Buying a pass mid-run
				-- became routine on 2026-08-13 (the game HUD's Shop button), so this
				-- collision is no longer hypothetical. Nothing legitimately revokes
				-- a pass mid-session, which is why the asymmetry is safe.
				if owns or map[key] ~= true then
					map[key] = owns
				else
					Log.Info(SCOPE, `'{key}' was purchased for {player.Name} while the join fetch was in flight — keeping the owned flag`)
				end
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
	writePerkAttributes(player)
	-- Refresh the shop catalogue's `owned` flags now that ownership is known.
	if ShopSubs then
		ShopSubs.SendShop(player)
	end
	-- ...and everything that was PUSHED before ownership existed.
	-- PushInitialState hooks run synchronously in alphabetical order, and this one
	-- yields on its first UserOwnsGamePassAsync — so when PetSubs.SendPets runs,
	-- the ownership cache is still EMPTY and StatsService.PetSlots returns the base
	-- 3. Nothing re-pushed it, so a VIP buyer saw "3 / 3" on every join and
	-- "Equip Best" filled 3 of the 5 slots they paid 799 R$ for. The server-side
	-- limit was always correct; only the number the client was told was stale.
	-- The belly bar's `capacity` reached the client the same way and had the same
	-- staleness (x2 with `capacity2`/`vip`) — one routine now covers both.
	pushDerivedPerks(player)
end

--API
-- Re-apply every perk from the CURRENT ownership cache, without re-querying
-- Roblox: the client-read attributes, the pets payload (`slots`) and the
-- pushed/applied stats (capacity, walk speed). Called after a mid-session
-- gamepass purchase — see the header for why the attributes alone are not enough.
function PassOwnershipSubs.ApplyPerkAttributes(player: Player)
	if ShopData == nil then
		Log.Warn(SCOPE, `ApplyPerkAttributes({player.Name}) before Start ran — perks not applied`)
		return
	end
	writePerkAttributes(player)
	pushDerivedPerks(player)
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
	BoostSubs = subscriptions.BoostSubs -- COMMON; owns the capacity/walk-speed re-derivation

	Players.PlayerRemoving:Connect(function(player)
		-- Drop the runtime ownership cache so it doesn't grow over the server's life.
		ShopData.passOwnership[player.UserId] = nil
	end)
end

return PassOwnershipSubs
