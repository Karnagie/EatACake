--[[
	LobbyQueueService -- server-authoritative queue-logic facade (R2).

	Internal helpers split setup/presentation, membership/reconciliation, and
	countdown/launch lifecycle into independently auditable responsibilities.
	They all mutate only the injected LobbyQueueData module and subscribe to no
	events. LobbyQueueSubs remains the sole queue wiring owner (R4).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Helpers = script.Parent:WaitForChild("LobbyQueue")
local Core = require(Helpers:WaitForChild("Core"))
local Membership = require(Helpers:WaitForChild("Membership"))
local Lifecycle = require(Helpers:WaitForChild("Lifecycle"))

local LobbyQueueService = {}

function LobbyQueueService.Init(data)
	local queueData = data.LobbyQueueData
	if queueData == nil then
		Log.Warn("LobbyQueue", "LobbyQueueData missing -- queue logic is disabled")
		return
	end
	Core.Init(queueData)
	Membership.Init(queueData)
	Lifecycle.Init(queueData)
end

--API
LobbyQueueService.SetupQueues = Core.SetupQueues
--API
LobbyQueueService.GetQueueForPlayer = Membership.GetQueueForPlayer
--API
LobbyQueueService.GetOpenPayload = Membership.GetOpenPayload
--API
LobbyQueueService.GetSelectorOwners = Membership.GetSelectorOwners
--API
LobbyQueueService.Admit = Membership.Admit
--API
LobbyQueueService.Remove = Membership.Remove
--API
LobbyQueueService.ForgetPlayer = Membership.ForgetPlayer
--API
LobbyQueueService.Reconcile = Membership.Reconcile
--API
LobbyQueueService.ValidateLeaderSession = Lifecycle.ValidateLeaderSession
--API
LobbyQueueService.Configure = Lifecycle.Configure
--API
LobbyQueueService.Snapshot = Lifecycle.Snapshot
--API
LobbyQueueService.Advance = Lifecycle.Advance
--API
LobbyQueueService.FailLaunch = Lifecycle.FailLaunch
--API
LobbyQueueService.CompleteLaunch = Lifecycle.CompleteLaunch
--API
LobbyQueueService.Reset = Lifecycle.Reset

return LobbyQueueService
