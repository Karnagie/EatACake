--[[ PetRevealOverlay
	Full-screen egg-hatch reveal: dim layer, a PetCard that slot-machine
	cycles rarities (petName "???") for Theme.RevealOverlay.SpinDuration
	before landing on the real pet, then name / sub / continue lines under
	the card, plus an ALWAYS-visible odds footer (Roblox odds-disclosure
	policy). Clicking anywhere dismisses — only after the spin has landed;
	during the spin the overlay still swallows clicks (modal).
	Renders nil when props.reveal is nil or false.
	Props: {
		reveal = { petName: string, rarity: string, subText: string? }?,
		revealCount: number?,  -- bump per reveal to force a new spin on
		                       -- back-to-back reveals (identity counter)
		oddsText: string, continueText: string,
		onDismiss: () -> ()?, zIndex: number? (90),
		style: table? (Theme.RevealOverlay), name: string?
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local PetCard = require(script.Parent.PetCard)

local NOT_LANDED = -1
local SPIN_NAME = "???"

-- Full-width text line whose CENTER sits at the given viewport-fraction point
local function centeredLine(text, center, height, gradient, zIndex)
	return React.createElement(OutlinedText, {
		text = text,
		position = UDim2.fromScale(center.X - 0.5, center.Y - height / 2),
		size = UDim2.fromScale(1, height),
		textColor = Color3.new(1, 1, 1),
		textGradient = gradient,
		textXAlignment = Enum.TextXAlignment.Center,
		zIndex = zIndex,
	})
end

local function PetRevealOverlay(props)
	local style = props.style or Theme.RevealOverlay
	local zIndex = props.zIndex or 90
	local reveal = props.reveal
	local hasReveal = reveal and true or false
	local spinKey = props.revealCount or 0

	-- landedKey == spinKey means the current reveal finished its spin;
	-- spinIndex walks Theme.Rarity.Order while spinning.
	local landedKey, setLandedKey = React.useState(NOT_LANDED)
	local spinIndex, setSpinIndex = React.useState(1)

	React.useEffect(function()
		if not hasReveal then
			-- Reset so the NEXT reveal spins from its very first rendered
			-- frame (no one-frame spoiler of the real pet)
			setLandedKey(NOT_LANDED)
			return
		end
		local alive = true
		local thread = task.spawn(function()
			local steps = math.max(1, math.round(style.SpinDuration / style.SpinStep))
			for step = 1, steps do
				if not alive then
					return
				end
				setSpinIndex(step)
				task.wait(style.SpinStep)
			end
			if alive then
				setLandedKey(spinKey)
			end
		end)
		return function()
			alive = false
			pcall(task.cancel, thread)
		end
	end, { hasReveal, spinKey }) -- boolean + number: jsdotlua deps must never hold nil

	if not hasReveal then
		return nil
	end

	local landed = landedKey == spinKey
	local rarityOrder = Theme.Rarity.Order
	local shownRarity = landed and reveal.rarity or rarityOrder[(spinIndex - 1) % #rarityOrder + 1]
	local shownName = landed and reveal.petName or SPIN_NAME

	-- PetCard bakes a bottom grid gap into its cell (CardHeightInCell < 1):
	-- oversize the holder cell so the VISIBLE card is exactly CardHeight
	-- tall at CardAspect, its top edge at CardPosition.Y - CardHeight / 2
	local cardInCell = Theme.PetCard.CardHeightInCell
	local cellHeight = style.CardHeight / cardInCell
	local cellAspect = style.CardAspect * cardInCell

	local children = {
		Dim = React.createElement("Frame", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = style.DimColor,
			BackgroundTransparency = style.DimTransparency,
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}),
		CardHolder = React.createElement("Frame", {
			Name = "CardHolder",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(style.CardPosition.X, style.CardPosition.Y - style.CardHeight / 2),
			Size = UDim2.fromScale(1, cellHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", {
				AspectRatio = cellAspect,
				AspectType = Enum.AspectType.FitWithinMaxSize,
			}),
			-- Single-cell grid: PetCard's root takes its size from a grid
			-- cell (kit convention), so a 1x1 cell makes it fill the holder
			Grid = React.createElement("UIGridLayout", {
				CellSize = UDim2.fromScale(1, 1),
				CellPadding = UDim2.fromScale(0, 0),
			}),
			Card = React.createElement(PetCard, {
				petName = shownName,
				rarity = shownRarity,
				zIndex = zIndex + 1,
			}),
		}),
		Odds = centeredLine(props.oddsText, style.OddsPosition, style.OddsHeight, style.OddsGradient, zIndex + 2),
		ClickCatcher = React.createElement("TextButton", {
			Name = "ClickCatcher",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			-- Stays Active during the spin so the overlay is modal (blocks
			-- HUD/world clicks); the handler only dismisses after landing
			Active = true,
			Selectable = landed,
			ZIndex = zIndex + 9,
			[React.Event.MouseButton1Click] = function()
				if landed and props.onDismiss then
					props.onDismiss()
				end
			end,
		}),
	}

	if landed then
		children.PetName = centeredLine(reveal.petName, style.NamePosition, style.NameHeight, style.NameGradient, zIndex + 2)
		if reveal.subText and reveal.subText ~= "" then
			children.SubLine = centeredLine(reveal.subText, style.SubPosition, style.SubHeight, style.SubGradient, zIndex + 2)
		end
		children.Continue = centeredLine(props.continueText, style.ContinuePosition, style.ContinueHeight, style.ContinueGradient, zIndex + 2)
	end

	return React.createElement("Frame", {
		Name = props.name or "PetRevealOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

return PetRevealOverlay
