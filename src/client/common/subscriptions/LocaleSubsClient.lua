--[[
	LocaleSubsClient — repaints the app when the translator lands (R4).

	`GetTranslatorForPlayerAsync` is a web round trip that resolves ~0.5-3 s
	AFTER the client boots, so the first paint of every screen is English by
	construction. React only re-renders through `AppRoot.Set`, and a screen that
	is not being fed state (the onboarding comic, the idle lobby menu) would
	simply STAY English until something unrelated patched it.

	So: one state bump on locale-ready, which is the whole job. `localeReady` is
	deliberately not read by any component — its only purpose is to change the
	state identity so the tree re-renders and every `T`/`Tr` re-resolves.

	Alphabetically after AppSubsClient, so the root is already mounted; and
	`AppRoot.Set` works pre-mount anyway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "LocaleSubsClient"

local LocaleSubsClient = {}

function LocaleSubsClient.Start(data, modules)
	local locale = data.LocaleData
	local AppRoot = modules.AppRoot
	if locale == nil or AppRoot == nil then
		Log.Warn(SCOPE, "LocaleData/AppRoot missing — the UI will never repaint on locale-ready and stays ENGLISH")
		return
	end
	if type(locale.OnReady) ~= "function" then
		Log.Warn(SCOPE, "LocaleData has no OnReady — stale module? the UI stays ENGLISH")
		return
	end
	locale.OnReady(function()
		AppRoot.Set({ localeReady = true })
		Log.Info(SCOPE, "translator landed — app repainted in the player's language")
	end)
	Log.Info(SCOPE, "waiting for the translator to repaint the app")
end

return LocaleSubsClient
