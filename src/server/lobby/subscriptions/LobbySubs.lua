--[[
	LobbySubs — lobby-place orchestration (lobby partition): builds the hub scene
	on boot. Mirrors how CakeSubs.Start calls MapService.Build in the game place.

	Future home for lobby-only scene wiring (e.g. a "Play" teleport pad's
	ProximityPrompt -> TeleportSubs.Send). The HUD "Play" button already routes
	through the RequestTeleport remote (TeleportSubs).
]]

local LobbySubs = {}

function LobbySubs.Start(data, services, subscriptions)
	-- In the COMBINED build (default.project.json) both partitions load and the
	-- GAME's MapService builds the cake arena — don't stack the lobby hub on top
	-- of it. Build the lobby scene only when this is a lobby-only place (the
	-- game's MapService isn't present).
	if services.MapService ~= nil then
		return
	end
	if services.LobbyMapService == nil then
		return -- defensive: LobbyMapService is a sibling lobby service
	end
	services.LobbyMapService.Build()
end

return LobbySubs
