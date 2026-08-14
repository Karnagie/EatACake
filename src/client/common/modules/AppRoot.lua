--[[
	AppRoot — the ONE composed React root (ui-kit contract: a single
	UiRoot.Render; windows toggle via `openPanel` state, panels zIndex 50
	over HUD zIndex 1, hidden panels stay MOUNTED with visible = false).

	Eat the Cake composition:
	  HUD: calories + gems StatPills; two icon+label menus in the SAME top-left
	       slot, one per place, both built by `menuBlock` from Theme.AppHud's grid
	       numbers — LOBBY meta menu (up to 8 entries; the two social offers appear
	       only once their server push lands) and GAME menu (UPGRADES / SHOP /
	       SQUISHIES / SETTINGS, 2026-08-13). An entry BADGES + BREATHES when there
	       is something behind it the player can afford right now (Upgrades from
	       LocalUpgradeTree.AnyAffordable, Shop from
	       LocalShopService.AffordableBoostCount — the shared predicates their own
	       windows use, so an icon can never advertise a refused purchase);
	       CakeBar (top center — doubles as the boss / zone-gate mini-boss HP
	       bar), BellyBar (bottom center), ComboBadge, AnnounceBanner
	  Panels (zIndex 50): Pets (inspect), Shop, DailyRewards, Codes,
	       Settings, Matchmaking, Cakes (the cake chooser — lobby only, but
	       NOT push-gated: cake #1 always exists), InviteFriends + GroupReward
	       (the two SocialPanel offers — lobby only, each gated on its server push)
	  Celebration (30): CelebrationBanner — the layer-clear / Cake Monster
	       splash, a full-bleed SIBLING of Hud in the free 4-39 band
	       (features/food-burst.md). Its food confetti is NOT in this tree: it
	       is FoodBurst's own ScreenGui at DisplayOrder 99, one below UiRoot.
	  Overlays: GymOverlay (40), Upgrades hex-tree (60 — opened by the game HUD's
	       Upgrades button OR the checkpoint's UpgradeStation prompt, both through
	       `onToggleUpgrades` so the modal wiring cannot be bypassed),
	       TutorialHint (70), PetRevealOverlay (90), TutorialSlides (95).
	       Onboarding's world guidance is a BEAM owned by TutorialSubsClient, not
	       a GUI layer.

	Data flows IN through AppRoot.Set(patch) (called by subscriptions when
	remoteUpdates arrive); user actions flow OUT through callbacks registered
	with AppRoot.SetCallbacks (wired to remotes in subscriptions, R4). Both
	work before AND after mount.

	State fields: openPanel, calories, gems, settings, daily, shop,
	group, codesStatus, cake, cakes, stomach, gym, upgrades, pets, petReveal,
	petRevealCount, combo, announceKey, celebration, matchmaking, checkpointFar,
	tutorial, referral, inviteStatus, groupClaim.
	⚠ `announceKey` and `celebration` are the SAME beat at two sizes and are
	mutually exclusive — CakeSubsClient writes one or the other off one shared
	sequence number (features/food-burst.md).
	⚠ `cake` and `cakes` are DIFFERENT things and both are live: `cake` is the
	in-run cycle snapshot that drives the CakeBar, `cakes` is the lobby's cake
	SELECTION ({ selected, unlocked }, features/cake-select.md).
	Callbacks: onClaimDaily(day), onToggleSetting(id, v),
	onShopActivated(rowId), onRedeem(code), onBuyUpgrade(id),
	onInviteFriends(), onClaimGroupReward(),
	onEquipPet(petId, equip), onToggleUpgrades(), onGymTap(),
	onDismissReveal(), onEatDown(input), onEatUp(input), onReturnCheckpoint(),
	onSelectCake(cakeId),
	onConfigureMatch(difficulty, maxPlayers), onCancelMatch(),
	onMatchDifficultyPick(difficulty, isDefault), onMatchPartyPick(n, isDefault),
	onTutorialSkip(), onTutorialHintDismiss(),
	onPanelChanged(panel|nil) — fired whenever `openPanel` changes (never on
	mount); AudioSubsClient turns it into the open/close whoosh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- Touch-only HUD: the hold-to-eat button shows on phones/tablets (no physical
-- keyboard). PC eats via mouse-hold anywhere (CakeSubsClient), so it needs no
-- button. TouchEnabled+KeyboardEnabled (hybrid laptop) reads as PC.
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local React = require(ReplicatedStorage.Packages.React)
local Log = require(ReplicatedStorage.Shared.Log)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local CakeConfig = require(ReplicatedStorage.Shared.config.CakeConfig)
local MatchConfig = require(ReplicatedStorage.Shared.config.MatchConfig)
local CakeSelectConfig = require(ReplicatedStorage.Shared.config.CakeSelectConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.config.TutorialConfig)
local LocalRewardsService = require(script.Parent.LocalRewardsService)
local LocalSettingsService = require(script.Parent.LocalSettingsService)
local LocalShopService = require(script.Parent.LocalShopService)
local LocalPetsService = require(script.Parent.LocalPetsService)
local LocalUpgradeTree = require(script.Parent.LocalUpgradeTree)

local Theme = UIKit.Theme
local Components = UIKit.Components

local AppRoot = {}

-- ONE shared, frozen empty table for the closed shop's balance row: a fresh `{}`
-- each render would fail React.memo's shallow compare exactly like the live table
-- does, which is the thing this constant exists to avoid.
local EMPTY_BALANCES = table.freeze({})

local locale
local showGame = true
local showLobby = true

-- The state bridge (module-level so subscriptions can feed it; the
-- component mirrors it into React state on change).
local current = {
	openPanel = nil,
	calories = 0,
	gems = 0,
	settings = nil,
	daily = nil,
	shop = nil,
	group = nil,
	codesStatus = nil,
	cake = nil,
	stomach = nil,
	gym = nil,
	upgrades = nil,
	pets = nil,
	petReveal = false,
	petRevealCount = 0,
	combo = nil,
	announceKey = false,
	-- CELEBRATION SPLASH (features/food-burst.md). `{ cheerKey, subKey?, seq }`
	-- for the two beats that are a moment rather than a notification — a layer
	-- cleared and the Cake Monster down. It carries KEYS, not resolved text, so
	-- the rolled phrase survives the ~14 re-renders/second the HUD does while it
	-- is on screen, plus the locale-ready repaint, without ever rerolling.
	-- ⚠ Mutually exclusive with `announceKey` by construction: CakeSubsClient
	-- pushes one or the other for a given beat, never both — two banners in one
	-- frame stomp each other (the same rule the mini-boss announce already
	-- follows, features/cake-cycle.md).
	celebration = false,
	matchmaking = false,
	-- Cake selection (features/cake-select.md): { selected = cakeId,
	-- unlocked = { [cakeId] = true } }, pushed by CakeSelectSubs and patched
	-- optimistically on a tap by CakeSelectSubsClient. nil until that push lands
	-- — the chooser still renders (cake #1 is always available), it just shows
	-- the catalogue's default selection until the server confirms.
	-- ⚠ NOT `cake`, which is the in-run cycle snapshot a few lines above.
	cakes = nil,
	-- Social offers (features/referrals.md, features/group-reward.md). `referral`
	-- is the server snapshot ({ rewarded, rewardGems }) and doubles as the gate
	-- for the Invite button — until it lands there is no reward figure to show.
	-- `inviteStatus` / `groupClaim` are CLIENT-owned transient status, written by
	-- SocialSubsClient, because the claim's red "wait" line has to appear on the
	-- press rather than a round-trip later.
	referral = nil,
	inviteStatus = false,
	groupClaim = false,
	-- Whether the player is far enough from the checkpoint platform to show the
	-- TO CHECKPOINT button (BodySubsClient proximity check). Shown by default.
	checkpointFar = true,
	-- Onboarding surfaces, all driven by TutorialSubsClient (features/tutorial.md).
	-- ONE table so a step change is one patch:
	--   slides          : boolean — the 4-panel comic board is up
	--   hint            : "eat" | nil — which instruction popup, nil = none
	--   arrow           : "upgrades" | nil — what the world pointer is aiming at
	--   pulseCheckpoint : boolean — breathe the TO CHECKPOINT button
	-- ⚠ NOT routed through `openPanel`: that would fire the panel whoosh, arm
	-- the tap-outside scrim's shop-closing branch, and — fatally for step 2 —
	-- hide the touch EAT button (see `eatButtonVisible` below), which is the
	-- very control the hint is pointing at.
	tutorial = nil,
}
local callbacks = {}
local applyState = nil -- setState captured while mounted

function AppRoot.Init(data)
	locale = data.LocaleData
	-- Partition marker modules are mapped only into their corresponding live
	-- place; the combined development project maps both markers.
	showGame = data.GameUiData ~= nil
	showLobby = data.LobbyUiData ~= nil
end

--API
-- Merge a patch into the app state and re-render (works pre-mount too).
-- ⚠ pairs() skips nil values — a `{ field = nil }` patch is a silent no-op.
-- Clearing a field goes through AppRoot.Clear / AppRoot.Open(nil).
function AppRoot.Set(patch: { [string]: any })
	for key, value in pairs(patch) do
		current[key] = value
	end
	if applyState then
		applyState(table.clone(current))
	end
end

--API
-- Clears one state field to nil (Set cannot — see the pairs note above).
function AppRoot.Clear(key: string)
	current[key] = nil
	if applyState then
		applyState(table.clone(current))
	end
end

--API
function AppRoot.SetCallbacks(patch: { [string]: any })
	for key, value in pairs(patch) do
		callbacks[key] = value
	end
end

--API
function AppRoot.Open(panel: string?)
	current.openPanel = panel
	if applyState then
		applyState(table.clone(current))
	end
end

--API
-- Read one state field back out. Subscriptions push state IN through Set; this
-- is for the rarer case of a sub that needs a value ANOTHER sub owns, without
-- duplicating its derivation (TutorialSubsClient reads `checkpointFar`, which
-- BodySubsClient computes from the plate footprint — one source of that fact).
-- Client subs Start alphabetically, so the owner has always armed first.
function AppRoot.Get(key: string): any
	return current[key]
end

--API
-- The currently open panel/overlay name (nil = none). Lets subscriptions defer
-- to a modal that owns shared world state (e.g. the upgrade tree disables the
-- checkpoint ProximityPrompts while open — see BodySubsClient gym-prompt gate).
function AppRoot.GetOpenPanel(): string?
	return current.openPanel
end

local function currentMatchmakingBusy(): boolean
	local matchmaking = current.matchmaking
	return type(matchmaking) == "table" and matchmaking.busy == true
end

-- ── helpers ─────────────────────────────────────────────────────────────

-- Simulator number formatting: exact with thousands separators below 10K, then
-- abbreviated. A HUD pill is ~128 nominal px wide — "1,284,930" renders at a
-- size a player cannot read at a glance, and in this genre the leading digits
-- are the only part that carries meaning anyway. The 10K floor keeps small,
-- countable values (find counts, early calories) exact.
-- { switchAt, divisor, suffix } — the two numbers are NOT the same: K switches on
-- at 10,000 (below that the exact figure still reads fine) but divides by 1,000.
local ABBREV = {
	{ 1e12, 1e12, "T" },
	{ 1e9, 1e9, "B" },
	{ 1e6, 1e6, "M" },
	{ 1e4, 1e3, "K" },
}

local function formatNumber(amount: number): string
	local value = math.floor(amount or 0)
	local sign = if value < 0 then "-" else ""
	value = math.abs(value)
	for _, step in ipairs(ABBREV) do
		local switchAt, scale, suffix = step[1], step[2], step[3]
		if value >= switchAt then
			-- One decimal below 100 units ("12.4M"), none above ("124M") — the
			-- decimal stops being informative once the integer part is 3 digits.
			local scaled = value / scale
			local text
			if scaled < 100 then
				-- gsub returns (string, count): bind it before use, or the count
				-- leaks into the concatenation.
				text = string.format("%.1f", scaled)
				text = text:gsub("%.0$", "")
			else
				text = tostring(math.floor(scaled))
			end
			return `{sign}{text}{suffix}`
		end
	end
	local text = tostring(value)
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return sign .. formatted
end

-- Fit a panel aspect within maxFraction of the supplied surface (or the camera
-- viewport). A surface override lets a full-bleed root keep panel chrome below
-- Roblox's topbar while the modal scrim still covers the whole display.
local function calculateScale(panelAspect: number, maxFraction: number, surface: Vector2?): Vector2
	local camera = Workspace.CurrentCamera
	local viewport = surface or (camera and camera.ViewportSize) or Vector2.new(1920, 1080)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	if viewportAspect >= panelAspect then
		return Vector2.new(maxFraction * panelAspect / viewportAspect, maxFraction)
	end
	return Vector2.new(maxFraction, maxFraction * viewportAspect / panelAspect)
end

-- ── Roblox's own GUI: the two reserved regions we must place around ──────────
-- Numbers and the measurement that produced them live in `Theme.SafeArea`; this
-- is the ONLY place that reads them off the engine (R1/R2 — Theme stays data).

-- How far down Roblox's topbar reaches, plus the pad that keeps us off it.
-- `GetGuiInset()` is the LEGACY inset (the pre-unibar 36 px bar) and can
-- under-report the modern chip; `GuiService.TopbarInset` is a Rect whose Max.Y
-- is the strip's real bottom edge. Take whichever is taller — a client that
-- only answers one of the two still gets the right number — clamp against a
-- nonsense report, then pad.
local insetNoticeLogged = false
local function resolveTopInset(): number
	local legacy = GuiService:GetGuiInset().Y
	local reserved = 0
	local bar = GuiService.TopbarInset
	if typeof(bar) == "Rect" then
		reserved = bar.Max.Y
	end
	if reserved > legacy and not insetNoticeLogged then
		-- Info, NOT Log.Once (which warns): this is the expected modern case and
		-- the resolver has already absorbed it. R8 reserves Warn for "needs
		-- attention", and a yellow line on every healthy boot is how a console
		-- stops being read. Latched because the resolver runs on every sync.
		insetNoticeLogged = true
		Log.Info(
			"AppRoot",
			`Roblox topbar reaches {reserved}px but GetGuiInset() reports {legacy}px — HUD placement follows the taller one`
		)
	end
	local top = math.clamp(math.max(legacy, reserved), 0, Theme.SafeArea.MaxTopInsetPx)
	return top + Theme.SafeArea.TopPadPx
end

-- Height of the bottom-right corner Roblox's touch JUMP button occupies, in px
-- (0 when there are no touch controls). Roblox scales that button with the
-- SHORTER viewport axis while our controls are placed by viewport FRACTION, so
-- a control that clears it on a desktop window lands on top of it on a phone —
-- callers keep their own bottom edge this far off the bottom instead.
local function resolveTouchReserve(size: Vector2): number
	-- ⚠ `TouchEnabled`, NOT `IS_TOUCH`. Those answer different questions:
	-- IS_TOUCH is `touch and no keyboard` and exists to decide whether to RENDER
	-- the EAT button, while this one asks whether ROBLOX may be drawing its
	-- controls. An iPad with a Magic Keyboard or a touchscreen laptop reports
	-- both, so IS_TOUCH is false there — and Roblox still shows a jump button
	-- the moment the player taps the screen. Reserving a corner that stays empty
	-- costs a little layout; not reserving it puts our control under Roblox's.
	if not UserInputService.TouchEnabled then
		return 0
	end
	-- `> 1`, not `> 0`: a session's first frames report a DEGENERATE (1,1)
	-- surface, and sizing a reserve off that is nonsense. The refit effect
	-- re-runs this the moment a real one lands.
	if size == nil or size.X <= 1 or size.Y <= 1 then
		return 0
	end
	local safe = Theme.SafeArea
	local button = math.min(math.min(size.X, size.Y) * safe.TouchButtonFraction, safe.TouchButtonMaxPx)
	return button * safe.TouchButtonReserveMult + safe.TouchCornerPadPx
end

-- Height of the full-bleed root in px, so the two safe-area numbers above can
-- also be handed to FULL-BLEED overlays as FRACTIONS of it (a full-bleed frame's
-- height IS this, so a fraction is exact there; inside the shortened `Hud` layer
-- only pixels are, which is why the two prop families differ by suffix).
-- The live value comes off the `App` frame's own AbsoluteSize — the surface we
-- are actually placing into, and the only source that stays honest when
-- `Camera.ViewportSize` does not (it reports a degenerate (1,1) for the first
-- frames of a session, and in a Studio session driven over MCP it can stay
-- there). The camera is only the seed for the very first render.
local function resolveViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	return if viewport ~= nil then viewport else Vector2.new(1920, 1080)
end

-- Server messages may be locale keys or already-authored display strings.
-- Keys go through T; display copy goes through Tr so a future localization
-- backend can translate it without changing the matchmaking contract.
local function localizeMessage(value, key, params, fallbackKey: string?): string?
	local hadValue = value ~= nil and value ~= false
	if type(key) == "string" and key ~= "" then
		return locale.T(key, params)
	end
	if type(value) == "table" then
		local tableKey = value.key
		if type(tableKey) == "string" and tableKey ~= "" then
			return locale.T(tableKey, value.params)
		end
		value = value.message
	end
	if type(value) == "string" and value ~= "" then
		if locale.strings[value] ~= nil then
			return locale.T(value, params)
		end
		return locale.Tr(value)
	end
	if hadValue and fallbackKey then
		return locale.T(fallbackKey)
	end
	return nil
end

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Secret = 6 }

-- View-model: CakeBar text + fill by cycle phase.
local function cakeBarModel(cake)
	if cake == nil then
		return 0, "", "eating"
	end
	local phase = cake.phase or "eating"
	if phase == "boss" then
		local hp01 = if cake.boss then cake.boss.hp / math.max(1, cake.boss.maxHp) else 1
		return hp01, locale.T("cake-boss", { timer = math.floor(cake.timer or 0) }), "boss"
	elseif phase == "miniboss" then
		-- The ZONE GATE (features/cake-cycle.md). Same red HP bar as the finale,
		-- but NO timer in the label — a mini-boss is untimed on purpose, and a
		-- counting-down "0s" would read as a fight you are losing.
		local mini = cake.miniBoss
		local hp01 = if mini then mini.hp / math.max(1, mini.maxHp) else 1
		return hp01, locale.T("cake-miniboss"), "boss"
	elseif phase == "reward" then
		return 1, locale.T("cake-reward"), "eating"
	elseif phase == "spawning" then
		local delay = CakeConfig.cycle.newCakeDelay
		local left = math.clamp(cake.timer or 0, 0, delay)
		return 1 - left / delay, locale.T("cake-spawning", { timer = math.floor(left) }), "eating"
	end
	-- EATING is ~all of the playtime, and the cake % bar is deliberately hidden
	-- then (it barely moves, 2026-07-19). Show the per-cake FIND GOAL instead —
	-- a countable set is what gives a long run something to aim at (Drain the
	-- Lake). Falls back to the % bar if the server sent no counts.
	local finds = cake.finds
	if type(finds) == "table" and (finds.total or 0) > 0 then
		local found = math.clamp(finds.found or 0, 0, finds.total)
		return found / finds.total,
			locale.T("cake-finds", { found = found, total = finds.total }),
			"eating"
	end
	local progress = math.clamp(cake.progress or 0, 0, 1)
	return progress, locale.T("cake-progress", { pct = math.floor(progress * 100) }), "eating"
end

-- ── the composed App component ──────────────────────────────────────────

local function App()
	-- Lazy initializers: plain values would re-evaluate on every render.
	local state, setState = React.useState(function()
		return table.clone(current)
	end)
	local portraitScale, setPortraitScale = React.useState(function()
		return calculateScale(Theme.Layout.PanelAspect, Theme.Layout.PanelMaxViewportFraction)
	end)
	local wideScale, setWideScale = React.useState(function()
		return calculateScale(Theme.RewardsLayout.PanelAspect, Theme.RewardsLayout.PanelMaxViewportFraction)
	end)
	local codesScale, setCodesScale = React.useState(function()
		return calculateScale(Theme.CodesLayout.PanelAspect, Theme.CodesLayout.PanelMaxViewportFraction)
	end)
	local petsScale, setPetsScale = React.useState(function()
		return calculateScale(Theme.PetsInspectLayout.PanelAspect, Theme.PetsInspectLayout.PanelMaxViewportFraction)
	end)
	-- Invite Friends + the community reward share ONE portrait shell
	-- (Components.SocialPanel), so they share its fit.
	local socialScale, setSocialScale = React.useState(function()
		return calculateScale(Theme.SocialLayout.PanelAspect, Theme.SocialLayout.PanelMaxViewportFraction)
	end)
	-- The shop is landscape now (grids per category), so it needs its own fit —
	-- it used to borrow portraitScale.
	local shopScale, setShopScale = React.useState(function()
		return calculateScale(Theme.ShopLayout.PanelAspect, Theme.ShopLayout.PanelMaxViewportFraction)
	end)
	-- Onboarding surfaces are aspect-locked blocks, so they fit like a panel
	-- does. ⚠ Two coupled sites per scale: the initializer here AND the `refit`
	-- body below — miss the second and the block stops resizing with the window.
	local slidesScale, setSlidesScale = React.useState(function()
		return calculateScale(Theme.TutorialSlides.BoardAspect, Theme.TutorialSlides.BoardMaxViewportFraction)
	end)
	local hintScale, setHintScale = React.useState(function()
		return calculateScale(Theme.TutorialHint.Aspect, Theme.TutorialHint.MaxViewportFraction)
	end)
	-- Topbar inset in px (see resolveTopInset). The root gui is full-bleed
	-- (UiRoot), so the HUD layer applies this itself — and so does every
	-- full-bleed overlay that PLACES a control near the top edge. Not a
	-- constant: it is 0 in some contexts, and it changes when the topbar
	-- shows/hides or the player rotates a phone.
	local topInset, setTopInset = React.useState(resolveTopInset)
	local appRef = React.useRef(nil)
	-- Prefer the surface we are actually placing into over what the camera
	-- claims; the two agree in a real client and only the first disagrees when
	-- the camera has not settled.
	local function rootSize(): Vector2
		local app = appRef.current
		if app ~= nil and app.AbsoluteSize.Y > 1 then
			return app.AbsoluteSize
		end
		return resolveViewportSize()
	end
	-- Bottom-right corner reserved for Roblox's touch jump button, px (0 on PC).
	local touchReserve, setTouchReserve = React.useState(function()
		return resolveTouchReserve(resolveViewportSize())
	end)
	local viewportY, setViewportY = React.useState(function()
		return math.max(resolveViewportSize().Y, 1)
	end)
	local codeInput, setCodeInput = React.useState("")
	local selectedPetId, setSelectedPetId = React.useState(nil :: string?)
	local sortByRarity, setSortByRarity = React.useState(true)
	-- Upgrades hex-tree navigation stack (top = the tree currently shown).
	local treeStack, setTreeStack = React.useState({ "root" })

	-- Bridge: subscriptions push state through AppRoot.Set.
	React.useEffect(function()
		applyState = setState
		setState(table.clone(current)) -- pick up pre-mount patches
		return function()
			applyState = nil
		end
	end, {})

	-- Panel open/close cue (AudioSubsClient wires the sound). ONE place: every
	-- panel opens through `openPanel`, so a whoosh can never drift out of sync
	-- with a panel that forgot to fire it. `primed` swallows the effect's first
	-- run — mounting with no panel open is not a close.
	-- Deps use `or false` (jsdotlua breaks on nil in a dep array).
	local panelCueRef = React.useRef(nil)
	if panelCueRef.current == nil then
		panelCueRef.current = { value = false, primed = false }
	end
	local openPanelDep = state.openPanel or false
	React.useEffect(function()
		local record = panelCueRef.current
		if not record.primed then
			record.primed = true
			record.value = openPanelDep
			return
		end
		if record.value == openPanelDep then
			return
		end
		record.value = openPanelDep
		if callbacks.onPanelChanged then
			callbacks.onPanelChanged(if openPanelDep == false then nil else openPanelDep)
		end
	end, { openPanelDep })

	-- Topbar inset tracking for the HUD layer. Separate effect from the viewport
	-- refit below: the inset changes on its own signal (the topbar can hide).
	-- Matchmaking's safe-area fit derives from this state during render.
	React.useEffect(function()
		local alive = true
		local function syncInset()
			if not alive then
				return
			end
			setTopInset(resolveTopInset())
		end
		syncInset()
		local connections = {
			GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(syncInset),
			-- The strip's height also moves when the Roblox menu opens/closes,
			-- and both APIs can still answer 0 for a beat after the client boots
			-- — one late re-read costs nothing and is the difference between a
			-- HUD parked under the bar for the session and a correct one.
			GuiService:GetPropertyChangedSignal("MenuIsOpen"):Connect(syncInset),
		}
		task.delay(1, syncInset)
		-- The root's own laid-out height is what the safe-area FRACTIONS are
		-- relative to, and it is correct even when the camera's ViewportSize is
		-- not. Own signal, because a gui can be re-laid-out (device safe area,
		-- rotation) without the camera changing.
		local app = appRef.current
		if app ~= nil then
			local function syncHeight()
				if not alive then
					return
				end
				local size = rootSize()
				setViewportY(math.max(size.Y, 1))
				setTouchReserve(resolveTouchReserve(size))
			end
			syncHeight()
			table.insert(connections, app:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncHeight))
		else
			Log.Once("AppRoot", "no-app-ref", "App frame ref never populated — safe-area fractions fall back to the camera viewport")
		end
		return function()
			alive = false
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end, {})

	-- Viewport re-fit (kit checklist: aspect held at any window size).
	React.useEffect(function()
		local viewportConnection, cameraConnection
		local function refit()
			setTopInset(resolveTopInset())
			-- Roblox scales its touch controls with the SHORTER viewport axis, so
			-- this has to be recomputed with the viewport, not once at mount.
			local size = rootSize()
			setTouchReserve(resolveTouchReserve(size))
			setViewportY(math.max(size.Y, 1))
			setPortraitScale(calculateScale(Theme.Layout.PanelAspect, Theme.Layout.PanelMaxViewportFraction))
			setWideScale(calculateScale(Theme.RewardsLayout.PanelAspect, Theme.RewardsLayout.PanelMaxViewportFraction))
			setCodesScale(calculateScale(Theme.CodesLayout.PanelAspect, Theme.CodesLayout.PanelMaxViewportFraction))
			setPetsScale(calculateScale(Theme.PetsInspectLayout.PanelAspect, Theme.PetsInspectLayout.PanelMaxViewportFraction))
			setSocialScale(calculateScale(Theme.SocialLayout.PanelAspect, Theme.SocialLayout.PanelMaxViewportFraction))
			setShopScale(calculateScale(
				Theme.ShopLayout.PanelAspect,
				Theme.ShopLayout.PanelMaxViewportFraction
			))
			setSlidesScale(calculateScale(
				Theme.TutorialSlides.BoardAspect,
				Theme.TutorialSlides.BoardMaxViewportFraction
			))
			setHintScale(calculateScale(
				Theme.TutorialHint.Aspect,
				Theme.TutorialHint.MaxViewportFraction
			))
		end
		local function bindCamera()
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end
			refit()
			local camera = Workspace.CurrentCamera
			if camera then
				viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
			end
		end
		bindCamera()
		cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
		return function()
			if viewportConnection then
				viewportConnection:Disconnect()
			end
			if cameraConnection then
				cameraConnection:Disconnect()
			end
		end
	end, {})

	-- Fat-burn overlay: active while a session is open; `remain01` is the
	-- server-streamed remaining-fat fraction (1 = untouched, 0 = empty).
	local gymActive = state.gym ~= nil and state.gym.active == true
	local gymRemain01 = if state.gym ~= nil and type(state.gym.remain01) == "number"
		then math.clamp(state.gym.remain01, 0, 1)
		else 1

	-- Is a modal already up? The scrim prevents POINTER access to the HUD, but
	-- controller selection is a separate channel and must obey the same boundary.
	-- Check both the synchronous mirror and this render: during either edge of a
	-- React commit, one of them still owns the modal and a held HUD control must
	-- not close/replace it.
	local function modalBusy(): string?
		return current.openPanel or state.openPanel
	end

	local function togglePanel(name: string)
		local blocking = modalBusy()
		if blocking ~= nil then
			-- R8: a dead press with nothing on the console used to be one button in
			-- the lobby; the game HUD now has four, so say which modal ate it.
			Log.Info("AppRoot", `HUD '{name}' press ignored — '{blocking}' is already open`)
			return
		end
		AppRoot.Open(name)
	end

	-- ── view-model builds ────────────────────────────────────────────────
	-- The App re-renders at bite frequency (StomachUpdate + combo). Every
	-- panel view-model is memoized on its state slice so eating doesn't
	-- rebuild pets/shop/rewards tables ~14x/s on a phone. Deps use
	-- `or false` — nil in jsdotlua dep arrays breaks the compare.
	local rewardCards = React.useMemo(function()
		local cards, footer = LocalRewardsService.BuildDailyCards(state.daily)
		return { dailyCards = cards, dailyFooter = footer }
	end, { state.daily or false })
	local dailyCards, dailyFooter = rewardCards.dailyCards, rewardCards.dailyFooter
	local dailyBadge = state.daily ~= nil and state.daily.claimable == true

	local petsProps = React.useMemo(function()
		local props = LocalPetsService.BuildPanelProps(state.pets, selectedPetId)
		if sortByRarity then
			table.sort(props.pets, function(a, b)
				local ra, rb = RARITY_RANK[a.rarity] or 0, RARITY_RANK[b.rarity] or 0
				if ra ~= rb then
					return ra > rb
				end
				return a.name < b.name
			end)
		else
			table.sort(props.pets, function(a, b)
				return a.name < b.name
			end)
		end
		return props
	end, { state.pets or false, selectedPetId or false, sortByRarity })

	-- Upgrades hex-tree: reset to the root honeycomb each time it opens; build
	-- the current tree's node/edge model from the replicated levels + calories.
	local upgradesOpen = state.openPanel == "Upgrades"
	React.useEffect(function()
		-- Reset to root when CLOSED, so the next open starts at root with NO
		-- one-frame flash of the previous sub-tree (the reset lands while hidden).
		if not upgradesOpen then
			setTreeStack({ "root" })
		end
	end, { upgradesOpen })
	local currentTree = treeStack[#treeStack] or "root"
	local upgradeTree = React.useMemo(function()
		-- Only build while open — the overlay is hidden otherwise, and this keeps
		-- calorie ticks (auto-gym etc.) from rebuilding the model when closed.
		if not upgradesOpen then
			return { nodes = {}, nodeWidth = 0.1, nodeHeight = 0.1 }
		end
		return LocalUpgradeTree.BuildTree(currentTree, state.upgrades, state.calories)
	end, { upgradesOpen, currentTree, state.upgrades or false, state.calories })
	-- The GEM BALANCE is a real input here, not just a HUD number: a gem-priced
	-- card renders grey and unclickable until the player can afford it, so
	-- `state.gems` MUST be in the deps — leave it out and the shop keeps saying
	-- "you can't afford this" after the find that paid for it.
	local shopTabs = React.useMemo(function()
		return LocalShopService.BuildTabs(state.shop, state.group, state.gems)
	end, { state.shop or false, state.group or false, state.gems })
	-- ShopPanel is React.memo'd and its tree is ~700 elements. A fresh closure
	-- in its props defeats the shallow compare outright, so the memo has to be
	-- paired with stable handlers or it is pure overhead. Empty deps are safe:
	-- `callbacks` is a module-level table read at call time, and AppRoot.Open
	-- is a module function.
	local onShopActivated = React.useCallback(function(rowId)
		if callbacks.onShopActivated then
			callbacks.onShopActivated(rowId)
		end
	end, {})
	-- Observation only (which tab the player browses never reaches the server
	-- unless they buy). Memoised for the same reason as onShopActivated:
	-- ShopPanel's memo depends on every one of its props being stable.
	local onShopTabChanged = React.useCallback(function(tabId)
		if callbacks.onShopTabChanged then
			callbacks.onShopTabChanged(tabId)
		end
	end, {})
	local closeShop = React.useCallback(function()
		AppRoot.Open(nil)
	end, {})
	-- Panels with close-time OBLIGATIONS get named closers so every close
	-- path (X button, scrim tap-outside, future gestures) runs the same
	-- contract — a blanket Open(nil) on the scrim skipped Matchmaking's
	-- server-side cancel and Codes' status clear (adversarial review
	-- 2026-08-01). Launch-busy matchmaking cannot be closed: configure is
	-- already ordered ahead of a leave, so hiding the panel would reject the
	-- late leave while the countdown continued invisibly. `callbacks` remains a
	-- module-level table, and `current.matchmaking` is also read at call time so
	-- the guard changes synchronously before React commits the next render.
	local closeMatchmaking = React.useCallback(function()
		-- Read the module-level mirror patched synchronously by AppRoot.Set. A
		-- render-captured value leaves one multitouch release window after START.
		if current.openPanel ~= "Matchmaking" or currentMatchmakingBusy() then
			return
		end
		if callbacks.onCancelMatch then
			callbacks.onCancelMatch()
		end
		AppRoot.Open(nil)
	end, {})
	local closeCodes = React.useCallback(function()
		AppRoot.Open(nil)
		AppRoot.Clear("codesStatus")
	end, {})
	-- CALORIES CHANGE EVERY BITE, and ShopPanel is React.memo'd over a ~700-element
	-- tree that stays MOUNTED (visible = false) while closed. A balances table
	-- rebuilt at bite rate fails the shallow compare and reconciles the whole panel
	-- for the entire eating phase — the exact cost the memo exists to avoid. So the
	-- table is only rebuilt while the shop is actually OPEN; closed, the panel keeps
	-- one frozen reference and re-renders on nothing.
	local shopOpen = state.openPanel == "Shop"
	local shopBalances = React.useMemo(function()
		if not shopOpen then
			return EMPTY_BALANCES
		end
		-- Same names as the HUD pills (Theme.AppHud.PillIcons): the shop can open
		-- over the HUD, so a currency showing two different glyphs at once reads as
		-- two different currencies.
		-- GEMS ONLY (UX audit 2026-08-01): nothing in the shop is priced in
		-- calories (products are Robux or gems), and calories are RUN-scoped —
		-- the pill sat there showing "0" most of the time. A balance the shop
		-- cannot spend is header noise, not an anchor.
		return {
			-- jumpTabId: the chip carries a green "+" and taps through to the
			-- gem packs (ShopPanel renders the badge + hit target).
			{ iconName = Theme.AppHud.PillIcons.Gems, value = formatNumber(state.gems), jumpTabId = "gems" },
		}
	end, { shopOpen, shopOpen and state.gems or 0 })
	local oddsText = React.useMemo(LocalPetsService.OddsText, {})

	local matchmaking = if type(state.matchmaking) == "table" then state.matchmaking else nil
	local matchmakingMaxPlayers = if matchmaking ~= nil and type(matchmaking.maxPlayers) == "number"
		then math.clamp(math.floor(matchmaking.maxPlayers), 1, MatchConfig.queue.maxPlayers)
		else MatchConfig.queue.maxPlayers
	local difficultyOptions = React.useMemo(function()
		local options = {}
		for _, id in ipairs(MatchConfig.difficultyOrder) do
			local difficulty = MatchConfig.difficulties[id]
			if difficulty ~= nil then
				local ui = if type(difficulty.ui) == "table" then difficulty.ui else {}
				local descriptionKey = ui["description-key"]
				table.insert(options, {
					id = id,
					label = locale.T(difficulty.labelKey),
					description = if type(descriptionKey) == "string" then locale.T(descriptionKey) else "",
					iconName = ui["icon-name"],
					accent = ui["accent"] or id,
					-- Icon-first passive reward tag. The value is config data, while
					-- punctuation, suffix order, and the reward noun belong to locale.
					rewardText = locale.T("match-reward-multiplier", {
						n = difficulty.caloriesMultiplier or 1,
					}),
				})
			end
		end
		return options
	end, { state.localeReady or false })
	local playerCountOptions = React.useMemo(function()
		local options = {}
		for _, count in ipairs(MatchConfig.playerCounts) do
			if count <= matchmakingMaxPlayers then
				table.insert(options, {
					value = count,
					label = if count == 1
						then locale.T("match-player-one")
						else locale.T("match-player-many", { n = count }),
				})
			end
		end
		return options
	end, { matchmakingMaxPlayers, state.localeReady or false })

	-- ── cake selection (features/cake-select.md) ─────────────────────────
	-- Built from the CATALOGUE, not gated on the server push. Unlike the two
	-- social offers — which have nothing to show until their payload lands —
	-- cake #1 is always available, so the chooser has to be usable on the first
	-- frame. Until `CakeSelectUpdate` arrives this renders the catalogue default
	-- as selected and every conditional cake as LOCKED, which is the
	-- conservative reading; the push corrects it a moment later.
	-- ⚠ Do not shortcut this with `leaderstats.Cakes` — that IntValue is written
	-- on a 10 s heartbeat, so a player who just cleared their first cake would
	-- watch the rainbow stay locked for up to ten seconds after earning it.
	local cakeState = if type(state.cakes) == "table" then state.cakes else nil
	local cakeSelectedId = if cakeState ~= nil and type(cakeState.selected) == "string"
		then cakeState.selected
		else CakeSelectConfig.defaultId
	local cakeUnlocked = if cakeState ~= nil and type(cakeState.unlocked) == "table"
		then cakeState.unlocked
		else nil
	-- Deps are written `x or false`: a nil in a jsdotlua dep array makes the
	-- comparison skip, which freezes the memo at its first value forever.
	local cakeOptions = React.useMemo(function()
		local options = {}
		for _, id in ipairs(CakeSelectConfig.order) do
			local definition = CakeSelectConfig.cakes[id]
			if definition ~= nil then
				-- An "always" cake is never locked even before the push; anything
				-- with a real rule stays locked until the server SAYS otherwise.
				local locked = definition.unlockRule ~= "none"
					and not (cakeUnlocked ~= nil and cakeUnlocked[id] == true)
				-- A teaser slot is LOCKED like any other unearned cake — equally
				-- unpickable — and differs only in the badge glyph and the copy,
				-- so "you can earn this" and "this does not exist yet" stay
				-- distinguishable without becoming two card types.
				local comingSoon = definition.unlockRule == "coming-soon"
				table.insert(options, {
					id = id,
					label = locale.T(definition.nameKey),
					iconName = definition.iconName,
					accent = definition.accent,
					selected = cakeSelectedId == id,
					locked = locked,
					comingSoon = comingSoon,
					-- The requirement is shown only while it is still a
					-- requirement — an unlocked card has nothing to explain.
					statusText = if locked and definition.unlockHintKey ~= nil
						then locale.T(definition.unlockHintKey)
						else nil,
				})
			end
		end
		return options
	end, { cakeSelectedId, cakeUnlocked or false, state.localeReady or false })
	local onSelectCake = React.useCallback(function(cakeId)
		-- Same synchronous guard as closeMatchmaking: a held cake press releasing
		-- after START or logical close must not persist a different account
		-- preference. This handler is shared by exactly these two cake surfaces.
		local openPanel = current.openPanel
		if (openPanel ~= "Matchmaking" and openPanel ~= "Cakes") or currentMatchmakingBusy() then
			return
		end
		if callbacks.onSelectCake then
			callbacks.onSelectCake(cakeId)
		end
	end, {})

	local matchStatusText = if matchmaking ~= nil
		then localizeMessage(
			matchmaking.statusText,
			matchmaking.statusKey,
			matchmaking.statusParams,
			nil
		)
		else nil
	local matchErrorText = if matchmaking ~= nil
		then localizeMessage(
			matchmaking.error,
			matchmaking.errorKey,
			matchmaking.errorParams,
			"match-error-start"
		)
		else nil
	local matchCurrentPlayers = if matchmaking ~= nil and type(matchmaking.currentPlayers) == "number"
		then math.max(math.floor(matchmaking.currentPlayers), 0)
		else 1

	local cakeFill, cakeText, cakeMode = cakeBarModel(state.cake)
	-- Hide the top-center bar during normal eating (no more "CAKE 45%"); keep it
	-- for boss fights (HP/timer) and the new-cake countdown / reward flash.
	local cakePhase = if state.cake ~= nil then (state.cake.phase or "eating") else "eating"
	-- Visible during EATING too now, because it carries the find goal there
	-- (cakeBarModel) — the loop used to run with no progress signal at all.
	local cakeFinds = state.cake and state.cake.finds
	local cakeVisible = cakePhase ~= "eating"
		or (type(cakeFinds) == "table" and (cakeFinds.total or 0) > 0)
	-- Touch hold-to-eat button: shown only while there's something to tap
	-- (eating / boss / the zone-gate mini-boss, which takes the same tap), never
	-- while the gym overlay or a panel is up (you're not eating then, and it
	-- would sit under/beside them). Touch devices only.
	-- ⚠ `tutorialSlidesUp` is checked separately from `openPanel`: the comic
	-- board deliberately is NOT a panel (it must not fire the whoosh or arm the
	-- scrim), so the openPanel test below does not cover it — and a pink EAT
	-- button glowing through the intro's scrim is exactly the kind of leak that
	-- test exists to prevent.
	local tutorialSlidesUp = showGame
		and type(state.tutorial) == "table"
		and state.tutorial.slides == true
	local eatButtonVisible = showGame
		and IS_TOUCH
		and (cakePhase == "eating" or cakePhase == "boss" or cakePhase == "miniboss")
		and not gymActive
		and not tutorialSlidesUp
		and state.openPanel == nil
	local stomach = state.stomach
	local capacity = stomach and math.max(1, stomach.capacity or 1) or 1
	local bellyFill = stomach and math.clamp((stomach.fill or 0) / capacity, 0, 1) or 0
	local glutton = stomach ~= nil and stomach.glutton == true
	local bellyText = if stomach == nil
		then ""
		elseif glutton then locale.T("belly-glutton")
		else locale.T("belly-label", { fill = math.floor(stomach.fill or 0), cap = math.floor(capacity) })

	local reveal = if type(state.petReveal) == "table" then LocalPetsService.BuildReveal(state.petReveal) else nil

	-- ── social offers (features/referrals.md, features/group-reward.md) ──
	-- Both status lines are CLIENT-owned transient state (`inviteStatus` /
	-- `groupClaim`, written by SocialSubsClient) rather than fields of the
	-- server payloads: the red "like the game and wait" message has to appear on
	-- the press, a round-trip before the server has said anything at all.
	-- Each offer also waits for its own server push before it exists at all: the
	-- reward figure and the friend count are server-side facts, so rendering
	-- early would advertise "0 Gems Per Friend", and a community button whose
	-- only possible answer is "not available" is worse than no button. Both
	-- pushes are lobby-only, which is where the whole feature lives.
	local groupState = if type(state.group) == "table" then state.group else nil
	local groupConfigured = groupState ~= nil and groupState.configured == true
	local referral = if type(state.referral) == "table" then state.referral else nil
	local referralRewardGems = if referral ~= nil then math.floor(tonumber(referral.rewardGems) or 0) else 0
	local referralRewarded = if referral ~= nil then math.floor(tonumber(referral.rewarded) or 0) else 0
	local inviteStatus = if type(state.inviteStatus) == "table" then state.inviteStatus else nil
	local inviteStatusText = if inviteStatus ~= nil
		then locale.T(inviteStatus.statusKey, inviteStatus.statusParams)
		elseif referralRewarded > 0 then locale.T("invite-count", { n = formatNumber(referralRewarded) })
		else locale.T("invite-count-none")
	local inviteStatusKind = if inviteStatus ~= nil then (inviteStatus.statusKind or "ok") else "ok"

	local groupClaim = if type(state.groupClaim) == "table" then state.groupClaim else nil
	local groupClaimed = groupState ~= nil and groupState.claimed == true
	local groupPending = groupClaim ~= nil and groupClaim.pending == true
	local groupStatusText = if groupClaim ~= nil
		then locale.T(groupClaim.statusKey, groupClaim.statusParams)
		elseif groupClaimed then locale.T("group-claimed")
		else nil
	local groupStatusKind = if groupClaim ~= nil then (groupClaim.statusKind or "error") else "ok"

	-- ── onboarding view-model (features/tutorial.md) ─────────────────────
	-- Every surface is game-place only, exactly like Gym/PetReveal: the panels
	-- themselves are not place-gated and would otherwise render in the lobby.
	local tutorial = if showGame and type(state.tutorial) == "table" then state.tutorial else nil
	local tutorialSlides = tutorial ~= nil and tutorial.slides == true
	-- The eat hint's copy AND its glyph branch on the device, from the same
	-- IS_TOUCH the touch EAT button uses — a phone is told to press the button
	-- it can see, a desktop is told to click. (Hybrid laptops read as PC.)
	-- ⚠ SUPPRESSED while any panel or overlay is up. The hint sits at zIndex 70,
	-- i.e. ABOVE every panel (50) and the hex tree (60), so it floated over
	-- whatever the player opened — reachable in the game place since the HUD grew
	-- Upgrades/Shop/Squishies buttons (2026-08-13). Hiding it costs the step
	-- nothing: its two exits are its own CTA and the first bite, and neither can
	-- happen behind a modal (the scrim is a full-screen TextButton, so every PC
	-- click is `gameProcessed` and the touch EAT button is already hidden while
	-- `openPanel ~= nil`). It comes straight back when the panel closes.
	local tutorialHint = tutorial ~= nil and tutorial.hint == "eat" and state.openPanel == nil

	-- ── attention: what is buyable RIGHT NOW ─────────────────────────────
	-- Two icons in the menu answer "is there something behind me you can afford?"
	-- with a BADGE and the kit's attention breathe (Theme.Feel.Pulse), because the
	-- audience is children who may not read the labels at all (squint-test skill):
	-- a dot plus motion survives a squint, a number does not.
	-- Both predicates are the SHARED ones their own windows use, so an icon can
	-- never advertise a purchase the panel then refuses — the same one-way
	-- guarantee the upgrade station's world sign has (features/upgrades.md).
	-- Memoised on their inputs: the App re-renders at bite rate and neither
	-- balance moves per bite (calories are BANKED at the gym, gems drop on a find).
	local upgradesAffordable = React.useMemo(function()
		return LocalUpgradeTree.AnyAffordable(state.upgrades, state.calories)
	end, { state.upgrades or false, state.calories })
	-- BOOSTS only — see LocalShopService.AffordableBoostCount for why the Robux
	-- shelf is deliberately not counted.
	local boostsAffordable = React.useMemo(function()
		return LocalShopService.AffordableBoostCount(state.shop, state.gems) > 0
	end, { state.shop or false, state.gems })
	-- ⚠ Gated by PLACE, not just by affordability. BOTH rosters mount in both
	-- places — only the parent Frame's `Visible` differs — and `Theme.Feel.Pulse`
	-- repeats forever, so an ungated cue would leave TweenService driving 2-3
	-- UIScales on invisible buttons for the whole session (and pop badges nobody
	-- can see). The lobby also has nothing to say about `upgradesAffordable`: the
	-- tree is RUN-scoped, so in the lobby it is always a tier-0 tree on a wiped
	-- balance (ADR-0013).
	local lobbyBoostCue = showLobby and boostsAffordable
	local gameBoostCue = showGame and boostsAffordable
	local gameUpgradeCue = showGame and upgradesAffordable

	-- ── menu ─────────────────────────────────────────────────────────────
	-- The META menu is LOBBY-only (its handlers are lobby subs); the GAME place
	-- builds its own, shorter roster from the same helper below.
	-- 8 entries at 2 columns = 4 rows (570/1080 from y 172 -> 742 ✓, the tallest
	-- form Theme.AppHud's grid arithmetic was cut for — and 8 is still 4 rows, so
	-- adding the Cakes button in 2026-08 did not change the block's height). The
	-- two social buttons sit at the END: the meta menu's order is stable across
	-- sessions and shuffling the established four would cost every returning
	-- player their muscle memory.
	-- `GroupReward` is hidden until the server says the community is CONFIGURED
	-- (SocialData.groupId ~= 0) and `InviteFriends` until `ReferralUpdate` lands —
	-- both resolved in the social view-model above.
	local menu = {
		{ name = "Pets", label = locale.T("menu-pets"), badge = false },
		{ name = "Shop", label = locale.T("menu-shop"), badge = lobbyBoostCue, pulse = lobbyBoostCue },
		{ name = "DailyRewards", label = locale.T("menu-daily"), badge = dailyBadge },
		{ name = "Codes", label = locale.T("menu-codes"), badge = false },
		{ name = "Settings", label = locale.T("menu-settings"), badge = false },
		-- Cake selection (features/cake-select.md). Appended AFTER the
		-- established five so no returning player loses the position of a button
		-- they already know, and BEFORE the two conditional social entries so it
		-- keeps a fixed slot whether or not those are present. Total menu height
		-- is unchanged in both cases: at 2 columns, 5 and 6 entries are both 3
		-- rows, 7 and 8 are both 4.
		{ name = "Cakes", label = locale.T("menu-cakes"), badge = false },
	}
	if referral ~= nil then
		table.insert(menu, { name = "InviteFriends", label = locale.T("menu-invite"), badge = false })
	end
	if groupConfigured then
		-- Badge while it is still claimable: this is a free 15-minute boost and the
		-- only thing in the menu that expires from the player's attention, not from
		-- a clock.
		table.insert(menu, {
			name = "GroupReward",
			label = locale.T("menu-group"),
			badge = groupState.claimed ~= true,
		})
	end

	-- The GAME place's menu (2026-08-13, user request). Four entries at 2 columns
	-- = 2 rows: 2*132 + 14 = 278 -> y 172..450 on the 1080 reference, clear of the
	-- checkpoint button's band at y 897 with room to spare.
	-- ⚠ `name` is THREE contracts at once: the React key, the rendered Instance
	-- Name (which is the analytics control id the kit derives automatically) and
	-- the `openPanel` value. So the squishies button stays named "Pets" — only its
	-- LABEL says Squishies (the display-only rename, features/pets.md) — and both
	-- places therefore report the same control id for the same window.
	-- Every one of these already worked in the game place and only the DOOR was
	-- missing: ShopSubs/PetSubs/PassOwnershipSubs and their client subs are all
	-- COMMON, and the panels below are not place-gated.
	-- Settings sits LAST on purpose: it was the game HUD's only button until now,
	-- but it is the one entry a player never needs mid-run, and the three added
	-- above it are the ones the pacing depends on.
	local gameMenu = {
		-- ⚠ Routed through `onToggleUpgrades`, NOT togglePanel — the hex tree is a
		-- MODAL (world blur, frozen camera, movement lock, world prompts off) owned
		-- by UpgradesSubsClient. See the dispatch in the builder below.
		{ name = "Upgrades", label = locale.T("menu-upgrades"), badge = gameUpgradeCue, pulse = gameUpgradeCue },
		{ name = "Shop", label = locale.T("menu-shop"), badge = gameBoostCue, pulse = gameBoostCue },
		{ name = "Pets", label = locale.T("menu-pets"), badge = false },
		{ name = "Settings", label = locale.T("menu-settings"), badge = false },
	}
	local hud = Theme.AppHud
	-- CELEBRATION SPLASH (features/food-burst.md). `state.celebration` carries
	-- KEYS; they are resolved here, once per state change rather than on every
	-- one of the HUD's ~14 renders per second. `localeReady` is a dep because a
	-- translator that lands while the splash is up must repaint it — and
	-- resolving a KEY is what makes that repaint safe: rerolling the phrase
	-- here would swap the words mid-animation.
	local celebration = if showGame and type(state.celebration) == "table" then state.celebration else nil
	local celebrationCheerKey = if celebration then celebration.cheerKey else nil
	local celebrationSubKey = if celebration then celebration.subKey else nil
	local celebrationSeq = if celebration then celebration.seq or 0 else 0
	-- ⚠ ONE table, not two return values: useMemo hands back exactly what the
	-- factory's FIRST result is, so `local a, b = useMemo(...)` silently drops b.
	local celebrationText = React.useMemo(function()
		if celebrationCheerKey == nil then
			return nil
		end
		return {
			cheer = locale.T(`announce-{celebrationCheerKey}`),
			sub = if celebrationSubKey ~= nil then locale.T(`announce-{celebrationSubKey}`) else nil,
		}
	end, { celebrationCheerKey or false, celebrationSubKey or false, state.localeReady or false })
	local celebrationCheer = if celebrationText then celebrationText.cheer else nil
	local celebrationSub = if celebrationText then celebrationText.sub else nil
	-- Safe area handed to the FULL-BLEED overlays as viewport fractions (see
	-- rootSize): they are Size (1,1) of the root, so a fraction is exact.
	-- ⚠ Both guards are load-bearing, and one of them was found the hard way.
	-- `Camera.ViewportSize` is legitimately DEGENERATE for the first frames of a
	-- session (measured (1,1) in a Studio playtest), and `inset / 1` is a
	-- fraction of 58 — which parked the hex tree's calories chip 40,000 px down
	-- the screen until the first refit. Below the threshold the safe area is
	-- simply unknown, and 0 is the only honest answer; the cap bounds any future
	-- surprise to something a player could still find.
	local haveViewport = viewportY > 1
	local safeTop01 = if haveViewport then math.min(topInset / viewportY, 0.5) else 0
	local safeBottom01 = if haveViewport then math.min(touchReserve / viewportY, 0.5) else 0
	-- The widest interactive panel keeps its title and close control below the
	-- Roblox topbar. Preserve the ordinary full-screen fit when it already fits;
	-- otherwise cap its height to the usable region and rebuild width from the
	-- locked aspect. Only the panel is constrained; the scrim stays full-bleed.
	local matchViewport = rootSize()
	local matchViewportY = math.max(matchViewport.Y, 1)
	local matchTopPx = math.clamp(topInset, 0, math.max(matchViewportY - 1, 0))
	local matchUsableY = math.max(matchViewportY - matchTopPx, 1)
	local matchBaseFit = calculateScale(
		Theme.MatchmakingLayout.PanelAspect,
		Theme.MatchmakingLayout.PanelMaxViewportFraction,
		Vector2.new(math.max(matchViewport.X, 1), matchViewportY)
	)
	local matchHeightPx = math.min(
		matchBaseFit.Y * matchViewportY,
		matchUsableY * Theme.MatchmakingLayout.SafeRegionMaxFraction
	)
	local matchSize = Vector2.new(
		matchHeightPx * Theme.MatchmakingLayout.PanelAspect / math.max(matchViewport.X, 1),
		matchHeightPx / matchViewportY
	)
	local matchCenterY = (matchTopPx + matchUsableY / 2) / matchViewportY
	-- Icon GRID: buttons flow left-to-right, wrapping after MenuColumns, so the
	-- buttons form a compact block instead of a column running to the bottom of
	-- the screen. Cell size/padding are fractions of the frame, all derived from
	-- the ROSTER LENGTH — adding or removing an entry needs no constant here
	-- (which is what let the two social buttons take the lobby from 5 entries to
	-- 7, i.e. 3 rows to 4, with no layout edit).
	-- ONE builder for BOTH places since 2026-08-13: the game place grew from a
	-- single Settings button to a four-entry roster, and a second hand-rolled
	-- grid would have been a second copy of this arithmetic to keep in step.
	local menuColumns = math.max(hud.MenuColumns or 1, 1)
	local function menuBlock(items): (any, UDim2)
		local rows = math.ceil(#items / menuColumns)
		local totalHeight = hud.MenuButtonHeight * rows + hud.MenuGap * (rows - 1)
		local totalWidth = hud.MenuButtonWidth * menuColumns + hud.MenuGapX * (menuColumns - 1)
		local children = {
			Layout = React.createElement("UIGridLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				FillDirectionMaxCells = menuColumns,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = Enum.VerticalAlignment.Top,
				SortOrder = Enum.SortOrder.LayoutOrder,
				CellSize = UDim2.fromScale(hud.MenuButtonWidth / totalWidth, hud.MenuButtonHeight / totalHeight),
				CellPadding = UDim2.fromScale(hud.MenuGapX / totalWidth, hud.MenuGap / totalHeight),
			}),
		}
		for index, item in ipairs(items) do
			-- Bare icon + label-below, no background (HudMenuButton). The button
			-- fills its grid cell (biggest tap area); UIGridLayout controls cell
			-- size, so no explicit size here.
			children[item.name] = React.createElement(Components.HudMenuButton, {
				name = item.name,
				icon = hud.MenuIcons[item.name] or hud.MenuIconPlaceholder,
				label = item.label,
				badge = item.badge,
				-- Attention breathe, on the same fact as the badge (one predicate,
				-- two channels — motion is what reaches a player who never reads
				-- the label, and it survives the squint test the dot alone fails
				-- at icon size).
				pulse = item.pulse,
				-- Under a modal, this button is unreachable by pointer but NOT by a
				-- D-pad — see the component header. Without this a controller could
				-- reach the (breathing) Upgrades icon through the shop's own scrim.
				selectable = modalBusy() == nil,
				layoutOrder = index,
				zIndex = 1,
				onActivated = function()
					-- The hex tree is a MODAL overlay (world blur, frozen camera,
					-- movement lock, world prompts off) owned by UpgradesSubsClient, so
					-- the Upgrades entry MUST route through onToggleUpgrades — falling
					-- through to togglePanel would open the tree with none of that
					-- wiring. LIVE since 2026-08-13 (the game roster); it was a dead
					-- guard for the two years the tree had no button at all.
					if item.name ~= "Upgrades" then
						togglePanel(item.name)
						return
					end
					-- `onToggleUpgrades` TOGGLES, so it must carry its own modal
					-- guard rather than borrowing togglePanel's: closing the tree
					-- from its own button is legal, opening it over ANOTHER panel is
					-- not (that would swap `openPanel` out from under a window the
					-- player never closed, and arm the camera freeze + movement lock
					-- + world-prompt disable behind it).
					local blocking = modalBusy()
					if blocking ~= nil and blocking ~= "Upgrades" then
						Log.Info("AppRoot", `HUD 'Upgrades' press ignored — '{blocking}' is already open`)
						return
					end
					if callbacks.onToggleUpgrades then
						callbacks.onToggleUpgrades()
					else
						-- R8. NOT "use the checkpoint prompt instead": every early
						-- return in UpgradesSubsClient.Start happens BEFORE both the
						-- SetCallbacks and the PromptTriggered connect, so a missing
						-- callback means the prompt is dead too and the tree cannot
						-- be opened at all in this place.
						Log.Once(
							"AppRoot",
							"no-toggle-upgrades",
							"Upgrades HUD button pressed but onToggleUpgrades is not registered — "
								.. "UpgradesSubsClient aborted its Start (see its own warn: UpgradesUiData "
								.. "config/state or PlayerControl missing). The checkpoint prompt is dead "
								.. "for the same reason: the upgrade tree cannot be opened AT ALL here."
						)
					end
				end,
			})
		end
		return children, UDim2.fromScale(totalWidth, totalHeight)
	end
	local menuChildren, menuSize = menuBlock(menu)
	local gameMenuChildren, gameMenuSize = menuBlock(gameMenu)
	-- ⚠ The COMBINED development build maps BOTH partition markers, so both menus
	-- render at once and would sit in the same slot. They already collided there
	-- (the game place's lone Settings button landed on top of the lobby's first
	-- cell); with a four-entry game roster that is four buttons buried under
	-- eight, in the one build Studio Play Solo actually runs. Stack instead: the
	-- game block drops below the lobby block, so both rosters stay reachable.
	-- A PUBLISHED place maps exactly one marker, so this offset is always 0 live —
	-- which is why it is computed from the lobby block's own measured height
	-- rather than added to Theme as a second position constant. ⚠ In the dev
	-- build the offset therefore MOVES when the lobby roster gains a row (the two
	-- social buttons arrive on their own server pushes): the game block visibly
	-- drops one row mid-session. Correct, not fixed — and dev-only.
	local gameMenuY = hud.MenuPosition.Y
	if showLobby then
		gameMenuY += menuSize.Y.Scale + hud.MenuGap
	end

	-- ── HUD ──────────────────────────────────────────────────────────────
	-- These all live in the `Hud` layer built at the bottom of this function,
	-- which is inset from the top by Roblox's topbar. Positions here are in the
	-- SAME coordinate space the root ScreenGui used to provide (it was inset;
	-- it is full-bleed now so modals can dim the whole screen — UiRoot), so
	-- nothing in this table had to move.
	local hudChildren = {
		CaloriesPill = React.createElement("Frame", {
			Name = "CaloriesPill",
			Visible = showGame,
			Position = UDim2.fromScale(hud.PillPosition.X, hud.PillPosition.Y),
			Size = UDim2.fromScale(0.5, hud.PillHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = hud.PillAspect }),
			Pill = React.createElement(Components.StatPill, {
				value = formatNumber(state.calories),
				-- Registry art, not StatPill's legacy hand-vectored `bolt` shape (the
				-- game HUD was the last thing still drawing those). Names live in
				-- Theme.AppHud.PillIcons so the shop's balance row matches.
				iconImage = Theme.Icon(hud.PillIcons.Calories),
				valueGradient = Theme.Hud.EnergyTextGradient,
				valueOutline = Theme.Hud.EnergyTextOutline,
				zIndex = 1,
			}),
		}),
		GemsPill = React.createElement("Frame", {
			Name = "GemsPill",
			Visible = showGame,
			Position = UDim2.fromScale(hud.SecondPillPosition.X, hud.SecondPillPosition.Y),
			Size = UDim2.fromScale(0.5, hud.PillHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = hud.PillAspect }),
			Pill = React.createElement(Components.StatPill, {
				value = formatNumber(state.gems),
				-- Was StatPill's legacy `coin` shape: the GEMS pill wore a COIN while
				-- the shop showed the same balance beside a GEM.
				iconImage = Theme.Icon(hud.PillIcons.Gems),
				valueGradient = Theme.Hud.CoinTextGradient,
				valueOutline = Theme.Hud.CoinTextOutline,
				zIndex = 1,
			}),
		}),
		Menu = React.createElement("Frame", {
			Name = "Menu",
			-- Meta/progression handlers live in the lobby partition. The game place
			-- keeps only its cake HUD; exposing this menu there creates dead remotes.
			Visible = showLobby,
			Position = UDim2.fromScale(hud.MenuPosition.X, hud.MenuPosition.Y),
			Size = menuSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, menuChildren),
		-- The GAME place's menu: UPGRADES / SHOP / SQUISHIES / SETTINGS (2026-08-13,
		-- user request). Same builder, same left column, same cell size as the
		-- lobby's — it simply carries the four entries whose whole stack is COMMON,
		-- and it replaces the lone `GameSettingsBtn` that used to sit in this slot.
		-- It is a SEPARATE frame from the meta menu above rather than a branch
		-- inside it, because that frame is `Visible = showLobby` for its lobby-only
		-- handlers; these four have server owners in both places
		-- (ShopSubs / PetSubs / PassOwnershipSubs / SettingsSubs, all COMMON).
		-- Directly under the two stat pills, which is free in the game HUD — the
		-- cake bar is top-centre and the top-right corner is deliberately empty.
		GameMenu = React.createElement("Frame", {
			Name = "GameMenu",
			Visible = showGame,
			Position = UDim2.fromScale(hud.MenuPosition.X, gameMenuY),
			Size = gameMenuSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, gameMenuChildren),
		CakeBar = React.createElement(Components.CakeBar, {
			name = "CakeBar",
			visible = showGame and cakeVisible,
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.fromScale(hud.CakeBarPosition.X, hud.CakeBarPosition.Y),
			size = UDim2.fromScale(0.5, hud.CakeBarHeight),
			progress01 = cakeFill,
			text = cakeText,
			mode = cakeMode,
			rare = state.cake ~= nil and state.cake.rareKind ~= nil,
			zIndex = 1,
		}),
		BellyBar = if showGame
			then React.createElement(Components.BellyBar, {
				name = "BellyBar",
				anchorPoint = Vector2.new(0.5, 1),
				position = UDim2.fromScale(hud.BellyPosition.X, hud.BellyPosition.Y),
				size = UDim2.fromScale(0.5, hud.BellyHeight),
				fill01 = bellyFill,
				text = bellyText,
				glutton = glutton,
				zIndex = 1,
			})
			else nil,
		-- Return to the checkpoint platform (gym) to burn fat — also the F key
		-- (BodySubsClient). Sits just above the belly bar.
		CheckpointBtn = React.createElement("Frame", {
			Name = "CheckpointBtn",
			-- Only shown when the player is away from the checkpoint platform
			-- (proximity fed by BodySubsClient); hidden once you are on/at it.
			Visible = showGame and state.checkpointFar ~= false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(hud.CheckpointPosition.X, hud.CheckpointPosition.Y),
			Size = UDim2.fromScale(0.3, hud.CheckpointHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = Theme.CheckpointButton.AspectRatio,
			}),
			Button = React.createElement(Components.Button, {
				name = "Return",
				style = Theme.CheckpointButton,
				text = locale.T("hud-burn-fat"),
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = 1,
				-- Tutorial step 3: breathe once the belly hits 90% so the button
				-- that ends the eating phase is impossible to miss. The pulse
				-- rides the Button's own UIScale (ADR-0006) — see its header.
				pulse = tutorial ~= nil and tutorial.pulseCheckpoint == true,
				onActivated = function()
					if callbacks.onReturnCheckpoint then
						callbacks.onReturnCheckpoint()
					end
				end,
			}),
		}),
		-- Touch hold-to-eat button (bottom-right thumb zone). Press-and-hold to
		-- keep eating the cake in front of you; a tap = one bite. Replaces the
		-- old "touch anywhere = eat" so the joystick never eats (Task 3).
		EatButton = React.createElement(Components.EatButton, {
			name = "EatButton",
			visible = eatButtonVisible,
			buttonText = locale.T("eat-button"),
			zIndex = 3,
			-- The Hud layer's bottom edge IS the viewport's, so a pixel offset
			-- from the bottom is exact here. Its old Y was a viewport fraction
			-- tuned at one aspect; Roblox's jump button is sized off the SHORTER
			-- axis, so the two only cleared on a wide window.
			bottomReservePx = touchReserve,
			onPressStart = function(input)
				if callbacks.onEatDown then
					callbacks.onEatDown(input)
				end
			end,
			onPressEnd = function(input)
				if callbacks.onEatUp then
					callbacks.onEatUp(input)
				end
			end,
		}),
		Combo = React.createElement(Components.ComboBadge, {
			name = "Combo",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(hud.ComboPosition.X, hud.ComboPosition.Y),
			size = UDim2.fromScale(0.3, hud.ComboHeight),
			combo = state.combo and state.combo.value or 0,
			intensity01 = state.combo and state.combo.intensity or 0,
			visible = showGame and state.combo ~= nil and (state.combo.value or 0) > 1,
			zIndex = 1,
		}),
		-- ⚠ The boss PRIZE CARD ("FIGHTING FOR <squishy>") lived here until
		-- 2026-08-07 and was REMOVED by request — what a cleared cake pays out is
		-- a surprise again. Nothing replaced it: the top-right corner during a
		-- boss is now deliberately empty.
		Announce = React.createElement(Components.AnnounceBanner, {
			name = "Announce",
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.fromScale(hud.AnnouncePosition.X, hud.AnnouncePosition.Y),
			size = UDim2.fromScale(0.6, hud.AnnounceHeight),
			text = if showGame and type(state.announceKey) == "string"
				then locale.T(`announce-{state.announceKey}`)
				else nil,
			zIndex = 2,
		}),
	}

	return React.createElement("Frame", {
		Name = "App",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ref = appRef, -- read for its AbsoluteSize (safe-area fractions)
	}, {
		-- The root gui is FULL-BLEED so panels/overlays and their scrims cover the
		-- whole screen including the topbar strip (UiRoot). The HUD must still not
		-- slide UNDER the topbar, so it gets its own layer offset down by the
		-- resolved safe-area inset and shortened by the same amount.
		-- ⚠ 2026-08-09: this is NO LONGER the identity transform the 2026-07-30
		-- note claimed. `topInset` is now max(GetGuiInset, TopbarInset.Max.Y) plus
		-- Theme.SafeArea.TopPadPx, so every HUD element moved DOWN by the pad (and
		-- by more on any client whose unibar is taller than the legacy inset).
		-- That is the point: the old margin was a viewport FRACTION and collapsed
		-- to ~8 px on a phone.
		Hud = React.createElement("Frame", {
			Name = "Hud",
			Position = UDim2.new(0, 0, 0, topInset),
			Size = UDim2.new(1, 0, 1, -topInset),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- The tutorial comic is a full-screen modal that swallows input, so
			-- the HUD under it is neither usable nor informative — and its own
			-- scrim is translucent enough that anything left on would glow
			-- through it. Hiding the LAYER (rather than each element) is what
			-- keeps a future HUD addition from leaking into the intro. The
			-- touch EAT button is ALSO gated on its own `visible` above: that
			-- one has to flip `enabled` so a hold in progress gets released
			-- (Interaction drops its handlers with `enabled`, not with an
			-- ancestor's Visible).
			Visible = not tutorialSlidesUp,
			ZIndex = 1,
		}, hudChildren),

		-- ── celebration splash (zIndex 30) ───────────────────────────────
		-- features/food-burst.md. A SIBLING of `Hud`, not a child of it: the
		-- splash is full-bleed and centres itself on the whole screen, while
		-- `Hud` is shortened by `topInset`, which would bias it downward by the
		-- unibar height on exactly the phones where the least room exists.
		-- zIndex 30 sits in the free 4-39 band — over every HUD element
		-- (1-3) and under the modal scrim (40), so an open panel still buries
		-- it rather than a "LAYER DEMOLISHED!" splash landing across the shop.
		-- ⚠ The food confetti itself is NOT here: it lives in its own
		-- ScreenGui at DisplayOrder 99, one BELOW UiRoot, so the sprites fly
		-- behind this banner and the words stay readable (FoodBurst.lua).
		-- ⚠ Suppressed under the tutorial comic for the same reason `Hud` is
		-- (`Visible = not tutorialSlidesUp` below): the comic's own dim is only
		-- ~76% opaque, so a gold splash behind it reads as a leak rather than a
		-- celebration. Being a SIBLING of `Hud` means that gate does not reach
		-- it, so it is re-applied here.
		Celebration = React.createElement(Components.CelebrationBanner, {
			name = "CelebrationBanner",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(hud.CelebrationPosition.X, hud.CelebrationPosition.Y),
			size = UDim2.fromScale(hud.CelebrationWidth, hud.CelebrationHeight),
			cheerText = if tutorialSlidesUp then nil else celebrationCheer,
			subText = celebrationSub,
			-- Identity, not value: two identical rolls back to back must still
			-- replay the slam-in.
			seq = celebrationSeq,
			zIndex = 30,
		}),

		-- ── modal scrim (zIndex 40, under every panel) ───────────────────
		-- Dims the world + HUD behind any open panel (UX audit 2026-08-01:
		-- panels floated over the full-brightness scene and the colorful HUD
		-- out-shouted panel content in every measurement). Also the
		-- tap-outside-to-close surface. The Upgrades overlay is excluded —
		-- HexTreeOverlay brings its own full-screen scrim and two dims stack.
		Scrim = React.createElement("TextButton", {
			Name = "Scrim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.PanelScrim.Color,
			BackgroundTransparency = Theme.PanelScrim.Transparency,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			-- Pointer-only tap-outside surface. Controller users close through the
			-- panel X; the full-screen background must not steal selection from it.
			Selectable = false,
			Visible = state.openPanel ~= nil and state.openPanel ~= "Upgrades",
			ZIndex = 40,
			-- Per-panel dispatch, NOT a blanket Open(nil): closing is a
			-- CONTRACT (Matchmaking must cancel the server session, Codes
			-- must clear its status) and the scrim is the easiest close
			-- gesture, so it must run the same closer the panel's X does.
			[React.Event.MouseButton1Click] = function()
				if state.openPanel == "Matchmaking" then
					closeMatchmaking()
				elseif state.openPanel == "Codes" then
					closeCodes()
				else
					closeShop()
				end
			end,
		}),

		-- ── panels (zIndex 50) ───────────────────────────────────────────
		Pets = React.createElement(Components.PetsInspectPanel, {
			name = "PetsPanel",
			title = locale.T("title-pets"),
			visible = state.openPanel == "Pets",
			size = UDim2.fromScale(petsScale.X, petsScale.Y),
			zIndex = 50,
			pets = petsProps.pets,
			equipped = petsProps.equipped,
			equippedCount = petsProps.equippedCount,
			maxEquipped = petsProps.maxEquipped,
			selectedId = petsProps.selectedId,
			selectedPet = petsProps.selectedPet,
			equipText = locale.T("btn-equip"),
			unequipText = locale.T("btn-unequip"),
			selectText = locale.T("label-select-pet"),
			equipBestText = locale.T("btn-equip-best"),
			onPetActivated = function(petId)
				setSelectedPetId(petId)
			end,
			onEquipToggle = function()
				if selectedPetId and callbacks.onEquipPet then
					callbacks.onEquipPet(selectedPetId, petsProps.equipped[selectedPetId] ~= true)
				end
			end,
			onEquipBest = function()
				if not callbacks.onEquipPet then
					return
				end
				-- Fill free slots with the best unequipped pets by rarity.
				local free = petsProps.maxEquipped - petsProps.equippedCount
				local candidates = {}
				for _, pet in ipairs(petsProps.pets) do
					if petsProps.equipped[pet.id] ~= true then
						table.insert(candidates, pet)
					end
				end
				table.sort(candidates, function(a, b)
					return (RARITY_RANK[a.rarity] or 0) > (RARITY_RANK[b.rarity] or 0)
				end)
				for k = 1, math.min(free, #candidates) do
					callbacks.onEquipPet(candidates[k].id, true)
				end
			end,
			onSort = function()
				setSortByRarity(not sortByRarity)
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		Upgrades = React.createElement(Components.HexTreeOverlay, {
			name = "UpgradesOverlay",
			visible = state.openPanel == "Upgrades",
			zIndex = 60,
			treeKey = currentTree,
			nodes = upgradeTree.nodes,
			nodeWidth = upgradeTree.nodeWidth,
			nodeHeight = upgradeTree.nodeHeight,
			caloriesText = formatNumber(state.calories),
			-- The overlay is FULL-BLEED (its scrim must dim the topbar strip),
			-- so its own edge controls carry the safe area: the calories chip and
			-- the Close X sat under Roblox's unibar, and the zoom stack sat under
			-- the touch jump button. Plain numbers — a table here would reconcile
			-- the whole tree at HUD re-render rate.
			topInset01 = safeTop01,
			bottomReserve01 = safeBottom01,
			onNodeActivated = function(action)
				if action.type == "open" then
					setTreeStack(function(stack)
						local copy = table.clone(stack)
						table.insert(copy, action.id)
						return copy
					end)
				elseif action.type == "back" then
					setTreeStack(function(stack)
						if #stack <= 1 then
							return stack
						end
						local copy = table.clone(stack)
						table.remove(copy)
						return copy
					end)
				elseif action.type == "buy" and callbacks.onBuyUpgrade then
					callbacks.onBuyUpgrade(action.id)
				end
			end,
			onClose = function()
				-- Route through the subscription (blur off + unbind E); it calls
				-- AppRoot.Open(nil). Fallback direct-close if not wired yet.
				if callbacks.onCloseUpgrades then
					callbacks.onCloseUpgrades()
				else
					AppRoot.Open(nil)
				end
			end,
		}),
		DailyRewards = React.createElement(Components.RewardsPanel, {
			name = "DailyRewardsPanel",
			title = locale.T("title-daily-rewards"),
			visible = state.openPanel == "DailyRewards",
			size = UDim2.fromScale(wideScale.X, wideScale.Y),
			zIndex = 50,
			cards = dailyCards,
			footerText = dailyFooter,
			onClaim = function(day)
				if callbacks.onClaimDaily then
					callbacks.onClaimDaily(day)
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		Shop = React.createElement(Components.ShopPanel, {
			name = "ShopPanel",
			title = locale.T("title-shop"),
			visible = state.openPanel == "Shop",
			size = UDim2.fromScale(shopScale.X, shopScale.Y),
			zIndex = 50,
			tabs = shopTabs,
			-- The shop shows what you can spend. Gem packs with no balance
			-- anchor next to them are just numbers.
			balances = shopBalances,
			onActivated = onShopActivated,
			-- MUST stay memoised. ShopPanel is React.memo'd on the assumption
			-- that every prop AppRoot hands it is stable; an inline closure
			-- here fails the shallow compare on every one of the HUD's ~14
			-- re-renders per second and reconciles the shop's ~700-element
			-- tree behind a hidden panel. See ShopPanel's footer note.
			onTabChanged = onShopTabChanged,
			onClose = closeShop,
		}),
		Matchmaking = React.createElement(Components.MatchmakingPanel, {
			name = "MatchmakingPanel",
			title = locale.T("match-title"),
			visible = showLobby and state.openPanel == "Matchmaking" and matchmaking ~= nil,
			position = UDim2.fromScale(0.5, matchCenterY),
			size = UDim2.fromScale(matchSize.X, matchSize.Y),
			zIndex = 50,
			sessionKey = matchmaking and matchmaking.sessionKey or false,
			busy = matchmaking ~= nil and matchmaking.busy == true,
			statusText = matchStatusText,
			error = matchErrorText,
			errorText = locale.T("match-error-start"),
			difficultyTitle = locale.T("match-difficulty-heading"),
			playersTitle = locale.T("match-players-heading"),
			difficultyOptions = difficultyOptions,
			playerCounts = playerCountOptions,
			-- The cake setup rail (features/cake-select.md). Presentation only: the
			-- same view models and the same callback the Cakes panel uses, so the
			-- two surfaces can never disagree about what is selected. It does NOT
			-- enter the panel's session state and does NOT ride the queue request
			-- — `onStart` still sends exactly difficulty + party size.
			-- The panel title already gives the verb; the compact rail needs only
			-- the one-word group label (all 16 locales already carry this key).
			cakeTitle = locale.T("match-cake-heading"),
			cakeOptions = cakeOptions,
			onSelectCake = onSelectCake,
			-- The selector opens on Easy / 1 Player (MatchConfig.defaults) so a solo
			-- run is ONE tap. The panel ignores a default it is not offering — the
			-- party row is capped by the pad's own maxPlayers.
			defaultDifficulty = MatchConfig.defaults.difficulty,
			defaultPlayers = MatchConfig.defaults.playerCount,
			startText = locale.T("match-start"),
			busyText = locale.T("match-starting"),
			unselectedStatusText = locale.T("match-status-choose"),
			partialStatusText = locale.T("match-status-partial"),
			readyStatusText = locale.T("match-status-ready", {
				current = matchCurrentPlayers,
				max = matchmakingMaxPlayers,
			}),
			busyStatusText = locale.T("match-status-starting"),
			onStart = function(difficulty, maxPlayers)
				if current.openPanel ~= "Matchmaking" then
					return
				end
				if callbacks.onConfigureMatch then
					callbacks.onConfigureMatch(difficulty, maxPlayers)
				end
			end,
			-- Observation only — the panel already owns the selection state.
			-- Neither choice reaches the server before START, so this is the
			-- one place they can be recorded (docs/features/analytics.md).
			-- `isDefault` is true for the preselection the panel applies when a
			-- session opens; the beat fires either way (the flow step must not go
			-- dark for a player who just presses START), and whether a finger
			-- actually landed on a choice is carried by the kit's press counting.
			onSelectDifficulty = function(difficulty, isDefault)
				if current.openPanel ~= "Matchmaking" then
					return
				end
				if callbacks.onMatchDifficultyPick then
					callbacks.onMatchDifficultyPick(difficulty, isDefault == true)
				end
			end,
			onSelectPlayers = function(maxPlayers, isDefault)
				if current.openPanel ~= "Matchmaking" then
					return
				end
				if callbacks.onMatchPartyPick then
					callbacks.onMatchPartyPick(maxPlayers, isDefault == true)
				end
			end,
			onClose = closeMatchmaking,
		}),
		-- Cake selection (features/cake-select.md). Lobby-only like the two social
		-- panels below, but deliberately NOT gated on its server push: cake #1 is
		-- always available, so this is a usable chooser on the first frame and
		-- the push only ever corrects it. The scrim's `else closeShop()` branch
		-- already closes it correctly (closeShop is a bare Open(nil)) — this panel
		-- has no close-time obligation, so it needs no named closer.
		Cakes = React.createElement(Components.CakeSelectPanel, {
			name = "CakeSelectPanel",
			title = locale.T("title-cakes"),
			visible = showLobby and state.openPanel == "Cakes",
			-- Same 1000x600 fit as the rewards window, so it rides the existing
			-- `wideScale` rather than adding a third coupled scale site. The
			-- coupling is documented on Theme.CakeSelectLayout.
			size = UDim2.fromScale(wideScale.X, wideScale.Y),
			zIndex = 50,
			cakes = cakeOptions,
			onSelect = onSelectCake,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		-- Invite Friends. The button asks Roblox for the native invite prompt
		-- (SocialSubsClient owns the SocialService call — R4); the gems are paid
		-- server-side when an invited account actually joins, which is why the
		-- status line reports a COUNT rather than a claim.
		InviteFriends = React.createElement(Components.SocialPanel, {
			name = "InvitePanel",
			title = locale.T("title-invite"),
			visible = showLobby and state.openPanel == "InviteFriends" and referral ~= nil,
			size = UDim2.fromScale(socialScale.X, socialScale.Y),
			zIndex = 50,
			iconName = "UiFriend",
			headlineText = locale.T("invite-headline", { n = formatNumber(referralRewardGems) }),
			bodyText = locale.T("invite-body", { n = formatNumber(referralRewardGems) }),
			statusText = inviteStatusText,
			statusKind = inviteStatusKind,
			buttonText = locale.T("invite-button"),
			onActivated = function()
				if callbacks.onInviteFriends then
					callbacks.onInviteFriends()
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		-- Like + join the community -> a 15-minute boost. The CTA goes dead while a
		-- claim is counting down and stays dead once claimed: the reward is
		-- one-time, and a live button over "Already claimed" is a lie.
		GroupReward = React.createElement(Components.SocialPanel, {
			name = "GroupRewardPanel",
			title = locale.T("title-group-reward"),
			visible = showLobby and state.openPanel == "GroupReward" and groupConfigured,
			size = UDim2.fromScale(socialScale.X, socialScale.Y),
			zIndex = 50,
			iconName = "UiHeart",
			headlineText = locale.T("group-headline"),
			bodyText = locale.T("group-body"),
			statusText = groupStatusText,
			statusKind = groupStatusKind,
			buttonText = locale.T("group-button"),
			buttonEnabled = not groupClaimed and not groupPending,
			onActivated = function()
				if callbacks.onClaimGroupReward then
					callbacks.onClaimGroupReward()
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		Codes = React.createElement(Components.CodesPanel, {
			name = "CodesPanel",
			title = locale.T("title-codes"),
			visible = state.openPanel == "Codes",
			size = UDim2.fromScale(codesScale.X, codesScale.Y),
			zIndex = 50,
			value = codeInput,
			placeholder = locale.T("placeholder-code"),
			submitText = locale.T("btn-redeem"),
			onChanged = setCodeInput,
			onSubmit = function(text)
				if callbacks.onRedeem and text ~= "" then
					callbacks.onRedeem(text)
					setCodeInput("")
				end
			end,
			statusText = state.codesStatus and state.codesStatus.text or nil,
			statusKind = state.codesStatus and state.codesStatus.kind or nil,
			onClose = closeCodes,
		}),
		Settings = React.createElement(Components.SettingsPanel, {
			name = "SettingsPanel",
			title = LocalSettingsService.Title(),
			visible = state.openPanel == "Settings",
			size = UDim2.fromScale(portraitScale.X, portraitScale.Y),
			zIndex = 50,
			rows = LocalSettingsService.Rows(),
			values = state.settings or LocalSettingsService.Defaults(),
			onToggle = function(id, value)
				if callbacks.onToggleSetting then
					callbacks.onToggleSetting(id, value)
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),

		-- ── overlays ─────────────────────────────────────────────────────
		Gym = React.createElement(Components.GymOverlay, {
			name = "GymOverlay",
			active = showGame and gymActive,
			remain01 = gymRemain01,
			fatText = locale.T("gym-fat-left", { n = math.ceil(gymRemain01 * 100) }),
			buttonText = locale.T("gym-tap"),
			zIndex = 40,
			-- Full-bleed overlay with a bottom-right thumb button: same corner as
			-- Roblox's touch jump button.
			bottomReserve01 = safeBottom01,
			onTap = function()
				if callbacks.onGymTap then
					callbacks.onGymTap()
				end
			end,
		}),
		PetReveal = React.createElement(Components.PetRevealOverlay, {
			name = "PetRevealOverlay",
			reveal = if showGame then reveal else nil,
			revealCount = state.petRevealCount,
			oddsText = oddsText,
			continueText = locale.T("reveal-continue"),
			zIndex = 90,
			onDismiss = function()
				if callbacks.onDismissReveal then
					callbacks.onDismissReveal()
				end
			end,
		}),

		-- ── onboarding (features/tutorial.md) ────────────────────────────
		-- ⚠ There is no TutorialArrow here any more (2026-08-09, user request).
		-- Both world-facing steps draw the same WORLD BEAM, owned end-to-end by
		-- TutorialSubsClient — teaching one "follow the line" instead of a line
		-- and then a screen marker. `Components.HintArrow` stays in the kit
		-- unused; nothing in the app renders it.
		-- The instruction popup deliberately brings no scrim/catcher (see the
		-- component header): a full-screen Active surface would swallow the
		-- left-click it is teaching. 70 = over panels, under the reveal.
		TutorialHint = React.createElement(Components.TutorialHint, {
			name = "TutorialHint",
			visible = tutorialHint,
			size = UDim2.fromScale(hintScale.X, hintScale.Y),
			glyphMode = if IS_TOUCH then "tap" else "mouse",
			-- The touch glyph wears the SAME word as the real EAT button, from
			-- the same locale key — the hint and the control can never disagree.
			glyphLabel = locale.T("eat-button"),
			titleText = locale.T("tutorial-eat-title"),
			bodyText = if IS_TOUCH
				then locale.T("tutorial-eat-body-touch")
				else locale.T("tutorial-eat-body-pc"),
			buttonText = locale.T("tutorial-eat-ok"),
			zIndex = 70,
			onDismiss = function()
				if callbacks.onTutorialHintDismiss then
					callbacks.onTutorialHintDismiss()
				end
			end,
		}),
		-- Top of the ladder: the comic is the first thing a session shows and
		-- nothing may cover it — including a reveal that landed mid-teleport.
		TutorialSlides = React.createElement(Components.TutorialSlides, {
			name = "TutorialSlides",
			visible = tutorialSlides,
			boardSize = UDim2.fromScale(slidesScale.X, slidesScale.Y),
			titleText = locale.T("tutorial-title"),
			slides = TutorialConfig.slideIcons,
			skipText = locale.T("tutorial-skip"),
			zIndex = 95,
			onSkip = function()
				if callbacks.onTutorialSkip then
					callbacks.onTutorialSkip()
				end
			end,
		}),
	})
end

--API
-- The root element for UiRoot.Render — rendered ONCE by AppSubsClient.
function AppRoot.Element()
	return React.createElement(App)
end

return AppRoot
