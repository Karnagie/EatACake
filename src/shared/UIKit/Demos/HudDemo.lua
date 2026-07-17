--[[ HudDemo
	Reference composition: HUD (stat rows + menu buttons) with panel toggling.
	Panels render ABOVE the HUD (zIndex 50 vs 1); one panel open at a time;
	panel state survives hide/show. Mock state only.
]]

local React = require(game:GetService("ReplicatedStorage").Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Hud = require(script.Parent.Parent.Components.Hud)
local SettingsPanel = require(script.Parent.Parent.Components.SettingsPanel)
local PetsInspectPanel = require(script.Parent.Parent.Components.PetsInspectPanel)

local MAX_EQUIPPED = 4

local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local MOCK_STATS = {
	speed = "+18%",
	gold = "12,450",
	energy = "+9%",
}

local INITIAL_VALUES = {
	Shadows = true,
	Music = true,
	Weather = false,
	Players = true,
	Invites = true,
}

local INITIAL_PETS = {
	{ id = "Doggy", name = "Doggy", rarity = "Common", speed = 6, energy = 4 },
	{ id = "Kitty", name = "Kitty", rarity = "Common", speed = 6, energy = 5 },
	{ id = "Bunny", name = "Bunny", rarity = "Common", speed = 7, energy = 3 },
	{ id = "Ducky", name = "Ducky", rarity = "Common", speed = 4, energy = 6 },
	{ id = "Piggy", name = "Piggy", rarity = "Common", speed = 4, energy = 8 },
	{ id = "Foxy", name = "Foxy", rarity = "Common", speed = 8, energy = 3 },
	{ id = "Bearo", name = "Bearo", rarity = "Common", speed = 5, energy = 4 },
	{ id = "Mousey", name = "Mousey", rarity = "Common", speed = 3, energy = 3 },
	{ id = "Froggy", name = "Froggy", rarity = "Common", speed = 5, energy = 7 },
	{ id = "Chick", name = "Chick", rarity = "Common", speed = 3, energy = 5 },
	{ id = "Wolfie", name = "Wolfie", rarity = "Rare", speed = 16, energy = 10 },
	{ id = "Panda", name = "Panda", rarity = "Rare", speed = 10, energy = 14 },
	{ id = "Tiggy", name = "Tiggy", rarity = "Rare", speed = 14, energy = 12 },
	{ id = "Owly", name = "Owly", rarity = "Rare", speed = 12, energy = 11 },
	{ id = "Sharky", name = "Sharky", rarity = "Rare", speed = 15, energy = 8 },
	{ id = "Turtle", name = "Turtle", rarity = "Rare", speed = 8, energy = 16 },
	{ id = "Penguin", name = "Penguin", rarity = "Rare", speed = 11, energy = 9 },
	{ id = "Dragon", name = "Dragon", rarity = "Epic", speed = 28, energy = 20 },
	{ id = "Phoenix", name = "Phoenix", rarity = "Epic", speed = 26, energy = 24 },
	{ id = "Golem", name = "Golem", rarity = "Epic", speed = 20, energy = 27 },
	{ id = "Axolotl", name = "Axolotl", rarity = "Epic", speed = 24, energy = 22 },
	{ id = "Unicorn", name = "Unicorn", rarity = "Legendary", speed = 38, energy = 45 },
	{ id = "Kraken", name = "Kraken", rarity = "Legendary", speed = 46, energy = 33 },
	{ id = "Griffin", name = "Griffin", rarity = "Legendary", speed = 42, energy = 38 },
}

local function calculateScale(panelAspect, maxFraction, viewport)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	if viewportAspect >= panelAspect then
		return Vector2.new(maxFraction * panelAspect / viewportAspect, maxFraction)
	end
	return Vector2.new(maxFraction, maxFraction * viewportAspect / panelAspect)
end

local function currentViewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1920, 1080)
end

local function sortedPets(sortMode)
	local pets = table.clone(INITIAL_PETS)
	if sortMode == "Rarity" then
		table.sort(pets, function(a, b)
			local rankA = RARITY_RANK[a.rarity] or 0
			local rankB = RARITY_RANK[b.rarity] or 0
			if rankA ~= rankB then
				return rankA > rankB
			end
			return a.name < b.name
		end)
	else
		table.sort(pets, function(a, b)
			return a.name < b.name
		end)
	end
	return pets
