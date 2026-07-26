--[[
	LobbyQueueData -- runtime state and shared configuration for lobby queues (R1).

	Configuration references:
	  match-config, queue-config, place-config -- shared lobby/game contract

	Runtime shape:
	  queues                 -- ordered queue records (left-to-right by pivot X)
	  queue-by-id            -- [queue id] = queue record
	  player-queue-by-user-id -- [userId] = queue id for admitted members
	  bound-map              -- the currently wired Workspace.LobbyMap clone
	  connections            -- subscription-owned global RBXScriptConnections
	  queue-connections      -- subscription-owned .Touched connections
	  request-remote/update-remote -- resolved networking instances
	  last-scan-at           -- occupancy/countdown scan clock
	  next-session-serial    -- monotonic selector-session discriminator
	  next-launch-serial     -- monotonic launch token across map rebinds
	  request-last-at-by-user-id -- per-player remote abuse throttle clocks

	Each queue record owns its authored instances, admitted member array/set,
	leader/config/countdown/launch state, exit-grace clocks, and manual-leave
	blocking state. No queue runtime state lives in a service.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("config")

local MatchConfig = require(Config:WaitForChild("MatchConfig"))
local PlaceConfig = require(Config:WaitForChild("PlaceConfig"))

local LobbyQueueData = {}

LobbyQueueData["match-config"] = MatchConfig
LobbyQueueData["queue-config"] = MatchConfig.queue
LobbyQueueData["place-config"] = PlaceConfig

LobbyQueueData.queues = {}
LobbyQueueData["queue-by-id"] = {}
LobbyQueueData["player-queue-by-user-id"] = {}
LobbyQueueData["bound-map"] = nil
LobbyQueueData.connections = {}
LobbyQueueData["queue-connections"] = {}
LobbyQueueData["request-remote"] = nil
LobbyQueueData["update-remote"] = nil
LobbyQueueData["last-scan-at"] = 0
LobbyQueueData["next-session-serial"] = 0
LobbyQueueData["next-launch-serial"] = 0
LobbyQueueData["request-last-at-by-user-id"] = {}

function LobbyQueueData.Init()
	LobbyQueueData.queues = {}
	LobbyQueueData["queue-by-id"] = {}
	LobbyQueueData["player-queue-by-user-id"] = {}
	LobbyQueueData["bound-map"] = nil
	LobbyQueueData.connections = {}
	LobbyQueueData["queue-connections"] = {}
	LobbyQueueData["request-remote"] = nil
	LobbyQueueData["update-remote"] = nil
	LobbyQueueData["last-scan-at"] = 0
	LobbyQueueData["next-session-serial"] = 0
	LobbyQueueData["next-launch-serial"] = 0
	LobbyQueueData["request-last-at-by-user-id"] = {}
end

return LobbyQueueData
