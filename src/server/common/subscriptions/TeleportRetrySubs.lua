--[[
	TeleportRetrySubs -- asynchronous TeleportInitFailed recovery (R4).

	Roblox returns the exact destination TeleportOptions with the failure event.
	Retrying those options is essential for a member of a partially teleported
	party to reach the same reserved server. The profile remains safely released
	during bounded retries and is re-acquired only after exhaustion/invalid failure.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "TeleportRetry"

local TeleportRetrySubs = {}

function TeleportRetrySubs.Start(data, _services, subscriptions)
	local teleportData = data.TeleportData
	local TeleportSubs = subscriptions and subscriptions.TeleportSubs
	if teleportData == nil then
		Log.Warn(SCOPE, "TeleportData missing -- failed teleports cannot retry")
		return
	end
	if TeleportSubs == nil or type(TeleportSubs.RecoverPlayer) ~= "function" then
		Log.Warn(SCOPE, "TeleportSubs.RecoverPlayer missing -- failed teleports cannot recover")
		return
	end

	local function recover(player: Player, reason: string)
		Log.Warn(SCOPE, `{player.Name}: {reason}; scheduling bounded source-profile recovery`)
		local ok, recoveredOrError = pcall(TeleportSubs.RecoverPlayer, player)
		if not ok then
			Log.Warn(SCOPE, `RecoverPlayer FAILED for {player.Name}: {recoveredOrError}`)
		elseif recoveredOrError == false then
			Log.Info(SCOPE, `recovery skipped for {player.Name}: handoff already ended`)
		end
	end

	local function retryFailedTeleport(
		player: Player,
		teleportResult: Enum.TeleportResult,
		errorMessage: string,
		placeId: number,
		teleportOptions: Instance
	)
		if teleportData["enabled"] ~= true or not teleportData["teleporting"][player] then
			return
		end
		if teleportData["retrying"][player] then
			Log.Once(SCOPE, `retry-reentry-{player.UserId}`, `{player.Name}: duplicate TeleportInitFailed ignored while retrying`)
			return
		end
		if player.Parent ~= Players then
			teleportData.Clear(player)
			return
		end
		if type(placeId) ~= "number" or placeId ~= teleportData["handoff-targets"][player] then
			recover(player, `TeleportInitFailed returned unexpected target {tostring(placeId)}`)
			return
		end
		if typeof(teleportOptions) ~= "Instance" or not teleportOptions:IsA("TeleportOptions") then
			recover(player, "TeleportInitFailed returned no reusable TeleportOptions")
			return
		end
		if teleportResult ~= Enum.TeleportResult.Flooded and teleportResult ~= Enum.TeleportResult.Failure then
			recover(player, `non-retryable teleport result {teleportResult.Name}: {errorMessage}`)
			return
		end

		teleportData["retrying"][player] = true
		local initialDelay = if teleportResult == Enum.TeleportResult.Flooded
			then teleportData["flood-retry-delay-seconds"]
			else teleportData["retry-delay-seconds"]
		task.wait(initialDelay)

		local limit = teleportData["retry-attempt-limit"]
		while player.Parent == Players and teleportData["teleporting"][player] do
			local attempt = (teleportData["retry-attempts"][player] or 0) + 1
			teleportData["retry-attempts"][player] = attempt
			if attempt > limit then
				break
			end

			local ok, retryOrError = pcall(
				TeleportService.TeleportAsync,
				TeleportService,
				placeId,
				{ player },
				teleportOptions
			)
			if ok then
				teleportData["retrying"][player] = nil
				Log.Info(SCOPE, `{player.Name}: retry {attempt}/{limit} initiated to the preserved destination`)
				return
			end
			Log.Warn(SCOPE, `{player.Name}: retry {attempt}/{limit} failed synchronously: {retryOrError}`)
			if attempt < limit then
				task.wait(teleportData["retry-delay-seconds"])
			end
		end

		teleportData["retrying"][player] = nil
		if player.Parent == Players and teleportData["teleporting"][player] then
			recover(player, `teleport retries exhausted after {limit} attempt(s)`)
		end
	end

	TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
		task.spawn(retryFailedTeleport, player, result, message, placeId, options)
	end)
end

return TeleportRetrySubs
