--[[
	AppRoot — the ONE composed React root (ui-kit contract: a single
	UiRoot.Render; windows toggle via `openPanel` state, panels zIndex 50
	over HUD zIndex 1, hidden panels stay MOUNTED with visible = false).

	Eat the Cake composition:
	  HUD: calories + gems StatPills; LOBBY meta menu (5 icon+label buttons, no
	       bg) / GAME single Upgrades button in the same slot (the tree is
	       RUN-scoped, ADR-0013 — there is nothing to spend in the lobby);
	       CakeBar (top center), BellyBar (bottom center), ComboBadge,
	       AnnounceBanner, BossPrizeCard (boss phase)
	  Panels (zIndex 50): Pets (inspect), Shop, DailyRewards, Codes,
	       Settings, Matchmaking
	  Overlays: GymOverlay (40), Upgrades hex-tree (60, lobby UpgradeStation
	       opener pending — no HUD button), PetRevealOverlay (90)

	Data flows IN through AppRoot.Set(patch) (called by subscriptions when
	remoteUpdates arrive); user actions flow OUT through callbacks registered
	with AppRoot.SetCallbacks (wired to remotes in subscriptions, R4). Both
	work before AND after mount.

	State fields: openPanel, calories, gems, settings, daily, shop,
	group, codesStatus, cake, stomach, gym, upgrades, pets, petReveal,
	petRevealCount, combo, announceKey, matchmaking.
	Callbacks: onClaimDaily(day), onToggleSetting(id, v),
	onShopActivated(rowId), onRedeem(code), onBuyUpgrade(id),
	onEquipPet(petId, equip), onToggleUpgrades(), onGymTap(),
	onDismissReveal(), onEatDown(input), onEatUp(input), onReturnCheckpoint(),
	onConfigureMatch(difficulty, maxPlayers), onCancelMatch(),
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
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local CakeConfig = require(ReplicatedStorage.Shared.config.CakeConfig)
local MatchConfig = require(ReplicatedStorage.Shared.config.MatchConfig)
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
	matchmaking = false,
	-- Whether the player is far enough from the checkpoint platform to show the
	-- TO CHECKPOINT button (BodySubsClient proximity check). Shown by default.
	checkpointFar = true,
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
-- The currently open panel/overlay name (nil = none). Lets subscriptions defer
-- to a modal that owns shared world state (e.g. the upgrade tree disables the
-- checkpoint ProximityPrompts while open — see BodySubsClient gym-prompt gate).
function AppRoot.GetOpenPanel(): string?
	return current.openPanel
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

-- Fit a panel aspect within maxFraction of the viewport on the limiting axis.
local function calculateScale(panelAspect: number, maxFraction: number): Vector2
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	if viewportAspect >= panelAspect then
		return Vector2.new(maxFraction * panelAspect / viewportAspect, maxFraction)
	end
	return Vector2.new(maxFraction, maxFraction * viewportAspect / panelAspect)
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
	local matchScale, setMatchScale = React.useState(function()
		return calculateScale(
			Theme.MatchmakingLayout.PanelAspect,
			Theme.MatchmakingLayout.PanelMaxViewportFraction
		)
	end)
	-- The shop is landscape now (grids per category), so it needs its own fit —
	-- it used to borrow portraitScale.
	local shopScale, setShopScale = React.useState(function()
		return calculateScale(Theme.ShopLayout.PanelAspect, Theme.ShopLayout.PanelMaxViewportFraction)
	end)
	-- Topbar inset in px. The root gui is full-bleed (UiRoot), so the HUD layer
	-- applies this itself. Not a constant: it is 0 in some contexts, and it
	-- changes when the topbar shows/hides.
	local topInset, setTopInset = React.useState(function()
		return GuiService:GetGuiInset().Y
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
	-- refit below: the inset changes on its own signal (the topbar can hide), and
	-- the refit's per-panel scales do not depend on it.
	React.useEffect(function()
		local function syncInset()
			setTopInset(GuiService:GetGuiInset().Y)
		end
		syncInset()
		local connection = GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(syncInset)
		return function()
			connection:Disconnect()
		end
	end, {})

	-- Viewport re-fit (kit checklist: aspect held at any window size).
	React.useEffect(function()
		local viewportConnection, cameraConnection
		local function refit()
			setTopInset(GuiService:GetGuiInset().Y)
			setPortraitScale(calculateScale(Theme.Layout.PanelAspect, Theme.Layout.PanelMaxViewportFraction))
			setWideScale(calculateScale(Theme.RewardsLayout.PanelAspect, Theme.RewardsLayout.PanelMaxViewportFraction))
			setCodesScale(calculateScale(Theme.CodesLayout.PanelAspect, Theme.CodesLayout.PanelMaxViewportFraction))
			setPetsScale(calculateScale(Theme.PetsInspectLayout.PanelAspect, Theme.PetsInspectLayout.PanelMaxViewportFraction))
			setMatchScale(calculateScale(
				Theme.MatchmakingLayout.PanelAspect,
				Theme.MatchmakingLayout.PanelMaxViewportFraction
			))
			setShopScale(calculateScale(
				Theme.ShopLayout.PanelAspect,
				Theme.ShopLayout.PanelMaxViewportFraction
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

	local function togglePanel(name: string)
		AppRoot.Open(if state.openPanel == name then nil else name)
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
	local closeShop = React.useCallback(function()
		AppRoot.Open(nil)
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
		return {
			{ iconName = Theme.AppHud.PillIcons.Gems, value = formatNumber(state.gems) },
			{ iconName = Theme.AppHud.PillIcons.Calories, value = formatNumber(state.calories) },
		}
	end, { shopOpen, shopOpen and state.gems or 0, shopOpen and state.calories or 0 })
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
				table.insert(options, {
					id = id,
					label = locale.T(difficulty.labelKey),
				})
			end
		end
		return options
	end, {})
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
	end, { matchmakingMaxPlayers })
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
	-- Touch hold-to-eat button: shown only while there's cake to eat (eating /
	-- boss phases), never while the gym overlay or a panel is up (you're not
	-- eating then, and it would sit under/beside them). Touch devices only.
	local eatButtonVisible = showGame
		and IS_TOUCH
		and (cakePhase == "eating" or cakePhase == "boss")
		and not gymActive
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

	-- The squishy on offer for beating the boss. Server-decided and attached to
	-- this player's cycle update while the fight is live (features/cake-cycle.md);
	-- it clears on win/loss, so the card's lifetime is the fight's.
	local bossPrize = React.useMemo(function()
		local cake = state.cake
		return if type(cake) == "table" then LocalPetsService.BuildPrize(cake.pendingPet) else nil
	end, { (state.cake ~= nil and state.cake.pendingPet ~= nil and state.cake.pendingPet.petId) or false })

	-- ── menu ─────────────────────────────────────────────────────────────
	-- The META menu is LOBBY-only (its handlers are lobby subs). UPGRADES is NOT
	-- in it any more (2026-07-30, by request): the tree is RUN-scoped (ADR-0013),
	-- so there is nothing to spend in the lobby — a run starts at tier 0 with an
	-- empty calorie balance and buys the whole tree back inside the cake. It gets
	-- its own button in the GAME HUD below instead, which is also where it was
	-- MISSING: this frame is `Visible = showLobby`, so before this change the tree
	-- had a button in the one place it was useless and none in the one place the
	-- pacing depends on it. The authored `UpgradeStation` prompt at the game
	-- checkpoint still opens it too (features/upgrades.md).
	local menu = {
		{ name = "Pets", label = locale.T("menu-pets"), badge = false },
		{ name = "Shop", label = locale.T("menu-shop"), badge = false },
		{ name = "DailyRewards", label = locale.T("menu-daily"), badge = dailyBadge },
		{ name = "Codes", label = locale.T("menu-codes"), badge = false },
		{ name = "Settings", label = locale.T("menu-settings"), badge = false },
	}
	local hud = Theme.AppHud
	local menuCount = #menu
	-- Icon GRID: buttons flow left-to-right, wrapping after MenuColumns, so the
	-- buttons form a compact block (2 columns, currently 3 rows with the last
	-- cell empty) instead of a column running to the bottom of the screen. Cell
	-- size/padding are fractions of this frame, both derived from menuCount —
	-- adding or removing an entry needs no constant here.
	local menuColumns = math.max(hud.MenuColumns or 1, 1)
	local menuRows = math.ceil(menuCount / menuColumns)
	local menuTotalHeight = hud.MenuButtonHeight * menuRows + hud.MenuGap * (menuRows - 1)
	local menuTotalWidth = hud.MenuButtonWidth * menuColumns + hud.MenuGapX * (menuColumns - 1)
	local menuChildren = {
		Layout = React.createElement("UIGridLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = menuColumns,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
			CellSize = UDim2.fromScale(hud.MenuButtonWidth / menuTotalWidth, hud.MenuButtonHeight / menuTotalHeight),
			CellPadding = UDim2.fromScale(hud.MenuGapX / menuTotalWidth, hud.MenuGap / menuTotalHeight),
		}),
	}
	for index, item in ipairs(menu) do
		-- Bare icon + label-below, no background (HudMenuButton). The button fills
		-- its grid cell (biggest tap area); UIGridLayout controls cell size, so no
		-- explicit size here.
		menuChildren[item.name] = React.createElement(Components.HudMenuButton, {
			name = item.name,
			icon = hud.MenuIcons[item.name] or hud.MenuIconPlaceholder,
			label = item.label,
			badge = item.badge,
			layoutOrder = index,
			zIndex = 1,
			onActivated = function()
				-- DEAD BRANCH ON PURPOSE (a guard, not a live path): no menu entry is
				-- named "Upgrades" any more — the tree opens only from the checkpoint
				-- prompt. Kept because the hex tree is a MODAL overlay (world blur,
				-- frozen camera, movement lock, world prompts off) owned by
				-- UpgradesSubsClient, so anyone re-adding it to the menu MUST route
				-- through onToggleUpgrades; falling through to togglePanel would open
				-- the tree with none of that wiring.
				if item.name == "Upgrades" and callbacks.onToggleUpgrades then
					callbacks.onToggleUpgrades()
				else
					togglePanel(item.name)
				end
			end,
		})
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
			Size = UDim2.fromScale(menuTotalWidth, menuTotalHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, menuChildren),
		-- ⚠ NO Upgrades button, in EITHER place. The tree's only entry point is the
		-- authored `UpgradeStation` ProximityPrompt on the checkpoint's computer
		-- (built by MapService, opened by UpgradesSubsClient) — you are stood at the
		-- checkpoint after every belly burn anyway, so a HUD button is a second door
		-- into the same room. `onToggleUpgrades` stays on the callback table for the
		-- prompt path; nothing in the HUD calls it.
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
		-- What the boss fight is FOR. Top-right, level with the calories pill on the
		-- left (same 22px reference margin), which is the one corner nothing else
		-- uses during a boss: the top-centre band is the HP bar + announce banner,
		-- and the bottom-right is the touch EAT button.
		BossPrize = if bossPrize ~= nil
			then React.createElement(Components.BossPrizeCard, {
				name = "BossPrize",
				visible = showGame and cakePhase == "boss",
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.fromScale(hud.BossPrizePosition.X, hud.BossPrizePosition.Y),
				size = UDim2.fromScale(0.5, hud.BossPrizeHeight),
				captionText = locale.T("boss-prize-caption"),
				petName = bossPrize.petName,
				rarity = bossPrize.rarity,
				iconName = bossPrize.iconName,
				zIndex = 2,
			})
			else nil,
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
	}, {
		-- The root gui is FULL-BLEED so panels/overlays and their scrims cover the
		-- whole screen including the topbar strip (UiRoot). The HUD must still not
		-- slide UNDER the topbar, so it gets its own layer occupying exactly the
		-- region the root gui used to: offset down by the gui inset, shortened by
		-- the same amount. That is an identity transform on every HUD position
		-- above — which is the point: the inset fix moved no HUD element.
		Hud = React.createElement("Frame", {
			Name = "Hud",
			Position = UDim2.new(0, 0, 0, topInset),
			Size = UDim2.new(1, 0, 1, -topInset),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, hudChildren),

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
			onClose = closeShop,
		}),
		Matchmaking = React.createElement(Components.MatchmakingPanel, {
			name = "MatchmakingPanel",
			title = locale.T("match-title"),
			visible = showLobby and state.openPanel == "Matchmaking" and matchmaking ~= nil,
			size = UDim2.fromScale(matchScale.X, matchScale.Y),
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
				if callbacks.onConfigureMatch then
					callbacks.onConfigureMatch(difficulty, maxPlayers)
				end
			end,
			onClose = function()
				if callbacks.onCancelMatch then
					callbacks.onCancelMatch()
				end
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
			onClose = function()
				AppRoot.Open(nil)
				AppRoot.Clear("codesStatus")
			end,
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
	})
end

--API
-- The root element for UiRoot.Render — rendered ONCE by AppSubsClient.
function AppRoot.Element()
	return React.createElement(App)
end

return AppRoot
