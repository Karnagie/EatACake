--[[
	BossPrizeCard — the STAKE of the boss fight, in the HUD.

	Shows the squishy this player is playing for: art plate on the left, a quiet
	caption + the prize's name on the right, and the whole card wearing the
	PRIZE'S OWN rarity accent (Theme.Rarity), so a Legendary on offer reads at a
	glance. The prize is decided server-side the moment the boss phase opens and
	committed on a win, so what this card shows IS what you get
	(features/cake-cycle.md).

	Archetype: a HUD "reward on offer" strip — ShopTile's plate-left /
	text-column-right shape, ratio-transferred to HUD height (Theme.BossPrize).
	Pure VISUAL, no input: nothing here is tappable, so it carries no Interaction
	press layer (ADR-0006 — only pressables animate).

	props:
	  name?         instance name (default "BossPrizeCard")
	  visible?      boolean (default true)
	  anchorPoint?  Vector2
	  position?     UDim2
	  size?         UDim2 — pair with a UIAspectRatioConstraint from the caller,
	                or let this component's own constraint hold style.AspectRatio
	  zIndex?       number (default 1)
	  captionText   the quiet label above the name (e.g. "FIGHTING FOR")
	  petName       the prize's display name
	  rarity?       Theme.Rarity style key ("Common".."Secret", default Common)
	  iconName?     Theme.Icons key; omitted = a bare plate
	  style?        Theme section override (default Theme.BossPrize)
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
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	})
end

local function BossPrizeCard(props)
	local style = props.style or Theme.BossPrize
	local rarity = Theme.Rarity[props.rarity or "Common"] or Theme.Rarity.Common
	local zIndex = props.zIndex or 1

	return React.createElement("Frame", {
		Name = props.name or "BossPrizeCard",
		Visible = props.visible ~= false,
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		Position = props.position or UDim2.fromScale(0, 0),
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = style.AspectRatio }),
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			rarity.Outer
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			rarity.Rim
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
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.PlateGradient,
				Rotation = 90,
			}),
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
		Caption = React.createElement(OutlinedText, {
			text = props.captionText or "",
			position = UDim2.fromScale(style.CaptionPosition.X, style.CaptionPosition.Y),
			size = UDim2.fromScale(style.CaptionSize.X, style.CaptionSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.CaptionGradient,
			-- style-rules §4.3: outline = the DARK version of the element's OWN hue,
			-- which here is the prize's rarity — not the kit default navy.
			outlineColor = rarity.Outline,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 4,
		}),
		PrizeName = React.createElement(OutlinedText, {
			text = props.petName or "",
			position = UDim2.fromScale(style.NamePosition.X, style.NamePosition.Y),
			size = UDim2.fromScale(style.NameSize.X, style.NameSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = rarity.Text,
			outlineColor = rarity.Outline,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 4,
		}),
	})
end

return BossPrizeCard
