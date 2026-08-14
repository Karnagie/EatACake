--[[
	InputBridge -- subscription-owned global input fan-out for UIKit gestures.

	Reusable UI gestures sometimes must observe InputChanged/InputEnded after the
	pointer leaves their GuiObject. Components register plain callbacks here; the
	client subscription owns the only UserInputService connections (R4). This
	module creates no engine subscriptions and owns no gameplay state.
]]

local Log = require(script.Parent.Parent.Log)

local InputBridge = {}

local listeners = {}
local nextListenerId = 0

local function dispatch(kind: string, input: InputObject)
	local callbacks = {}
	for listenerId, listener in pairs(listeners) do
		local callback = listener[kind]
		if callback ~= nil then
			table.insert(callbacks, { id = listenerId, callback = callback })
		end
	end
	for _, entry in ipairs(callbacks) do
		local ok, err = pcall(entry.callback, input)
		if not ok then
			Log.Once(
				"UIKit/InputBridge",
				`listener-{entry.id}-{kind}`,
				`global {kind} listener failed: {tostring(err)}`
			)
		end
	end
end

--API
-- Register component-internal listeners. Returns an idempotent cleanup closure.
function InputBridge.Register(onChanged, onEnded): () -> ()
	nextListenerId += 1
	local listenerId = nextListenerId
	listeners[listenerId] = {
		changed = onChanged,
		ended = onEnded,
	}
	local active = true
	return function()
		if not active then
			return
		end
		active = false
		listeners[listenerId] = nil
	end
end

--API
-- Called only by UiInputSubsClient, which owns the engine subscription.
function InputBridge.DispatchChanged(input: InputObject)
	dispatch("changed", input)
end

--API
-- Called only by UiInputSubsClient, which owns the engine subscription.
function InputBridge.DispatchEnded(input: InputObject)
	dispatch("ended", input)
end

return InputBridge
