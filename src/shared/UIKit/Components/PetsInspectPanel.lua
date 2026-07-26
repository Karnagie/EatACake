local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local IconButton = require(script.Parent.IconButton)
local ScrollPane = require(script.Parent.ScrollPane)
local PetCard = require(script.Parent.PetCard)
local OutlinedText = require(script.Parent.OutlinedText)

local function roundedFrame(name, position, size, corner, zIndex, gradient)
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

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

local function statRow(name, label, value, position, zIndex)
	local style = Theme.StatRow
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = UDim2.fromScale(Theme.Inspector.StatSize.X, Theme.Inspector.StatSize.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 1,
			style.FaceGradient
		),
		Label = React.createElement(OutlinedText, {
			text = label,
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			zIndex = zIndex + 2,
		}),
		Value = React.createElement(OutlinedText, {
			text = value,
			position = UDim2.fromScale(style.ValuePosition.X, style.ValuePosition.Y),
			size = UDim2.fromScale(style.ValueSize.X, style.ValueSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TextGradient,
			outlineColor = style.OutlineColor,
			textXAlignment = Enum.TextXAlignment.Right,
			zIndex = zIndex + 2,
		}),
	})
end

local function inspector(props, layout, zIndex)
	local style = Theme.Inspector
	local pet = props.selectedPet
	local isEquipped = pet ~= nil and props.equipped ~= nil and props.equipped[pet.id] == true

	local children = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Fill = roundedFrame(
			"Fill",
			UDim2.fromScale(style.FillPosition.X, style.FillPosition.Y),
			UDim2.fromScale(style.FillSize.X, style.FillSize.Y),
			style.FillCorner,
			zIndex + 1,
			style.FillGradient
		),
	}

	if pet then
		children.PlateRing = React.createElement("Frame", {
			Name = "PlateRing",
			Position = UDim2.fromScale(style.PlateRingPosition.X, style.PlateRingPosition.Y),
			Size = UDim2.fromScale(style.PlateRingSize.X, style.PlateRingSize.Y),
			BackgroundColor3 = Theme.Colors.Outline,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
		children.Plate = React.createElement("Frame", {
			Name = "Plate",
			Position = UDim2.fromScale(style.PlatePosition.X, style.PlatePosition.Y),
			Size = UDim2.fromScale(style.PlateSize.X, style.PlateSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", { Color = Theme.PetCard.PlateGradient, Rotation = 90 }),
			Icon = if pet.iconName
				then React.createElement("ImageLabel", {
					Name = "Icon",
					Position = UDim2.fromScale(Theme.PetCard.IconInset, Theme.PetCard.IconInset),
					Size = UDim2.fromScale(1 - Theme.PetCard.IconInset * 2, 1 - Theme.PetCard.IconInset * 2),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = Theme.Icon(pet.iconName),
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = zIndex + 4,
				})
				else nil,
		})
		local rarityStyle = Theme.Rarity[pet.rarity or "Common"] or Theme.Rarity.Common
		children.PetName = React.createElement(OutlinedText, {
			text = pet.name,
			position = UDim2.fromScale(style.NamePosition.X, style.NamePosition.Y),
			size = UDim2.fromScale(style.NameSize.X, style.NameSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = Theme.PetCard.NameGradient,
			outlineColor = rarityStyle.Outline, -- same hue rule as PetCard
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 2,
		})
		-- Optional generic stat rows (backwards-compatible extension):
		-- selectedPet.stats = { { label, value } } overrides the legacy
		-- speed/energy pair when present.
		if type(pet.stats) == "table" and #pet.stats > 0 then
			for index, stat in ipairs(pet.stats) do
				local statPosition = style.StatPositions[index]
				if statPosition == nil then
					break
				end
				children[`Stat{index}`] = statRow(
					`Stat{index}`,
					tostring(stat.label or ""),
					tostring(stat.value or ""),
					UDim2.fromScale(statPosition.X, statPosition.Y),
					zIndex + 2
				)
			end
		else
			children.SpeedStat = statRow(
				"SpeedStat",
				"Speed",
				string.format("+%d%%", pet.speed or 0),
				UDim2.fromScale(style.StatPositions[1].X, style.StatPositions[1].Y),
				zIndex + 2
			)
			children.EnergyStat = statRow(
				"EnergyStat",
				"Energy",
				string.format("+%d%%", pet.energy or 0),
				UDim2.fromScale(style.StatPositions[2].X, style.StatPositions[2].Y),
				zIndex + 2
			)
		end
		children.EquipToggle = React.createElement(Button, {
			name = "EquipToggle",
			-- Optional localized labels (backwards-compatible props).
			text = isEquipped and (props.unequipText or "Unequip") or (props.equipText or "Equip"),
			style = isEquipped and Theme.UnequipRed or Theme.EquipGreen,
			textXAlignment = Enum.TextXAlignment.Center,
			position = UDim2.fromScale(style.EquipPosition.X, style.EquipPosition.Y),
			size = UDim2.fromScale(style.EquipSize.X, style.EquipSize.Y),
			zIndex = zIndex + 2,
			onActivated = props.onEquipToggle,
		})
	else
		children.EmptyLabel = React.createElement(OutlinedText, {
			text = props.selectText or "Select a pet",
			position = UDim2.fromScale(0.1, 0.44),
			size = UDim2.fromScale(0.8, 0.12),
			textColor = Color3.new(1, 1, 1),
			textGradient = Theme.PetCard.NameGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 2,
		})
	end

	return React.createElement("Frame", {
		Name = "Inspector",
		Position = UDim2.fromScale(layout.InspectorPosition.X, layout.InspectorPosition.Y),
		Size = UDim2.fromScale(layout.InspectorSize.X, layout.InspectorSize.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function PetsInspectPanel(props)
	local layout = Theme.PetsInspectLayout
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
			iconName = pet.iconName,
			equipped = props.equipped ~= nil and props.equipped[pet.id] == true,
			selected = props.selectedId == pet.id,
			layoutOrder = index,
			zIndex = zIndex,
			onActivated = props.onPetActivated,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = "PetsInspectPanel",
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
			text = props.equipBestText or "Equip Best",
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
		Inspector = inspector(props, layout, zIndex),
	})
end

return PetsInspectPanel
