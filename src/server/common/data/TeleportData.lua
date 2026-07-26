--[[
	TeleportData -- COMMON transient handoff state and tuning (never persisted).

	Data shape:
	  ["teleporting"]             : { [Player] = true }
	  ["release-timeout-seconds"] : number
	  ["next-release-check-at"]   : { [Player] = os.clock timestamp }
	  ["release-verification-tokens"] : { [Player] = opaque generation token }
	  ["recovery-timeout-seconds"] : number
	  ["recovery-failure-message"] : string
	  ["recovery-tokens"]         : { [Player] = opaque generation token }
	  ["handoff-targets"]         : { [Player] = PlaceId }
	  ["retry-attempts"]          : { [Player] = number }
	  ["retrying"]                : { [Player] = true }

	TeleportSubs owns the handoff logic. Keeping the re-entry guard here makes
	the in-flight state visible to the architecture instead of hiding game state
	inside a subscription module (R1).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("config"):WaitForChild("MatchConfig"))

local TeleportData = {
	["enabled"] = false,
	["teleporting"] = {} :: { [Player]: boolean },
	["release-timeout-seconds"] = MatchConfig.teleport.releaseTimeoutSeconds,
	["release-verification-interval-seconds"] = MatchConfig.teleport.releaseVerificationIntervalSeconds,
	["next-release-check-at"] = {} :: { [Player]: number },
	["release-verification-tokens"] = {} :: { [Player]: any },
	["recovery-timeout-seconds"] = MatchConfig.teleport.releaseTimeoutSeconds,
	["recovery-failure-message"] = "Couldn't restore your save after the move failed. Please rejoin.",
	["recovery-tokens"] = {} :: { [Player]: any },
	["handoff-targets"] = {} :: { [Player]: number },
	["retry-attempts"] = {} :: { [Player]: number },
	["retrying"] = {} :: { [Player]: boolean },
	["retry-attempt-limit"] = MatchConfig.teleport.retryAttemptLimit,
	["retry-delay-seconds"] = MatchConfig.teleport.retryDelaySeconds,
	["flood-retry-delay-seconds"] = MatchConfig.teleport.floodRetryDelaySeconds,
}

function TeleportData.Init()
	TeleportData["enabled"] = false
	table.clear(TeleportData["teleporting"])
	table.clear(TeleportData["next-release-check-at"])
	table.clear(TeleportData["release-verification-tokens"])
	table.clear(TeleportData["recovery-tokens"])
	table.clear(TeleportData["handoff-targets"])
	table.clear(TeleportData["retry-attempts"])
	table.clear(TeleportData["retrying"])
end

--API
function TeleportData.Clear(player: Player)
	TeleportData["teleporting"][player] = nil
	TeleportData["next-release-check-at"][player] = nil
	TeleportData["release-verification-tokens"][player] = nil
	TeleportData["recovery-tokens"][player] = nil
	TeleportData["handoff-targets"][player] = nil
	TeleportData["retry-attempts"][player] = nil
	TeleportData["retrying"][player] = nil
end

return TeleportData
