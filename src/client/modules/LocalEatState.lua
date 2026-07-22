--[[
	LocalEatState — one client-local boolean: is the LOCAL player ACTIVELY eating
	(EAT button / mouse hold, or Auto-Eat)? Set by `CakeSubsClient` (the input
	owner), read by `CakeFeelSubsClient` to keep movement FLAT while eating — no
	trampoline bounce, jump capped to normal — so running-while-eating goes in a
	straight line instead of constantly bouncing (Task 4).

	Client-only wiring state (no game data): a plain flag both subs share via the
	`modules` table. No Init.
]]

local LocalEatState = {}

local eating = false

--API
function LocalEatState.Set(value: boolean)
	eating = value == true
end

--API
function LocalEatState.Get(): boolean
	return eating
end

return LocalEatState
