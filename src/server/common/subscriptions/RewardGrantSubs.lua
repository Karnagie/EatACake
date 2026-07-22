--[[
	RewardGrantSubs — the game-wide grant point for reward descriptors (ADR-0002).

	A REWARD DESCRIPTOR is the shared loot grammar every feature speaks:
	  { kind = "calories", amount = n }
	  { kind = "gems", amount = n }      -- GemsMult (pets/passes) applies
	  { kind = "boost", boostId = s }    -- TreasureConfig.boosts
	  { kind = "egg", eggType = s }      -- registered by PetSubs (pet roll)

	Features (daily rewards, shop, codes, finds, quests) PRODUCE descriptors;
	THIS module GRANTS them: the single R3-legal orchestration point that
	coordinates services and fires the follow-up remoteUpdates.

	Adding a kind: from your feature subscription's Start, call
	  RewardGrantSubs.Register("kind", function(player, reward, source)
	      ... coordinate services ...
	      return { kind = "kind", ... }  -- "granted" descriptor for the client
	  end)
	Registration order doesn't matter: Grant only runs at event time, after
	all subscriptions have started.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local RewardGrantSubs = {}

local handlers: { [string]: (Player, { [string]: any }, string?) -> { [string]: any }? } = {}

--API
-- Registers a grant handler for a descriptor kind. Handler returns a
-- "granted" descriptor (echoed to the client for celebration UI) or nil.
function RewardGrantSubs.Register(kind: string, handler)
	if handlers[kind] ~= nil then
		warn(`[RewardGrantSubs] Handler for kind '{kind}' overwritten`)
	end
	handlers[kind] = handler
end

--API
-- Whether a kind can be granted. Features should check this BEFORE consuming
-- a claim, so a mistuned reward table never eats a player's claim.
function RewardGrantSubs.HasHandler(kind: string?): boolean
	return kind ~= nil and handlers[kind :: string] ~= nil
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
		warn(`[RewardGrantSubs] No handler for reward kind '{reward.kind}' (source: {source or "?"})`)
		return nil
	end
	return handler(player, reward, source)
end

function RewardGrantSubs.Start(data, services)
	local uCurrency = Net.Update("CurrencyUpdate")

	local function sendCurrency(player: Player)
		local calories = services.EconomyService.GetCalories(player.UserId)
		local gems = services.EconomyService.GetGems(player.UserId)
		if calories ~= nil and gems ~= nil then
			uCurrency:FireClient(player, { calories = calories, gems = gems })
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
		sendCurrency(player)
		return { kind = "gems", amount = amount }
	end)

	RewardGrantSubs.Register("boost", function(player: Player, reward, source: string?)
		if type(reward.boostId) ~= "string" then
			return nil
		end
		if not services.StatsService.GrantBoost(player.UserId, reward.boostId) then
			return nil -- unknown boost id or profile not loaded
		end
		return { kind = "boost", boostId = reward.boostId }
	end)

	-- "egg" is registered by PetSubs (owns the reveal channel).
end

return RewardGrantSubs
