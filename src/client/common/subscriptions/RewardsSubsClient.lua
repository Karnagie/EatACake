--[[
	RewardsSubsClient — daily reward consumer (R4).

	DailyRewardUpdate arrives with an ARRAY node list (RemoteEvents stringify
	integer dict keys) — re-keyed to a dict here, then pushed into AppRoot
	state; card building happens in LocalRewardsService.

	The claim callback fires the remote; the server resyncs on invalid claims,
	so no client-side validation beyond the card's own state gate.

	CELEBRATION HOOK: payload.granted = { kind, amount, day } — show a
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
end

return RewardsSubsClient
