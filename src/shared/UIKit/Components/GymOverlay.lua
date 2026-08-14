--[[ GymOverlay
	Fat-burn overlay: full-screen transparent layer shown while a burn session
	is active. Bottom-RIGHT round green TAP button (Outer/Rim/Face circle stack,
	the whole button is the hit area — sized/placed for the phone thumb), with a
	"fat left" bar and a percentage label stacked just above it. The bar fill
	eases toward `props.remain01` (the server-streamed remaining-fat fraction,
	1 → 0) via a ~30 Hz task-loop into a binding, so the drain reads smoothly
	between pushes. The rest of the screen stays interactive (the root frame is
	NOT Active) so the player can walk away — which stops the session.
	Props: { active: boolean, remain01: number?, fatText: string,
		buttonText: string, onTap: () -> (), zIndex: number?, style: table?,
		bottomReserve01: number? — viewport fraction Roblox's touch jump button
		owns at the bottom (AppRoot resolves it from Theme.SafeArea) }.
	Style: Theme.GymOverlay (override via props.style). Defaults to zIndex 40.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)

-- Ease step for the fat-bar drain (~30 updates/sec eases smoothly between the
-- server's ~8 Hz progress pushes).
local TICK_SECONDS = 0.03
local EASE = 0.35

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

-- The big round TAP button — a component (not a plain helper) so it can use the
-- shared press primitive: every tap squishes + springs back (satisfying feedback
-- on the button you mash to burn fat). Disabled while no session is active.
local function TapButton(props)
	local style = props.style
	local zIndex = props.zIndex
	local active = props.active

	local scaleRef, handlers = Interaction.usePressable({
		enabled = active,
		onActivated = props.onTap,
	})

	return React.createElement("TextButton", Interaction.merge({
		Name = "TapButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(style.ButtonPosition.X, style.ButtonPosition.Y - (props.lift01 or 0)),
		Size = UDim2.fromScale(0.5, style.ButtonHeight),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Active = active,
		Selectable = active,
		ZIndex = zIndex,
	}, handlers), {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.ButtonAspect,
		}),
		Content = Interaction.pressLayer(scaleRef, zIndex, {
			Outer = roundedFrame(
				"Outer",
				UDim2.fromScale(0, 0),
				UDim2.fromScale(1, 1),
				style.ButtonOuterCorner,
				zIndex,
				style.ButtonOuterGradient
			),
			Rim = roundedFrame(
				"Rim",
				UDim2.fromScale(style.RimPosition.X, style.RimPosition.Y),
				UDim2.fromScale(style.RimSize.X, style.RimSize.Y),
				style.ButtonOuterCorner,
				zIndex + 1,
				style.ButtonRimGradient
			),
			Face = roundedFrame(
				"Face",
				UDim2.fromScale(style.FacePosition.X, style.FacePosition.Y),
				UDim2.fromScale(style.FaceSize.X, style.FaceSize.Y),
				style.ButtonOuterCorner,
				zIndex + 2,
				style.ButtonFaceGradient
			),
			Label = React.createElement(OutlinedText, {
				text = props.buttonText,
				position = UDim2.fromScale(style.TextPosition.X, style.TextPosition.Y),
				size = UDim2.fromScale(style.TextSize.X, style.TextSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.ButtonTextGradient,
				outlineColor = style.ButtonOutline,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 3,
			}),
		}),
	})
end

-- Remaining-fat bar: a groove whose Fill width tracks `fillSize` (binding).
local function fatBar(style, fillSize, zIndex, lift01)
	return React.createElement("Frame", {
		Name = "FatBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(style.BarPosition.X, style.BarPosition.Y - (lift01 or 0)),
		Size = UDim2.fromScale(0.5, style.BarHeight),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.BarAspect,
		}),
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = style.BarOuterGradient,
			Rotation = 90,
		}),
		Groove = React.createElement("Frame", {
			Name = "Groove",
			Position = UDim2.fromScale(style.BarGrooveInset.X, style.BarGrooveInset.Y),
			Size = UDim2.fromScale(1 - style.BarGrooveInset.X * 2, 1 - style.BarGrooveInset.Y * 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Gradient = React.createElement("UIGradient", {
				Color = style.BarGrooveGradient,
				Rotation = 90,
			}),
			Fill = React.createElement("Frame", {
				Name = "Fill",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = fillSize,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = zIndex + 2,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = React.createElement("UIGradient", {
					Color = style.BarFillGradient,
					Rotation = 90,
				}),
			}),
		}),
	})
end

local function GymOverlay(props)
	local style = props.style or Theme.GymOverlay
	local zIndex = props.zIndex or 40
	local active = props.active == true

	local fillFraction, setFillFraction = React.useBinding(1)

	-- Ref so the ease loop always reads the LATEST remain01 without putting an
	-- optional number in the effect's dependency array.
	local remainRef = React.useRef(1)
	remainRef.current = if type(props.remain01) == "number" then math.clamp(props.remain01, 0, 1) else 1

	React.useEffect(function()
		if not active then
			setFillFraction(1)
			return
		end
		local alive = true
		local cur = 1
		task.spawn(function()
			while alive do
				local target = remainRef.current or 0
				-- Ease the DRAIN down; snap on any jump UP (a fresh session resets
				-- remain01 to 1) so the bar can never stick near-empty between
				-- sessions, even if two land in one render batch.
				if target > cur + 0.05 then
					cur = target
				else
					cur += (target - cur) * EASE
					if math.abs(target - cur) < 0.003 then
						cur = target
					end
				end
				setFillFraction(cur)
				task.wait(TICK_SECONDS)
			end
		end)
		return function()
			alive = false
		end
	end, { active })

	local fillSize = fillFraction:map(function(fraction)
		return UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end)

	-- SAFE AREA. This overlay is full-bleed (the rest of the screen must stay
	-- usable), and its thumb button sits in the SAME bottom-right corner as
	-- Roblox's touch jump button — measured overlapping it by 37x15 px at
	-- 1375x1031 on 2026-08-09. `bottomReserve01` is how much of the bottom the
	-- jump button owns, as a viewport fraction (exact here: a full-bleed frame's
	-- height IS the viewport's). The whole cluster — button, bar, counter — lifts
	-- by the amount the BUTTON intrudes, so the composition is preserved.
	local reserve01 = math.max(tonumber(props.bottomReserve01) or 0, 0)
	local buttonBottom01 = style.ButtonPosition.Y + style.ButtonHeight / 2
	local lift01 = math.max(0, reserve01 - (1 - buttonBottom01))

	return React.createElement("Frame", {
		Name = props.name or "GymOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = active,
		ZIndex = zIndex,
	}, {
		TapButton = React.createElement(TapButton, {
			style = style,
			active = active,
			buttonText = props.buttonText,
			onTap = props.onTap,
			zIndex = zIndex + 1,
			lift01 = lift01,
		}),
		FatBar = fatBar(style, fillSize, zIndex + 1, lift01),
		Counter = React.createElement("Frame", {
			Name = "Counter",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(style.CounterPosition.X, style.CounterPosition.Y - lift01),
			Size = UDim2.fromScale(0.5, style.CounterHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Value = React.createElement(OutlinedText, {
				text = props.fatText,
				position = UDim2.fromScale(0, 0),
				size = UDim2.fromScale(1, 1),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.CounterGradient,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 1,
			}),
		}),
	})
end

return GymOverlay
