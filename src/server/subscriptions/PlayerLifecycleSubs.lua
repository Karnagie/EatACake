--[[
	PlayerLifecycleSubs — join/leave wiring + initial-state push
	(R4: events are connected ONLY in subscription modules).

	Initial state is pushed only after BOTH gates:
	  1. the profile finished loading (LoadProfile returned), AND
	  2. the client reported ClientReady (fired at the end of LocalBootstrap).
	RemoteEvents fired before the client connects its OnClientEvent listeners
	are silently LOST — pushing right after LoadProfile alone can drop the
	first sync on fast loads (especially with the Studio mock store).

	Feature onboarding: add the feature's join push to pushInitialState below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local EconomySubs = require(script.Parent.EconomySubs)
local RewardsSubs = require(script.Parent.RewardsSubs)
local ShopSubs = require(script.Parent.ShopSubs)
local GroupRewardSubs = require(script.Parent.GroupRewardSubs)
local SettingsSubs = require(script.Parent.SettingsSubs)
local CakeSubs = require(script.Parent.CakeSubs)
local BodySubs = require(script.Parent.BodySubs)
local UpgradeSubs = require(script.Parent.UpgradeSubs)
local PetSubs = require(script.Parent.PetSubs)
local RebirthSubs = require(script.Parent.RebirthSubs)
local QuestsSubs = require(script.Parent.QuestsSubs)

local SCOPE = "Lifecycle"

local PlayerLifecycleSubs = {}

function PlayerLifecycleSubs.Start(data, services)
	-- Wiring state (not game data): which sync gates each player has passed.
	local profileLoaded: { [Player]: boolean } = {}
	local clientReady: { [Player]: boolean } = {}

	local function pushInitialState(player: Player)
		-- FEATURE HOOKS: push initial per-domain state to the client.
		EconomySubs.SendCurrency(player)
		SettingsSubs.SendSettings(player)
		RewardsSubs.SendDaily(player)
		RewardsSubs.SendTime(player)
		ShopSubs.SendShop(player)
		GroupRewardSubs.SendState(player)
		CakeSubs.SendSnapshot(player)
		BodySubs.SendStomach(player)
		UpgradeSubs.SendUpgrades(player)
		PetSubs.SendPets(player)
		RebirthSubs.SendRebirth(player)
		QuestsSubs.SendQuests(player)
		Log.Info(SCOPE, `initial state pushed to {player.Name} (currency, settings, daily, time, shop, group, cake, stomach, upgrades, pets, rebirth, quests)`)
		-- Gamepass ownership needs web calls — refresh + re-push async.
		task.spawn(ShopSubs.RefreshPassOwnership, player)
	end

	local function onPlayerAdded(player: Player)
		local profile, isNew = services.PersistenceService.LoadProfile(player)
		if not profile then
			return -- player left or was kicked during load
		end
		-- Anchor the playtime clock as soon as the profile exists (not
		-- gated on ClientReady — played time counts from the actual join).
		services.TimeRewardService.BeginSession(player.UserId)
		profileLoaded[player] = true
		if clientReady[player] then
			pushInitialState(player)
		end

		if isNew then
			-- First-ever join. Reliable signal: true only when a fresh
			-- profile was created, never after a failed read. Use for
			-- analytics cohorts / one-time starter grants.
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		-- Players who joined before Start ran (fast server start).
		task.spawn(onPlayerAdded, player)
	end

	Net.Remote("ClientReady").OnServerEvent:Connect(function(player)
		if clientReady[player] then
			return -- once per session
		end
		clientReady[player] = true
		if profileLoaded[player] then
			pushInitialState(player)
		else
			Log.Info(SCOPE, `{player.Name}: client ready, waiting for profile load`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		profileLoaded[player] = nil
		clientReady[player] = nil
		data.PlayerRuntimeData.Clear(player.UserId)
		-- Fold the final session slice into the profile BEFORE the final save.
		services.TimeRewardService.EndSession(player.UserId)
		services.PersistenceService.Unload(player.UserId)
	end)

	-- Deliberately absent (handled inside ProfileStore — see ADR-0001):
	-- * autosave loop  — auto-saves every ~30 seconds per profile
	-- * BindToClose    — final save on server shutdown
	-- * retry logic    — DataStore call retries
end

return PlayerLifecycleSubs
