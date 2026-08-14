--[[
	RewardGrantSubs — the game-wide grant point for reward descriptors (ADR-0002).

	A REWARD DESCRIPTOR is the shared loot grammar every feature speaks:
	  { kind = "calories", amount = n }
	  { kind = "gems", amount = n }      -- GemsMult (pets/passes) applies
	  { kind = "boost", boostId = s }    -- TreasureConfig.boosts
	  { kind = "egg", eggType = s }      -- registered by PetSubs (pet roll)

	Features (daily rewards, shop, codes, finds) PRODUCE descriptors;
	THIS module GRANTS them: the single R3-legal orchestration point that
	coordinates services and fires the follow-up remoteUpdates.

	Adding a kind: from your feature subscription's Start, call
	  RewardGrantSubs.Register("kind", function(player, reward, source)
	      ... coordinate services ...
	      return { kind = "kind", ... }  -- "granted" descriptor for the client
	  end)
	Registration order doesn't matter: Grant only runs at event time, after
	all subscriptions have started.

	READINESS (`RegisterReady`) — optional, and it exists for the MONEY path.
	`HasHandler` answers "is this kind deliverable in this place at all"; it
	cannot answer "can it be delivered to THIS player RIGHT NOW". A handler that
	answers that question by returning nil is too late: ShopSubs.grantProduct has
	already committed the receipt, so the player pays and gets nothing (`burn`
	against a player with no stomach state was exactly that hole). A readiness
	predicate runs inside `grantableList`, i.e. BEFORE the first grant and before
	the gem path spends anything, so a "not yet" becomes NotProcessedYet (Roblox
	re-delivers) or a refusal that never charges. Return `false, reason` to defer.
	Kinds with no predicate are always ready — nothing had to change to keep
	working.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))

-- Resolved from the subscriptions registry in Start. COMMON, so present in both
-- places — still nil-tolerant, per the registry pattern (ADR-0014).
local BoostSubs

local SCOPE = "RewardGrantSubs"

local RewardGrantSubs = {}

local handlers: { [string]: (Player, { [string]: any }, string?) -> { [string]: any }? } = {}
local ready: { [string]: (Player, { [string]: any }) -> (boolean, string?) } = {}

--API
-- Registers a grant handler for a descriptor kind. Handler returns a
-- "granted" descriptor (echoed to the client for celebration UI) or nil.
function RewardGrantSubs.Register(kind: string, handler)
	if handlers[kind] ~= nil then
		Log.Warn(SCOPE, `Handler for kind '{kind}' overwritten`)
	end
	handlers[kind] = handler
end

--API
-- Registers the "can this land RIGHT NOW" predicate for a kind (see the header).
-- `predicate(player, reward)` returns true, or false + a human reason. Optional:
-- a kind without one is always ready.
function RewardGrantSubs.RegisterReady(kind: string, predicate)
	if ready[kind] ~= nil then
		Log.Warn(SCOPE, `Readiness predicate for kind '{kind}' overwritten`)
	end
	ready[kind] = predicate
end

--API
-- Whether a kind can be granted. Features should check this BEFORE consuming
-- a claim, so a mistuned reward table never eats a player's claim.
function RewardGrantSubs.HasHandler(kind: string?): boolean
	return kind ~= nil and handlers[kind :: string] ~= nil
end

--API
-- Whether this descriptor can land for THIS player right now. Callers on a money
-- path must check it BEFORE committing (ShopSubs.grantableList does). A throwing
-- predicate answers "not ready" rather than taking the purchase path down (R8).
function RewardGrantSubs.IsReady(player: Player, reward: { [string]: any }?): (boolean, string?)
	if type(reward) ~= "table" or type(reward.kind) ~= "string" then
		return false, "malformed descriptor"
	end
	local predicate = ready[reward.kind]
	if predicate == nil then
		return true
	end
	local ok, result, reason = pcall(predicate, player, reward)
	if not ok then
		Log.Warn(SCOPE, `readiness predicate for '{reward.kind}' THREW — treating as not ready: {tostring(result)}`)
		return false, "readiness check failed"
	end
	if result then
		return true
	end
	return false, reason or `kind '{reward.kind}' is not ready for {player.Name}`
end

--API
-- Grants one reward descriptor to the player. Returns the granted descriptor
-- for the client toast, or nil (unknown kind / handler declined).
function RewardGrantSubs.Grant(player: Player, reward: { [string]: any }?, source: string?): { [string]: any }?
	if type(reward) ~= "table" or type(reward.kind) ~= "string" then
		return nil
	end
	local handler = handlers[reward.kind]
	if handler == nil then
		Log.Warn(SCOPE, `No handler for reward kind '{reward.kind}' (source: {source or "?"})`)
		return nil
	end
	return handler(player, reward, source)
end

