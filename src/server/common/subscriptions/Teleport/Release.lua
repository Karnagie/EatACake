--[[
	Teleport.Release -- bounded group release-verification helper.

	It owns no event subscriptions and stores no state. ProfileStore read-back may
	retry beyond the handoff deadline, so verification runs in nonce-gated worker
	threads while this loop keeps the caller's timeout live.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local Release = {}

--API
function Release.Wait(group: { Player }, teleportData, persistence): string
	local departed = false
	local timeoutSeconds = teleportData["release-timeout-seconds"]
	local verificationInterval = teleportData["release-verification-interval-seconds"]
	local deadline = os.clock() + timeoutSeconds
	while true do
		local allReleased = true
		for _, player in ipairs(group) do
			if player.Parent ~= Players then
				-- PlayerRemoving clears this user's local release proof. Ignore only
				-- that departed member; every present member still has to prove its
				-- ending save before the caller may recover the cancelled group.
				departed = true
				continue
			elseif not persistence.IsReleased(player.UserId) then
				allReleased = false
				local now = os.clock()
				if now >= (teleportData["next-release-check-at"][player] or 0)
					and teleportData["release-verification-tokens"][player] == nil
				then
					teleportData["next-release-check-at"][player] = now + verificationInterval
					local verifyPlayer = player
					local verifyToken = {}
					teleportData["release-verification-tokens"][verifyPlayer] = verifyToken
					task.spawn(function()
						local ok, verifyOrError = pcall(persistence.VerifyReleased, verifyPlayer.UserId)
						if teleportData["release-verification-tokens"][verifyPlayer] == verifyToken then
							teleportData["release-verification-tokens"][verifyPlayer] = nil
						end
						if not ok then
							Log.Warn("Teleport", `release verification FAILED for {verifyPlayer.Name}: {verifyOrError}`)
						end
					end)
				end
			end
		end
		if allReleased then
			return if departed then "departed" else "released"
		end
		if os.clock() > deadline then
			return "timeout"
		end
		task.wait(0.1)
	end
end

return Release
