--[[
	DayCard — one day/milestone card for reward grids (PetCard family).

	props:
		id           -- passed to onActivated
		title        -- "Day 3" / "10:00"
		rewardText   -- "+300 Gold"
		subText      -- state line ("Claim!", "Tomorrow", countdown, "")
		state        -- "claimable" | "claimed" | "locked" | "tomorrow"
		layoutOrder, zIndex, onActivated(id)

	States (kit rules): claimable = gold Outer/Rim swap (selection rule) +
	clickable; claimed = green check badge; locked/tomorrow = CanvasGroup
	dimmed (SettingRow disabled recipe). Only "claimable" accepts clicks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
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
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(corner, 0) }),
		Gradient = React.createElement("UIGradient", { Color = gradient, Rotation = 90 }),
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
		Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
	})
end

local function DayCard(props)
	local style = props.style or Theme.DayCard
	local zIndex = props.zIndex or 5
	local state = props.state or "locked"
	local claimable = state == "claimable"

	local outerGradient = if claimable then style.ClaimableOuterGradient else Theme.Button.OuterGradient
	local rimGradient = if claimable then style.ClaimableRimGradient else Theme.Button.RimGradient

	local cardChildren = {
		Outer = roundedFrame("Outer", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), style.OuterCorner, zIndex, outerGradient),
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
			Theme.Button.FaceGradient
		),
		Title = React.createElement(OutlinedText, {
			text = props.title or "",
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textGradient = style.TitleGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
		Reward = React.createElement(OutlinedText, {
			text = props.rewardText or "",
			position = UDim2.fromScale(style.RewardPosition.X, style.RewardPosition.Y),
			size = UDim2.fromScale(style.RewardSize.X, style.RewardSize.Y),
			textGradient = style.RewardGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
		Sub = React.createElement(OutlinedText, {
			text = props.subText or "",
			position = UDim2.fromScale(style.SubPosition.X, style.SubPosition.Y),
			size = UDim2.fromScale(style.SubSize.X, style.SubSize.Y),
			textGradient = style.RewardGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 3,
		}),
	}

	if state == "claimed" then
		cardChildren.ClaimedBadge = React.createElement("Frame", {
			Name = "ClaimedBadge",
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
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			}),
			Fill = React.createElement("Frame", {
				Name = "Fill",
				Position = UDim2.fromScale(0.13, 0.13),
				Size = UDim2.fromScale(0.74, 0.74),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 6,
			}, {
				Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = React.createElement("UIGradient", { Color = style.BadgeGradient, Rotation = 90 }),
			}),
			CheckA = pill("CheckA", Vector2.new(0.36, 0.58), Vector2.new(0.34, 0.16), 45, style.CheckColor, zIndex + 7),
			CheckB = pill("CheckB", Vector2.new(0.58, 0.48), Vector2.new(0.52, 0.16), -45, style.CheckColor, zIndex + 7),
		})
	end

	local button = React.createElement("TextButton", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = claimable,
		Selectable = claimable,
		ZIndex = zIndex,
		[React.Event.MouseButton1Click] = function()
			if claimable and props.onActivated then
				props.onActivated(props.id)
			end
		end,
	}, cardChildren)

	local content
	if state == "locked" or state == "tomorrow" then
		-- Disabled recipe (SettingRow): CanvasGroup dim; still shows texts.
		content = React.createElement("CanvasGroup", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			GroupTransparency = style.DisabledTransparency,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, { Card = button })
	else
		content = button
	end

	return React.createElement("Frame", {
		Name = props.name or `DayCard_{tostring(props.id)}`,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Content = content,
	})
end

return DayCard
