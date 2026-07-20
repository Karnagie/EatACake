local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)

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

local function pill(name, center, size, color, zIndex)
	return React.createElement("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(center.X, center.Y),
		Size = UDim2.fromScale(size.X, size.Y),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
	})
end

local SORT_BARS = {
	{ y = 0.30, outline = 0.60, fill = 0.52 },
	{ y = 0.45, outline = 0.48, fill = 0.40 },
	{ y = 0.60, outline = 0.36, fill = 0.28 },
}

local function circle(name, center, diameter, color, zIndex, gradient)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
	}
	if gradient then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		})
	end
	return React.createElement("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(center.X, center.Y),
		Size = UDim2.fromScale(diameter, diameter),
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function rotatedPill(name, center, size, rotation, color, zIndex)
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

local function addGearIcon(children, style, zIndex)
	local radius = 0.27
	for index = 0, 7 do
		local angle = index * 45
		local radians = math.rad(angle)
		local center = Vector2.new(0.5 + radius * math.cos(radians), 0.47 + radius * math.sin(radians))
		children["ToothOutline" .. index] = rotatedPill(
			"ToothOutline" .. index,
			center,
			Vector2.new(0.16, 0.26),
			angle + 90,
			style.IconOutlineColor,
			zIndex + 3
		)
		children["ToothFill" .. index] = rotatedPill(
			"ToothFill" .. index,
			center,
			Vector2.new(0.10, 0.19),
			angle + 90,
			style.IconColor,
			zIndex + 4
		)
	end
	children.GearRingOutline = circle("GearRingOutline", Vector2.new(0.5, 0.47), 0.56, style.IconOutlineColor, zIndex + 3)
	children.GearRingFill = circle("GearRingFill", Vector2.new(0.5, 0.47), 0.46, style.IconColor, zIndex + 4)
	children.GearHole = circle("GearHole", Vector2.new(0.5, 0.47), 0.22, style.IconOutlineColor, zIndex + 5)
end

local PAW_TOES = {
	Vector2.new(0.28, 0.36),
	Vector2.new(0.50, 0.28),
	Vector2.new(0.72, 0.36),
}

local function addPawIcon(children, style, zIndex)
	children.PadOutline = React.createElement("Frame", {
		Name = "PadOutline",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.60),
		Size = UDim2.fromScale(0.42, 0.36),
		BackgroundColor3 = style.IconOutlineColor,
		BorderSizePixel = 0,
		ZIndex = zIndex + 3,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
	children.PadFill = React.createElement("Frame", {
		Name = "PadFill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.60),
		Size = UDim2.fromScale(0.34, 0.28),
		BackgroundColor3 = style.IconColor,
		BorderSizePixel = 0,
		ZIndex = zIndex + 4,
	}, {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
	for index, toe in ipairs(PAW_TOES) do
		children["ToeOutline" .. index] = circle("ToeOutline" .. index, toe, 0.20, style.IconOutlineColor, zIndex + 3)
		children["ToeFill" .. index] = circle("ToeFill" .. index, toe, 0.13, style.IconColor, zIndex + 4)
	end
end

local function IconButton(props)
	local style = props.style or Theme.IconButton
	local zIndex = props.zIndex or 1
	local enabled = props.enabled ~= false

	local scaleRef, handlers = Interaction.usePressable({
		enabled = enabled,
		onActivated = props.onActivated,
	})

	-- Visual stack (everything but the Aspect, which stays on the hit target).
	local children = {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			style.RimGradient
		),
		Face = roundedFrame(
			"Face",
			UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			style.FaceCorner,
			zIndex + 2,
			style.FaceGradient
		),
	}

	if props.iconImage then
		children.IconImage = React.createElement("ImageLabel", {
			Name = "IconImage",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.47),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.iconImage,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 3,
		})
	elseif props.icon == "sort" then
		for index, row in ipairs(SORT_BARS) do
			children["BarOutline" .. index] = pill(
				"BarOutline" .. index,
				Vector2.new(0.5, row.y),
				Vector2.new(row.outline, 0.15),
				style.IconOutlineColor,
				zIndex + 3
			)
			children["BarFill" .. index] = pill(
				"BarFill" .. index,
				Vector2.new(0.5, row.y),
				Vector2.new(row.fill, 0.075),
				style.IconColor,
				zIndex + 4
			)
		end
	elseif props.icon == "gear" then
		addGearIcon(children, style, zIndex)
	elseif props.icon == "paw" then
		addPawIcon(children, style, zIndex)
	end

	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	return React.createElement("TextButton", Interaction.merge({
		Name = props.name or "IconButton",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = enabled,
		Selectable = enabled,
		ZIndex = zIndex,
	}, handlers), {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, children),
	})
end

return IconButton
