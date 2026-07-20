--[[ HexNode
	One honeycomb node for the upgrades tree — a pure VISUAL (no input; the
	overlay is a single pan/zoom surface that hit-tests taps to nodes). A
	flat-top hex SPRITE stacked Outer/Rim/Face (each an ImageLabel tinted by a
	vertical UIGradient per STATE — the kit bevel on a shape UICorner can't
	make), a centred OutlinedText name + status, and an optional red "!"
	notifier badge (a category with an affordable upgrade inside).

	props: { name, position (centre-anchored UDim2), size (UDim2), zIndex,
		state ("locked"|"available"|"owned"|"category"|"back"|"logo"),
		title, status }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function hexLayer(name, center: Vector2, scale: number, gradient, zIndex: number)
	return React.createElement("ImageLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(center.X, center.Y),
		Size = UDim2.fromScale(scale, scale),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = Theme.HexTree.HexImage,
		ImageColor3 = Color3.new(1, 1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = zIndex,
	}, {
		Gradient = React.createElement("UIGradient", { Color = gradient, Rotation = 90 }),
	})
end

-- NOTE: the "!" notifier is rendered by HexTreeOverlay in a TOP layer (so packed
-- neighbours can't cover it), not here.

local function HexNode(props)
	local hx = Theme.HexTree
	-- "logo" borrows the owned (blue) look; other kinds map 1:1 to a state.
	local state = hx.States[props.state] or hx.States.locked
	local z = props.zIndex or 5

	local layers = {
		Outer = hexLayer("Outer", Vector2.new(0.5, 0.5), 1, state.Outer, z),
		Rim = hexLayer("Rim", hx.RimCenter, hx.RimScale, state.Rim, z + 1),
		Face = hexLayer("Face", hx.FaceCenter, hx.FaceScale, state.Face, z + 2),
		Title = React.createElement(OutlinedText, {
			text = props.title or "",
			position = UDim2.fromScale(hx.NamePosition.X, hx.NamePosition.Y),
			size = UDim2.fromScale(hx.NameSize.X, hx.NameSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = state.Text,
			outlineColor = state.Outline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = z + 3,
		}),
	}
	if props.status ~= nil and props.status ~= "" then
		layers.Status = React.createElement(OutlinedText, {
			text = props.status,
			position = UDim2.fromScale(hx.StatusPosition.X, hx.StatusPosition.Y),
			size = UDim2.fromScale(hx.StatusSize.X, hx.StatusSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = state.Text,
			outlineColor = state.Outline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = z + 3,
		})
	end

	return React.createElement("Frame", {
		Name = props.name or "HexNode",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = hx.HexAspect }),
		Layers = React.createElement("Frame", {
			Name = "Layers",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = z,
		}, layers),
	})
end

return HexNode
