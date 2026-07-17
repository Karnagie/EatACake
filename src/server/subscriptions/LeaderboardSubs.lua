--[[
	LeaderboardSubs — Roblox leaderstats (GDD §12.2): Rebirths, Cakes and
	Belly (biggest belly this life — the comedic one). Values mirror the
	profile at load + refresh every 10 s (cheap; leaderstats are not a
	realtime HUD).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LeaderboardSubs = {}

function LeaderboardSubs.Start(data, services)
	local function ensureStats(player: Player): Folder
		local stats = player:FindFirstChild("leaderstats") :: Folder?
		if not stats then
			stats = Instance.new("Folder")
			stats.Name = "leaderstats"
			for _, name in ipairs({ "Rebirths", "Cakes", "Belly" }) do
				local value = Instance.new("IntValue")
				value.Name = name
				value.Parent = stats
			end
			stats.Parent = player
		end
		return stats
	end

	local function refresh(player: Player)
		local summary = services.ProgressService.Summary(player.UserId)
		if not summary then
			return -- profile not loaded yet; next tick catches it
		end
		local stats = ensureStats(player)
		;(stats:FindFirstChild("Rebirths") :: IntValue).Value = summary.rebirths
		;(stats:FindFirstChild("Cakes") :: IntValue).Value = summary.cakesEaten
		;(stats:FindFirstChild("Belly") :: IntValue).Value = math.floor(summary.biggestBelly)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 10 then
			acc = 0
			for _, player in ipairs(Players:GetPlayers()) do
				refresh(player)
			end
		end
	end)

	Players.PlayerAdded:Connect(ensureStats)
	for _, player in ipairs(Players:GetPlayers()) do
		ensureStats(player)
	end
end

return LeaderboardSubs
