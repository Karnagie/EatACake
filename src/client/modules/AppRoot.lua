--[[
	AppRoot — the ONE composed React root (ui-kit contract: a single
	UiRoot.Render; windows toggle via `openPanel` state, panels zIndex 50
	over HUD zIndex 1, hidden panels stay MOUNTED with visible = false).

	Eat the Cake composition:
	  HUD: calories + gems StatPills, menu column (9 buttons + badges),
	       CakeBar (top center), BellyBar (bottom center), ComboBadge,
	       AnnounceBanner
	  Panels (zIndex 50): Pets (inspect), Upgrades, Rebirth, Quests, Shop,
	       DailyRewards, TimeRewards, Codes, Settings
	  Overlays: GymOverlay (40), PetRevealOverlay (90)

	Data flows IN through AppRoot.Set(patch) (called by subscriptions when
	remoteUpdates arrive); user actions flow OUT through callbacks registered
	with AppRoot.SetCallbacks (wired to remotes in subscriptions, R4). Both
	work before AND after mount.

	State fields: openPanel, calories, gems, settings, daily, time, shop,
	group, codesStatus, cake, stomach, gym, upgrades, pets, petReveal,
	petRevealCount, rebirth, quests, combo, announceKey.
	Callbacks: onClaimDaily(day), onClaimTime(index), onToggleSetting(id, v),
	onShopActivated(rowId), onRedeem(code), onBuyUpgrade(id),
	onEquipPet(petId, equip), onDoRebirth(), onClaimQuest(id), onGymTap(),
	onDismissReveal().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local UIKit = require(ReplicatedStorage.Shared.UIKit)
local UpgradeConfig = require(ReplicatedStorage.Shared.config.UpgradeConfig)
local CakeConfig = require(ReplicatedStorage.Shared.config.CakeConfig)
local LocalRewardsService = require(script.Parent.LocalRewardsService)
local LocalSettingsService = require(script.Parent.LocalSettingsService)
local LocalShopService = require(script.Parent.LocalShopService)
local LocalPetsService = require(script.Parent.LocalPetsService)
local LocalStatsService = require(script.Parent.LocalStatsService)

local Theme = UIKit.Theme
local Components = UIKit.Components

local AppRoot = {}

local locale

-- The state bridge (module-level so subscriptions can feed it; the
-- component mirrors it into React state on change).
local current = {
	openPanel = nil,
	calories = 0,
	gems = 0,
	settings = nil,
	daily = nil,
	time = nil,
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
	rebirth = nil,
	quests = nil,
	combo = nil,
	announceKey = false,
}
local callbacks = {}
local applyState = nil -- setState captured while mounted

function AppRoot.Init(data)
	locale = data.LocaleData
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

-- ── helpers ─────────────────────────────────────────────────────────────

local function formatNumber(amount: number): string
	local text = tostring(math.floor(amount or 0))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return formatted
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

local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Secret = 6 }

-- View-model: upgrade panel rows from replicated levels + config formulas.
local function buildUpgradeRows(levels, calories: number)
	local rows = {}
	for _, id in ipairs(UpgradeConfig.order) do
		local def = UpgradeConfig.upgrades[id]
		local level = (levels and levels[id]) or 0
		local cost = LocalStatsService.NextCost(id)
		local state, buttonText
		if cost == nil then
			state = "max"
			buttonText = locale.T("btn-max")
		elseif calories < cost then
			state = "poor"
			buttonText = locale.T("price-calories", { n = formatNumber(cost) })
		else
			state = "buy"
			buttonText = locale.T("price-calories", { n = formatNumber(cost) })
		end
		table.insert(rows, {
			id = id,
			label = locale.T(def.nameKey),
			subText = locale.T("label-level-n", { n = level, cap = def.cap }),
			buttonText = buttonText,
			state = state,
		})
	end
	return rows
end

-- View-model: quest panel rows from the QuestsUpdate payload.
local function buildQuestRows(quests)
	local rows = {}
	for _, quest in ipairs(quests or {}) do
		local rewardText
		if quest.reward and quest.reward.kind == "gems" then
			rewardText = locale.T("quest-reward-gems", { n = quest.reward.amount })
		else
			rewardText = locale.T("quest-reward-egg")
		end
		local state
		if quest.claimed then
			state = "claimed"
		elseif quest.progress >= quest.target then
			state = "claim"
		else
			state = "progress"
		end
		table.insert(rows, {
			id = quest.id,
			name = locale.T(`quest-{quest.id}`),
			progress01 = math.clamp(quest.progress / math.max(1, quest.target), 0, 1),
			progressText = `{formatNumber(quest.progress)}/{formatNumber(quest.target)}`,
			rewardText = rewardText,
			buttonText = if quest.claimed then locale.T("btn-done") else locale.T("btn-claim"),
			state = state,
		})
	end
	return rows
end

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
	local rebirthScale, setRebirthScale = React.useState(function()
		return calculateScale(Theme.RebirthLayout.PanelAspect, Theme.RebirthLayout.PanelMaxViewportFraction)
	end)
	local codeInput, setCodeInput = React.useState("")
	local selectedPetId, setSelectedPetId = React.useState(nil :: string?)
	local sortByRarity, setSortByRarity = React.useState(true)
	local gymTaps, setGymTaps = React.useState(0)
	local _tick, setTick = React.useState(0)

	-- Bridge: subscriptions push state through AppRoot.Set.
	React.useEffect(function()
		applyState = setState
		setState(table.clone(current)) -- pick up pre-mount patches
		return function()
			applyState = nil
		end
	end, {})

	-- Viewport re-fit (kit checklist: aspect held at any window size).
	React.useEffect(function()
		local viewportConnection, cameraConnection
		local function refit()
			setPortraitScale(calculateScale(Theme.Layout.PanelAspect, Theme.Layout.PanelMaxViewportFraction))
			setWideScale(calculateScale(Theme.RewardsLayout.PanelAspect, Theme.RewardsLayout.PanelMaxViewportFraction))
			setCodesScale(calculateScale(Theme.CodesLayout.PanelAspect, Theme.CodesLayout.PanelMaxViewportFraction))
			setPetsScale(calculateScale(Theme.PetsInspectLayout.PanelAspect, Theme.PetsInspectLayout.PanelMaxViewportFraction))
			setRebirthScale(calculateScale(Theme.RebirthLayout.PanelAspect, Theme.RebirthLayout.PanelMaxViewportFraction))
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

	-- 1s countdown ticker while the time panel is open (live countdowns).
	-- Deps: BOOLEAN, never the raw panel name (jsdotlua nil-in-deps footgun).
	local timePanelOpen = state.openPanel == "TimeRewards"
	React.useEffect(function()
		if not timePanelOpen then
			return
		end
		local alive = true
		task.spawn(function()
			while alive do
				task.wait(1)
				if alive then
					setTick(os.clock())
				end
			end
		end)
		return function()
			alive = false
		end
	end, { timePanelOpen })

	-- Gym tap counter resets when a session starts. Keyed on SESSION
	-- IDENTITY (startedAt), not the active boolean: with a concurrent root,
	-- "result" + next "started" can batch into one render where the boolean
	-- never flips — the new session would inherit the old tap count.
	local gymActive = state.gym ~= nil and state.gym.active == true
	local gymSessionKey = (state.gym ~= nil and state.gym.startedAt) or 0
	React.useEffect(function()
		if gymActive then
			setGymTaps(0)
		end
	end, { gymSessionKey })

	local function togglePanel(name: string)
		AppRoot.Open(if state.openPanel == name then nil else name)
	end

	-- ── view-model builds ────────────────────────────────────────────────
	-- The App re-renders at bite frequency (StomachUpdate + combo). Every
	-- panel view-model is memoized on its state slice so eating doesn't
	-- rebuild pets/shop/rewards tables ~14x/s on a phone. Deps use
	-- `or false` — nil in jsdotlua dep arrays breaks the compare.
	local rewardCards = React.useMemo(function()
		local dailyCards, dailyFooter = LocalRewardsService.BuildDailyCards(state.daily)
		local timeCards, timeFooter = LocalRewardsService.BuildTimeCards(state.time)
		return { dailyCards = dailyCards, dailyFooter = dailyFooter, timeCards = timeCards, timeFooter = timeFooter }
	end, { state.daily or false, state.time or false, _tick })
	local dailyCards, dailyFooter = rewardCards.dailyCards, rewardCards.dailyFooter
	local timeCards, timeFooter = rewardCards.timeCards, rewardCards.timeFooter
	local dailyBadge = state.daily ~= nil and state.daily.claimable == true
	local timeBadge = LocalRewardsService.AnyTimeClaimable(state.time)

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

	local upgradeRows = React.useMemo(function()
		return buildUpgradeRows(state.upgrades, state.calories)
	end, { state.upgrades or false, state.calories })
	local questRows = React.useMemo(function()
		return buildQuestRows(state.quests)
	end, { state.quests or false })
	local shopSections = React.useMemo(function()
		return LocalShopService.BuildSections(state.shop, state.group)
	end, { state.shop or false, state.group or false })
	local oddsText = React.useMemo(LocalPetsService.OddsText, {})

	local questsBadge = false
	for _, row in ipairs(questRows) do
		if row.state == "claim" then
			questsBadge = true
			break
		end
	end

	local cakeFill, cakeText, cakeMode = cakeBarModel(state.cake)
	local stomach = state.stomach
	local capacity = stomach and math.max(1, stomach.capacity or 1) or 1
	local bellyFill = stomach and math.clamp((stomach.fill or 0) / capacity, 0, 1) or 0
	local glutton = stomach ~= nil and stomach.glutton == true
	local bellyText = if stomach == nil
		then ""
		elseif glutton then locale.T("belly-glutton")
		else locale.T("belly-label", { fill = math.floor(stomach.fill or 0), cap = math.floor(capacity) })

	local rebirth = state.rebirth
	local canRebirth = rebirth ~= nil
		and rebirth.nextCost ~= nil
		and state.calories >= rebirth.nextCost

	local reveal = if type(state.petReveal) == "table" then LocalPetsService.BuildReveal(state.petReveal) else nil

	-- ── menu ─────────────────────────────────────────────────────────────
	local menu = {
		{ name = "Pets", label = locale.T("menu-pets"), badge = false },
		{ name = "Upgrades", label = locale.T("menu-upgrades"), badge = false },
		{ name = "Rebirth", label = locale.T("menu-rebirth"), badge = canRebirth },
		{ name = "Quests", label = locale.T("menu-quests"), badge = questsBadge },
		{ name = "Shop", label = locale.T("menu-shop"), badge = false },
		{ name = "DailyRewards", label = locale.T("menu-daily"), badge = dailyBadge },
		{ name = "TimeRewards", label = locale.T("menu-time"), badge = timeBadge },
		{ name = "Codes", label = locale.T("menu-codes"), badge = false },
		{ name = "Settings", label = locale.T("menu-settings"), badge = false },
	}
	local hud = Theme.AppHud
	local menuCount = #menu
	local menuTotalHeight = hud.MenuButtonHeight * menuCount + hud.MenuGap * (menuCount - 1)
	local menuChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(hud.MenuGap / menuTotalHeight, 0),
		}),
	}
	for index, item in ipairs(menu) do
		menuChildren[item.name] = React.createElement("Frame", {
			Name = item.name,
			Size = UDim2.fromScale(1, hud.MenuButtonHeight / menuTotalHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = index,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = Theme.MenuButton.AspectRatio,
			}),
			Button = React.createElement(Components.Button, {
				name = "Open",
				style = Theme.MenuButton,
				text = item.label,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = 1,
				onActivated = function()
					togglePanel(item.name)
				end,
			}),
			Badge = React.createElement(Components.Badge, {
				visible = item.badge,
				anchorPoint = hud.BadgeAnchor,
				position = UDim2.fromScale(hud.BadgePosition.X, hud.BadgePosition.Y),
				size = UDim2.fromScale(hud.BadgeSize.X, hud.BadgeSize.Y),
				zIndex = 3,
			}),
		})
	end

	return React.createElement("Frame", {
		Name = "App",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		-- ── HUD ──────────────────────────────────────────────────────────
		CaloriesPill = React.createElement("Frame", {
			Name = "CaloriesPill",
			Position = UDim2.fromScale(hud.PillPosition.X, hud.PillPosition.Y),
			Size = UDim2.fromScale(0.5, hud.PillHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = hud.PillAspect }),
			Pill = React.createElement(Components.StatPill, {
				value = formatNumber(state.calories),
				icon = "bolt",
				valueGradient = Theme.Hud.EnergyTextGradient,
				valueOutline = Theme.Hud.EnergyTextOutline,
				zIndex = 1,
			}),
		}),
		GemsPill = React.createElement("Frame", {
			Name = "GemsPill",
			Position = UDim2.fromScale(hud.SecondPillPosition.X, hud.SecondPillPosition.Y),
			Size = UDim2.fromScale(0.5, hud.PillHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = hud.PillAspect }),
			Pill = React.createElement(Components.StatPill, {
				value = formatNumber(state.gems),
				icon = "coin",
				valueGradient = Theme.Hud.CoinTextGradient,
				valueOutline = Theme.Hud.CoinTextOutline,
				zIndex = 1,
			}),
		}),
		Menu = React.createElement("Frame", {
			Name = "Menu",
			Position = UDim2.fromScale(hud.MenuPosition.X, hud.MenuPosition.Y),
			Size = UDim2.fromScale(hud.MenuWidth, menuTotalHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, menuChildren),
		CakeBar = React.createElement(Components.CakeBar, {
			name = "CakeBar",
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.fromScale(hud.CakeBarPosition.X, hud.CakeBarPosition.Y),
			size = UDim2.fromScale(0.5, hud.CakeBarHeight),
			progress01 = cakeFill,
			text = cakeText,
			mode = cakeMode,
			rare = state.cake ~= nil and state.cake.rareKind ~= nil,
			zIndex = 1,
		}),
		BellyBar = React.createElement(Components.BellyBar, {
			name = "BellyBar",
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.fromScale(hud.BellyPosition.X, hud.BellyPosition.Y),
			size = UDim2.fromScale(0.5, hud.BellyHeight),
			fill01 = bellyFill,
			text = bellyText,
			glutton = glutton,
			zIndex = 1,
		}),
		Combo = React.createElement(Components.ComboBadge, {
			name = "Combo",
			anchorPoint = Vector2.new(0.5, 0.5),
			position = UDim2.fromScale(hud.ComboPosition.X, hud.ComboPosition.Y),
			size = UDim2.fromScale(0.3, hud.ComboHeight),
			combo = state.combo and state.combo.value or 0,
			intensity01 = state.combo and state.combo.intensity or 0,
			visible = state.combo ~= nil and (state.combo.value or 0) > 1,
			zIndex = 1,
		}),
		Announce = React.createElement(Components.AnnounceBanner, {
			name = "Announce",
			anchorPoint = Vector2.new(0.5, 0),
			position = UDim2.fromScale(hud.AnnouncePosition.X, hud.AnnouncePosition.Y),
			size = UDim2.fromScale(0.6, hud.AnnounceHeight),
			text = if type(state.announceKey) == "string" then locale.T(`announce-{state.announceKey}`) else nil,
			zIndex = 2,
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
		Upgrades = React.createElement(Components.UpgradesPanel, {
			name = "UpgradesPanel",
			title = locale.T("title-upgrades"),
			visible = state.openPanel == "Upgrades",
			size = UDim2.fromScale(portraitScale.X, portraitScale.Y),
			zIndex = 50,
			rows = upgradeRows,
			onBuy = function(id)
				if callbacks.onBuyUpgrade then
					callbacks.onBuyUpgrade(id)
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		Rebirth = React.createElement(Components.RebirthPanel, {
			name = "RebirthPanel",
			title = locale.T("title-rebirth"),
			visible = state.openPanel == "Rebirth",
			size = UDim2.fromScale(rebirthScale.X, rebirthScale.Y),
			zIndex = 50,
			stats = {
				{ label = locale.T("rebirth-stat-count"), value = tostring(rebirth and rebirth.rebirths or 0) },
				{
					label = locale.T("rebirth-stat-mult"),
					value = `+{math.floor((rebirth and rebirth.rebirths or 0) * UpgradeConfig.rebirth.multPerLevel * 100)}%`,
				},
				{
					label = locale.T("rebirth-stat-biome"),
					-- "Next Biome" = the biome UNLOCKED BY this rebirth:
					-- biomes[rebirths + 2] (server's `biome` is the current one).
					value = locale.T(
						`biome-{UpgradeConfig.rebirth.biomes[math.clamp((rebirth and rebirth.rebirths or 0) + 2, 1, #UpgradeConfig.rebirth.biomes)]}`
					),
				},
			},
			warnText = locale.T("rebirth-warning"),
			costText = if rebirth and rebirth.nextCost
				then locale.T("rebirth-cost", { n = formatNumber(rebirth.nextCost) })
				else "",
			buttonText = locale.T("btn-rebirth"),
			canAfford = canRebirth,
			onRebirth = function()
				if callbacks.onDoRebirth then
					callbacks.onDoRebirth()
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
			end,
		}),
		Quests = React.createElement(Components.QuestsPanel, {
			name = "QuestsPanel",
			title = locale.T("title-quests"),
			visible = state.openPanel == "Quests",
			size = UDim2.fromScale(portraitScale.X, portraitScale.Y),
			zIndex = 50,
			quests = questRows,
			onClaim = function(id)
				if callbacks.onClaimQuest then
					callbacks.onClaimQuest(id)
				end
			end,
			onClose = function()
				AppRoot.Open(nil)
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
		TimeRewards = React.createElement(Components.RewardsPanel, {
			name = "TimeRewardsPanel",
			title = locale.T("title-time-rewards"),
			visible = state.openPanel == "TimeRewards",
			size = UDim2.fromScale(wideScale.X, wideScale.Y),
			zIndex = 50,
			cards = timeCards,
			footerText = timeFooter,
			onClaim = function(index)
				if callbacks.onClaimTime then
					callbacks.onClaimTime(index)
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
			size = UDim2.fromScale(portraitScale.X, portraitScale.Y),
			zIndex = 50,
			sections = shopSections,
			onActivated = function(rowId)
				if callbacks.onShopActivated then
					callbacks.onShopActivated(rowId)
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
			active = gymActive,
			duration = state.gym and state.gym.duration or nil,
			startedAt = state.gym and state.gym.startedAt or nil,
			tapText = locale.T("gym-taps-n", { n = gymTaps }),
			buttonText = locale.T("gym-tap"),
			zIndex = 40,
			onTap = function()
				setGymTaps(function(n)
					return n + 1
				end)
				if callbacks.onGymTap then
					callbacks.onGymTap()
				end
			end,
		}),
		PetReveal = React.createElement(Components.PetRevealOverlay, {
			name = "PetRevealOverlay",
			reveal = reveal,
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
