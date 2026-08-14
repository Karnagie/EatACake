--[[ CelebrationBanner
	The BIG transient splash for the game's three celebration beats — a cake
	layer cleared, a crumb monster down, and the Cake Monster down
	(features/food-burst.md). Sibling of the plain AnnounceBanner, deliberately
	NOT a replacement for it: that one is a notification line, this one is a
	moment, and the two never share the screen.

	PURE TYPE — no plate, no card, no background of any kind (the gold plate it
	shipped with for one commit was cut 2026-08-13). What makes it readable over
	a bright cake and 30-odd flying sprites is size plus `OutlinedText`'s own
	thick stroke and shadow copy; what makes it land is the motion.

	Structure (Theme.CelebrationBanner, nominal 900x260):
	  Group (CanvasGroup)   <- the whole splash, so ONE property fades it
	    Pop (UIScale)       <- slam-in / breathe / launch-out
	    Cheer               <- the rolled phrase, gold, huge
	    Sub                 <- optional second line, white, subordinate

	Props: { cheerText?, subText?, seq?, name?, anchorPoint?, position?, size?,
	         zIndex?, style? }

	`seq` is an IDENTITY counter, not a value: two identical cheers in a row
	must still replay the animation, and comparing the text would swallow the
	second one. Bump it on every fire.

	⚠ ADR-0006. The animated properties — `Pop.Scale`, `Group.GroupTransparency`,
	`Group.Rotation` — are ones React NEVER writes here. The HUD re-renders at
	bite frequency (~14/s); a React-controlled property would be snapped back to
	its prop value mid-tween on the next bite and the splash would strobe.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local OutlinedText = require(script.Parent.OutlinedText)

local function CelebrationBanner(props)
	local style = props.style or Theme.CelebrationBanner
	local zIndex = props.zIndex or 1
	local cheerText = props.cheerText
	local subText = props.subText
	local seq = props.seq or 0
	local shown = type(cheerText) == "string" and cheerText ~= ""

	local groupRef = React.useRef(nil)
	local popRef = React.useRef(nil)

	-- ONE effect owns the whole timeline: enter -> breathe+sway -> exit.
	-- Re-keyed on `seq`, so a second celebration inside the first one's lifetime
	-- restarts cleanly instead of layering two tween stacks on the same UIScale.
	--
	-- ⚠ `useLayoutEffect`, NOT `useEffect` (same reason as TutorialSlides'
	-- entrance pop). React commits the CanvasGroup at its PROPERTY DEFAULTS —
	-- Scale 1, Rotation 0, GroupTransparency 0, i.e. full size and fully opaque
	-- — and a passive effect is flushed only AFTER that frame paints. With
	-- `useEffect` the splash appears at full size for one frame, vanishes, then
	-- slams in: a visible double-pop on the beat that fires dozens of times a
	-- run.
	React.useLayoutEffect(function()
		local group = groupRef.current
		local pop = popRef.current
		if not shown or group == nil or pop == nil then
			-- Not a failure path: `shown == false` unmounts the whole subtree,
			-- so there are no refs and nothing to animate. R8 wants a reason,
			-- not a warning — a banner with no text is the resting state.
			return
		end

		-- Pose it BEFORE the frame paints so the first thing on screen is the
		-- small, tilted, invisible state rather than a full-size flash.
		pop.Scale = style.EnterScale
		group.Rotation = style.EnterTilt
		group.GroupTransparency = 1

		local alive = true
		local enter = TweenService:Create(pop, style.EnterTween, { Scale = 1 })
		local straighten = TweenService:Create(group, style.EnterTween, { Rotation = 0 })
		local appear = TweenService:Create(group, style.EnterTween, { GroupTransparency = 0 })
		local breathe: Tween? = nil
		local wobble: Tween? = nil
		local exitScale: Tween? = nil
		local exitFade: Tween? = nil

		enter:Play()
		straighten:Play()
		appear:Play()

		-- Back/Out overshoots past 1 on its own, so the hold loops only start
		-- once the overshoot has settled — otherwise they fight the entrance
		-- over Scale/Rotation and the splash judders on arrival.
		task.delay(style.EnterTween.Time, function()
			if not alive then
				return
			end
			breathe = TweenService:Create(pop, style.BreathTween, { Scale = style.BreathScale })
			breathe:Play()
			-- Sway: seed the far side so the reversing tween covers the whole
			-- arc rather than only half of it. The jump from 0 is ~1.6 degrees.
			group.Rotation = -style.WobbleDegrees
			wobble = TweenService:Create(group, style.WobbleTween, { Rotation = style.WobbleDegrees })
			wobble:Play()
		end)

		task.delay(style.EnterTween.Time + style.HoldSeconds, function()
			if not alive then
				return
			end
			-- Cancel the infinite loops first: an interrupted reversing tween
			-- otherwise keeps writing underneath the exit.
			if breathe then
				breathe:Cancel()
			end
			if wobble then
				wobble:Cancel()
			end
			exitScale = TweenService:Create(pop, style.ExitTween, { Scale = style.ExitScale })
			exitFade = TweenService:Create(group, style.ExitTween, { GroupTransparency = 1 })
			exitScale:Play()
			exitFade:Play()
		end)

		return function()
			alive = false
			enter:Cancel()
			straighten:Cancel()
			appear:Cancel()
			if breathe then
				breathe:Cancel()
			end
			if wobble then
				wobble:Cancel()
			end
			if exitScale then
				exitScale:Cancel()
			end
			if exitFade then
				exitFade:Cancel()
			end
			-- Belt and braces. On a real unmount React has already detached the
			-- ref, and on a `seq` re-key the new effect body re-poses this two
			-- lines in — so in both shipped paths this is a no-op. It stays for
			-- the third path: a future caller that keeps the banner mounted and
			-- swaps only its style would otherwise strand a cancelled fade.
			local instance = groupRef.current
			if instance then
				instance.GroupTransparency = 1
			end
		end
	end, { seq, shown })

	-- After hooks (hook order must not change between renders).
	if not shown then
		return nil
	end

	return React.createElement("Frame", {
		Name = props.name or "CelebrationBanner",
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.AspectRatio,
		}),
		Group = React.createElement("CanvasGroup", {
			Name = "Group",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = zIndex,
			ref = groupRef,
		}, {
			-- The UIScale rides the CanvasGroup itself, not a child: the canvas
			-- re-rasterises at the scaled size, so the overshoot cannot be
			-- clipped by the group's own bounds.
			Pop = React.createElement("UIScale", { ref = popRef }),
			Cheer = React.createElement(OutlinedText, {
				text = cheerText,
				position = UDim2.fromScale(style.CheerPosition.X, style.CheerPosition.Y),
				size = UDim2.fromScale(style.CheerSize.X, style.CheerSize.Y),
				textColor = Color3.new(1, 1, 1),
				textGradient = style.CheerGradient,
				outlineColor = style.CheerOutlineColor,
				textXAlignment = Enum.TextXAlignment.Center,
				zIndex = zIndex + 1,
			}),
			-- Renders only when the caller has something factual to add under
			-- the cheer ("everyone gets a squishy") — the cheer carries the
			-- feeling, this line carries the news.
			Sub = if type(subText) == "string" and subText ~= ""
				then React.createElement(OutlinedText, {
					text = subText,
					position = UDim2.fromScale(style.SubPosition.X, style.SubPosition.Y),
					size = UDim2.fromScale(style.SubSize.X, style.SubSize.Y),
					textColor = Color3.new(1, 1, 1),
					textGradient = style.SubGradient,
					outlineColor = style.SubOutlineColor,
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex + 1,
				})
				else nil,
		}),
	})
end

return CelebrationBanner
