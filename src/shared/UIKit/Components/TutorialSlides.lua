--[[ TutorialSlides
	The onboarding COMIC: four story panels in a 2x2 board (read TL -> TR ->
	BL -> BR) over a full-screen dim, with one SKIP button bottom-centre.

	Archetype: a Roblox sim's first-session intro — full-bleed scrim, centred
	content block, ONE bottom-centre CTA. Geometry + the check-sums live in
	`Theme.TutorialSlides` / `Theme.TutorialPanel`.

	A panel is a CARD (style-rules §2b: EVEN outline + internal zones), NOT a
	button: it is a framed art window and must not wear the button bevel.
	Each carries an ORDER BADGE — this audience may not read the title, but
	1-2-3-4 is universal (squint-test rule: every element carries a glyph).

	The art is drawn with `ScaleType.Crop`: the window is cut to the source
	art's 4:3, and Crop guarantees a full-bleed panel even if a future slide is
	re-uploaded at a slightly different aspect (Fit would letterbox it with
	background bars inside the frame).

	Renders nil when `visible` is false — the board is a one-shot screen, so
	there is no state worth keeping mounted.

	Props: {
		visible: boolean,
		titleText: string,
		slides: { string },   -- icon NAMES (Theme.Icon resolves), in story order
		skipText: string,
		boardSize: UDim2,     -- viewport-fitted by the caller (aspect held here)
		onSkip: () -> ()?,
		zIndex: number? (95), style/panelStyle: table?, name: string?
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)

local function roundedFrame(name, position, size, corner, zIndex, gradient, outlineColor)
	local children = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(corner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = gradient,
			Rotation = 90,
		}),
	}
	if outlineColor then
		children.Stroke = React.createElement("UIStroke", {
			Color = outlineColor,
			LineJoinMode = Enum.LineJoinMode.Round,
			Thickness = 2,
		})
	end
	return React.createElement("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, children)
end

-- One comic panel: dark Outer -> light Rim ("window frame") -> art -> order
-- badge. All fractions are of the panel's OWN 440x336 nominal grid.
local function panel(index: number, iconName: string?, style, zIndex: number)
	local badgeInset = style.BadgeTextInset
	return {
		Outer = roundedFrame(
			"Outer",
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			style.OuterCorner,
			zIndex,
			style.OuterGradient,
			style.OutlineColor
		),
		Rim = roundedFrame(
			"Rim",
			UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
			UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
			style.RimCorner,
			zIndex + 1,
			style.RimGradient
		),
		Art = React.createElement("ImageLabel", {
			Name = "Art",
			Position = UDim2.fromScale(style.ArtPosition.X, style.ArtPosition.Y),
			Size = UDim2.fromScale(style.ArtSize.X, style.ArtSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(iconName),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = zIndex + 2,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(style.ArtCorner, 0),
			}),
		}),
		Badge = React.createElement("Frame", {
			Name = "Badge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(style.BadgeCenter.X, style.BadgeCenter.Y),
			Size = UDim2.fromScale(style.BadgeSize.X, style.BadgeSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 3,
		}, {
			Corner = React.createElement("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Gradient = React.createElement("UIGradient", {
				Color = style.BadgeFillGradient,
				Rotation = 90,
			}),
			Stroke = React.createElement("UIStroke", {
				Color = style.BadgeRingColor,
				LineJoinMode = Enum.LineJoinMode.Round,
				Thickness = 3,
			}),
			Number = React.createElement(OutlinedText, {
				text = tostring(index),
				position = UDim2.fromScale(badgeInset, badgeInset),
				size = UDim2.fromScale(1 - badgeInset * 2, 1 - badgeInset * 2),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.BadgeTextGradient,
				outlineColor = style.BadgeTextOutline,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 4,
			}),
		}),
	}
end

local function TutorialSlides(props)
	local style = props.style or Theme.TutorialSlides
	local panelStyle = props.panelStyle or Theme.TutorialPanel
	local zIndex = props.zIndex or 95

	if not props.visible then
		return nil
	end

	local slides = props.slides or {}
	local boardChildren = {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.BoardAspect,
			AspectType = Enum.AspectType.FitWithinMaxSize,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.titleText or "",
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TitleGradient,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 2,
		}),
		Skip = React.createElement("Frame", {
			Name = "Skip",
			Position = UDim2.fromScale(style.SkipPosition.X, style.SkipPosition.Y),
			Size = UDim2.fromScale(style.SkipSize.X, style.SkipSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
		}, {
			Button = React.createElement(Button, {
				name = "SkipButton",
				style = Theme.TutorialSkipButton,
				text = props.skipText or "",
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 2,
				onActivated = props.onSkip,
			}),
		}),
	}

	-- Four fixed cells, positioned outright — no UIGridLayout and no
	-- ScrollingFrame, so none of the kit's grid pitfalls (cell collapse, canvas
	-- overflow, float-rounding wrap) can apply here at all.
	for index, position in ipairs(style.PanelPositions) do
		boardChildren[`Panel{index}`] = React.createElement("Frame", {
			Name = `Panel{index}`,
			Position = UDim2.fromScale(position.X, position.Y),
			Size = UDim2.fromScale(style.PanelSize.X, style.PanelSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, panel(index, slides[index], panelStyle, zIndex + 1))
	end

	return React.createElement("Frame", {
		Name = props.name or "TutorialSlides",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		-- MODAL on purpose: while the comic is up there is nothing else to do,
		-- and swallowing clicks here also stops the PC hold-to-eat from firing
		-- behind the board (CakeSubsClient's InputBegan honours `gameProcessed`).
		Dim = React.createElement("TextButton", {
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = style.DimColor,
			BackgroundTransparency = style.DimTransparency,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			Selectable = false,
			ZIndex = zIndex,
		}),
		Board = React.createElement("Frame", {
			Name = "Board",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = props.boardSize or UDim2.fromScale(style.BoardMaxViewportFraction, style.BoardMaxViewportFraction),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, boardChildren),
	})
end

return TutorialSlides
