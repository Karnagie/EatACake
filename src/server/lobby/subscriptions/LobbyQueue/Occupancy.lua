--[[
	LobbyQueue.Occupancy -- internal GroupToucher overlap resolution and scan
	projection. LobbyQueueSubs owns the actual Touched/Heartbeat connections.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Occupancy = {}
local queueData
local queueService
local Protocol
local Launch

function Occupancy.Init(data, service, protocol, launch)
	queueData = data
	queueService = service
	Protocol = protocol
	Launch = launch
end

function Occupancy.PlayerFromPart(part: Instance): Player?
	local ancestor = part
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			if player then
				return player
			end
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function occupantsFor(toucher: BasePart, queueId: number): { [number]: Player }?
	if toucher.Parent == nil then
		Log.Once("LobbyQueueSubs", `detached-toucher-{queueId}`, `{toucher.Name} occupancy scan skipped: toucher detached`)
		return nil
	end
	local ok, partsOrError = pcall(workspace.GetPartsInPart, workspace, toucher)
	if not ok then
		Log.Once("LobbyQueueSubs", `parts-scan-{queueId}`, `GetPartsInPart failed for {toucher:GetFullName()}: {partsOrError}`)
		return nil
	end
	local occupants = {}
	for _, part in ipairs(partsOrError) do
		local player = Occupancy.PlayerFromPart(part)
		if player then
			occupants[player.UserId] = player
		end
	end
	return occupants
end

function Occupancy.Scan(now: number)
	for _, queue in ipairs(queueData.queues) do
		local occupants = occupantsFor(queue.toucher, queue.id)
		if occupants then
			Protocol.EmitEffects(queueService.Reconcile(queue.id, occupants, now))
		end
	end
	for _, launch in ipairs(queueService.Advance(now)) do
		task.spawn(Launch.Perform, launch)
	end
end

return Occupancy
