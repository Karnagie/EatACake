--[[
	CodesSubs — promo-code redemption domain (R4).

	RedeemCode(raw): type/length check + per-player cooldown -> Check (so a
	code is never consumed when its reward can't be granted) -> TryRedeem ->
	grant via RewardGrantSubs -> Save -> CodeResultUpdate.

	CodeResultUpdate payload: { status, granted? }
	status ∈ "ok" | "invalid" | "expired" | "already".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))
local RewardGrantSubs = require(script.Parent.RewardGrantSubs)

local SCOPE = "CodesSubs"

local CodesSubs = {}

function CodesSubs.Start(data, services)
	local codesData = data.CodesData
	local CodesService = services.CodesService
	local PersistenceService = services.PersistenceService
	local uResult = Net.Update("CodeResultUpdate")

	local lastAttempt = {} -- wiring state: [userId] = os.clock()

	Net.Remote("RedeemCode").OnServerEvent:Connect(function(player, raw)
		if type(raw) ~= "string" or #raw == 0 or #raw > codesData.maxLength then
			return
		end
		local userId = player.UserId
		local now = os.clock()
		if lastAttempt[userId] and (now - lastAttempt[userId]) < codesData.attemptCooldownSeconds then
			-- Answer (don't silently drop): the player's second Enter press
			-- must not look dead.
			uResult:FireClient(player, { status = "cooldown" })
			return
		end
		lastAttempt[userId] = now

		local status, def = CodesService.Check(userId, raw)
		if status == "ok" and def and not RewardGrantSubs.HasHandler(def.reward.kind) then
			-- Mistuned catalogue: never consume a code we can't grant.
			Log.Warn(SCOPE, `code reward kind '{tostring(def.reward.kind)}' has no grant handler`)
			uResult:FireClient(player, { status = "invalid" })
			return
		end

		if status ~= "ok" then
			uResult:FireClient(player, { status = status })
			return
		end

		local redeemStatus, reward = CodesService.TryRedeem(userId, raw)
		if redeemStatus ~= "ok" or reward == nil then
			uResult:FireClient(player, { status = redeemStatus })
			return
		end
		local granted = RewardGrantSubs.Grant(player, reward, "code")
		PersistenceService.Save(userId)
		uResult:FireClient(player, { status = "ok", granted = granted })
		Log.Info(SCOPE, `code redeemed by {player.Name}`)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastAttempt[player.UserId] = nil
	end)

	-- Config validation (after all Starts).
	task.defer(function()
		for code, def in pairs(codesData.codes) do
			if CodesService.Normalize(code) ~= code then
				warn(`[CodesSubs] code '{code}' is not normalized (must be UPPER-CASE, no spaces) — unreachable`)
			end
			if type(def.reward) ~= "table" or not RewardGrantSubs.HasHandler(def.reward.kind) then
				warn(`[CodesSubs] code '{code}' reward kind is missing/unregistered`)
			end
		end
	end)
end

return CodesSubs
