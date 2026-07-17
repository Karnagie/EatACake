local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local IconButton = require(script.Parent.IconButton)
local ScrollPane = require(script.Parent.ScrollPane)
local PetCard = require(script.Parent.PetCard)
local OutlinedText = require(script.Parent.OutlinedText)

local function chip(props, layout, zIndex)
	return React.createElement("Frame", {
		Name = "Chip",
		Position = UDim2.fromScale(layout.ChipPosition.X, layout.ChipPosition.Y),
		Size = UDim2.fromScale(layout.ChipSize.X, layout.ChipSize.Y),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Gradient = React.createElement("UIGradient", { Color = Theme.Chip.OuterGradient, Rotation = 90 }),
		Face = React.createElement("Frame", {
			Name = "Face",
			Position = UDim2.fromScale(Theme.Chip.FaceInset.X, Theme.Chip.FaceInset.Y),
			Size = UDim2.fromScale(1 - Theme.Chip.FaceInset.X * 2, 1 - Theme.Chip.FaceInset.Y * 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", { Color = Theme.Chip.FaceGradient, Rotation = 90 }),
		}),
		Label = React.createElement(OutlinedText, {
			text = string.format("%d / %d", props.equippedCount or 0, props.maxEquipped or 0),
			position = UDim2.fromScale(0.1, 0.22),
			size = UDim2.fromScale(0.8, 0.56),
			textColor = Color3.new(1, 1, 1),
			textGradient = Theme.Chip.TextGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 2,
		}),
	})
end

local function PetsPanel(props)
	local layout = Theme.PetsLayout
	local zIndex = 5
	local petCount = props.pets and #props.pets or 0
	local rows = math.max(math.ceil(petCount / layout.Columns), 1)
	local canvasHeightScale = math.max(rows * layout.CellHeightWithGap, 1)

	local gridChildren = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromScale(layout.CellWidth, layout.CellHeightWithGap / canvasHeightScale),
			CellPadding = UDim2.fromScale(layout.CellPaddingX, 0),
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = layout.Columns,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, pet in ipairs(props.pets or {}) do
		gridChildren[pet.id] = React.createElement(PetCard, {
			id = pet.id,
			petName = pet.name,
			rarity = pet.rarity,
			equipped = props.equipped ~= nil and props.equipped[pet.id] == true,
			layoutOrder = index,
			zIndex = zIndex,
			onActivated = props.onPetActivated,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = "PetsPanel",
		size = props.size,
		visible = props.visible,
		title = props.title or "Pets",
		onClose = props.onClose,
		panelStyle = Theme.PanelWide,
		headerStyle = Theme.HeaderWide,
		headerSize = UDim2.fromScale(1, layout.HeaderHeight),
		zIndex = props.zIndex,
	}, {
		Chip = chip(props, layout, zIndex),
		EquipBest = React.createElement(Button, {
			name = "EquipBest",
			text = "Equip Best",
			style = Theme.ActionButton,
			textXAlignment = Enum.TextXAlignment.Center,
			position = UDim2.fromScale(layout.EquipButtonPosition.X, layout.EquipButtonPosition.Y),
			size = UDim2.fromScale(layout.EquipButtonSize.X, layout.EquipButtonSize.Y),
			zIndex = zIndex,
			onActivated = props.onEquipBest,
		}),
		SortButton = React.createElement(IconButton, {
			name = "SortButton",
			icon = "sort",
			position = UDim2.fromScale(layout.SortButtonPosition.X, layout.SortButtonPosition.Y),
			size = UDim2.fromScale(layout.SortButtonSize.X, layout.SortButtonSize.Y),
			zIndex = zIndex,
			onActivated = props.onSort,
		}),
		Grid = React.createElement(ScrollPane, {
			name = "Grid",
			position = UDim2.fromScale(layout.GridPosition.X, layout.GridPosition.Y),
			size = UDim2.fromScale(layout.GridSize.X, layout.GridSize.Y),
			windowFraction = layout.ScrollWindowFraction,
			barWidth = layout.ScrollBarWidth,
			canvasHeightScale = canvasHeightScale,
			zIndex = zIndex,
			children = gridChildren,
		}),
	})
end

return PetsPanel
