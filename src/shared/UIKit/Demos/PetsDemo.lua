--[[ PetsDemo
	Reference composition: landscape panel, 6-column card grid, custom scrollbar,
	action row (counter chip / action button / sort icon button). Mock state only.
]]

local React = require(game:GetService("ReplicatedStorage").Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PetsPanel = require(script.Parent.Parent.Components.PetsPanel)

local MAX_EQUIPPED = 4

local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 }

local INITIAL_PETS = {
	{ id = "Doggy", name = "Doggy", rarity = "Common" },
	{ id = "Kitty", name = "Kitty", rarity = "Common" },
	{ id = "Bunny", name = "Bunny", rarity = "Common" },
	{ id = "Ducky", name = "Ducky", rarity = "Common" },
	{ id = "Piggy", name = "Piggy", rarity = "Common" },
	{ id = "Foxy", name = "Foxy", rarity = "Common" },
	{ id = "Bearo", name = "Bearo", rarity = "Common" },
	{ id = "Mousey", name = "Mousey", rarity = "Common" },
	{ id = "Froggy", name = "Froggy", rarity = "Common" },
	{ id = "Chick", name = "Chick", rarity = "Common" },
	{ id = "Wolfie", name = "Wolfie", rarity = "Rare" },
	{ id = "Panda", name = "Panda", rarity = "Rare" },
	{ id = "Tiggy", name = "Tiggy", rarity = "Rare" },
	{ id = "Owly", name = "Owly", rarity = "Rare" },
	{ id = "Sharky", name = "Sharky", rarity = "Rare" },
	{ id = "Turtle", name = "Turtle", rarity = "Rare" },
	{ id = "Penguin", name = "Penguin", rarity = "Rare" },
	{ id = "Dragon", name = "Dragon", rarity = "Epic" },
	{ id = "Phoenix", name = "Phoenix", rarity = "Epic" },
	{ id = "Golem", name = "Golem", rarity = "Epic" },
	{ id = "Axolotl", name = "Axolotl", rarity = "Epic" },
	{ id = "Unicorn", name = "Unicorn", rarity = "Legendary" },
	{ id = "Kraken", name = "Kraken", rarity = "Legendary" },
	{ id = "Griffin", name = "Griffin", rarity = "Legendary" },
}

local function calculatePanelScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	local viewportAspect = viewport.X / math.max(viewport.Y, 1)
	local panelAspect = Theme.PetsLayout.PanelAspect
	local maxFraction = Theme.PetsLayout.PanelMaxViewportFraction

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

local function App()
	local visible, setVisible = React.useState(true)
	local equipped, setEquipped = React.useState({ Unicorn = true, Dragon = true })
	local sortMode, setSortMode = React.useState("Rarity")
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
		Pets = React.createElement(PetsPanel, {
			visible = visible,
			size = UDim2.fromScale(panelScale.X, panelScale.Y),
			pets = sortedPets(sortMode),
			equipped = equipped,
			equippedCount = equippedCount,
			maxEquipped = MAX_EQUIPPED,
			onPetActivated = onPetActivated,
			onEquipBest = onEquipBest,
			onSort = onSort,
			onClose = function()
				setVisible(false)
			end,
		}),
	})
end

return App
