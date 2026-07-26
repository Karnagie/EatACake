local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local HUD = Theme.Hud

local function circle(name, position, size, color, zIndex, gradient)
	local children = {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
	}
	if gradient then
		children.Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		})
	end
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function rotatedPill(name, center, size, rotation, color, zIndex, gradient)
	local children = {
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
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
		Position = UDim2.fromScale(center.X / 190, center.Y / 48),
		Size = UDim2.fromScale(size.X / 190, size.Y / 48),
		Rotation = rotation,
		BackgroundColor3 = gradient and Color3.new(1, 1, 1) or color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

local function addCoin(children, zIndex)
	children.CoinRing = circle(
		"CoinRing",
		UDim2.fromScale(9 / 190, 7 / 48),
		UDim2.fromScale(34 / 190, 34 / 48),
		HUD.CoinOutline,
		zIndex + 2
	)
	children.CoinFill = circle(
		"CoinFill",
		UDim2.fromScale(12.5 / 190, 10.5 / 48),
		UDim2.fromScale(27 / 190, 27 / 48),
		nil,
		zIndex + 3,
		HUD.CoinFill
	)
	children.CoinHighlight = circle(
		"CoinHighlight",
		UDim2.fromScale(17 / 190, 13 / 48),
		UDim2.fromScale(10 / 190, 10 / 48),
		HUD.CoinHighlight,
		zIndex + 4
	)
end

local function addChevrons(children, zIndex)
	local arms = {
		{ center = Vector2.new(20, 19.5), rotation = 45 },
		{ center = Vector2.new(20, 28.5), rotation = -45 },
		{ center = Vector2.new(30, 19.5), rotation = 45 },
		{ center = Vector2.new(30, 28.5), rotation = -45 },
	}
	for index, arm in ipairs(arms) do
		children["ChevronOutline" .. index] = rotatedPill(
			"ChevronOutline" .. index,
			arm.center,
			Vector2.new(17, 9),
			arm.rotation,
			HUD.ChevronOutline,
			zIndex + 2
		)
	end
	for index, arm in ipairs(arms) do
		children["ChevronFill" .. index] = rotatedPill(
			"ChevronFill" .. index,
			arm.center,
			Vector2.new(13, 5),
			arm.rotation,
			nil,
			zIndex + 3,
			HUD.ChevronFill
		)
	end
end

local function addBolt(children, zIndex)
	-- N-zigzag of three strokes: \ / \
	local bars = {
		{ center = Vector2.new(29.5, 15.5), rotation = 25, size = Vector2.new(9.5, 15.5), fill = Vector2.new(6.5, 12) },
		{ center = Vector2.new(25.75, 23.8), rotation = -38, size = Vector2.new(9.5, 14.5), fill = Vector2.new(6.5, 11) },
		{ center = Vector2.new(22, 32), rotation = 25, size = Vector2.new(9.5, 15.5), fill = Vector2.new(6.5, 12) },
	}
	for index, bar in ipairs(bars) do
		children["BoltOutline" .. index] = rotatedPill(
			"BoltOutline" .. index,
			bar.center,
			bar.size,
			bar.rotation,
			HUD.BoltOutline,
			zIndex + 2
		)
	end
	for index, bar in ipairs(bars) do
		children["BoltFill" .. index] = rotatedPill(
			"BoltFill" .. index,
			bar.center,
			bar.fill,
			bar.rotation,
			nil,
			zIndex + 3,
			HUD.BoltFill
		)
	end
end

local function StatPill(props)
	local zIndex = props.zIndex or 1

	local children = {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = HUD.PillAspect,
		}),
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Gradient = React.createElement("UIGradient", {
			Color = Theme.Chip.OuterGradient,
			Rotation = 90,
		}),
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
		Value = React.createElement(OutlinedText, {
			text = props.value or "",
			position = UDim2.fromScale(HUD.ValuePosition.X, HUD.ValuePosition.Y),
			size = UDim2.fromScale(HUD.ValueSize.X, HUD.ValueSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = props.valueGradient or Theme.Chip.TextGradient,
			outlineColor = props.valueOutline,
			zIndex = zIndex + 2,
		}),
	}

	if props.iconImage then
		children.IconImage = React.createElement("ImageLabel", {
			Name = "IconImage",
			-- 42 of the pill's 48 height: a square glyph under ScaleType.Fit
			-- draws at the zone's shorter side, so this IS the drawn size.
			Position = UDim2.fromScale(5 / 190, 3 / 48),
			Size = UDim2.fromScale(42 / 190, 42 / 48),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.iconImage,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex + 2,
		})
	elseif props.icon == "coin" then
		addCoin(children, zIndex)
	elseif props.icon == "chevrons" then
		addChevrons(children, zIndex)
	elseif props.icon == "bolt" then
		addBolt(children, zIndex)
	end

	return React.createElement("Frame", {
		Name = props.name or "StatPill",
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

return StatPill
