--[[
	Net
	Central resolver for networking instances living under ReplicatedStorage.Shared.
	  - remotes/        RemoteEvents  (client -> server)
	  - remoteUpdates/  RemoteEvents  (server -> client)

	Usage:
		local Net = require(ReplicatedStorage.Shared.Net)
		Net.Remote("ClaimDailyReward"):FireServer(...)
		Net.Update("GoldUpdate").OnClientEvent:Connect(...)

	Remotes are declared as .model.json files ({"className": "RemoteEvent"})
	in src/shared/remotes/ and src/shared/remoteUpdates/.
	⚠ RemoteEvent serialization stringifies numeric table keys — send arrays,
	or re-normalize on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Net = {}

local remotesFolder = Shared:WaitForChild("remotes")
local updatesFolder = Shared:WaitForChild("remoteUpdates")

Net.Remotes = remotesFolder
Net.Updates = updatesFolder

--API
function Net.Remote(name: string): RemoteEvent
	return remotesFolder:WaitForChild(name)
end

--API
function Net.Update(name: string): RemoteEvent
	return updatesFolder:WaitForChild(name)
end

return Net
