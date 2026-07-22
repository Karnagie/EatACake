--[[
	PassOwnershipSubs — gamepass ownership resolution (COMMON: runs in BOTH the
	lobby and the game place).

	Gamepass PERKS (CaloriesMult, Capacity, AutoEat, AutoGym, PetSlots) are read
	from ShopData.passOwnership by StatsService — which runs in the GAME place.
	But the shop UI + ProcessReceipt live in the LOBBY (ShopSubs). So the
	ownership fetch can't live in ShopSubs; it must run on join in EVERY place,
	or the game place would apply stale/empty perks. UserOwnsGamePassAsync is a
	cheap Roblox-side query (no DataStore).

	Writes ShopData.passOwnership directly (StatsService reads it directly, so
	the game needs no ShopService). The LOBBY's ShopSubs still owns purchase +
	catalogue; here we re-push its catalogue once ownership resolves.

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
local ShopSubs -- optional (LOBBY only): re-push the catalogue after the async fetch

local function applyOwnership(player: Player)
	local userId = player.UserId
	for key, def in pairs(ShopData.gamepasses) do
		if type(def.gamePassId) == "number" and def.gamePassId > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(userId, def.gamePassId)
			end)
			if player.Parent ~= Players then
				return -- left mid-fetch; writing now would leak the runtime cache
			end
			if ok then
				local map = ShopData.passOwnership[userId]
				if map == nil then
					map = {}
					ShopData.passOwnership[userId] = map
				end
				map[key] = owns == true
			else
				Log.Warn(SCOPE, `UserOwnsGamePassAsync failed for '{key}': {owns}`)
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
	-- LOBBY: refresh the shop catalogue's `owned` flags now that ownership is known.
	if ShopSubs then
		ShopSubs.SendShop(player)
	end
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function PassOwnershipSubs.PushInitialState(player: Player)
	-- UserOwnsGamePassAsync YIELDS per pass — never block the join push chain.
	task.spawn(applyOwnership, player)
end

function PassOwnershipSubs.Start(data, services, subscriptions)
	ShopData = data.ShopData
	ShopSubs = subscriptions.ShopSubs -- nil in the game place (no shop UI there)

	Players.PlayerRemoving:Connect(function(player)
		-- Drop the runtime ownership cache so it doesn't grow over the server's life.
		ShopData.passOwnership[player.UserId] = nil
	end)
end

return PassOwnershipSubs
