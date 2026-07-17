--[[ PetsInspectDemo
	Reference composition: landscape panel with 4-column grid + inspector sidebar
	(selection, stat rows, green/red accent action button). Mock state only.
]]

local React = require(game:GetService("ReplicatedStorage").Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PetsInspectPanel = require(script.Parent.Parent.Components.PetsInspectPanel)

local MAX_EQUIPPED = 4

local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

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

local function calculatePanelScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	local panelAspect = Theme.PetsInspectLayout.PanelAspect
	local maxFraction = Theme.PetsInspectLayout.PanelMaxViewportFraction

	if viewportAspect >= panelAspect then
		return Vector2.new(maxFraction * panelAspect / viewportAspect, maxFraction)
	end

	return Vector2.new(maxFraction, maxFraction * viewportAspect / panelAspect)
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
	local visible, setVisible = React.useState(true)
	local equipped, setEquipped = React.useState({ Unicorn = true, Dragon = true })
	local sortMode, setSortMode = React.useState("Rarity")
	local selectedId, setSelectedId = React.useState("Griffin")
	local panelScale, setPanelScale = React.useState(calculatePanelScale())

	React.useEffect(function()
		local viewportConnection
		local cameraConnection

		local function bindCamera()
			if viewportConnection then
				viewportConnection:Disconnect()
				viewportConnection = nil
			end

			local camera = workspace.CurrentCamera
			setPanelScale(calculatePanelScale())
			if camera then
				viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					setPanelScale(calculatePanelScale())
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

	local equippedCount = 0
	for _ in pairs(equipped) do
		equippedCount += 1
	end

	local function onPetActivated(id)
		setSelectedId(id)
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
		Pets = React.createElement(PetsInspectPanel, {
			visible = visible,
			size = UDim2.fromScale(panelScale.X, panelScale.Y),
			pets = sortedPets(sortMode),
			equipped = equipped,
			equippedCount = equippedCount,
			maxEquipped = MAX_EQUIPPED,
			selectedId = selectedId,
			selectedPet = findPet(selectedId),
			onPetActivated = onPetActivated,
			onEquipToggle = onEquipToggle,
			onEquipBest = onEquipBest,
			onSort = onSort,
			onClose = function()
				setVisible(false)
			end,
		}),
	})
end

return App
