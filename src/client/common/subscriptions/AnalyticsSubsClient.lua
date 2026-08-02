--[[
	AnalyticsSubsClient — every client-side signal, connected in ONE place (R4).

	The player's fingers are on the client and AnalyticsService is on the
	server, so this module is the bridge. It is deliberately the only client
	file that knows analytics exists at the INPUT level: the rest of the game
	is instrumented for free because the kit's press primitive reports every
	button it owns.

	What it owns:

	  TAPS        `Interaction.SetTrackHandler` — one injection counts every
	              pressable in the kit, live or disabled, with no per-button
	              wiring. The same hook the audio layer uses to click them.
	  SCREEN      the open panel, POLLED rather than taken from AppRoot's
	              `onPanelChanged` callback, which AudioSubsClient already
	              owns (SetCallbacks merges by key and the LAST writer wins —
	              registering it here would silently unplug the panel whoosh,
	              and Audio sorts after Analytics so this file would lose).
	              A panel lives for seconds; a 4 Hz poll is exact enough.
	  PADS        distance to the nearest authored lobby pad, so "walked up to
	              the starting area and did not step on it" is a measurable
	              step of the funnel rather than an invisible one.
	  PLATFORM    input device + screen class, once, as the segmentation field
	              every other beat is broken down by.
	  ERRORS      client-side errors, counted (R8) — a UI that throws where
	              nobody is watching is exactly where players get stuck.
	  PUMP        the flush cadence, plus a FORCED flush the moment the server
	              flags a teleport, so the lobby half of the funnel is not
	              still sitting in a queue when the place changes.

	Everything here degrades to nothing: no LocalAnalyticsService, no AppRoot,
	no lobby map — each one warns once and the rest keeps running. Telemetry
	must never be able to take a gameplay path down with it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LogService = game:GetService("LogService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Log"))
local AnalyticsConfig = require(Shared:WaitForChild("config"):WaitForChild("AnalyticsConfig"))
local MatchConfig = require(Shared:WaitForChild("config"):WaitForChild("MatchConfig"))
-- Through the kit's public surface, exactly like AudioSubsClient's sound
-- handler — never by reaching into Interaction directly.
local UIKit = require(Shared:WaitForChild("UIKit"))

local SCOPE = "Analytics"

local AnalyticsSubsClient = {}

local function classifyPlatform(): (string, string)
	local platform
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		platform = "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		platform = "gamepad"
	else
		platform = "desktop"
	end

	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local size
	if viewport.X < 700 then
		size = "phone"
	elseif viewport.X < 1100 then
		size = "tablet"
	else
		size = "wide"
	end
	return platform, size
end

function AnalyticsSubsClient.Start(data, modules)
	local Analytics = modules and modules.LocalAnalyticsService
	if Analytics == nil then
		Log.Warn(SCOPE, "LocalAnalyticsService missing — NO client-side telemetry (taps, panels, tutorial beats) will be recorded")
		return
	end
	local AppRoot = modules.AppRoot
	if AppRoot == nil then
		Log.Warn(SCOPE, "AppRoot missing — panel/screen context will be absent from every tap")
	end

	local player = Players.LocalPlayer
	local clientConfig = AnalyticsConfig.client

	-- ── every kit press, from one injection ──────────────────────────────
	if type(UIKit.SetTrackHandler) == "function" then
		UIKit.SetTrackHandler(function(kind: string, id: string)
			Analytics.Press(id, kind == "dead")
		end)
		Log.Info(SCOPE, "kit press tracking armed (every UIKit pressable, live and disabled)")
	else
		Log.Warn(SCOPE, "UIKit.SetTrackHandler missing — button taps will NOT be counted (stale UIKit?)")
	end

	-- ── platform, once ───────────────────────────────────────────────────
	local platform, screenClass = classifyPlatform()
	Analytics.Track("platform", platform, screenClass, { urgent = true })

	-- ── the HUD existing at all is a flow beat ───────────────────────────
	-- Deferred: client subscriptions Start alphabetically and AppSubsClient
	-- ("App") mounts the React root AFTER this one ("Analytics"), so asking
	-- now would always answer "no root". task.defer resumes once the whole
	-- bootstrap loop has finished.
	task.defer(function()
		if AppRoot ~= nil then
			Analytics.Flow("hud-ready")
		end
	end)

	-- ── panel watcher (polled — see the header) ──────────────────────────
	local lastPanel: string? = nil
	local function pollPanel()
		if AppRoot == nil then
			return
		end
		local current = AppRoot.GetOpenPanel()
		if current == lastPanel then
			return
		end
		if lastPanel ~= nil then
			Analytics.Panel(lastPanel, false)
		end
		if current ~= nil then
			Analytics.Panel(current, true)
			if current == "Shop" then
				-- A fresh shop VISIT, not another step on the last one; the
				-- `shop` beat kind logs the count and the funnel step together.
				Analytics.Track("shop", "open", "panel", { urgent = true })
			elseif current == "Upgrades" then
				Analytics.Funnel("upgrades", "open")
				Analytics.Flow("upgrades-open")
			end
		end
		lastPanel = current
		Analytics.SetScreen(current)
	end

	-- ── lobby pad proximity ──────────────────────────────────────────────
	-- Lobby only. Resolved lazily and re-resolved on a slow timer, never
	-- cached hard: LobbyMap is place content and arrives when it arrives.
	local isLobby = data ~= nil and data.LobbyUiData ~= nil
	local pads: { BasePart } = {}
	local nextPadScanAt = 0
	local approachSent = false

	local function rescanPads()
		table.clear(pads)
		local map = Workspace:FindFirstChild(MatchConfig.queue.mapName)
		local environment = map and map:FindFirstChild(MatchConfig.queue.environmentName)
		local touchers = environment and environment:FindFirstChild(MatchConfig.queue.touchersFolderName)
		if touchers == nil then
			return
		end
		for _, model in ipairs(touchers:GetChildren()) do
			local toucher = model:FindFirstChild(MatchConfig.queue.toucherName)
			if toucher and toucher:IsA("BasePart") then
				table.insert(pads, toucher)
			end
		end
	end

	local function pollPads(now: number)
		if not isLobby or approachSent then
			return
		end
		if now >= nextPadScanAt then
			nextPadScanAt = now + clientConfig.padRescanSeconds
			rescanPads()
			if #pads == 0 then
				Log.GraceOnce(SCOPE, "no-lobby-pads", 20, function()
					return #pads == 0
				end, `no authored {MatchConfig.queue.toucherName} found under workspace.{MatchConfig.queue.mapName} — the 'approached a pad' funnel step can never fire (docs/features/lobby-matchmaking.md)`)
			end
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root == nil then
			return
		end
		local threshold = clientConfig.padApproachStuds
		for _, pad in ipairs(pads) do
			if pad.Parent ~= nil and (pad.Position - root.Position).Magnitude <= threshold then
				approachSent = true
				Analytics.Flow("pad-approach")
				Log.Info(SCOPE, "player came within reach of a lobby pad")
				return
			end
		end
	end

	-- ── errors are data ──────────────────────────────────────────────────
	LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		if messageType ~= Enum.MessageType.MessageError then
			return
		end
		-- Never feed this module's own failures back into itself: one broken
		-- beat would otherwise become an unbounded loop of beats about it.
		if string.find(message, "Analytics", 1, true) ~= nil then
			return
		end
		-- Bucket by the LEADING token only. The full text is unbounded and
		-- would burn the experience-wide 8000-unique-field-value budget in a
		-- day, taking every other breakdown down with it.
		local head = string.match(message, "^%[?([%w_/]+)") or "unknown"
		Analytics.Error(head)
	end)

	-- ── flush the queue before the place changes ─────────────────────────
	-- The server sets this attribute the moment a verified-release handoff
	-- starts. Whatever is still queued belongs to the LOBBY half of the
	-- funnel and has seconds to live.
	player:GetAttributeChangedSignal("Teleporting"):Connect(function()
		if player:GetAttribute("Teleporting") == true then
			Analytics.Flush()
			Analytics.Flush() -- two messages' worth; the queue is small by design
		end
	end)

	-- ── one throttled loop drives all of it ──────────────────────────────
	local accumulated = math.huge
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < clientConfig.pollSeconds then
			return
		end
		accumulated = 0
		local now = os.clock()
		pollPanel()
		pollPads(now)
		Analytics.Pump(now)
	end)

	Log.Sum(
		SCOPE,
		`client telemetry armed — platform {platform}/{screenClass}, {if isLobby then "lobby pad watcher on" else "no pad watcher (not the lobby)"}, flushing every {AnalyticsConfig.beat.flushSeconds}s`
	)
end

return AnalyticsSubsClient
