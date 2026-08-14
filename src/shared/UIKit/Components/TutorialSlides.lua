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
	there is no state worth keeping mounted. That unmount is also what arms the
	ENTRANCE below: refs populate exactly on the false -> true edge.

	ENTRANCE (Theme.Feel.SlideIn). The board assembles one piece at a time —
	title, panel 1, 2, 3, 4, then SKIP — each HIDDEN until its `task.delay`
	elapses and then popping from `ClosedScale`. Hiding is the half that makes it
	an arrival rather than a growth spurt: 0.68 is fully opaque, so without it the
	whole board is legible from the first frame.
	Ownership follows ADR-0006 to the letter: the pop rides a
	UIScale inside a centre-anchored `Interaction.pressLayer` wrapper (the panel
	frames are top-left anchored, so a bare UIScale would grow them out of the
	board's 20 px gaps), and React NEVER passes `Scale`. That matters here more
	than usual: the comic is guaranteed to re-render mid-animation — the locale
	repaint lands 0.5-3 s after boot and swaps `titleText`/`skipText` — and a
	React-written Scale would snap every panel back to its closed size.
	Each piece owns one effect keyed on `visible` alone; its cleanup cancels the
	tween and lands the scale on 1, so a SKIP mid-entrance leaves nothing behind.

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
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Theme = require(script.Parent.Parent.Theme)
local Interaction = require(script.Parent.Parent.Interaction)
local OutlinedText = require(script.Parent.OutlinedText)
local Button = require(script.Parent.Button)

-- The ONE value React ever writes for the scrim's transparency: fully clear.
-- The entrance tween fades it to `style.DimTransparency` and owns it from there
-- (ADR-0006, same class of constant as Interaction.ZeroFill / HintArrow.PARKED).
local DIM_CLEAR = 1

-- The ONE value React ever writes for an entrance piece's `Visible`: hidden.
-- The entrance owns it from there, exactly like HintArrow's START_HIDDEN.
local AWAITING_TURN = false

-- One staggered entrance pop. Returns (scaleRef, frameRef): the first goes on an
-- `Interaction.pressLayer` UIScale, the second on the piece's own frame. The
-- caller passes no `Scale` prop and only the constant above for `Visible`, so
-- this effect is the sole writer of both (ADR-0006).
-- The piece is HIDDEN until its delay elapses — a pop from 0.68 is fully opaque,
-- so without this the whole board is legible from frame one and merely grows in
-- sequence, which is not "appearing one after another".
-- `useLayoutEffect` and not `useEffect`: both initial values have to be written
-- BEFORE the frame paints, or every piece flashes at full size first.
local function useEntrancePop(visible: boolean, delaySeconds: number)
	local scaleRef = React.useRef(nil)
	local frameRef = React.useRef(nil)
	React.useLayoutEffect(function()
		local scale = scaleRef.current
		if scale == nil then
			-- Hidden: pressLayer is not mounted, so there is nothing to animate.
			-- Not a failure path — the board is unmounted whenever it is closed.
			return
		end
		local feel = Theme.Feel.SlideIn
		scale.Scale = feel.ClosedScale
		local frame = frameRef.current
		if frame then
			frame.Visible = false
		end
		local alive = true
		local tween = nil
		task.spawn(function()
			-- ⚠ WAIT FOR THE SESSION TO BE ON SCREEN FIRST. A LocalScript runs
			-- well before `game.Loaded`, and this project ships no custom loading
			-- screen — so Roblox's default one is still covering everything while
			-- the comic mounts. Without this gate the entire choreography plays
			-- out behind it and the player's first sight of the board is the
			-- FINISHED board, which is exactly the "they all show at once" report
			-- (2026-08-09). `task.delay` alone could never fix that: the clock has
			-- to start when the player can see, not when React commits.
			if not game:IsLoaded() then
				game.Loaded:Wait()
			end
			if alive and delaySeconds > 0 then
				task.wait(delaySeconds)
			end
			local instance = if alive then scaleRef.current else nil
			if instance == nil then
				return
			end
			local target = frameRef.current
			if target then
				target.Visible = true
			end
			tween = TweenService:Create(instance, feel.Tween, { Scale = 1 })
			tween:Play()
		end)
		-- Cleanup lands BOTH properties on their rest values, so a SKIP mid-
		-- entrance can never leave a piece shrunk or invisible for a re-open.
		return function()
			alive = false
			if tween then
				tween:Cancel()
			end
			local instance = scaleRef.current
			if instance then
				instance.Scale = 1
			end
			local target = frameRef.current
			if target then
				target.Visible = true
			end
		end
	end, { visible })
	return scaleRef, frameRef
end

-- One comic cell. Its own component so each panel carries its own hook pair —
-- the alternative (N refs in the parent) would tie the hook COUNT to the length
-- of Theme.TutorialSlides.PanelPositions.
local function SlidePanel(props)
	local scaleRef, frameRef = useEntrancePop(props.visible, props.delaySeconds)
	local style = props.style
	return React.createElement("Frame", {
		Name = `Panel{props.index}`,
		Position = UDim2.fromScale(props.position.X, props.position.Y),
		Size = UDim2.fromScale(props.size.X, props.size.Y),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = AWAITING_TURN, -- constant; the entrance owns it
		ZIndex = props.zIndex,
		ref = frameRef,
	}, {
		Content = Interaction.pressLayer(
			scaleRef,
			props.zIndex,
			props.render(props.index, props.iconName, style, props.zIndex)
		),
	})
end

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
	-- Coerced: a jsdotlua dep array must never hold nil (a `{nil}` array has
	-- length 0 and compares equal forever, so the effect would never re-run).
	local visible = props.visible == true
	local feel = Theme.Feel.SlideIn
	local panelCount = #style.PanelPositions

	-- Hooks BEFORE the early return (Rules of Hooks). The title leads, the four
	-- panels follow one step apart, the CTA lands last after an extra beat — so
	-- the only way out of the screen is also the last thing to arrive, which is
	-- the point of TailDelay rather than an oversight.
	local titleScaleRef, titleFrameRef = useEntrancePop(visible, feel.LeadDelay)
	local skipScaleRef, skipFrameRef =
		useEntrancePop(visible, feel.LeadDelay + (panelCount + 1) * feel.StepSeconds + feel.TailDelay)
	-- The scrim fades in under all of it. React writes DIM_CLEAR (a constant) and
	-- the tween owns BackgroundTransparency thereafter — same ownership rule as
	-- the UIScales above.
	local dimRef = React.useRef(nil)
	React.useLayoutEffect(function()
		local dim = dimRef.current
		if dim == nil then
			return
		end
		dim.BackgroundTransparency = 1
		local tween = TweenService:Create(dim, feel.FadeTween, { BackgroundTransparency = style.DimTransparency })
		tween:Play()
		return function()
			tween:Cancel()
			local instance = dimRef.current
			if instance then
				instance.BackgroundTransparency = style.DimTransparency
			end
		end
	end, { visible })

	if not visible then
		return nil
	end

	local slides = props.slides or {}
	local boardChildren = {
		Aspect = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = style.BoardAspect,
			AspectType = Enum.AspectType.FitWithinMaxSize,
		}),
		-- ⚠ The title and the CTA each gained a wrapper Frame so the entrance has
		-- a centre-anchored carrier for its UIScale. Their RECTS are unchanged —
		-- the board's 900x958 check-sums still hold.
		Title = React.createElement("Frame", {
			Name = "Title",
			Position = UDim2.fromScale(style.TitlePosition.X, style.TitlePosition.Y),
			Size = UDim2.fromScale(style.TitleSize.X, style.TitleSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = AWAITING_TURN, -- constant; the entrance owns it
			ZIndex = zIndex + 2,
			ref = titleFrameRef,
		}, {
			Content = Interaction.pressLayer(titleScaleRef, zIndex + 2, {
				Text = React.createElement(OutlinedText, {
					text = props.titleText or "",
					position = UDim2.fromScale(0, 0),
					size = UDim2.fromScale(1, 1),
					textColor = Color3.new(1, 1, 1),
					textGradient = style.TitleGradient,
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex + 2,
				}),
			}),
		}),
		Skip = React.createElement("Frame", {
			Name = "Skip",
			Position = UDim2.fromScale(style.SkipPosition.X, style.SkipPosition.Y),
			Size = UDim2.fromScale(style.SkipSize.X, style.SkipSize.Y),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = AWAITING_TURN, -- constant; the entrance owns it
			ZIndex = zIndex + 2,
			ref = skipFrameRef,
		}, {
			Content = Interaction.pressLayer(skipScaleRef, zIndex + 2, {
				-- Name unchanged: `Interaction.deriveId` turns it into the
				-- `SkipButton` analytics id (features/analytics.md).
				Button = React.createElement(Button, {
					name = "SkipButton",
					style = Theme.TutorialSkipButton,
					text = props.skipText or "",
					textXAlignment = Enum.TextXAlignment.Center,
					zIndex = zIndex + 2,
					onActivated = props.onSkip,
				}),
			}),
		}),
	}

	-- Four fixed cells, positioned outright — no UIGridLayout and no
	-- ScrollingFrame, so none of the kit's grid pitfalls (cell collapse, canvas
	-- overflow, float-rounding wrap) can apply here at all.
	for index, position in ipairs(style.PanelPositions) do
		boardChildren[`Panel{index}`] = React.createElement(SlidePanel, {
			index = index,
			iconName = slides[index],
			position = position,
			size = style.PanelSize,
			style = panelStyle,
			zIndex = zIndex + 1,
			visible = visible,
			delaySeconds = feel.LeadDelay + index * feel.StepSeconds,
			render = panel,
		})
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
			-- CONSTANT; the fade tween above owns this property (ADR-0006).
			BackgroundTransparency = DIM_CLEAR,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Active = true,
			Selectable = false,
			ZIndex = zIndex,
			ref = dimRef,
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
