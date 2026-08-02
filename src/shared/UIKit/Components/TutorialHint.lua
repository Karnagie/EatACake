--[[ TutorialHint
	Small centred instruction card: input glyph | headline + body | one CTA.
	Used for "EAT THE CAKE" — the popup that teaches the game's only verb.

	⚠ IT BRINGS NO SCRIM AND NO CLICK CATCHER, deliberately.
	PC eating is a global `UserInputService.InputBegan` guarded by
	`gameProcessed` (CakeSubsClient), so any full-screen Active surface over
	this card would swallow the exact left-click the card is teaching. Only the
	CTA is a TextButton; the card body, the glyph and the text are inert
	(`Active = false` is the default for Frames — nothing here is a button).
	The same reason it sits at `Theme.TutorialHint.Position` (upper-middle):
	clear of the bottom-centre belly bar and of the bottom-right touch EAT
	button on phones.

	Geometry + check-sums: `Theme.TutorialHint`. Card recipe (§2b) — even
	outline, internal zones — because it is a card, not a slab you press.

	Renders nil when `visible` is false.

	Props: {
		visible: boolean,
		titleText: string, bodyText: string,
		glyphMode: "mouse" | "tap", glyphLabel: string?,
		buttonText: string, onDismiss: () -> ()?,
		size: UDim2,          -- viewport-fitted by the caller (aspect held here)
		zIndex: number? (70), style: table?, name: string?
	}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)
local InputGlyph = require(script.Parent.InputGlyph)

local function TutorialHint(props)
	local style = props.style or Theme.TutorialHint
	local zIndex = props.zIndex or 70

	if not props.visible then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "TutorialHint",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(style.Position.X, style.Position.Y),
		Size = props.size or UDim2.fromScale(style.MaxViewportFraction, style.MaxViewportFraction),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.Aspect,
			AspectType = Enum.AspectType.FitWithinMaxSize,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(style.OuterCorner, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = style.OuterGradient,
			Rotation = 90,
		}),
		Stroke = React.createElement("UIStroke", {
			Color = style.OutlineColor,
			LineJoinMode = Enum.LineJoinMode.Round,
			Thickness = 3,
		}),
		Face = React.createElement("Frame", {
			Name = "Face",
			Position = UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			Size = UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(style.FaceCorner, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = style.FaceGradient,
				Rotation = 90,
			}),
		}),
		-- Glyph/title/body/button are siblings of Face (not children): Face's
		-- fractions are of the CARD, and re-basing every zone onto the inset
		-- face would silently shift the check-summed layout by 10px.
		Glyph = React.createElement(InputGlyph, {
			name = "Glyph",
			mode = props.glyphMode,
			-- "tap" only: the word the real on-screen button wears, so the
			-- glyph is a miniature of THAT control, not a generic pink dot.
			label = props.glyphLabel,
			position = UDim2.fromScale(style.GlyphPosition.X, style.GlyphPosition.Y),
			size = UDim2.fromScale(style.GlyphSize.X, style.GlyphSize.Y),
			zIndex = zIndex + 2,
		}),
		Title = React.createElement(OutlinedText, {
			text = props.titleText or "",
			position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.TitleGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 2,
		}),
		Body = React.createElement(OutlinedText, {
			text = props.bodyText or "",
			position = UDim2.fromScale(style.BodyPosition.X, style.BodyPosition.Y),
			size = UDim2.fromScale(style.BodySize.X, style.BodySize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = style.BodyGradient,
			textXAlignment = Enum.TextXAlignment.Left,
			zIndex = zIndex + 2,
		}),
		Cta = React.createElement("Frame", {
			Name = "Cta",
			Position = UDim2.fromScale(style.ButtonPosition.X, style.ButtonPosition.Y),
			Size = UDim2.fromScale(style.ButtonSize.X, style.ButtonSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 2,
		}, {
			Button = React.createElement(Button, {
				name = "GotIt",
				style = Theme.TutorialHintButton,
				text = props.buttonText or "",
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 2,
				onActivated = props.onDismiss,
			}),
		}),
	})
end

return TutorialHint
