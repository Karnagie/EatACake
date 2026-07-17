--[[
	QuestsSubsClient — daily quests consumer (R4, GDD §12.2): QuestsUpdate
	feeds the AppRoot quests panel; claim clicks flow back via ClaimQuest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local QuestsSubsClient = {}

function QuestsSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	local rClaim = Net.Remote("ClaimQuest")

	Net.Update("QuestsUpdate").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.quests) == "table" then
			AppRoot.Set({ quests = payload.quests })
		end
	end)

	AppRoot.SetCallbacks({
		onClaimQuest = function(questId: string)
			rClaim:FireServer(questId)
		end,
	})
end

return QuestsSubsClient
