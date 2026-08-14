--[[
	CakeSelectSubsClient -- the lobby cake picker's client state bridge (R4,
	LOBBY partition).

	IN   CakeSelectUpdate -> AppRoot.Set({ cakes = { selected, unlocked } }).
	     The wire carries `unlocked` as an ARRAY of ids (RemoteEvent
	     serialization stringifies numeric table keys -- Net.lua); the UI asks
	     `unlocked[id]` per card, so the array is turned into a SET once per
	     push instead of a linear search per card.

	OUT  onSelectCake(id) -> patch the local mirror FIRST so the card highlights
	     on the tap rather than a round-trip later, then fire SelectCake. The
	     server's next push is authoritative and overwrites the guess
	     (SettingsSubsClient's optimistic-then-authoritative pattern).

	This module owns AppRoot's `cakes` field and nothing else.

	⚠ `cakes`, plural. The singular `cake` is the in-run cycle snapshot owned by
	  CakeSubsClient -- a different thing entirely, never touched here.
	⚠ Unlock rules are evaluated SERVER-SIDE only (CakeSelectConfig header): this
	  module renders the answer it is pushed and never re-derives one, so before
	  the first push nothing is published and nothing is selectable.
	⚠ A tap on a locked id is dropped here AND re-validated server-side (R6) --
	  the local drop exists so a UI bug cannot spam the remote, never as the
	  security check.

	Feature doc: docs/features/cake-select.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local Net = require(Shared:WaitForChild("Net"))

local SCOPE = "CakeSelectClient"

local CakeSelectSubsClient = {}

-- Wire array -> lookup set. Returns the set plus how many ids survived, so the
-- caller can tell "the server sent an empty list" from "the server sent
-- something this build could not read" (R8).
local function toUnlockedSet(list: any): ({ [string]: boolean }, number)
	local set = {}
	local accepted = 0
	if type(list) ~= "table" then
		return set, accepted
	end
	for _, id in ipairs(list) do
		if type(id) == "string" and id ~= "" and set[id] == nil then
			set[id] = true
			accepted += 1
		end
	end
	return set, accepted
end

function CakeSelectSubsClient.Start(data, modules)
	local AppRoot = modules.AppRoot
	if AppRoot == nil then
		Log.Warn(SCOPE, "AppRoot missing -- cake selection wiring skipped")
		return
	end

	local rSelectCake = Net.Remote("SelectCake")
	local uCakeSelect = Net.Update("CakeSelectUpdate")

	-- Local mirror of the last authoritative push. `selected` stays nil until it
	-- lands: an empty set means "no answer yet", which is exactly the state in
	-- which no card may be tapped.
	local selected: string? = nil
	local unlocked: { [string]: boolean } = {}

	-- A FRESH `cakes` table every publish: the kit compares shallowly, so the
	-- optimistic patch has to change identity to reach the cards.
	local function publish()
		AppRoot.Set({ cakes = { selected = selected, unlocked = table.clone(unlocked) } })
	end

	AppRoot.SetCallbacks({
		onSelectCake = function(id)
			if type(id) ~= "string" or id == "" then
				Log.Warn(SCOPE, `onSelectCake got '{tostring(id)}' instead of a cake id -- select dropped`)
				return
			end
			if selected == nil then
				Log.Once(
					SCOPE,
					"cake-select-before-push",
					`cake '{id}' tapped before the first CakeSelectUpdate -- select dropped (no unlock answer to trust yet)`
				)
				return
			end
			if not unlocked[id] then
				Log.Once(
					SCOPE,
					`cake-select-locked-{id}`,
					`cake '{id}' is not unlocked -- select dropped, SelectCake NOT fired (a locked card should not be tappable)`
				)
				return
			end
			-- Optimistic: the highlight is the tap's only feedback, and the server
			-- push that follows either confirms it or corrects it.
			selected = id
			publish()
			rSelectCake:FireServer(id)
		end,
	})

	uCakeSelect.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			Log.Warn(SCOPE, `CakeSelectUpdate payload was '{tostring(payload)}', expected a table -- selection state unchanged`)
			return
		end
		if type(payload.selected) ~= "string" or payload.selected == "" then
			Log.Warn(SCOPE, `CakeSelectUpdate carried no selected id ('{tostring(payload.selected)}') -- selection state unchanged`)
			return
		end

		local set, accepted = toUnlockedSet(payload.unlocked)
		if accepted == 0 then
			-- Never expected: the default cake unlocks unconditionally, so an empty
			-- result means either an empty list or a shape this build cannot read
			-- (a map instead of the documented array). Applied anyway -- the server
			-- is authoritative and the client must not invent an unlock -- but the
			-- picker will render every card locked, so it has to be loud.
			local shape = if type(payload.unlocked) == "table" then "no usable ids" else `a {type(payload.unlocked)}`
			Log.Warn(SCOPE, `CakeSelectUpdate.unlocked yielded {shape} -- every cake will render LOCKED (expected an array of ids)`)
		elseif set[payload.selected] == nil then
			Log.Once(
				SCOPE,
				`cake-select-unlisted-{payload.selected}`,
				`CakeSelectUpdate selected '{payload.selected}' but did not list it as unlocked -- the picker will show it locked`
			)
		end

		selected = payload.selected
		unlocked = set
		publish()
		Log.Info(SCOPE, `cake selection -> '{selected}' ({accepted} unlocked)`)
	end)
end

return CakeSelectSubsClient
