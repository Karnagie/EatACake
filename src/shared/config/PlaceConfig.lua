--[[
	PlaceConfig — the two PlaceIds of the lobby/game universe (ADR-0009).

	FILL THESE after publishing BOTH places to the SAME Roblox universe/experience
	(DataStores are universe-scoped — that shared lock is the whole reason the
	profile stays consistent across the teleport, see docs/features/persistence.md).
	Until they are set, `current()` returns "unknown" and TeleportSubs warns on
	boot + refuses to teleport (never silently strands a player).

	`current()` compares game.PlaceId:
	  - matches lobbyPlaceId -> "lobby"
	  - matches gamePlaceId  -> "game"
	  - neither (Studio / the combined default.project.json build) -> "unknown"
	    (teleport disabled; both feature sets run together in one place).
]]

local PlaceConfig = {}

-- Universe 10515688913 ("EatACake_DontPublish"). The lobby is the START place
-- (players land there). The game place is created in Studio at publish time.
PlaceConfig.lobbyPlaceId = 80059832045175 -- existing START place (the lobby)
PlaceConfig.gamePlaceId = 0 -- TODO(publish): set to the NEW game place's id

export type Place = "lobby" | "game" | "unknown"

--API
function PlaceConfig.current(): Place
	local id = game.PlaceId
	if PlaceConfig.lobbyPlaceId ~= 0 and id == PlaceConfig.lobbyPlaceId then
		return "lobby"
	elseif PlaceConfig.gamePlaceId ~= 0 and id == PlaceConfig.gamePlaceId then
		return "game"
	end
	return "unknown"
end

--API
-- The PlaceId a player in `current` should teleport TO (the opposite place),
-- or nil when unknown/unconfigured.
function PlaceConfig.otherPlaceId(): number?
	local here = PlaceConfig.current()
	if here == "lobby" then
		return PlaceConfig.gamePlaceId
	elseif here == "game" then
		return PlaceConfig.lobbyPlaceId
	end
	return nil
end

return PlaceConfig
