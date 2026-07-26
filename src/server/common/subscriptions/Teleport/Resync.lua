--[[
	Resync -- restores every available client domain after a failed teleport.

	A failed handoff releases and then re-acquires the player's profile. Once the
	new session is live, subscription-owned initial-state hooks rebuild the
	client's authoritative view before movement and gameplay input are unlocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "Teleport"

local Resync = {}

--API
function Resync.Push(player: Player, subscriptions)
	local names = {}
	for name, subscription in pairs(subscriptions or {}) do
		if type(subscription) == "table" and type(subscription.PushInitialState) == "function" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	local pushed = 0
	for _, name in ipairs(names) do
		local ok, err = pcall(subscriptions[name].PushInitialState, player)
		if ok then
			pushed += 1
		else
			Log.Warn(SCOPE, `{name}.PushInitialState FAILED during recovery resync for {player.Name}: {err}`)
		end
	end
	Log.Info(SCOPE, `recovery resync pushed {pushed}/{#names} domain(s) to {player.Name}`)
end

return Resync
