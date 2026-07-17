--[[
	RewardsSubsClient — daily + time reward consumers (R4).

	DailyRewardUpdate / TimeRewardUpdate arrive with ARRAY node/claimed lists
	(RemoteEvents stringify integer dict keys) — re-keyed to dicts here, then
	pushed into AppRoot state; card building happens in LocalRewardsService.

	Claim callbacks fire the remotes; the server resyncs on invalid claims,
	so no client-side validation beyond the card's own state gate.

	CELEBRATION HOOK: payload.granted = { kind, amount, day/index } — show a
	toast/particles here when the game adds an FX layer (locale keys
	toast-claimed / toast-claimed-gold are reserved).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local RewardsSubsClient = {}

function RewardsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local rClaimDaily = Net.Remote("ClaimDailyReward")
	local rClaimTime = Net.Remote("ClaimTimeReward")

	AppRoot.SetCallbacks({
		onClaimDaily = function(_day)
			rClaimDaily:FireServer()
		end,
		onClaimTime = function(index)
			if type(index) == "number" then
				rClaimTime:FireServer(index)
			end
		end,
	})

	Net.Update("DailyRewardUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local nodes = {}
		if type(payload.nodes) == "table" then
			for _, desc in ipairs(payload.nodes) do
				if type(desc) == "table" and type(desc.day) == "number" then
					nodes[desc.day] = desc
				end
			end
		end
		AppRoot.Set({
			daily = {
				day = payload.day or 1,
				claimable = payload.claimable == true,
				nodes = nodes,
			},
		})
	end)

	Net.Update("TimeRewardUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local nodes = {}
		if type(payload.nodes) == "table" then
			for _, desc in ipairs(payload.nodes) do
				if type(desc) == "table" and type(desc.index) == "number" then
					nodes[desc.index] = desc
				end
			end
		end
		local claimed = {}
		if type(payload.claimed) == "table" then
			for _, index in ipairs(payload.claimed) do
				if type(index) == "number" then
					claimed[index] = true
				end
			end
		end
		AppRoot.Set({
			time = {
				secondsToday = payload.secondsToday or 0,
				receivedClock = os.clock(),
				claimed = claimed,
				nodes = nodes,
			},
		})
	end)
end

return RewardsSubsClient
