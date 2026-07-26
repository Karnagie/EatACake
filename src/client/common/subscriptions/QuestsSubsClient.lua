--[[
	QuestsSubsClient — daily quests consumer (R4, GDD §12.2): QuestsUpdate
	feeds the AppRoot quests panel; claim clicks flow back via ClaimQuest.

	The completion cue is driven by a quest turning `claimed` in the UPDATE, not
	by the button — a rejected or duplicate claim (server resync) must stay
	silent, and a spam-clicker must not earn N jingles for one grant. Same
	contract as RewardsSubsClient (docs/features/audio.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local QuestsSubsClient = {}

function QuestsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local SoundPool = modules.SoundPool
	local rClaim = Net.Remote("ClaimQuest")

	-- nil until the first push: the join snapshot lists already-claimed quests
	-- and must not fire a jingle per quest.
	local claimed: { [string]: boolean }? = nil

	Net.Update("QuestsUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.quests) ~= "table" then
			return
		end
		AppRoot.Set({ quests = payload.quests })
		local seen, newlyClaimed = {}, false
		for _, quest in ipairs(payload.quests) do
			if type(quest) == "table" and type(quest.id) == "string" and quest.claimed == true then
				seen[quest.id] = true
				if claimed ~= nil and not claimed[quest.id] then
					newlyClaimed = true
				end
			end
		end
		claimed = seen
		if newlyClaimed then
			SoundPool.Play("questDone")
		end
	end)

	AppRoot.SetCallbacks({
		onClaimQuest = function(questId: string)
			rClaim:FireServer(questId)
		end,
	})
end

return QuestsSubsClient
