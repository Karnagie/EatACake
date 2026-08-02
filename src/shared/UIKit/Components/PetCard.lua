local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
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

local function pill(name, center, size, rotation, color, zIndex)
	return React.createElement("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(center.X, center.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		Rotation = rotation,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
	})
end

local function PetCard(props)
	local style = props.style or Theme.PetCard
	local rarity = Theme.Rarity[props.rarity or "Common"] or Theme.Rarity.Common
	local zIndex = props.zIndex or 5

	-- Selection: gold Outer/Rim gradient swap, geometry unchanged (an outer ring would get
	-- clipped by the scroll window on edge columns)
	local outerGradient = props.selected and style.SelectOuterGradient or rarity.Outer
	local rimGradient = props.selected and style.SelectRingGradient or rarity.Rim

	local cardChildren = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			outerGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			rimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			rarity.Face
		),
		Plate = React.createElement("Frame", {
			Name = "Plate",
			Position = UDim2.fromScale(style.PlatePosition.X, style.PlatePosition.Y),
			Size = UDim2.fromScale(style.PlateSize.X, style.PlateSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = style.PlateTransparency,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = style.PlateGradient,
				Rotation = 90,
			}),
			-- Optional squishy art. Omitted = the original bare plate, so every
			-- existing caller is unaffected.
			Icon = if props.iconName
				then React.createElement("ImageLabel", {
					Name = "Icon",
					Position = UDim2.fromScale(style.IconInset, style.IconInset),
					Size = UDim2.fromScale(1 - style.IconInset * 2, 1 - style.IconInset * 2),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = Theme.Icon(props.iconName),
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = zIndex + 4,
				})
				else nil,
		}),
		PetName = React.createElement(OutlinedText, {
			text = props.petName or "Pet",
			position = UDim2.fromScale(style.NamePosition.X, style.NamePosition.Y),
			size = UDim2.fromScale(style.NameSize.X, style.NameSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.NameGradient,
			-- style-rules §4.3: outline = the DARK version of the element's OWN
			-- hue. Without this a Secret card wore the default navy, and the
			-- cream Common face carried the lowest-contrast pairing in the ladder.
			outlineColor = rarity.Outline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 4,
		}),
	}

	if props.equipped then
		cardChildren.Badge = React.createElement("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			Size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 5,
		}, {
			Ring = React.createElement("Frame", {
				Name = "Ring",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = style.BadgeOutlineColor,
				BorderSizePixel = 0,
				ZIndex = zIndex + 5,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			Fill = React.createElement("Frame", {
				Name = "Fill",
				Position = UDim2.fromScale(0.13, 0.13),
				Size = UDim2.fromScale(0.74, 0.74),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 6,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = React.createElement("UIGradient", {
					Color = style.BadgeGradient,
					Rotation = 90,
				}),
			}),
			CheckA = pill("CheckA", Vector2.new(0.36, 0.58), Vector2.new(0.34, 0.16), 45, style.CheckColor, zIndex + 7),
			CheckB = pill("CheckB", Vector2.new(0.58, 0.48), Vector2.new(0.52, 0.16), -45, style.CheckColor, zIndex + 7),
		})
	end

	return React.createElement("Frame", {
		Name = props.id or "PetCard",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
	}, {
		Card = React.createElement("TextButton", {
			Name = "Card",
			Size = UDim2.fromScale(1, style.CardHeightInCell),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = zIndex,
			[React.Event.MouseButton1Click] = function()
				Interaction.Cue("press", "Squishies/Card")
				if props.onActivated then
					props.onActivated(props.id)
				end
			end,
		}, cardChildren),
	})
end

return PetCard