function RewardGrantSubs.Start(data, services, subscriptions)
	BoostSubs = subscriptions.BoostSubs
	local AnalyticsSubs = subscriptions.AnalyticsSubs
	if AnalyticsSubs == nil then
		Log.Warn(SCOPE, "AnalyticsSubs missing — currency SOURCES will be absent from the economy dashboard")
	end
	local uCurrency = Net.Update("CurrencyUpdate")

	local function sendCurrency(player: Player)
		local calories = services.EconomyService.GetCalories(player.UserId)
		local gems = services.EconomyService.GetGems(player.UserId)
		if calories ~= nil and gems ~= nil then
			uCurrency:FireClient(player, { calories = calories, gems = gems })
		end
	end

	-- Every currency GRANT in the game passes through this module (ADR-0002),
	-- which makes it the one honest place to log economy sources: the amount
	-- recorded is what the handler actually added, after the gems/calorie
	-- multipliers, not the descriptor's advertised number. `source` is already
	-- the grant's provenance string ("shop-gems:key", "find", "daily") — it
	-- becomes the SKU, so the economy chart breaks down by where money is
	-- minted without a single extra event name.
	local function beatSource(player: Player, currency: string, amount: number, balance: number?, source: string?)
		if AnalyticsSubs == nil or amount <= 0 then
			return
		end
		local ok, err = pcall(
			AnalyticsSubs.Economy,
			player,
			"source",
			currency,
			amount,
			balance or 0,
			AnalyticsConfig.economy.transactions.gameplay,
			source
		)
		if not ok then
			Log.Once(SCOPE, "grant-analytics", `economy analytics beat FAILED (telemetry only, grant unaffected): {err}`)
		end
	end

	RewardGrantSubs.Register("calories", function(player: Player, reward, source: string?)
		local amount = math.floor(tonumber(reward.amount) or 0)
		if amount <= 0 then
			return nil
		end
		if services.EconomyService.AddCalories(player.UserId, amount) == nil then
			return nil -- profile not loaded
		end
		sendCurrency(player)
		beatSource(
			player,
			AnalyticsConfig.economy.currencies.calories,
			amount,
			services.EconomyService.GetCalories(player.UserId),
			source
		)
		return { kind = "calories", amount = amount }
	end)

	RewardGrantSubs.Register("gems", function(player: Player, reward, source: string?)
		local amount = math.floor(tonumber(reward.amount) or 0)
		if amount <= 0 then
			return nil
		end
		-- Gems earned in-game scale with the player's gems multiplier
		-- (pets, x2-gems pass) — paid gem PACKS bypass via rawAmount.
		if not reward.rawAmount then
			amount = math.max(1, math.floor(amount * services.StatsService.GemsMult(player.UserId)))
		end
		if services.EconomyService.AddGems(player.UserId, amount) == nil then
			return nil
		end
		-- The ONLY gem INCOME path in the game, which is what makes the lifetime
		-- counter behind the Top Gems board (features/leaderboards.md) exact with
		-- one line. The other AddGems call site is ShopSubs' refund of a failed
		-- gem purchase — deliberately NOT counted: the original spend never
		-- decremented this, so crediting the refund would mint lifetime gems.
		if services.ProgressService ~= nil then
			services.ProgressService.AddStat(player.UserId, "lifetimeGems", amount)
		else
			Log.Once(SCOPE, "no-progress-service", "ProgressService missing -- lifetime gems are NOT being counted")
		end
		sendCurrency(player)
		beatSource(
			player,
			AnalyticsConfig.economy.currencies.gems,
			amount,
			services.EconomyService.GetGems(player.UserId),
			source
		)
		return { kind = "gems", amount = amount }
	end)

	RewardGrantSubs.Register("boost", function(player: Player, reward, source: string?)
		if type(reward.boostId) ~= "string" then
			-- Malformed descriptor from a reward table (R8 — never silent).
			Log.Once(SCOPE, `boost-no-id-{source or "?"}`, `boost reward from '{source or "?"}' has no string boostId — dropped`)
			return nil
		end
		if not services.StatsService.GrantBoost(player.UserId, reward.boostId) then
			-- Unknown id or unloaded profile. Worth a warn either way: a shop
			-- product or reward table still pointing at a DELETED boost def sells
			-- normally and grants nothing at all, which is invisible otherwise.
			Log.Once(
				SCOPE,
				`boost-grant-failed-{reward.boostId}`,
				`boost '{reward.boostId}' (source: {source or "?"}) NOT granted — no such TreasureConfig.boosts def, or the profile isn't loaded`
			)
			return nil
		end
		-- Three of the four boosts feed stats that are PUSHED or APPLIED once
		-- (bite radius on the client, WalkSpeed on the Humanoid, capacity in the
		-- StomachUpdate payload), so they do nothing until something re-applies
		-- them. BoostSubs' sweep would get there within a tick, but a player who
		-- just spent 500 gems should not watch a second of nothing.
		if BoostSubs then
			BoostSubs.Apply(player)
		else
			Log.Once(
				SCOPE,
				"boostsubs-missing",
				`BoostSubs absent — boost '{reward.boostId}' granted, but bite radius / speed / capacity will not apply until something else refreshes them`
			)
		end
		return { kind = "boost", boostId = reward.boostId }
	end)

	-- "egg" is registered by PetSubs (owns the reveal channel).
end

return RewardGrantSubs
