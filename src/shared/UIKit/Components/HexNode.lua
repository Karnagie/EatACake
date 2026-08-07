--[[ HexNode
	One honeycomb node for the upgrades tree — a pure VISUAL (no input; the
	overlay is a single pan/zoom surface that hit-tests taps to nodes). A
	flat-top hex SPRITE stacked Outer/Rim/Face (each an ImageLabel tinted by a
	vertical UIGradient per STATE — the kit bevel on a shape UICorner can't
	make), a centred OutlinedText name + status, and an optional red "!"
	notifier badge (a category with an affordable upgrade inside).

	A node may also carry an ICON (a Theme.Icons registry NAME, chosen per stat in
	UpgradeTreeConfig.icons). When it does, the content switches to the
	icon-first cut in Theme.HexTree (`Icon*` zones): glyph on top, name under it,
	status under that — the glyph is what identifies the stat for a player who
	does not read the label. Without one, the original text-only cut is used
	unchanged, so an unmapped stat still renders correctly.

	`pulse = true` breathes the whole node forever — the tree's "you can buy this
	RIGHT NOW" signal (an affordable tier, or a category holding one). It rides
	its OWN UIScale on the root frame, which is centre-anchored, so the hex grows
	around its middle; React never writes that UIScale's `Scale` (ADR-0006), the
	repeating tween is its only writer, and turning `pulse` off returns it to 1
	instead of freezing mid-breath. The node carries no press feedback of its own
	(the overlay hit-tests taps through a single input surface), so there is no
	second scale to collide with.

	props: { name, position (centre-anchored UDim2), size (UDim2), zIndex,
		state ("locked"|"available"|"owned"|"category"|"back"|"logo"),
		title, status, icon (Theme.Icons name, optional), pulse (boolean) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
	-- Every kind maps 1:1 to a `States` entry EXCEPT "logo", which has none — the
	-- logo node is sent `state = "owned"` by LocalUpgradeTree so it borrows the
	-- blue look. ⚠ Passing the literal string "logo" here falls through to
	-- `States.locked`, which since 2026-08-04 also carries `IconTransparency`, so
	-- the mistake now renders gray AND faded rather than merely gray.
	local state = hx.States[props.state] or hx.States.locked
	local z = props.zIndex or 5

	-- Attention breathe (opt-in). The tween REVERSES and repeats forever, so it
	-- is the only writer of this UIScale's Scale; `pulse = false` cancels it and
	-- returns to 1 rather than leaving the hex stuck mid-breath. (React runs the
	-- CLEANUP before the next effect body, so the reset lands first and StopTween
	-- only ever tweens 1 -> 1 — at a 6% peak the snap is imperceptible, and this
	-- matches Components/Button's shipped pulse exactly.) Same recipe
	-- as Components/Button's `pulse` — see Theme.HexTree.Pulse for why the tree
	-- uses a gentler scale than Theme.Feel.Pulse.
	local pulse = props.pulse == true
	local pulseRef = React.useRef(nil)
	React.useEffect(function()
		local scale = pulseRef.current
		if scale == nil then
			return
		end
		local feel = hx.Pulse
		if not pulse then
			TweenService:Create(scale, feel.StopTween, { Scale = 1 }):Play()
			return
		end
		local tween = TweenService:Create(scale, feel.Tween, { Scale = feel.Scale })
		tween:Play()
		return function()
			-- Cancel, then LAND on 1: an interrupted infinite tween otherwise
			-- leaves the node frozen at whatever size the breath reached, and a
			-- tree reflow (buying a tier) unmounts nodes mid-tween constantly.
			tween:Cancel()
			local instance = pulseRef.current
			if instance then
				instance.Scale = 1
			end
		end
	end, { pulse })

	-- The glyph and the text zones move together: a node either has an icon (and
	-- uses the icon-first cut) or it does not (and keeps the original one). Two
	-- half-applied cuts would overlap the name onto the glyph.
	local hasIcon = type(props.icon) == "string" and props.icon ~= ""
	local namePos = if hasIcon then hx.IconNamePosition else hx.NamePosition
	local nameSize = if hasIcon then hx.IconNameSize else hx.NameSize
	local statusPos = if hasIcon then hx.IconStatusPosition else hx.StatusPosition
	local statusSize = if hasIcon then hx.IconStatusSize else hx.StatusSize

	local layers = {
		Outer = hexLayer("Outer", Vector2.new(0.5, 0.5), 1, state.Outer, z),
		Rim = hexLayer("Rim", hx.RimCenter, hx.RimScale, state.Rim, z + 1),
		Face = hexLayer("Face", hx.FaceCenter, hx.FaceScale, state.Face, z + 2),
		Title = React.createElement(OutlinedText, {
			text = props.title or "",
			position = UDim2.fromScale(namePos.X, namePos.Y),
			size = UDim2.fromScale(nameSize.X, nameSize.Y),
			textColor = Color3.new(1, 1, 1),
			textGradient = state.Text,
			outlineColor = state.Outline,
			textXAlignment = Enum.TextXAlignment.Center,
			zIndex = z + 3,
		}),
	}
	if hasIcon then
		layers.Icon = React.createElement("ImageLabel", {
			Name = "Icon",
			Position = UDim2.fromScale(hx.IconPosition.X, hx.IconPosition.Y),
			Size = UDim2.fromScale(hx.IconSize.X, hx.IconSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- Through Theme.Icon, never a raw asset id (kit iron rule 2): it warns
			-- once on an unknown name and returns a visible fallback, so a typo in
			-- UpgradeTreeConfig shows up as a wrong glyph in the console instead of
			-- an invisible one that reads as a layout bug.
			Image = Theme.Icon(props.icon),
			ImageTransparency = state.IconTransparency or 0,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = z + 3,
		})
	end
	if props.status ~= nil and props.status ~= "" then
		layers.Status = React.createElement(OutlinedText, {
			text = props.status,
			position = UDim2.fromScale(statusPos.X, statusPos.Y),
			size = UDim2.fromScale(statusSize.X, statusSize.Y),
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
		-- Mounted unconditionally: the effect above needs the instance in order to
		-- reset to 1 when `pulse` turns off, and a Scale-1 UIScale on a still node
		-- costs nothing. It sits on the root (AnchorPoint 0.5, 0.5) so the
		-- breath grows from the hex's centre.
		PulseScale = React.createElement("UIScale", { ref = pulseRef }),
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
