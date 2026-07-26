--[[
	Ribbon — corner tag ("BEST VALUE", "ONE TIME", "NEW").

	Built from the kit's layer recipe (dark Outer pill + accent Face +
	OutlinedText), not from the Ribbon*.png art: that art is a square rosette, so
	at this element's 4:1 aspect ScaleType.Fit shrinks it to a blob behind the
	text. Frames also let the variant carry ONE accent set, so a caller can never
	pair a gold tag with green text.

	Every place that renders one gives it a RESERVED band in its own zone
	arithmetic — a tag is never floated over neighbouring content, because that
	overlap only shows up on the one card that happens to have a tag.

	props:
		text            -- "BEST VALUE"
		variant         -- key into Theme.ShopRibbon.Variants (default "BestValue")
		position, size, zIndex, style
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function Ribbon(props)
	local style = props.style or Theme.ShopRibbon
	local variant = style.Variants[props.variant or "BestValue"] or style.Variants.BestValue
	local zIndex = props.zIndex or 1

	return React.createElement("Frame", {
		Name = props.name or "Ribbon",
		Position = props.position,
		Size = props.size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(style.OuterCorner, 0),
		}),
		OuterGradient = React.createElement("UIGradient", {
			Color = variant.Outer,
			Rotation = 90,
		}),
		Face = React.createElement("Frame", {
			Name = "Face",
			Position = UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
			Size = UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(style.FaceCorner, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = variant.Face,
				Rotation = 90,
			}),
		}),
		Label = React.createElement(OutlinedText, {
			text = props.text or "",
			position = UDim2.fromScale(style.LabelPosition.X, style.LabelPosition.Y),
			size = UDim2.fromScale(style.LabelSize.X, style.LabelSize.Y),
			textGradient = variant.Text,
			outlineColor = variant.Outline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = zIndex + 2,
		}),
	})
end

return Ribbon