end

local function findPet(id)
	for _, pet in ipairs(INITIAL_PETS) do
		if pet.id == id then
			return pet
		end
	end
	return nil
end

local function App()
	local openPanel, setOpenPanel = React.useState(nil)
	local values, setValues = React.useState(INITIAL_VALUES)
	local equipped, setEquipped = React.useState({ Unicorn = true, Dragon = true })
	local sortMode, setSortMode = React.useState("Rarity")
	local selectedId, setSelectedId = React.useState("Griffin")
	local viewport, setViewport = React.useState(currentViewport())

	React.useEffect(function()
		local viewportConnection
		local cameraConnection

		local function bindCamera()
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			local camera = workspace.CurrentCamera
			setViewport(currentViewport())
			if camera then
				viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					setViewport(currentViewport())
				end)
			end
		end

		bindCamera()
		cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

		return function()
			if viewportConnection then
				viewportConnection:Disconnect()
			end
			if cameraConnection then
				cameraConnection:Disconnect()
			end
		end
	end, {})

	local settingsScale = calculateScale(Theme.Layout.PanelAspect, Theme.Layout.PanelMaxViewportFraction, viewport)
	local petsScale = calculateScale(
		Theme.PetsInspectLayout.PanelAspect,
		Theme.PetsInspectLayout.PanelMaxViewportFraction,
		viewport
	)

	local equippedCount = 0
	for _ in pairs(equipped) do
		equippedCount += 1
	end

	local function togglePanel(panel)
		setOpenPanel(function(previous)
			return previous ~= panel and panel or nil
		end)
	end

	local function onToggleSetting(id, value)
		setValues(function(previous)
			local nextValues = table.clone(previous)
			nextValues[id] = value
			return nextValues
		end)
	end

	local function onEquipToggle()
		local id = selectedId
		if not id then
			return
		end
		setEquipped(function(previous)
			local nextEquipped = table.clone(previous)
			if nextEquipped[id] then
				nextEquipped[id] = nil
			else
				local count = 0
				for _ in pairs(nextEquipped) do
					count += 1
				end
				if count >= MAX_EQUIPPED then
					return previous
				end
				nextEquipped[id] = true
			end
			return nextEquipped
		end)
	end

	local function onEquipBest()
		local best = sortedPets("Rarity")
		local nextEquipped = {}
		for index = 1, math.min(MAX_EQUIPPED, #best) do
			nextEquipped[best[index].id] = true
		end
		setEquipped(nextEquipped)
	end

	local function onSort()
		setSortMode(function(previous)
			return previous == "Rarity" and "Name" or "Rarity"
		end)
	end

	return React.createElement("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		Hud = React.createElement(Hud, {
			speedText = MOCK_STATS.speed,
			goldText = MOCK_STATS.gold,
			energyText = MOCK_STATS.energy,
			onSettings = function()
				togglePanel("Settings")
			end,
			onPets = function()
				togglePanel("Pets")
			end,
			zIndex = 1,
		}),
		Settings = React.createElement(SettingsPanel, {
			visible = openPanel == "Settings",
			size = UDim2.fromScale(settingsScale.X, settingsScale.Y),
			zIndex = 50,
			values = values,
			onToggle = onToggleSetting,
			onClose = function()
				setOpenPanel(nil)
			end,
		}),
		Pets = React.createElement(PetsInspectPanel, {
			visible = openPanel == "Pets",
			size = UDim2.fromScale(petsScale.X, petsScale.Y),
			zIndex = 50,
			pets = sortedPets(sortMode),
			equipped = equipped,
			equippedCount = equippedCount,
			maxEquipped = MAX_EQUIPPED,
			selectedId = selectedId,
			selectedPet = findPet(selectedId),
			onPetActivated = setSelectedId,
			onEquipToggle = onEquipToggle,
			onEquipBest = onEquipBest,
			onSort = onSort,
			onClose = function()
				setOpenPanel(nil)
			end,
		}),
	})
end

return App
