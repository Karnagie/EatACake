--[[
	QuestRow — one quest line for the Quests window's vertical list
	(ShopRow family cell recipe: the 10px vertical gap is baked into the
	cell aspect, no list Padding). Content: quest name, progress pill
	(dark outer > groove > left-anchored fill + centered counter), reward
	line, right-side CLAIM button driven by props.state.

	props:
		id           -- passed to onClaim
		name         -- quest display name ("Eat 50 cakes")
		progress01   -- 0..1, fill fraction of the progress bar
		progressText -- centered counter on the bar ("32/50"; "" hides)
		rewardText   -- reward line ("+500 Coins")
		buttonText   -- claim button label (defaults: "CLAIM"; claimed "DONE")
		state        -- "claim"    = green, clickable
		             -- "progress" = neutral blue, disabled fade
		             -- "claimed"  = neutral blue, disabled fade (done)
		layoutOrder, zIndex, onClaim(id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)

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

local function QuestRow(props)
	local style = props.style or Theme.QuestRow
	local zIndex = props.zIndex or 5
	local state = props.state or "progress"
	local canClaim = state == "claim"
	-- "claim" = green action button; "progress"/"claimed" = the neutral blue
	-- Button look with a centered text zone (ActionButton IS the Button
	-- recipe/gradients with centered text — same geometry as EquipGreen, so
	-- the label doesn't jump when the state flips).
	-- 120x56-aspect variants: the claim zone is 2.14, a 4.06-aspect style
	-- would self-constrain the button to ~53% of the zone height.
	local buttonStyle = if canClaim then Theme.ClaimButton else Theme.ClaimButtonNeutral
	local buttonText = props.buttonText or (if state == "claimed" then "DONE" else "CLAIM")
	local progress = math.clamp(props.progress01 or 0, 0, 1)

	local claimButton = React.createElement(Button, {
		name = "ClaimButton",
		style = buttonStyle,
		position = if canClaim
			then UDim2.fromScale(style.ClaimPosition.X, style.ClaimPosition.Y)
			else UDim2.fromScale(0, 0),
		size = if canClaim
			then UDim2.fromScale(style.ClaimSize.X, style.ClaimSize.Y)
			else UDim2.fromScale(1, 1),
		text = buttonText,
		textXAlignment = Enum.TextXAlignment.Center,
		enabled = canClaim,
		zIndex = zIndex + 3,
		onActivated = function()
			if canClaim and props.onClaim then
				props.onClaim(props.id)
			end
		end,
	})

	-- Kit disabled state: CanvasGroup fade over the claim zone only — the
	-- name/progress/reward text stays fully readable (SettingRow pattern).
	local claim = if canClaim
		then claimButton
		else React.createElement("CanvasGroup", {
			Name = "ClaimDim",
			Position = UDim2.fromScale(style.ClaimPosition.X, style.ClaimPosition.Y),
			Size = UDim2.fromScale(style.ClaimSize.X, style.ClaimSize.Y),
			GroupTransparency = Theme.DayCard.DisabledTransparency,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, { Button = claimButton })

	local bar = React.createElement("Frame", {
		Name = "Bar",
		Position = UDim2.fromScale(style.BarPosition.X, style.BarPosition.Y),
		Size = UDim2.fromScale(style.BarSize.X, style.BarSize.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex + 3,
	}, {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			1,
			zIndex + 3,
			style.BarOuterGradient
		),
		Groove = React.createElement("Frame", {
			Name = "Groove",
			Position = UDim2.fromScale(style.BarGrooveInset.X, style.BarGrooveInset.Y),
			Size = UDim2.fromScale(1 - 2 * style.BarGrooveInset.X, 1 - 2 * style.BarGrooveInset.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 4,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", { Color = style.BarGrooveGradient, Rotation = 90 }),
			Fill = if progress > 0
				then roundedFrame(
					"Fill",
					UDim2.fromScale(0, 0),
					UDim2.fromScale(progress, 1),
					1,
					zIndex + 5,
					style.BarFillGradient
				)
				else nil,
		}),
		Counter = if props.progressText ~= nil and props.progressText ~= ""
			then React.createElement(OutlinedText, {
				text = props.progressText,
				position = UDim2.fromScale(0, 0),
				size = UDim2.fromScale(1, 1),
				textGradient = style.BarTextGradient,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 6,
			})
			else nil,
	})

	local rowChildren = {
		Outer = roundedFrame("Outer", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), style.OuterCorner, zIndex, style.OuterGradient),
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
		QuestName = React.createElement(OutlinedText, {
			text = props.name or "",
			position = UDim2.fromScale(style.NamePosition.X, style.NamePosition.Y),
			size = UDim2.fromScale(style.NameSize.X, style.NameSize.Y),
			textGradient = style.NameGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		}),
		Bar = bar,
		Reward = React.createElement(OutlinedText, {
			text = props.rewardText or "",
			position = UDim2.fromScale(style.RewardPosition.X, style.RewardPosition.Y),
			size = UDim2.fromScale(style.RewardSize.X, style.RewardSize.Y),
			textGradient = style.RewardGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 3,
		}),
		Claim = claim,
	}

	-- List cell with the vertical gap baked into its aspect (see Theme note):
	-- the row content occupies the top ContentHeightInCell of the cell.
	-- In a PLAIN frame list the caller MUST pass an explicit scale height
	-- (props.size) — (1, 0) + FitWithinMaxSize collapses to zero outside an
	-- AutomaticCanvasSize ScrollPane (kit pitfall).
	return React.createElement("Frame", {
		Name = `QuestRow_{tostring(props.id)}`,
		Size = props.size or UDim2.fromScale(1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.CellAspectRatio,
		}),
		Cell = React.createElement("Frame", {
			Name = "Cell",
			Size = UDim2.fromScale(1, style.ContentHeightInCell),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Content = React.createElement("Frame", {
				Name = "Row",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zIndex,
			}, rowChildren),
		}),
	})
end

return QuestRow
