--[[
	RewardsSubsClient — daily + time reward consumers (R4).

	DailyRewardUpdate / TimeRewardUpdate arrive with ARRAY node/claimed lists
	(RemoteEvents stringify integer dict keys) — re-keyed to dicts here, then
	pushed into AppRoot state; card building happens in LocalRewardsService.

	Claim callbacks fire the remotes; the server resyncs on invalid claims,
	so no client-side validation beyond the card's own state gate.

	CELEBRATION HOOK: payload.granted = { kind, amount, day/index } — show a
	toast/particles here when the game adds an FX layer (locale keys
	toast-claimed / toast-claimed-gold are reserved). The SOUND half of that
	hook is wired: a grant plays the reward cue (audio.md). It is driven by
	`granted` on the UPDATE, not by the button, so a rejected claim stays
	silent — the server resyncs those without a grant.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local RewardsSubsClient = {}

function RewardsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rClaimDaily = Net.Remote("ClaimDailyReward")
	local rClaimTime = Net.Remote("ClaimTimeReward")

	-- A gem/boost grant is a small win; an egg is the big one.
	local function celebrate(granted)
		if type(granted) ~= "table" then
			return
		end
		SoundPool.Play(if granted.kind == "egg" then "rewardBig" else "reward")
	end

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
		celebrate(payload.granted) -- AFTER the push: a cue must never eat a state update
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
		celebrate(payload.granted) -- AFTER the push (see the daily handler)
	end)
end

return RewardsSubsClient
