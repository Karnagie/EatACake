local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local StatPill = require(script.Parent.StatPill)
local IconButton = require(script.Parent.IconButton)
local OutlinedText = require(script.Parent.OutlinedText)

local HUD = Theme.Hud

-- Variant switches (false = bring back pill backgrounds / framed buttons):
local BARE_STATS = true
local BARE_BUTTONS = true

local function statLabel(valueText, position, size, zIndex, alignment, gradient, outlineColor)
	return React.createElement(OutlinedText, {
		text = valueText,
		position = position,
		size = size,
		textColor = Color3.new(1, 1, 1),
		textGradient = gradient or Theme.Chip.TextGradient,
		outlineColor = outlineColor,
		textXAlignment = alignment or Enum.TextXAlignment.Left,
		zIndex = zIndex,
	})
end

local function bareStatRow(name, iconImage, valueText, y, zIndex, gradient, outlineColor)
	return React.createElement("Frame", {
		Name = name,
		Position = UDim2.fromScale(HUD.PillX, y),
		Size = UDim2.fromScale(0.5, HUD.StatRowHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = HUD.StatRowAspect,
		}),
		Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(HUD.StatIconWidth, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = iconImage,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex,
		}),
		Value = statLabel(
			valueText,
			UDim2.fromScale(HUD.StatValuePosition.X, HUD.StatValuePosition.Y),
			UDim2.fromScale(HUD.StatValueSize.X, HUD.StatValueSize.Y),
			zIndex,
			nil,
			gradient,
			outlineColor
		),
	})
end

local function menuButton(name, iconImage, labelText, y, onActivated, zIndex)
	local buttonElement
	if BARE_BUTTONS then
		buttonElement = React.createElement("ImageButton", {
			Name = "Button",
			Size = UDim2.fromScale(1, HUD.ButtonPartHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = iconImage,
			ScaleType = Enum.ScaleType.Fit,
			AutoButtonColor = false,
			ZIndex = zIndex,
			[React.Event.MouseButton1Click] = function()
				if onActivated then
					onActivated()
				end
			end,
		})
	else
		buttonElement = React.createElement(IconButton, {
			name = "Button",
			iconImage = iconImage,
			size = UDim2.fromScale(1, HUD.ButtonPartHeight),
			zIndex = zIndex,
			onActivated = onActivated,
		})
	end

	return React.createElement("Frame", {
		Name = name,
		Position = UDim2.fromScale(HUD.ButtonX, y),
		Size = UDim2.fromScale(0.5, HUD.ButtonContainerHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = HUD.ButtonContainerAspect,
		}),
		Button = buttonElement,
		Label = React.createElement(OutlinedText, {
			text = labelText,
			position = UDim2.fromScale(0, HUD.LabelY),
			size = UDim2.fromScale(1, HUD.LabelHeight),
			textColor = Color3.new(1, 1, 1),
			textGradient = HUD.ButtonLabelGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex,
		}),
	})
end

local function Hud(props)
	local zIndex = props.zIndex or 1

	return React.createElement("Frame", {
		Name = props.name or "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		SpeedPill = BARE_STATS
				and bareStatRow(
					"SpeedPill",
					HUD.Icons.Speed,
					props.speedText or "+0%",
					HUD.PillYs[1],
					zIndex,
					HUD.SpeedTextGradient,
					HUD.SpeedTextOutline
				)
			or React.createElement(StatPill, {
				name = "SpeedPill",
				iconImage = HUD.Icons.Speed,
				value = props.speedText or "+0%",
				valueGradient = HUD.SpeedTextGradient,
				valueOutline = HUD.SpeedTextOutline,
				position = UDim2.fromScale(HUD.PillX, HUD.PillYs[1]),
				size = UDim2.fromScale(0.5, HUD.PillHeight),
				zIndex = zIndex,
			}),
		GoldPill = BARE_STATS
				and bareStatRow(
					"GoldPill",
					HUD.Icons.Coin,
					props.goldText or "0",
					HUD.PillYs[2],
					zIndex,
					HUD.CoinTextGradient,
					HUD.CoinTextOutline
				)
			or React.createElement(StatPill, {
				name = "GoldPill",
				iconImage = HUD.Icons.Coin,
				value = props.goldText or "0",
				valueGradient = HUD.CoinTextGradient,
				valueOutline = HUD.CoinTextOutline,
				position = UDim2.fromScale(HUD.PillX, HUD.PillYs[2]),
				size = UDim2.fromScale(0.5, HUD.PillHeight),
				zIndex = zIndex,
			}),
		EnergyPill = BARE_STATS
				and bareStatRow(
					"EnergyPill",
					HUD.Icons.Energy,
					props.energyText or "+0%",
					HUD.PillYs[3],
					zIndex,
					HUD.EnergyTextGradient,
					HUD.EnergyTextOutline
				)
			or React.createElement(StatPill, {
				name = "EnergyPill",
				iconImage = HUD.Icons.Energy,
				value = props.energyText or "+0%",
				valueGradient = HUD.EnergyTextGradient,
				valueOutline = HUD.EnergyTextOutline,
				position = UDim2.fromScale(HUD.PillX, HUD.PillYs[3]),
				size = UDim2.fromScale(0.5, HUD.PillHeight),
				zIndex = zIndex,
			}),
		SettingsButton = menuButton("SettingsButton", HUD.Icons.Settings, "Settings", HUD.ButtonYs[1], props.onSettings, zIndex),
		PetsButton = menuButton("PetsButton", HUD.Icons.Pets, "Pets", HUD.ButtonYs[2], props.onPets, zIndex),
	})
end

return Hud
