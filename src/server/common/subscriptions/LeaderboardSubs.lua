--[[
	LeaderboardSubs — Roblox leaderstats (GDD §12.2): Calories (lifetime), Cakes
	and Finds (DISTINCT buried-find KINDS discovered, out of 9 — the collection
	set, see features/treasures.md; it replaced "biggest belly", a joke stat with
	nothing actionable behind it). Values mirror the profile at load
	+ refresh every 10 s (cheap; leaderstats are not a realtime HUD).
	("Rebirths" was the first column until rebirth was removed 2026-07-26;
	lifetime calories is the natural "how far have you got" number now.)
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
			for _, name in ipairs({ "Calories", "Cakes", "Finds" }) do
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
		;(stats:FindFirstChild("Calories") :: IntValue).Value = math.floor(summary.lifetimeCalories)
		;(stats:FindFirstChild("Cakes") :: IntValue).Value = summary.cakesEaten
		-- The DISCOVERY SET (kinds found, not pickups collected): a small number out
		-- of 9 that visibly stalls is a far stronger pull to come back than a big
		-- number that only ever ticks up. Replaced "Belly" (biggestBelly), a joke
		-- stat with nothing actionable behind it.
		;(stats:FindFirstChild("Finds") :: IntValue).Value = summary.findKindsFound or 0
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
