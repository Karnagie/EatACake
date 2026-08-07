--[[ SocialPanel
	One offer, one button — the shape both social rewards want:

	  Invite Friends   (features/referrals.md)  "500 Gems per friend" + INVITE
	  Community reward (features/group-reward.md) "like + join for a boost" + GET REWARD

	Art window / headline / body / status line / CTA, on the portrait Panel family
	(Theme.SocialLayout). It is a pure presentation shell: it owns no state, makes
	no decision about whether the button should be live, and never talks to a
	remote — the wiring lives in a subscription (R4).

	props:
		name, title, size, visible, zIndex, onClose
		iconName                -- Theme.Icons NAME (never a raw asset id)
		headlineText, bodyText
		statusText, statusKind  -- "ok" | "error" | nil (hides the line)
		buttonText, buttonEnabled (default true), onActivated

	The CTA is wrapped in a CanvasGroup that dims the whole button when it is not
	pressable, rather than only greying its label — "already claimed" has to read
	at a glance, and Components.Button carries no disabled palette of its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local PanelWithHeader = require(script.Parent.PanelWithHeader)
local Button = require(script.Parent.Button)
local OutlinedText = require(script.Parent.OutlinedText)

local function SocialPanel(props)
	local layout = props.layout or Theme.SocialLayout
	local enabled = props.buttonEnabled ~= false
	local statusText = props.statusText
	local hasStatus = type(statusText) == "string" and statusText ~= ""

	local children = {
		-- The offer's face. Square zone (ScaleType.Fit draws at the shorter side),
		-- resolved through Theme.Icon so an unknown name warns once and still
		-- renders something visible instead of a blank that reads as a layout bug.
		Art = React.createElement("ImageLabel", {
			Name = "Art",
			Position = UDim2.fromScale(layout.ArtPosition.X, layout.ArtPosition.Y),
			Size = UDim2.fromScale(layout.ArtSize.X, layout.ArtSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Icon(props.iconName),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		}),
		Headline = React.createElement(OutlinedText, {
			text = props.headlineText or "",
			position = UDim2.fromScale(layout.HeadlinePosition.X, layout.HeadlinePosition.Y),
			size = UDim2.fromScale(layout.HeadlineSize.X, layout.HeadlineSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = layout.HeadlineGradient,
			outlineColor = layout.TextOutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = 5,
		}),
		-- Plain wrapped label, not OutlinedText: this zone holds two lines of prose
		-- and TextScaled binds on WIDTH, so a stroke on every glyph at that size is
		-- noise rather than legibility (ui-kit gotcha).
		Body = React.createElement("TextLabel", {
			Name = "Body",
			Position = UDim2.fromScale(layout.BodyPosition.X, layout.BodyPosition.Y),
			Size = UDim2.fromScale(layout.BodySize.X, layout.BodySize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			FontFace = Theme.Font,
			Text = props.bodyText or "",
			TextColor3 = layout.BodyColor,
			TextScaled = true,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 5,
		}, {
			Constraint = React.createElement("UITextSizeConstraint", { MaxTextSize = layout.BodyMaxTextSize }),
		}),
		-- The group is INFLATED about the button's centre and the button DEFLATED by
		-- the same factor inside it: rest geometry identical, but the hover/press
		-- bounce `usePressable` gives every kit button now has room. A CanvasGroup
		-- clips to its own bounds, so without this the 1.05 hover pose is shaved on
		-- all four sides (ui-kit gotcha).
		Cta = React.createElement("CanvasGroup", {
			Name = "Cta",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(
				layout.ButtonPosition.X + layout.ButtonSize.X / 2,
				layout.ButtonPosition.Y + layout.ButtonSize.Y / 2
			),
			Size = UDim2.fromScale(
				layout.ButtonSize.X * layout.ButtonPressHeadroom,
				layout.ButtonSize.Y * layout.ButtonPressHeadroom
			),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			GroupTransparency = if enabled then 0 else layout.ButtonDisabledTransparency,
			ZIndex = 5,
		}, {
			Button = React.createElement(Button, {
				name = "SocialButton",
				style = Theme.EquipGreen,
				anchorPoint = Vector2.new(0.5, 0.5),
				position = UDim2.fromScale(0.5, 0.5),
				size = UDim2.fromScale(1 / layout.ButtonPressHeadroom, 1 / layout.ButtonPressHeadroom),
				text = props.buttonText or "",
				textXAlignment = Enum.TextXAlignment.Center,
				enabled = enabled,
				zIndex = 5,
				onActivated = props.onActivated,
			}),
		}),
	}

	if hasStatus then
		children.Status = React.createElement(OutlinedText, {
			text = statusText,
			position = UDim2.fromScale(layout.StatusPosition.X, layout.StatusPosition.Y),
			size = UDim2.fromScale(layout.StatusSize.X, layout.StatusSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = if props.statusKind == "ok" then layout.StatusOkGradient else layout.StatusErrorGradient,
			outlineColor = layout.TextOutlineColor,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = 5,
		})
	end

	return React.createElement(PanelWithHeader, {
		name = props.name or "SocialPanel",
		size = props.size,
		visible = props.visible,
		title = props.title,
		onClose = props.onClose,
		zIndex = props.zIndex,
	}, children)
end

return SocialPanel
