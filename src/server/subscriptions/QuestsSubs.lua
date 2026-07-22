--[[
	QuestsSubs — daily quests orchestration (R4, GDD §12.2): ClaimQuest
	remote, QuestsUpdate pushes. Rewards go through RewardGrantSubs
	(handler checked BEFORE consuming the claim — ADR-0002 rule).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Log = require(Shared:WaitForChild("Log"))

local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "QuestsSubs"

local QuestsSubs = {}

local services_
local uQuests

--API
function QuestsSubs.SendQuests(player: Player)
	if uQuests == nil then
		Log.Warn(SCOPE, `SendQuests({player.Name}) before Start ran — push dropped`)
		return
	end
	local rows = services_.QuestService.Summary(player.UserId)
	if rows == nil then
		Log.Warn(SCOPE, `SendQuests({player.Name}): profile not loaded — push dropped`)
		return
	end
	uQuests:FireClient(player, { quests = rows })
end

--API
-- Join-state hook: PlayerLifecycleSubs calls this after profile load + ClientReady.
function QuestsSubs.PushInitialState(player: Player)
	QuestsSubs.SendQuests(player)
end

function QuestsSubs.Start(data, services)
	services_ = services
	uQuests = Net.Update("QuestsUpdate")

	Net.Remote("ClaimQuest").OnServerEvent:Connect(function(player, questId)
		if type(questId) ~= "string" then
			return
		end
		local userId = player.UserId
		if not services.PersistenceService.IsLoaded(userId) then
			-- Joining: profile not ready (R8 — never silent, mirrors CakeSubs).
			Log.Once(SCOPE, `claim-preload-{userId}`, `{player.Name}: ClaimQuest before profile load — dropped until loaded`)
			return
		end
		-- Peek the reward kind BEFORE consuming (never eat a claim on a
		-- mistuned reward table).
		local rows = services.QuestService.Summary(userId)
		if not rows then
			return
		end
		for _, row in ipairs(rows) do
			if row.id == questId and not RewardGrantSubs.HasHandler(row.reward.kind) then
				Log.Warn(SCOPE, `quest '{questId}' reward kind '{row.reward.kind}' has no handler — claim refused`)
				return
			end
		end
		local reward, reason = services.QuestService.TryClaim(userId, questId)
		if reward then
			RewardGrantSubs.Grant(player, reward, `quest:{questId}`)
		else
			Log.Info(SCOPE, `{player.Name}: claim({questId}) refused — {reason}`)
		end
		QuestsSubs.SendQuests(player) -- resync either way
	end)
end

return QuestsSubs
