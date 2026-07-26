--[[
	PlaceConfig — the two PlaceIds of the lobby/game universe (ADR-0009).

	Both IDs must remain places in the SAME Roblox universe/experience. DataStores
	are universe-scoped — that shared lock is why the profile stays consistent
	across the teleport (see docs/features/persistence.md). Invalid/unset ids make
	`current()` return "unknown" so TeleportSubs warns and refuses the handoff.

	`current()` compares game.PlaceId:
	  - matches lobbyPlaceId -> "lobby"
	  - matches gamePlaceId  -> "game"
	  - neither (an unpublished/local place) -> "unknown" (teleport disabled).
]]

local PlaceConfig = {}

-- Universe 10515688913 ("EatACake_DontPublish"). The lobby is the START place
-- (players land there). The game place is created in Studio at publish time.
PlaceConfig.lobbyPlaceId = 80059832045175 -- existing START place (the lobby)
PlaceConfig.gamePlaceId = 91726662453442

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
		return PlaceConfig.gamePlaceId ~= 0 and PlaceConfig.gamePlaceId or nil
	elseif here == "game" then
		return PlaceConfig.lobbyPlaceId ~= 0 and PlaceConfig.lobbyPlaceId or nil
	end
	return nil
end

return PlaceConfig
