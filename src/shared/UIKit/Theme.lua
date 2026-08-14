-- Layout values are normalized Scale ratios. SourceRects are raster sampling coordinates only.

-- Icon registry (name -> rbxassetid). Lives in its own module so Theme.lua
-- stays about STYLE, but it is reached as `Theme.Icons.X` — components take an
-- icon NAME and never inline an asset id (iron rule 2). See Icons.lua header.
local Icons = require(script.Parent.Icons)
local Log = require(script.Parent.Parent.Log)

local Theme = {
	Colors = {
		Outline = Color3.fromRGB(4, 42, 64),
		TextOutline = Color3.fromRGB(27, 42, 53),
		DeepShadow = Color3.fromRGB(0, 43, 67),
		PanelLight = Color3.fromRGB(245, 244, 249),
		PanelBlue = Color3.fromRGB(187, 231, 255),
		PanelStripe = Color3.fromRGB(123, 214, 255),
		BlueRim = Color3.fromRGB(73, 190, 255),
		BlueTop = Color3.fromRGB(64, 180, 255),
		BlueBottom = Color3.fromRGB(77, 156, 255),
		BlueHighlight = Color3.fromRGB(196, 242, 255),
		Text = Color3.fromRGB(166, 215, 255),
		TextDisabled = Color3.fromRGB(218, 238, 248),
		HeaderText = Color3.fromRGB(174, 218, 255),
		ToggleRim = Color3.fromRGB(121, 162, 164),
		ToggleOn = Color3.fromRGB(100, 255, 129),
		ToggleOff = Color3.fromRGB(255, 103, 102),
		TrackOnTop = Color3.fromRGB(250, 255, 253),
		TrackOnBottom = Color3.fromRGB(194, 255, 226),
		TrackOffTop = Color3.fromRGB(255, 248, 251),
		TrackOffBottom = Color3.fromRGB(255, 185, 205),
		CloseRim = Color3.fromRGB(122, 17, 32),
		CloseTop = Color3.fromRGB(255, 91, 105),
		CloseBottom = Color3.fromRGB(226, 42, 65),
		CloseX = Color3.fromRGB(255, 183, 193),
	},
	Gradients = {
		Row = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(77, 156, 255)),
		}),
		Panel = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 244, 249)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(181, 228, 255)),
		}),
		Close = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 91, 105)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(226, 42, 65)),
		}),
	},
	Toggle = {
		AspectRatio = 90 / 52,
		OuterCorner = 1,
		TrackPosition = Vector2.new(4 / 90, 5 / 52),
		TrackSize = Vector2.new(81 / 90, 40 / 52),
		TrackCorner = 1,
		KnobOnCenter = Vector2.new(64.5 / 90, 25 / 52),
		KnobOffCenter = Vector2.new(25.5 / 90, 25 / 52),
		KnobSize = Vector2.new(32 / 90, 32 / 52),
		KnobFillPosition = Vector2.new(3.5 / 32, 3.5 / 32),
		KnobFillSize = Vector2.new(25 / 32, 25 / 32),
		OuterGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 79, 120)),
			ColorSequenceKeypoint.new(0.02, Color3.fromRGB(0, 36, 64)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(0, 44, 69)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(0, 38, 60)),
			ColorSequenceKeypoint.new(0.94, Color3.fromRGB(0, 32, 59)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 43, 83)),
		}),
		TrackOnGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 255, 253)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(225, 255, 242)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(194, 255, 226)),
		}),
		TrackOffGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 253)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 244, 246)),
			ColorSequenceKeypoint.new(0.60, Color3.fromRGB(255, 220, 225)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 193, 202)),
		}),
		KnobOnOutlineColor = Color3.fromRGB(0, 91, 18),
		KnobOnGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 255, 132)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 248, 113)),
		}),
		KnobOffOutlineColor = Color3.fromRGB(95, 10, 11),
		KnobOffColor = Color3.fromRGB(255, 103, 102),
	},
	Header = {
		AspectRatio = 512 / 116,
		OuterCorner = 0.20,
		RimPosition = Vector2.new(8 / 512, 9 / 116),
		RimSize = Vector2.new(496 / 512, 93 / 116),
		RimCorner = 0.18,
		FacePosition = Vector2.new(15 / 512, 12.5 / 116),
		FaceSize = Vector2.new(482 / 512, 83.5 / 116),
		FaceCorner = 0.16,
		TitlePosition = Vector2.new(146 / 512, 19 / 116),
		TitleSize = Vector2.new(220 / 512, 59.6 / 116),
		CloseCenter = Vector2.new(457 / 512, 54 / 116),
		CloseSize = Vector2.new(61 / 512, 63 / 116),
		OutlineColor = Color3.fromRGB(0, 40, 64),
		OuterGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 46, 75)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(0, 41, 67)),
			ColorSequenceKeypoint.new(0.82, Color3.fromRGB(0, 42, 67)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 38, 60)),
		}),
		RimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(123, 195, 252)),
			ColorSequenceKeypoint.new(0.08, Color3.fromRGB(133, 201, 255)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(141, 201, 251)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(133, 195, 252)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 202, 252)),
		}),
		FaceGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(127, 195, 255)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(87, 187, 255)),
			ColorSequenceKeypoint.new(0.12, Color3.fromRGB(64, 180, 255)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(69, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 158, 255)),
		}),
		TitleGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 244, 255)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(190, 230, 252)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(152, 201, 250)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(113, 174, 248)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 158, 240)),
		}),
	},
	Panel = {
		AspectRatio = 512 / 727,
		ShadowPosition = Vector2.new(27 / 512, 91 / 727),
		ShadowSize = Vector2.new(458 / 512, 636 / 727),
		ShadowCorner = 0.070,
		BorderPosition = Vector2.new(27 / 512, 84 / 727),
		BorderSize = Vector2.new(458 / 512, 629 / 727),
		BorderCorner = 0.060,
		FillPosition = Vector2.new(35 / 512, 92 / 727),
		FillSize = Vector2.new(442 / 512, 613 / 727),
		FillCorner = 0.058,
		ShadowGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 44, 69)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 42, 67)),
		}),
		BorderGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 46, 72)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(0, 42, 66)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 41, 65)),
		}),
		FillGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(252, 253, 255)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(248, 253, 255)),
			ColorSequenceKeypoint.new(0.11, Color3.fromRGB(245, 250, 252)),
			ColorSequenceKeypoint.new(0.20, Color3.fromRGB(239, 248, 251)),
			ColorSequenceKeypoint.new(0.29, Color3.fromRGB(234, 248, 252)),
			ColorSequenceKeypoint.new(0.38, Color3.fromRGB(229, 245, 252)),
			ColorSequenceKeypoint.new(0.47, Color3.fromRGB(225, 242, 253)),
			ColorSequenceKeypoint.new(0.56, Color3.fromRGB(216, 240, 252)),
			ColorSequenceKeypoint.new(0.64, Color3.fromRGB(212, 239, 252)),
			ColorSequenceKeypoint.new(0.73, Color3.fromRGB(205, 235, 253)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(204, 235, 254)),
			ColorSequenceKeypoint.new(0.86, Color3.fromRGB(209, 236, 254)),
			ColorSequenceKeypoint.new(0.90, Color3.fromRGB(204, 235, 254)),
			ColorSequenceKeypoint.new(0.94, Color3.fromRGB(195, 232, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(166, 219, 253)),
		}),
	},
	Button = {
		AspectRatio = 418 / 103,
		OuterCorner = 0.20,
		RimPosition = Vector2.new(6 / 418, 6 / 103),
		RimSize = Vector2.new(406 / 418, 84.5 / 103),
		RimCorner = 0.18,
		FacePosition = Vector2.new(9 / 418, 8 / 103),
		FaceSize = Vector2.new(400 / 418, 80.5 / 103),
		FaceCorner = 0.17,
		TextPosition = Vector2.new(22 / 418, 23 / 103),
		TextSize = Vector2.new(270 / 418, 50 / 103),
		OutlineColor = Color3.fromRGB(4, 42, 64),
		OuterGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 47, 73)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(0, 41, 67)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(0, 42, 67)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 44, 64)),
		}),
		RimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 39, 67)),
			ColorSequenceKeypoint.new(0.02, Color3.fromRGB(50, 146, 200)),
			ColorSequenceKeypoint.new(0.04, Color3.fromRGB(73, 190, 255)),
			ColorSequenceKeypoint.new(0.06, Color3.fromRGB(73, 190, 255)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(68, 164, 244)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(43, 124, 229)),
		}),
		FaceGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(73, 190, 255)),
			ColorSequenceKeypoint.new(0.04, Color3.fromRGB(66, 183, 255)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(70, 168, 255)),
			ColorSequenceKeypoint.new(0.935, Color3.fromRGB(74, 159, 253)),
			ColorSequenceKeypoint.new(0.95, Color3.fromRGB(39, 125, 248)),
			ColorSequenceKeypoint.new(0.97, Color3.fromRGB(31, 124, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 122, 228)),
		}),
		TextGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 244, 255)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(190, 230, 252)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(152, 201, 250)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(113, 174, 248)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 158, 240)),
		}),
	},
	Exit = {
		AspectRatio = 61 / 63,
		OuterCorner = 0.315,
		RimPosition = Vector2.new(0.10, 0.085),
		RimSize = Vector2.new(0.80, 0.785),
		RimCorner = 0.23,
		InnerRimPosition = Vector2.new(0.125, 0.115),
		InnerRimSize = Vector2.new(0.75, 0.735),
		InnerRimCorner = 0.215,
		FacePosition = Vector2.new(0.15, 0.145),
		FaceSize = Vector2.new(0.70, 0.685),
		FaceCorner = 0.20,
		XCenter = Vector2.new(0.5, 0.475),
		XOutlineSize = Vector2.new(0.53, 0.20),
		XFillSize = Vector2.new(0.36, 0.10),
		OuterGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(51, 0, 14)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(66, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(49, 0, 13)),
		}),
		RimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 119, 128)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(225, 101, 109)),
		}),
		InnerRimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 118, 130)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 117, 130)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 96, 114)),
		}),
		FaceGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 111, 127)),
			ColorSequenceKeypoint.new(0.12, Color3.fromRGB(255, 92, 110)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 67, 94)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 46, 74)),
		}),
		XOutline = Color3.fromRGB(61, 0, 10),
		XGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 207, 211)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(254, 167, 175)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 138, 150)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(248, 122, 136)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(245, 92, 113)),
		}),
	},
	Font = Font.new(
		"rbxasset://fonts/families/FredokaOne.json",
		Enum.FontWeight.Regular,
		Enum.FontStyle.Normal
	),
	Layout = {
		PanelAspect = 512 / 727,
		PanelMaxViewportFraction = 0.92,
		HeaderHeight = 116 / 727,
		RowsPosition = Vector2.new(47 / 512, 128 / 727),
		RowsSize = Vector2.new(418 / 512, 563 / 727),
		RowHeight = 103 / 563,
		RowGap = 12 / 563,
		TogglePosition = Vector2.new(349 / 418, 51 / 103),
		ToggleSize = Vector2.new(91 / 418, 52 / 103),
		TextPosition = Vector2.new(19 / 418, 20 / 103),
		TextSize = Vector2.new(270 / 418, 50 / 103),
		ClosePosition = Vector2.new(459 / 512, 53 / 727),
		CloseSize = Vector2.new(61 / 512, 63 / 727),
	},
}

-- ===== Motion / "juice" (shared feel for every interactive element) =====
-- One place tuning the whole UI's responsiveness. Press feedback (usePressable,
-- Interaction.lua), panel open/close pops (PanelShell), badge pop-ins (Badge),
-- and bar-fill glides (BellyBar/CakeBar) all read from here.
Theme.Feel = {
	-- Button press/hover bounce (UIScale multipliers).
	HoverScale = 1.05,
	PressScale = 0.93,
	PressTween = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ReleaseTween = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Panel window open (springy pop) / close (quick shrink then hide).
	PanelClosedScale = 0.85,
	PanelOpenTween = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	PanelCloseTween = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- Notification badge pop-in from nothing.
	BadgePopTween = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Progress bars gliding to a new fill instead of snapping.
	FillTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Settings toggle knob sliding across its track.
	ToggleTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

-- ===== Squish: the theme's motion signature (squash & stretch) =====
-- UIScale is UNIFORM — it cannot squash. Squash needs anti-correlated X/Y
-- (sx*sy ≈ 1, so the shape deforms but the "volume" reads constant). The only
-- ADR-0006-safe carrier is the `Size` of Interaction's `Content` frame: React
-- writes it exactly once with a value that never changes (Interaction.FullSize)
-- and then diffs it away forever — the same sanctioned trick as ZeroFill /
-- KNOB_INITIAL. NEVER squash a Size that React recomputes (PanelShell.size,
-- grid cells): the reconciler would clobber the tween on the next render.
-- Poses are Vector2(scaleX, scaleY) fed through usePressable's `squash` opt-in.
Theme.Feel.Squish = {
	-- (a) button press: flatten while held, spring back on release.
	PressPose = Vector2.new(1.08, 0.90), -- 1.08*0.90 = 0.972 ≈ volume preserved
	PressTween = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	ReleaseTween = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- (b) collection card: a gentle vertical stretch on hover, hard squash on press.
	CardHoverPose = Vector2.new(0.970, 1.045),
	CardHoverTween = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	CardPressPose = Vector2.new(1.10, 0.88),
	-- (c) GRID CELL flush against a clip edge — never grows past 1.0 in X.
	-- A ScrollingFrame CLIPS, and a deterministic grid packs its columns to the
	-- canvas edges exactly (3*282 + 2*12 = 870), so there is ZERO horizontal
	-- slack. The (b) poses combine with the uniform UIScale to 1.05*0.970 = 1.019
	-- on hover and 0.93*1.10 = 1.023 on press — which shaves ~3px off the outer
	-- columns' dark outline, and ~10px off a full-width banner's, every time the
	-- pointer touches one. Callers using these poses ALSO pass
	-- `hoverScale = 1, pressScale = 1`: the UIScale is uniform, so it cannot be
	-- part of an X-safe deform. The squash survives — it just runs on Y, which
	-- has budget (`ShopLayout.CanvasTopPadPx`).
	GridCellHoverPose = Vector2.new(0.985, 1.030),
	GridCellPressPose = Vector2.new(0.995, 0.920),
	-- Panel-jelly, reward-splat and idle-breath poses were designed alongside
	-- these but are NOT shipped: they had no call sites, and naming one of them
	-- PanelOpenTween would have SHADOWED the live Theme.Feel.PanelOpenTween that
	-- PanelShell actually reads — two identically named knobs, one of them dead.
	-- Add them back WITH their call site, not before it.
}
table.freeze(Theme.Feel.Squish)

-- ===== Safe area: where Roblox's OWN GUI sits, and how far to stay off it =====
-- The root ScreenGui is FULL-BLEED on purpose (UiRoot) so that modal SCRIMS
-- cover the topbar strip. That is only HALF a contract: a surface may cover the
-- whole screen, but anything that PLACES A CONTROL still has to keep off
-- Roblox's CoreGui furniture, which is drawn above every player GUI and cannot
-- be moved, resized or switched off.
--
-- MEASURED live (Studio play, viewport 1375x1031, 2026-08-09):
--   GuiService:GetGuiInset().Y = 58            -- the strip's height
--   GuiService.TopbarInset     = Rect(208, 0, 1375, 58)
--                                 Max.Y = the strip's BOTTOM edge;
--                                 Min.X = where Roblox's own left chip ENDS
--   unibar chip (left)  x  16..204   y  10..58   (logo / nine-dot / chat / mic)
--   touch JUMP button   x 1205..1325 y 821..941  (120 px; 50 right, 90 bottom)
--   touch thumbstick    x   58..206  y 845..993
--
-- ⚠ `GetGuiInset()` is the LEGACY value and can under-report the modern unibar,
-- so the resolver in AppRoot takes the MAX of it and `TopbarInset.Max.Y`.
Theme.SafeArea = {
	-- Extra clearance below the strip. The HUD's own top margin is a viewport
	-- FRACTION of the region left under the bar, so it SHRINKS as the window
	-- does (23 px at 1080p, ~8 px on a phone) while the bar stays a fixed pixel
	-- height — this pad is what stops a phone parking the calories pill on the
	-- unibar's rounded corner.
	TopPadPx = 10,
	-- Sanity clamp: a client reporting a nonsense TopbarInset must not be able
	-- to push the whole HUD off the screen.
	MaxTopInsetPx = 140,
	-- Roblox sizes its touch JUMP button min(0.20 * shorterAxis, 120) and hangs
	-- it off the bottom-right corner. 1.75x the button covers button + margin
	-- (measured: 210 px of 1031 at the reference above), and the pad keeps our
	-- own control from touching it.
	TouchButtonFraction = 0.20,
	TouchButtonMaxPx = 120,
	TouchButtonReserveMult = 1.75,
	TouchCornerPadPx = 16,
}
table.freeze(Theme.SafeArea)

-- ===== Wide (landscape) panel family. Nominal grids: panel 1000x600, header 1000x120. =====

Theme.PanelWide = {
	AspectRatio = 1000 / 600,
	ShadowPosition = Vector2.new(28 / 1000, 93 / 600),
	ShadowSize = Vector2.new(944 / 1000, 507 / 600),
	ShadowCorner = 0.063,
	BorderPosition = Vector2.new(28 / 1000, 86 / 600),
	BorderSize = Vector2.new(944 / 1000, 497 / 600),
	BorderCorner = 0.055,
	FillPosition = Vector2.new(38 / 1000, 96 / 600),
	FillSize = Vector2.new(924 / 1000, 477 / 600),
	FillCorner = 0.054,
	ShadowGradient = Theme.Panel.ShadowGradient,
	BorderGradient = Theme.Panel.BorderGradient,
	FillGradient = Theme.Panel.FillGradient,
}

Theme.HeaderWide = {
	AspectRatio = 1000 / 120,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(8 / 1000, 9 / 120),
	RimSize = Vector2.new(984 / 1000, 96 / 120),
	RimCorner = 0.18,
	FacePosition = Vector2.new(15 / 1000, 13 / 120),
	FaceSize = Vector2.new(970 / 1000, 86 / 120),
	FaceCorner = 0.16,
	TitlePosition = Vector2.new(350 / 1000, 20 / 120),
	TitleSize = Vector2.new(300 / 1000, 62 / 120),
	CloseCenter = Vector2.new(943 / 1000, 56 / 120),
	CloseSize = Vector2.new(63 / 1000, 65 / 120),
	OutlineColor = Theme.Header.OutlineColor,
	OuterGradient = Theme.Header.OuterGradient,
	RimGradient = Theme.Header.RimGradient,
	FaceGradient = Theme.Header.FaceGradient,
	TitleGradient = Theme.Header.TitleGradient,
}

-- Square icon button. Nominal 48x48.
Theme.IconButton = {
	AspectRatio = 1,
	OuterCorner = 0.24,
	RimPosition = Vector2.new(3 / 48, 3 / 48),
	RimSize = Vector2.new(42 / 48, 38 / 48),
	RimCorner = 0.22,
	FacePosition = Vector2.new(4.5 / 48, 4.5 / 48),
	FaceSize = Vector2.new(39 / 48, 35 / 48),
	FaceCorner = 0.20,
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	IconColor = Color3.new(1, 1, 1),
	IconOutlineColor = Theme.Colors.Outline,
}

-- Action button: Button recipe with a centered text zone.
Theme.ActionButton = {
	AspectRatio = Theme.Button.AspectRatio,
	OuterCorner = Theme.Button.OuterCorner,
	RimPosition = Theme.Button.RimPosition,
	RimSize = Theme.Button.RimSize,
	RimCorner = Theme.Button.RimCorner,
	FacePosition = Theme.Button.FacePosition,
	FaceSize = Theme.Button.FaceSize,
	FaceCorner = Theme.Button.FaceCorner,
	TextPosition = Vector2.new(74 / 418, 23 / 103),
	TextSize = Vector2.new(270 / 418, 50 / 103),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
}

-- Custom vertical scrollbar. Nominal bar 22 wide, track 367 tall.
Theme.Scrollbar = {
	-- Track ring quieted with the thumb (tonal audit 2026-08-01): the Toggle's
	-- near-black well made the whole track a dark stripe on the white panel —
	-- a level-4 element out-shouting card titles. Same slate family, light.
	TrackOuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(148, 166, 190)),
		ColorSequenceKeypoint.new(0.06, Color3.fromRGB(140, 158, 184)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(122, 140, 166)),
	}),
	GrooveGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 246, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 225, 250)),
	}),
	GrooveInset = Vector2.new(4 / 22, 4 / 367),
	-- The thumb is CHROME and must recede: the saturated button-blue thumb
	-- with the near-black button outer measurably out-shouted card titles in
	-- every scroll window (tonal audit 2026-08-01 — a level-4 element ranking
	-- above level-3 content). Same hue family, pulled toward the groove's
	-- value; still obviously draggable, no longer a competitor.
	ThumbOuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(122, 158, 196)),
		ColorSequenceKeypoint.new(0.06, Color3.fromRGB(114, 150, 188)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 136, 174)),
	}),
	ThumbFaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(178, 216, 248)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(160, 200, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(134, 176, 222)),
	}),
	ThumbFaceInset = Vector2.new(3 / 22, 0.02),
	MinThumbFraction = 0.12,
}

-- Horizontal carousel scrollbar. It shares the quiet slate/cyan colour family
-- with the vertical bar, but its insets are cut for a nominal 904x30 bottom
-- track. Do not rotate this style: every gradient remains screen-vertical, so
-- the kit's top-light / bottom-dark material language stays intact.
Theme.HorizontalScrollbar = {
	TrackOuterGradient = Theme.Scrollbar.TrackOuterGradient,
	GrooveGradient = Theme.Scrollbar.GrooveGradient,
	GrooveInset = Vector2.new(4 / 904, 4 / 30),
	ThumbOuterGradient = Theme.Scrollbar.ThumbOuterGradient,
	ThumbFaceGradient = Theme.Scrollbar.ThumbFaceGradient,
	ThumbFaceInset = Vector2.new(4 / 904, 3 / 30),
	MinThumbFraction = Theme.Scrollbar.MinThumbFraction,
}

-- Rarity accents: Button keypoint structure and lightness curve, hue-shifted.
Theme.Rarity = {
	Order = { "Common", "Rare", "Epic", "Legendary" },
	-- Common used to ALIAS Theme.Button — same blue, and structurally a different
	-- animal from the other five tiers (6-keypoint Rim starting DARK + 7-keypoint
	-- Face, vs the canonical 4/4/5 with a BRIGHT Rim kp0). So a Common card obeyed
	-- different light physics AND was indistinguishable from every button, row and
	-- chip in the kit.
	-- Restructured to the canonical form and hue-shifted to warm FOAM CREAM: H 30°,
	-- S ≈ 0.13 (Rim/Face) / 0.45 (Outer), V curve inherited unchanged from the Rare
	-- prototype. Two separations had to hold at once and both are published here:
	--   vs the locked/disabled hex-gray family (hexGrayFace H 215°, S 0.16) — 185°
	--     of hue apart, so a Common squishy never reads as "locked";
	--   vs Legendary gold (H 43.6°, S 0.65) — only 13.6° apart in hue but 5x apart
	--     in saturation, so pale foam never reads as gold.
	-- A cool grey satisfied the first test but failed it against hexGray; cream is
	-- also simply what squishy foam looks like.
	Common = {
		Outer = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(54, 42, 30)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(45, 35, 25)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(46, 36, 25)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 39, 28)),
		}),
		Rim = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(160, 148, 136)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(225, 211, 196)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(195, 182, 168)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 139, 127)),
		}),
		Face = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 211, 197)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(200, 187, 173)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(185, 172, 159)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(145, 134, 122)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(155, 144, 132)),
		}),
	},
	Rare = {
		Outer = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 54, 30)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(0, 45, 24)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(0, 46, 25)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 50, 26)),
		}),
		Rim = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 160, 90)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(80, 225, 140)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(60, 195, 115)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 150, 80)),
		}),
		Face = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 225, 140)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(65, 200, 120)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(55, 185, 105)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(30, 145, 75)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 155, 85)),
		}),
	},
	Epic = {
		Outer = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 0, 48)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(48, 0, 40)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(50, 0, 42)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(54, 0, 45)),
		}),
		Rim = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 70, 190)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(250, 120, 240)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(225, 95, 215)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 60, 175)),
		}),
		Face = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 125, 240)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(230, 100, 220)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(215, 85, 205)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(175, 50, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 65, 185)),
		}),
	},
	Legendary = {
		Outer = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(78, 50, 0)),
			ColorSequenceKeypoint.new(0.10, Color3.fromRGB(66, 42, 0)),
			ColorSequenceKeypoint.new(0.80, Color3.fromRGB(68, 44, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(74, 48, 0)),
		}),
		Rim = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 165, 45)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(255, 215, 95)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(245, 190, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 150, 35)),
		}),
		Face = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 90)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(245, 185, 65)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(235, 170, 55)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(200, 130, 25)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(215, 145, 40)),
		}),
	},
}

-- Rarity extensions (hue-shift rule §7): Uncommon = teal family between
-- Common(blue) and Rare(green); Secret = void magenta, dark face + pink rim.
Theme.Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }
Theme.Rarity.Uncommon = {
	Outer = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 56, 52)),
		ColorSequenceKeypoint.new(0.10, Color3.fromRGB(0, 46, 43)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(0, 47, 44)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 52, 48)),
	}),
	Rim = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 170, 155)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(85, 230, 210)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(65, 200, 180)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 155, 140)),
	}),
	Face = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 230, 210)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(70, 205, 185)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(60, 190, 170)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(35, 150, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 160, 140)),
	}),
}
-- Secret was 316.7° magenta — only 11.9° from Epic (304.8°), so at card size the
-- two top tiers read as the same purple and the rarest drop in the game lands
-- without a distinct colour. Hue-shifted −42° to 274.7° violet-void, keeping the
-- keypoint positions and the dark V≈.47 face that makes it read as "forbidden".
Theme.Rarity.Secret = {
	Outer = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 0, 38)),
		ColorSequenceKeypoint.new(0.10, Color3.fromRGB(12, 0, 30)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(13, 0, 32)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 0, 36)),
	}),
	Rim = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(191, 60, 215)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(235, 105, 255)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(215, 85, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 50, 200)),
	}),
	Face = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(82, 30, 120)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(64, 22, 96)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(56, 18, 84)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(33, 8, 55)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 12, 66)),
	}),
}

-- Per-tier outline + text gradient + rarity marks. style-rules §4.3: an
-- element's outline is the DARK version of its own hue — Secret had none at all
-- and fell back to the default navy. Icons are NAMES into Theme.Icons: the disc
-- keeps its silhouette at chip size (18px), the star only survives ≥36px.
local rarityTrim = {
	Common = {
		Outline = Color3.fromRGB(34, 26, 18),
		TextStop = Color3.fromRGB(234, 224, 214),
		TextMid = Color3.fromRGB(246, 241, 236),
	},
	Uncommon = {
		Outline = Color3.fromRGB(0, 52, 48),
		TextStop = Color3.fromRGB(186, 240, 230),
		TextMid = Color3.fromRGB(222, 250, 245),
	},
	Rare = {
		Outline = Color3.fromRGB(0, 60, 24),
		TextStop = Color3.fromRGB(168, 240, 196),
		TextMid = Color3.fromRGB(224, 255, 236),
	},
	Epic = {
		Outline = Color3.fromRGB(46, 0, 38),
		TextStop = Color3.fromRGB(255, 196, 240),
		TextMid = Color3.fromRGB(255, 228, 250),
	},
	Legendary = {
		Outline = Color3.fromRGB(74, 48, 0),
		TextStop = Color3.fromRGB(255, 214, 120),
		TextMid = Color3.fromRGB(255, 238, 178),
	},
	Secret = {
		Outline = Color3.fromRGB(24, 0, 46),
		TextStop = Color3.fromRGB(226, 170, 255),
		TextMid = Color3.fromRGB(243, 214, 255),
	},
}
for tier, trim in pairs(rarityTrim) do
	local set = Theme.Rarity[tier]
	set.Outline = trim.Outline
	set.Text = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, trim.TextMid),
		ColorSequenceKeypoint.new(1, trim.TextStop),
	})
	set.IconDisc = `RarityDisc{tier}`
	set.IconStar = `RarityStar{tier}`
end

-- Pet card. Nominal 140x160; grid cell bakes the 12px vertical gap into its aspect.
Theme.PetCard = {
	CellAspectRatio = 135 / 166.3,
	CardHeightInCell = 154.3 / 166.3,
	OuterCorner = 0.14,
	RimPosition = Vector2.new(7 / 140, 8 / 160),
	RimSize = Vector2.new(126 / 140, 138 / 160),
	RimCorner = 0.13,
	FacePosition = Vector2.new(10 / 140, 10 / 160),
	FaceSize = Vector2.new(120 / 140, 134 / 160),
	FaceCorner = 0.12,
	PlatePosition = Vector2.new(26 / 140, 24 / 160),
	PlateSize = Vector2.new(88 / 140, 88 / 160),
	IconInset = 0.04, -- squishy art nearly fills the plate (was 0.10)
	PlateGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(252, 253, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(208, 234, 252)),
	}),
	PlateTransparency = 0.25,
	NamePosition = Vector2.new(12 / 140, 116 / 160),
	NameSize = Vector2.new(116 / 140, 28 / 160),
	NameGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(232, 240, 248)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 220, 235)),
	}),
	BadgeCenter = Vector2.new(120 / 140, 28 / 160),
	BadgeSize = Vector2.new(30 / 140, 30 / 160),
	BadgeOutlineColor = Theme.Toggle.KnobOnOutlineColor,
	BadgeGradient = Theme.Toggle.KnobOnGradient,
	CheckColor = Color3.new(1, 1, 1),
}

-- Selection accent: gold Outer/Rim swap (geometry unchanged). Compact controls
-- may also use SelectFaceGradient when a thin ring would disappear at a squint;
-- large image cards keep their neutral face and use only the shared trim.
Theme.PetCard.SelectOuterGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 208, 64)),
	ColorSequenceKeypoint.new(0.10, Color3.fromRGB(238, 178, 28)),
	ColorSequenceKeypoint.new(0.80, Color3.fromRGB(230, 170, 24)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(244, 188, 36)),
})
Theme.PetCard.SelectRingGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 232)),
	ColorSequenceKeypoint.new(0.05, Color3.fromRGB(255, 246, 196)),
	ColorSequenceKeypoint.new(0.72, Color3.fromRGB(255, 232, 140)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 214, 84)),
})
Theme.PetCard.SelectFaceGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(232, 176, 52)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(214, 152, 38)),
	ColorSequenceKeypoint.new(0.93, Color3.fromRGB(198, 138, 30)),
	ColorSequenceKeypoint.new(0.96, Color3.fromRGB(162, 102, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 114, 24)),
})

-- Inspector sidebar (pet details). Nominal 278x427.
Theme.Inspector = {
	OuterGradient = Theme.Toggle.OuterGradient,
	OuterCorner = 0.055,
	FillPosition = Vector2.new(5 / 278, 5 / 427),
	FillSize = Vector2.new(268 / 278, 414 / 427),
	FillCorner = 0.052,
	FillGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(250, 252, 255)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(232, 245, 254)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 238, 252)),
	}),
	PlateRingPosition = Vector2.new(66 / 278, 23 / 427),
	PlateRingSize = Vector2.new(146 / 278, 146 / 427),
	PlatePosition = Vector2.new(69 / 278, 26 / 427),
	PlateSize = Vector2.new(140 / 278, 140 / 427),
	NamePosition = Vector2.new(20 / 278, 180 / 427),
	NameSize = Vector2.new(238 / 278, 36 / 427),
	StatPositions = {
		Vector2.new(20 / 278, 236 / 427),
		Vector2.new(20 / 278, 300 / 427),
	},
	StatSize = Vector2.new(238 / 278, 52 / 427),
	EquipPosition = Vector2.new(41.5 / 278, 364 / 427),
	EquipSize = Vector2.new(195 / 278, 48 / 427),
}

-- Stat row inside the inspector (label left, value right). Nominal 238x52.
Theme.StatRow = {
	OuterGradient = Theme.Button.OuterGradient,
	OuterCorner = 0.20,
	FacePosition = Vector2.new(3 / 238, 3 / 52),
	FaceSize = Vector2.new(232 / 238, 43 / 52),
	FaceCorner = 0.19,
	FaceGradient = Theme.Button.FaceGradient,
	LabelPosition = Vector2.new(14 / 238, 13 / 52),
	LabelSize = Vector2.new(110 / 238, 26 / 52),
	ValuePosition = Vector2.new(114 / 238, 13 / 52),
	ValueSize = Vector2.new(110 / 238, 26 / 52),
	TextGradient = Theme.Button.TextGradient,
	OutlineColor = Theme.Button.OutlineColor,
}

-- Green/red action buttons (accent rule: hue-shifted gradients, dark outline of same hue).
Theme.EquipGreen = {
	AspectRatio = Theme.ActionButton.AspectRatio,
	OuterCorner = Theme.ActionButton.OuterCorner,
	RimPosition = Theme.ActionButton.RimPosition,
	RimSize = Theme.ActionButton.RimSize,
	RimCorner = Theme.ActionButton.RimCorner,
	FacePosition = Theme.ActionButton.FacePosition,
	FaceSize = Theme.ActionButton.FaceSize,
	FaceCorner = Theme.ActionButton.FaceCorner,
	TextPosition = Theme.ActionButton.TextPosition,
	TextSize = Theme.ActionButton.TextSize,
	OutlineColor = Color3.fromRGB(0, 60, 24),
	OuterGradient = Theme.Rarity.Rare.Outer,
	RimGradient = Theme.Rarity.Rare.Rim,
	FaceGradient = Theme.Rarity.Rare.Face,
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(224, 255, 236)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(168, 240, 196)),
	}),
}

Theme.UnequipRed = {
	AspectRatio = Theme.ActionButton.AspectRatio,
	OuterCorner = Theme.ActionButton.OuterCorner,
	RimPosition = Theme.ActionButton.RimPosition,
	RimSize = Theme.ActionButton.RimSize,
	RimCorner = Theme.ActionButton.RimCorner,
	FacePosition = Theme.ActionButton.FacePosition,
	FaceSize = Theme.ActionButton.FaceSize,
	FaceCorner = Theme.ActionButton.FaceCorner,
	TextPosition = Theme.ActionButton.TextPosition,
	TextSize = Theme.ActionButton.TextSize,
	OutlineColor = Theme.Exit.XOutline,
	OuterGradient = Theme.Exit.OuterGradient,
	RimGradient = Theme.Exit.RimGradient,
	FaceGradient = Theme.Exit.FaceGradient,
	TextGradient = Theme.Exit.XGradient,
}

-- Match selector choice. Nominal 288x68, derived from the Button family at a
-- shorter height class. Selection swaps the Outer/Rim to the existing gold
-- selection accent; the blue Face stays put so the state reads as selected,
-- not as a different action type.
Theme.MatchChoice = {
	AspectRatio = 288 / 68,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(5 / 288, 5 / 68),
	RimSize = Vector2.new(278 / 288, 55 / 68),
	RimCorner = 0.20,
	FacePosition = Vector2.new(8 / 288, 7 / 68),
	FaceSize = Vector2.new(272 / 288, 51 / 68),
	FaceCorner = 0.19,
	TextPosition = Vector2.new(16 / 288, 18 / 68),
	TextSize = Vector2.new(256 / 288, 32 / 68),
	LayerColor = Color3.new(1, 1, 1),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	SelectedRimGradient = Theme.PetCard.SelectRingGradient,
	DisabledTransparency = 0.32,
}

-- Large match-mode card. Nominal 526x118, one per row in the scrollable
-- primary column. This is a CARD, not a stretched button: even body outline,
-- neutral body, and an internal accent art window. Only the whole card's hit
-- target is pressable; the reward chip is a passive information tag.
-- Horizontal: 14 art(94) 16 text(250) 12 reward(126) 14 = 526 ✓
-- Vertical: art y12..106; title y18..54; detail y60..86; reward y31..87.
Theme.MatchModeCard = {
	AspectRatio = 526 / 118,
	OuterCorner = 0.12,
	FacePosition = Vector2.new(6 / 526, 6 / 118),
	FaceSize = Vector2.new(514 / 526, 104 / 118),
	FaceCorner = 0.105,
	ArtPosition = Vector2.new(14 / 526, 12 / 118),
	ArtSize = Vector2.new(94 / 526, 94 / 118),
	ArtCorner = 0.16,
	ArtFacePosition = Vector2.new(18 / 526, 16 / 118),
	ArtFaceSize = Vector2.new(86 / 526, 86 / 118),
	ArtFaceCorner = 0.15,
	IconPosition = Vector2.new(27 / 526, 25 / 118),
	IconSize = Vector2.new(68 / 526, 68 / 118),
	IconColor = Color3.new(1, 1, 1),
	TitlePosition = Vector2.new(124 / 526, 18 / 118),
	TitleSize = Vector2.new(250 / 526, 36 / 118),
	DescriptionPosition = Vector2.new(124 / 526, 60 / 118),
	DescriptionSize = Vector2.new(250 / 526, 26 / 118),
	RewardPosition = Vector2.new(386 / 526, 31 / 118),
	RewardSize = Vector2.new(126 / 526, 56 / 118),
	RewardOuterCorner = 0.24,
	RewardFacePosition = Vector2.new(3 / 126, 3 / 56),
	RewardFaceSize = Vector2.new(120 / 126, 46 / 56),
	RewardFaceCorner = 0.22,
	RewardIconPosition = Vector2.new(10 / 126, 11 / 56),
	RewardIconSize = Vector2.new(34 / 126, 34 / 56),
	RewardTextPosition = Vector2.new(50 / 126, 13 / 56),
	RewardTextSize = Vector2.new(66 / 126, 30 / 56),
	RewardIconName = "BadgeLightning",
	RewardIconColor = Color3.new(1, 1, 1),
	BadgeCenter = Vector2.new(98 / 526, 20 / 118),
	BadgeSize = Vector2.new(30 / 526, 30 / 118),
	SelectedIconName = "UiCheck",
	OutlineColor = Color3.fromRGB(8, 26, 48),
	OuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 62, 98)),
		ColorSequenceKeypoint.new(0.06, Color3.fromRGB(8, 36, 62)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(6, 30, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 42, 70)),
	}),
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 130, 180)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(78, 110, 158)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(62, 90, 136)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(50, 74, 116)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(32, 50, 84)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 62, 100)),
	}),
	TitleGradient = Theme.PetCard.NameGradient,
	DescriptionGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(188, 210, 238)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(158, 184, 218)),
	}),
	RewardOuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 66, 98)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 58, 88)),
	}),
	RewardFaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 66, 98)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 58, 88)),
	}),
	RewardTextGradient = Theme.PetCard.NameGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	DisabledTransparency = 0.32,
}

-- The art-window accents carry difficulty at a glance. Their keypoint curves
-- are existing kit accents; only the hue family changes. The card BODY stays
-- neutral so three modes do not become three equally loud color fields.
Theme.MatchModeAccents = {
	easy = {
		OutlineColor = Theme.Rarity.Rare.Outline,
		OuterGradient = Theme.Rarity.Rare.Outer,
		FaceGradient = Theme.Rarity.Rare.Face,
		TextGradient = Theme.Rarity.Rare.Text,
	},
	medium = {
		OutlineColor = Theme.Rarity.Legendary.Outline,
		OuterGradient = Theme.Rarity.Legendary.Outer,
		FaceGradient = Theme.Rarity.Legendary.Face,
		TextGradient = Theme.Rarity.Legendary.Text,
	},
	hard = {
		OutlineColor = Theme.Exit.XOutline,
		OuterGradient = Theme.Exit.OuterGradient,
		FaceGradient = Theme.Exit.FaceGradient,
		TextGradient = Theme.Exit.XGradient,
	},
}

-- Difficulty uses three 142x112 portrait/icon-first tiles across the 452px
-- setup column: 3*142 + 2*13 = 452. The prior 344x52 rows repeated a reward
-- glyph/value on every line and made this child-facing selector read like a
-- settings table. The config still carries reward copy; this compact surface
-- deliberately omits it.
Theme.MatchDifficultyChoice = {
	AspectRatio = 142 / 112,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(5 / 142, 5 / 112),
	RimSize = Vector2.new(132 / 142, 94 / 112),
	RimCorner = 0.18,
	FacePosition = Vector2.new(8 / 142, 8 / 112),
	FaceSize = Vector2.new(126 / 142, 85 / 112),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(44 / 142, 10 / 112),
	IconSize = Vector2.new(54 / 142, 54 / 112),
	-- Keep the label and its down-left OutlinedText shadow inside the raised Face.
	-- Horizontally it spans x9..133 (shadow starts at x8.63); vertically its
	-- shadow ends at y92.4, before the Face bottom at y93.
	LabelPosition = Vector2.new(9 / 142, 66 / 112),
	LabelSize = Vector2.new(124 / 142, 24 / 112),
	LabelTextXAlignment = Enum.TextXAlignment.Center,
	ShowReward = false,
	LayerColor = Color3.new(1, 1, 1),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	SelectedRimGradient = Theme.PetCard.SelectRingGradient,
	-- Setup remains secondary: selection is a gold perimeter around the same
	-- familiar blue pressable face.
	SelectedFaceGradient = Theme.Button.FaceGradient,
	DisabledTransparency = 0.32,
}

-- Party Size uses four 101x84 horizontal controls across 452px:
-- 4*101 + 3*16 = 452. The large numeral on the LEFT and friend glyph on the
-- RIGHT make the two pieces readable without stacking either onto the lip.
Theme.MatchPartyChoice = {
	AspectRatio = 101 / 84,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(5 / 101, 5 / 84),
	RimSize = Vector2.new(91 / 101, 71 / 84),
	RimCorner = 0.18,
	FacePosition = Vector2.new(7 / 101, 7 / 84),
	FaceSize = Vector2.new(87 / 101, 65 / 84),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(51 / 101, 16 / 84),
	IconSize = Vector2.new(42 / 101, 42 / 84),
	-- Face is x7..94, y7..72. With the main 0.08*42 stroke, the count is
	-- x7.64..50.36/y10.64..59.36; its offset shadow plus 0.06*42 stroke is
	-- x8.37..49.41/y15.68..62.72. The icon ends at x93/y58, so every visible
	-- pixel remains inside the Face rather than spilling onto the lower lip.
	CountPosition = Vector2.new(11 / 101, 14 / 84),
	CountSize = Vector2.new(36 / 101, 42 / 84),
	IconName = "UiFriend",
	LayerColor = Color3.new(1, 1, 1),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	-- On this compact tile a second gold band occupied too much of the surface
	-- and competed with the cake hero. One gold perimeter is enough selection;
	-- its interior keeps the ordinary blue button value family.
	SelectedRimGradient = Theme.Button.RimGradient,
	-- Match difficulty's quiet selected language: a gold perimeter around the
	-- same blue face as its siblings. A pale fill made this tiny tile compete
	-- with the cake gallery under Tonal/Squint even though it is only setup.
	SelectedFaceGradient = Theme.Button.FaceGradient,
	DisabledTransparency = 0.32,
}

-- Matchmaking's compact cake list. Nominal 294x58, re-cut from CakeChoice for
-- the narrow setup rail instead of horizontally squashing its 442px grid.
Theme.MatchCakeChoice = {
	AspectRatio = 294 / 58,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(5 / 294, 4 / 58),
	RimSize = Vector2.new(284 / 294, 47 / 58),
	RimCorner = 0.20,
	FacePosition = Vector2.new(8 / 294, 6 / 58),
	FaceSize = Vector2.new(278 / 294, 43 / 58),
	FaceCorner = 0.19,
	ThumbPosition = Vector2.new(14 / 294, 10 / 58),
	ThumbSize = Vector2.new(38 / 294, 38 / 58),
	TextPosition = Vector2.new(60 / 294, 14 / 58),
	TextSize = Vector2.new(184 / 294, 30 / 58),
	BadgeCenter = Vector2.new(266 / 294, 29 / 58),
	BadgeSize = Vector2.new(34 / 294, 34 / 58),
	LayerColor = Color3.new(1, 1, 1),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	SelectedRimGradient = Theme.PetCard.SelectRingGradient,
	SelectedFaceGradient = Theme.PetCard.SelectFaceGradient,
	LockedArtTransparency = 0.4,
	DisabledTransparency = 0.32,
}

-- Matchmaking keeps its escape hatch discoverable without letting the global
-- red close affordance become the screen's strongest color island. Geometry
-- remains the standard Exit recipe; only the hue is folded into the header.
local matchmakingCloseButton = table.clone(Theme.Exit)
matchmakingCloseButton.OuterGradient = Theme.Button.OuterGradient
matchmakingCloseButton.RimGradient = Theme.Header.RimGradient
matchmakingCloseButton.InnerRimGradient = Theme.Header.RimGradient
matchmakingCloseButton.FaceGradient = Theme.Header.FaceGradient
matchmakingCloseButton.XOutline = Theme.Colors.Outline
matchmakingCloseButton.XGradient = Theme.PetCard.NameGradient
Theme.MatchmakingCloseButton = matchmakingCloseButton

-- Matchmaking uses the standard saturated landscape header. The prior pale
-- slate override looked detached from the rest of the candy-style catalog.
local matchmakingHeader = table.clone(Theme.HeaderWide)
Theme.MatchmakingHeader = matchmakingHeader

local matchmakingStartButton = table.clone(Theme.EquipGreen)
-- One centred 760x76 footer CTA completes both columns. Its own layer and
-- content fractions keep the very wide shelf physical without stretching the
-- 418x103 reference button's inset math.
matchmakingStartButton.AspectRatio = 760 / 76
matchmakingStartButton.RimPosition = Vector2.new(6 / 760, 5 / 76)
matchmakingStartButton.RimSize = Vector2.new(748 / 760, 61 / 76)
matchmakingStartButton.FacePosition = Vector2.new(9 / 760, 7 / 76)
matchmakingStartButton.FaceSize = Vector2.new(742 / 760, 56 / 76)
-- The CTA is the screen's only large, high-chroma green field, so a child can
-- find the next action before reading. The selected cake is the second read.
matchmakingStartButton.RimGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 99, 32)),
	ColorSequenceKeypoint.new(0.05, Color3.fromRGB(55, 205, 98)),
	ColorSequenceKeypoint.new(0.72, Color3.fromRGB(18, 153, 56)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 90, 28)),
})
matchmakingStartButton.FaceGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 192, 70)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(8, 153, 42)),
	ColorSequenceKeypoint.new(0.93, Color3.fromRGB(4, 126, 28)),
	ColorSequenceKeypoint.new(0.96, Color3.fromRGB(1, 81, 16)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(3, 97, 22)),
})
matchmakingStartButton.IconName = "UiTeleport"
matchmakingStartButton.IconPosition = Vector2.new(221 / 760, 12 / 76)
matchmakingStartButton.IconSize = Vector2.new(52 / 760, 52 / 76)
matchmakingStartButton.IconColor = Color3.new(1, 1, 1)
matchmakingStartButton.TextPosition = Vector2.new(289 / 760, 14 / 76)
matchmakingStartButton.TextSize = Vector2.new(250 / 760, 44 / 76)
Theme.MatchmakingStartButton = matchmakingStartButton

-- Matchmaking selector: calm setup + narrow three-card cake rail, nominal
-- 1000x600. Content is 904x432 at x48..952, y132..564.
--
-- ⚠ THE FLOOR IS 573, NOT 600. Theme.PanelWide's visible BODY FILL is
-- y 96..573 (FillPosition 96/600 + FillSize 477/600); below that is the dark
-- border ring (86..583), which content draws OVER at zIndex 5. Budgeting against
-- the 600 nominal is the trap: it silently buys px that are not body, and the
-- first cut of the cake band did exactly that (content to 576, so START's bottom
-- 3 nominal px sat on the ring — ~5 real px at 1080p). 564 is the floor every
-- peer wide layout already respects (Rewards footer 564, Shop pane 564).
--
-- Horizontal: setup 452 + empty gutter 32 + cake carousel 420 = 904 exactly.
-- Upper configuration: 340px. Left is 28 + 12 + 112 + 48 + 28 + 12 + 84
-- + 16 = 340; Right is 28 + 12 + 300 = 340.
-- Footer: 340 + 8 + START 76 + 8 = 432. There is no separate status row.
-- Difficulty: 3*142 + 2*13 = 452. Party: 4*101 + 3*16 = 452.
-- Cakes: 8 + 3*264 + 2*16 + 8 = 840 = 2*420 canvas width. At offset
-- zero Classic is fully visible (x8..272) and Rainbow is exactly half visible
-- (x288..420 of x288..552). Rainbow centers at offset 210.
--
Theme.MatchmakingLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	-- If the ordinary 90%-of-screen fit overlaps Roblox's topbar, it may use
	-- nearly all of the remaining safe region. This preserves useful touch-target
	-- size on short landscape phones while retaining a small breathing margin.
	SafeRegionMaxFraction = 0.98,
	HeaderHeight = 120 / 600,
	ContentZIndex = 5,
	ContentPosition = Vector2.new(48 / 1000, 132 / 600),
	ContentSize = Vector2.new(904 / 1000, 432 / 600),
	CakeTitlePosition = Vector2.new(484 / 904, 0),
	CakeTitleSize = Vector2.new(420 / 904, 28 / 432),
	CakePanePosition = Vector2.new(484 / 904, 40 / 432),
	CakePaneSize = Vector2.new(420 / 904, 300 / 432),
	CakeOrientation = "horizontal",
	CakeColumns = 1,
	CakePaneWidthPx = 420,
	CakePaneHeightPx = 300,
	CakeCardWidthPx = 264,
	CakeCardHeightPx = 292,
	CakeCardGapPx = 16,
	CakeCanvasPaddingPx = 8,
	CakeCanvasCrossPaddingPx = 4,
	CakeIncompleteRowAlignment = "left",
	CakeCardAspectRatio = 264 / 292,
	-- Unlock requirements belong to the locked cake card. The default panel has
	-- no separate status row; busy/error feedback is carried by START itself.
	CakeNoticeUsesStatus = false,
	DifficultyTitlePosition = Vector2.new(0, 0),
	DifficultyTitleSize = Vector2.new(452 / 904, 28 / 432),
	DifficultyListPosition = Vector2.new(0, 40 / 432),
	DifficultyListSize = Vector2.new(452 / 904, 112 / 432),
	DifficultyOrientation = "horizontal",
	DifficultyChoiceWidth = 142 / 452,
	DifficultyChoiceGap = 13 / 452,
	DifficultyChoiceAspectRatio = 142 / 112,
	PartyTitlePosition = Vector2.new(0, 200 / 432),
	PartyTitleSize = Vector2.new(452 / 904, 28 / 432),
	PartyRowPosition = Vector2.new(0, 240 / 432),
	PartyRowSize = Vector2.new(452 / 904, 84 / 432),
	PartyChoiceWidth = 101 / 452,
	PartyChoiceGap = 16 / 452,
	PartyChoiceAspectRatio = 101 / 84,
	StatusPosition = Vector2.new(0, 316 / 432),
	StatusSize = Vector2.new(904 / 904, 24 / 432),
	StartPosition = Vector2.new(72 / 904, 348 / 432),
	StartSize = Vector2.new(760 / 904, 76 / 432),
	-- START breathes while it can be pressed, and its dim-when-disabled CanvasGroup
	-- CLIPS to its own bounds — a pulse inside a group sized exactly to the button
	-- would have its peak sliced off on all four sides. So the group is grown by
	-- this factor about the button's centre and the button is shrunk by 1/factor
	-- inside it: identical geometry at rest, headroom for the breath.
	-- Must stay > Theme.Feel.Pulse.Scale (1.10) with a little margin for the
	-- press/hover bounce (1.05) riding the same button.
	StartPulseHeadroom = 1.18,
	-- All three configuration headings share one visual language; Cake is a
	-- sibling group, not a separate state or callout.
	CakeHeadingGradient = Theme.PetCard.NameGradient,
	CakeHeadingOutlineColor = Theme.Colors.TextOutline,
	CakeNoticeGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 210, 232)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(148, 188, 216)),
	}),
	CakeNoticeOutlineColor = Color3.fromRGB(122, 164, 196),
	SetupHeadingGradient = Theme.PetCard.NameGradient,
	ShowStatus = false,
	ShowReadyStatus = false,
	ShowBusyStatus = false,
	-- The polished footer is transient system state only; setup guidance belongs
	-- to the visible choice groups. Legacy/custom layouts keep guidance by default.
	ShowSelectionStatus = false,
	StatusGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 210, 232)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(148, 188, 216)),
	}),
	StatusOutlineColor = Color3.fromRGB(122, 164, 196),
	ErrorGradient = Theme.Exit.XGradient,
	ErrorOutlineColor = Theme.Exit.XOutline,
	TextOutlineColor = Theme.Colors.TextOutline,
	StartDisabledTransparency = 0.38,
}

-- Pets panel variation with inspector. Nominal 1000x600; grid pane 610 wide, inspector 278.
Theme.PetsInspectLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	ChipPosition = Vector2.new(48 / 1000, 132 / 600),
	ChipSize = Vector2.new(190 / 1000, 48 / 600),
	EquipButtonPosition = Vector2.new(407 / 1000, 132 / 600),
	EquipButtonSize = Vector2.new(195 / 1000, 48 / 600),
	SortButtonPosition = Vector2.new(610 / 1000, 132 / 600),
	SortButtonSize = Vector2.new(48 / 1000, 48 / 600),
	GridPosition = Vector2.new(48 / 1000, 192 / 600),
	GridSize = Vector2.new(610 / 1000, 367 / 600),
	ScrollWindowFraction = 576 / 610,
	ScrollBarWidth = 22 / 610,
	Columns = 4,
	CellWidth = 135 / 576,
	CellPaddingX = 12 / 576,
	CellHeightWithGap = 166.3 / 367,
	InspectorPosition = Vector2.new(674 / 1000, 132 / 600),
	InspectorSize = Vector2.new(278 / 1000, 427 / 600),
}

-- HUD: stat pills (nominal 190x48, Chip family) and menu buttons. Reference screen 1920x1080.
Theme.Hud = {
	PillAspect = 190 / 48,
	PillHeight = 64 / 1080,
	PillX = 22 / 1920,
	PillYs = { 24 / 1080, 100 / 1080, 176 / 1080 },
	ValuePosition = Vector2.new(52 / 190, 11 / 48),
	ValueSize = Vector2.new(128 / 190, 26 / 48),
	CoinOutline = Color3.fromRGB(94, 63, 5),
	CoinFill = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 229, 120)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(244, 196, 48)),
	}),
	CoinHighlight = Color3.fromRGB(255, 244, 178),
	ChevronOutline = Color3.fromRGB(4, 42, 64),
	ChevronFill = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 224, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(73, 190, 255)),
	}),
	BoltOutline = Color3.fromRGB(0, 80, 20),
	BoltFill = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 255, 164)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(84, 232, 110)),
	}),
	ButtonContainerAspect = 132 / 172,
	ButtonContainerHeight = 172 / 1080,
	ButtonX = 22 / 1920,
	ButtonYs = { 400 / 1080, 592 / 1080 },
	ButtonPartHeight = 132 / 172,
	LabelY = 128 / 172,
	LabelHeight = 40 / 172,
	ButtonLabelGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(235, 242, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(208, 222, 238)),
	}),
	-- Placeholder icon assets (game projects replace these with their own uploads).
	Icons = {
		Settings = "rbxassetid://125326761329907",
		Pets = "rbxassetid://72513323517624",
		Speed = "rbxassetid://106459645052606",
		Energy = "rbxassetid://94326149644018",
		Coin = "rbxassetid://104517020247462",
	},
	-- Bare stat rows (icon + text, no pill background). Nominal 170x44.
	StatRowAspect = 170 / 44,
	StatRowHeight = 64 / 1080,
	StatIconWidth = 44 / 170,
	StatValuePosition = Vector2.new(54 / 170, 5 / 44),
	StatValueSize = Vector2.new(114 / 170, 34 / 44),
	-- Stat value colors: icon's hue, outline is a dark version of the same hue.
	SpeedTextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 158, 155)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 108, 112)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(238, 66, 82)),
	}),
	SpeedTextOutline = Color3.fromRGB(88, 8, 20),
	CoinTextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 232, 150)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 205, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(242, 168, 32)),
	}),
	CoinTextOutline = Color3.fromRGB(96, 60, 4),
	EnergyTextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 190)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 232, 95)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(250, 205, 40)),
	}),
	EnergyTextOutline = Color3.fromRGB(92, 72, 0),
}

-- Counter chip (e.g. "3 / 4"). Nominal 190x48.
Theme.Chip = {
	OuterGradient = Theme.Toggle.OuterGradient,
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 84, 128)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 62, 100)),
	}),
	FaceInset = Vector2.new(4 / 190, 4 / 48),
	TextGradient = Theme.Button.TextGradient,
}

-- Pets panel geometry. Nominal 1000x600.
Theme.PetsLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	ChipPosition = Vector2.new(48 / 1000, 132 / 600),
	ChipSize = Vector2.new(190 / 1000, 48 / 600),
	EquipButtonPosition = Vector2.new(701 / 1000, 132 / 600),
	EquipButtonSize = Vector2.new(195 / 1000, 48 / 600),
	SortButtonPosition = Vector2.new(904 / 1000, 132 / 600),
	SortButtonSize = Vector2.new(48 / 1000, 48 / 600),
	GridPosition = Vector2.new(48 / 1000, 192 / 600),
	GridSize = Vector2.new(904 / 1000, 367 / 600),
	ScrollWindowFraction = 870 / 904,
	ScrollBarWidth = 22 / 904,
	Columns = 6,
	CellWidth = 0.155,
	CellPaddingX = 12 / 870,
	CellHeightWithGap = 166.3 / 367,
}

-- ===== Template feature windows (rewards / shop / codes / app HUD) =====

-- Notification badge (green dot, ratio-transferred from PetCard.Badge 30x30).
-- With an optional `iconName` the same dot becomes an OWNED / CLAIMED mark.
Theme.Badge = {
	AspectRatio = 1,
	RingColor = Theme.Toggle.KnobOnOutlineColor,
	FillGradient = Theme.Toggle.KnobOnGradient,
	FillPosition = Vector2.new(0.13, 0.13),
	FillSize = Vector2.new(0.74, 0.74),
	IconInset = 0.12, -- glyph inset inside the fill circle
}

-- Rewards window geometry (daily + time share it). Nominal 1000x600.
-- WAS 7 columns of 118x135 in a 904x360 zone: a single row of short cards left
-- 62% of the grid zone empty ("big panel, tiny buttons"). 7 across a 904 canvas
-- caps a card at 117px wide no matter how much vertical room there is, so the
-- fix is FEWER COLUMNS over TWO ROWS, with a landscape card cut.
-- Vertical: header 120, gap 22, grid 360 (y 142..502), gap 14, footer 48, margin 36
--   120 + 22 + 360 + 14 + 48 + 36 = 600 ✓
-- Grid rows: 2*172 + 16 = 360 ✓   Grid cols: 4*214 + 3*16 = 856 + 48 = 904 ✓
Theme.RewardsLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	GridPosition = Vector2.new(48 / 1000, 142 / 600),
	GridSize = Vector2.new(904 / 1000, 360 / 600),
	Columns = 4,
	-- 213.5, not 214: an exact-fit grid can wrap its last cell on float
	-- rounding (kit pitfall 6).
	CellWidth = 213.5 / 904,
	CellPaddingX = 16 / 904,
	CellHeight = 172 / 360,
	FooterPosition = Vector2.new(48 / 1000, 516 / 600),
	FooterSize = Vector2.new(904 / 1000, 48 / 600),
	FooterGradient = Theme.Header.TitleGradient,
}

-- Day/milestone card, LANDSCAPE cut for the 4x2 rewards grid. Nominal 214x172.
-- The portrait 118x135 cut is kept below as Theme.DayCardTall for any caller
-- that still wants a strip.
-- Vertical: 14 title(32) 6 art(58) 6 sub(26) 30 = 172 ✓ (art zone holds the
-- reward icon + its amount side by side, so the card reads at a glance).
-- Horizontal: 14 content(186) 14 = 214 ✓
Theme.DayCard = {
	AspectRatio = 214 / 172,
	OuterCorner = 0.14,
	RimPosition = Vector2.new(7 / 214, 7 / 172),
	RimSize = Vector2.new(200 / 214, 150 / 172),
	RimCorner = 0.13,
	FacePosition = Vector2.new(11 / 214, 11 / 172),
	FaceSize = Vector2.new(192 / 214, 142 / 172),
	FaceCorner = 0.12,
	TitlePosition = Vector2.new(14 / 214, 14 / 172),
	TitleSize = Vector2.new(186 / 214, 32 / 172),
	RewardPosition = Vector2.new(14 / 214, 52 / 172),
	RewardSize = Vector2.new(186 / 214, 58 / 172),
	SubPosition = Vector2.new(14 / 214, 116 / 172),
	SubSize = Vector2.new(186 / 214, 26 / 172),
	-- Reward art sits left of the amount inside the reward band.
	IconPosition = Vector2.new(30 / 214, 52 / 172),
	IconSize = Vector2.new(58 / 214, 58 / 172),
	IconTextPosition = Vector2.new(96 / 214, 60 / 172),
	IconTextSize = Vector2.new(96 / 214, 42 / 172),
	TitleGradient = Theme.Button.TextGradient,
	RewardGradient = Theme.PetCard.NameGradient,
	-- Claimable accent: gold Outer/Rim swap (PetCard selection rule).
	ClaimableOuterGradient = Theme.PetCard.SelectOuterGradient,
	ClaimableRimGradient = Theme.PetCard.SelectRingGradient,
	BadgeCenter = Vector2.new(182 / 214, 30 / 172),
	BadgeSize = Vector2.new(34 / 214, 34 / 172),
	BadgeOutlineColor = Theme.Toggle.KnobOnOutlineColor,
	BadgeGradient = Theme.Toggle.KnobOnGradient,
	CheckColor = Color3.new(1, 1, 1),
	DisabledTransparency = 0.22,
}

-- Shop row (vertical sectioned list archetype). Nominal 418x88.
-- Horizontal: 16 label(230) 16 buy(140) 16 = 418 ✓.
-- Vertical: label 14..48, sub 50..74; buy button 14..74 (60). 88 total ✓.
Theme.ShopRow = {
	-- List cell bakes a 10px vertical gap into its aspect (PetCard's
	-- CellAspectRatio recipe): scale Padding inside an AutomaticCanvasSize
	-- ScrollPane references the GROWING canvas and inflates (kit pitfall).
	CellAspectRatio = 418 / 98,
	ContentHeightInCell = 88 / 98,
	AspectRatio = 418 / 88,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(6 / 418, 6 / 88),
	RimSize = Vector2.new(406 / 418, 72 / 88),
	RimCorner = 0.20,
	FacePosition = Vector2.new(9 / 418, 8 / 88),
	FaceSize = Vector2.new(400 / 418, 68 / 88),
	FaceCorner = 0.19,
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	LabelPosition = Vector2.new(16 / 418, 14 / 88),
	LabelSize = Vector2.new(230 / 418, 34 / 88),
	SubPosition = Vector2.new(16 / 418, 50 / 88),
	SubSize = Vector2.new(230 / 418, 24 / 88),
	BuyPosition = Vector2.new(262 / 418, 14 / 88),
	BuySize = Vector2.new(140 / 418, 60 / 88),
	LabelGradient = Theme.Button.TextGradient,
	SubGradient = Theme.PetCard.NameGradient,
}

-- ===== Shop: LANDSCAPE sectioned scroll, one multi-column grid per section ====
--
-- window-archetypes' "Shop" worked example is a portrait one-column list sized
-- for ~8 items. This catalogue is 17 items in 5 categories — comparison content,
-- which the genre (Pet Sim 99, Blade Ball, Adopt Me) always renders as a hero
-- banner + per-category GRIDS in a long scroll. The old portrait panel occupied
-- 36% of screen width and could structurally never hold two cells side by side.
--
-- PANEL FAMILY: the existing PanelWide/HeaderWide. A bespoke 1280x800 family was
-- designed and REJECTED: calculateScale pins height to maxFraction*viewportH
-- regardless of aspect, so on 16:9 a 1.6 panel renders 1624x1015 while PanelWide
-- at the same fraction renders 1692x1015 — the new grid would have been NARROWER
-- while costing a whole second chrome family to maintain.
--
-- TABS (2026-07-31). The single stacked scroll held all five sections at once:
-- 2046 nominal px of canvas in a 367 px window = 5.6 SCREENS, of which the first
-- showed the balance chips, one section header and one banner. A player looking
-- for a gem pack had to scroll past everything. That is the other half of
-- "cluttered" — not density, but a window showing 20% of one category.
-- With four tabs the worst tab is Passes at 1.9 screens (Offers 1.6) and the
-- other TWO FIT ENTIRELY. The 56px the tab row costs is paid for by moving the
-- balance chips up into the header band, which was empty either side of the title.
--
-- Vertical (content y 128..564, h 436):   tabs 56 · gap 10 · pane 370
--   56 + 10 + 370 = 436 ✓  (balances now live at y 34..82 INSIDE the header)
-- Horizontal (content x 48..952, w 904):  window 870 + gap 12 + bar 22 = 904 ✓
--   (PetsLayout's proven split. The old ShopLayout had 0.96 + 0.05 = 1.01 — the
--   scrollbar track overlapped the scroll window and there was no gap at all.)
-- Tab row: 4 * 217 + 3 * 12 = 904 ✓
Theme.ShopLayout = {
	PanelAspect = Theme.PanelWide.AspectRatio,
	PanelMaxViewportFraction = 0.92,
	HeaderHeight = 120 / 600,
	-- Balance chips ride the header band, left of the centred title. Chips end
	-- at x 390; "SHOP" centred in its 350..650 zone starts near 430.
	BalancePosition = Vector2.new(34 / 1000, 34 / 600),
	BalanceSize = Vector2.new(356 / 1000, 48 / 600),
	BalanceChipWidth = 172 / 356, -- Theme.Chip nominal 190x48, tightened
	BalanceChipStride = 184 / 356, -- 172 + 12 gap
	TabsPosition = Vector2.new(48 / 1000, 128 / 600),
	TabsSize = Vector2.new(904 / 1000, 56 / 600),
	TabWidth = 217 / 904,
	TabStride = 229 / 904, -- 217 + 12 gap
	PanePosition = Vector2.new(48 / 1000, 194 / 600),
	PaneSize = Vector2.new(904 / 1000, 370 / 600),
	ScrollWindowFraction = 870 / 904,
	ScrollBarWidth = 22 / 904,

	-- DETERMINISTIC CANVAS (nominal px on the 870x370 scroll window). The panel
	-- walks the sections, sums these, and positions every cell by an explicit
	-- fraction of the resulting canvas.
	--
	-- The alternative — a UIListLayout with AutomaticCanvasSize and one aspect
	-- constraint per cell — was built first and DOES NOT WORK here: an aspect
	-- constraint fits within (windowWidth, seedFraction * canvas), the canvas is
	-- what the cells are growing, and the fixed point that converges is one where
	-- the height binds and every row renders narrower than the window. Measured:
	-- 377px rows in a 596px window, all four row kinds the same height.
	-- Deterministic math is what patterns.md prescribes for grids, and it removes
	-- the aspect constraints, the automatic canvas and UIGridLayout all at once.
	CanvasWidthPx = 870,
	WindowHeightPx = 370,
	SectionHeaderPx = 48,
	SectionHeaderGapPx = 10,
	SectionGapPx = 20, -- after each section block
	BannerPx = 176,
	BannerGapPx = 16,
	TilePx = 160,
	TileRowGapPx = 14,
	PackPx = 264,
	PackRowGapPx = 14,
	-- Top pad must clear the ribbon's 12px overhang above its card AS DEFORMED BY
	-- THE HOVER POSE, not the static 12: the cell grows about its centre, so the
	-- tag's offset from that centre (169 + 12 = 181 on the big card) is what gets
	-- scaled. 181 * 1.03 - 169 = 17.4 -> 20 with margin. Section headers used to
	-- guarantee this clearance by accident; a single-section tab has none, so the
	-- first row starts at canvas y = 0.
	CanvasTopPadPx = 20,
	-- Cap on the centering pad for content that FITS the window: pure
	-- centering gave every tab a different content start and the block
	-- jumped on tab switches (composition audit 2026-08-01).
	CanvasMaxTopPadPx = 48,
	CanvasBottomPadPx = 16,
	-- Column packing on the 870 canvas:
	--   tiles: 3*282 + 2*12 = 846 + 24 = 870 ✓
	--   packs: 4*208 + 3*12 = 832 + 36 = 868 — 2px slack ON PURPOSE; exact-fit
	--          grids wrap their last cell on float rounding (kit pitfall 6).
	TileColumns = 3,
	TileWidthPx = 282,
	TileStridePx = 294,
	PackColumns = 4,
	PackWidthPx = 208,
	PackStridePx = 220,

	-- ===== CARD kinds (2026-07-30 redesign) =====
	-- One smallcard grid for every product tab since 2026-08-01 (the hero is
	-- visible: passes (6, the premium permanent perks) get the big card 3
	-- across; eggs/boosts (4) and gem packs (4) get the small card 4 across.
	-- At one shared column count a section always ended in a lonely orphan
	-- (6 over 4 columns = 4+2; 4 over 3 = 3+1).
	--   big:   3 * 282 + 2 * 12 = 870 ✓ exact
	--   small: 4 * 208 + 3 * 12 = 868 — 2px slack ON PURPOSE (kit pitfall 6)
	CardPx = 338,
	CardRowGapPx = 14,
	CardColumns = 3,
	CardWidthPx = 282,
	CardStridePx = 294,
	SmallCardPx = 264,
	SmallCardRowGapPx = 14,
	SmallCardColumns = 4,
	SmallCardWidthPx = 208,
	SmallCardStridePx = 220,
	HeroPx = 300,
	HeroGapPx = 16,

	-- Retired portrait ShopRow still reads this for its default cell height.
	RowCellHeight = 98 / 563,
}

-- Section header. Nominal 870x48: icon 38 | label | right-aligned count, over a
-- full-width 4px underline pill. Only drawn when a TAB holds more than one
-- section (otherwise the tab label already names the content, and a header
-- repeating it is the "chrome that says nothing" the redesign removed).
-- Horizontal: 0 icon(38) 10 label(560) 32 count(230) = 870 ✓
-- Vertical: icon y 3..41, label y 6..36, underline y 44..48 ✓
Theme.ShopSectionHeader = {
	AspectRatio = 870 / 48,
	IconPosition = Vector2.new(0, 2 / 48),
	IconSize = Vector2.new(38 / 870, 38 / 48),
	LabelPosition = Vector2.new(48 / 870, 5 / 48),
	LabelSize = Vector2.new(560 / 870, 32 / 48),
	CountPosition = Vector2.new(610 / 870, 9 / 48),
	CountSize = Vector2.new(240 / 870, 26 / 48), -- ends at 850: 20px right margin
	UnderlinePosition = Vector2.new(0, 43 / 48),
	UnderlineSize = Vector2.new(1, 4 / 48),
	UnderlineCorner = 1,
	UnderlineColor = Theme.Colors.Outline,
	LabelGradient = Theme.Header.TitleGradient,
	CountGradient = Theme.PetCard.NameGradient,
}

-- ===== SHOP TAB — the category selector row ==================================
-- Nominal 217x56, four across the 904 content column (4*217 + 3*12 = 904 ✓).
-- ICON-FIRST since 2026-08-01 (squint-test skill): each tab leads with its
-- section's glyph and the label rides beside it — this audience may not read
-- the labels at all. (The earlier label-only argument optimised for a centred
-- word; a non-reader has no use for a centred word.)
-- Selected wears the kit's gold selection accent (§4, the PetCard rule — the
-- same "this one is active" language the pets grid and the hex tree use), idle
-- is the neutral dark chip so the active tab is the only bright thing in the row.
-- Thickness on H=56 (§2): rim top 4 (7%), face top 6 / bottom 10 (1.7x) — a tab
-- IS pressable, so it keeps the button weight.
Theme.ShopTab = {
	AspectRatio = 217 / 56,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(5 / 217, 4 / 56),
	RimSize = Vector2.new(207 / 217, 44 / 56),
	RimCorner = 0.20,
	FacePosition = Vector2.new(7 / 217, 6 / 56),
	FaceSize = Vector2.new(203 / 217, 40 / 56),
	FaceCorner = 0.19,
	LabelPosition = Vector2.new(16 / 217, 13 / 56),
	LabelSize = Vector2.new(185 / 217, 28 / 56),
	-- Icon-first variant (squint-test skill, 2026-08-01: children may not
	-- read the tab labels at all — every tab carries its section's glyph).
	-- Horizontal with icon: 20 icon(34) 8 label(139) 16 = 217 ✓
	IconPosition = Vector2.new(20 / 217, 11 / 56),
	IconSize = Vector2.new(34 / 217, 34 / 56),
	LabelWithIconPosition = Vector2.new(62 / 217, 13 / 56),
	LabelWithIconSize = Vector2.new(139 / 217, 28 / 56),
}
Theme.ShopTabStates = {
	selected = {
		OutlineColor = Color3.fromRGB(92, 58, 0),
		OuterGradient = Theme.PetCard.SelectOuterGradient,
		RimGradient = Theme.PetCard.SelectRingGradient,
		-- Deeper than Rarity.Legendary.Face ON PURPOSE (same hue and keypoint
		-- structure, V scaled ~0.85): the bright gold sat in the panel's own
		-- L* band, so in grayscale the SELECTED tab was the least visible tab
		-- (tonal audit 2026-08-01, tools/tonal-hierarchy). The anchor the
		-- active state needs is VALUE, not more brightness.
		FaceGradient = Theme.PetCard.SelectFaceGradient,
		TextGradient = Theme.Rarity.Legendary.Text,
	},
	-- Idle: a LIGHT SKY-BLUE BUTTON — quieter than selected in both value and
	-- chroma, but unmistakably alive. Two failed cuts, both measured (tonal
	-- audit 2026-08-01): (1) a "muted" slate that was desaturated but DARK
	-- (dL* −58 on the ~L* 90 panel — the three idle tabs out-shouted the
	-- selected one 3.6x); (2) a near-gray wash that fixed the value but hit
	-- the kit's LOCKED/DISABLED color language — the user read the tabs as
	-- locked. The affordance rule that came out of it: quiet an interactive
	-- element by LIGHTENING ITS OWN HUE FAMILY while keeping the pressable
	-- recipe (rim flash + dark bottom lip); never by draining saturation.
	-- Face mid L* ~71 (dL* ~ −19) vs selected's deeper gold ~66 (−24): the
	-- selected tab leads on value AND chroma AND outline weight.
	idle = {
		-- text outline stays FULL dark (sticker text is self-contained);
		-- only the SURFACES went light
		OutlineColor = Color3.fromRGB(12, 34, 64),
		OuterGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(84, 128, 180)),
			ColorSequenceKeypoint.new(0.06, Color3.fromRGB(76, 118, 170)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(64, 102, 152)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 110, 160)),
		}),
		RimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 234, 254)),
			ColorSequenceKeypoint.new(0.06, Color3.fromRGB(196, 226, 252)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(150, 192, 238)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 172, 222)),
		}),
		FaceGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(164, 206, 248)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(150, 196, 242)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(128, 178, 232)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(112, 162, 220)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(86, 132, 190)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(96, 144, 202)),
		}),
		TextGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(216, 236, 252)),
		}),
	},
}

-- Shop tile — the workhorse cell (passes, eggs, boosts). Nominal 282x160,
-- icon LEFT / name+perk+price RIGHT so three fit across the 870 canvas and the
-- perk line finally has somewhere to live (it was hardcoded "" before).
-- Layer recipe by style-rules §2 on H=160: rim top 8 (5%) / bottom 19 (11.9%,
-- 2.4x), face top 12 / bottom 22. Corners .14/.13/.12 of the shorter side.
-- Horizontal: 16 plate(80) 8 column(162) 16 = 282 ✓
-- Vertical right column: 20 name(30) 2 sub(24) 6 price(48) 30 = 160 ✓
-- Vertical left column: 22 plate(80) 58 = 160 ✓
Theme.ShopTile = {
	AspectRatio = 282 / 160,
	OuterCorner = 0.14,
	RimPosition = Vector2.new(8 / 282, 8 / 160),
	RimSize = Vector2.new(266 / 282, 133 / 160),
	RimCorner = 0.13,
	FacePosition = Vector2.new(12 / 282, 12 / 160),
	FaceSize = Vector2.new(258 / 282, 126 / 160),
	FaceCorner = 0.12,
	PlatePosition = Vector2.new(14 / 282, 20 / 160),
	PlateSize = Vector2.new(88 / 282, 88 / 160),
	IconInset = 0.06, -- icon nearly fills the plate (was 0.16: 68% -> 88%)
	NamePosition = Vector2.new(110 / 282, 20 / 160),
	NameSize = Vector2.new(158 / 282, 30 / 160),
	SubPosition = Vector2.new(110 / 282, 52 / 160),
	SubSize = Vector2.new(158 / 282, 24 / 160),
	-- Price is CENTRED under the text column (104 + (162-130)/2 = 120), not
	-- left-aligned with it: a 130-wide button under a 162-wide column left a
	-- visible dead notch at the card's bottom-right.
	PricePosition = Vector2.new(124 / 282, 82 / 160),
	PriceSize = Vector2.new(130 / 282, 48 / 160),
	BadgeCenter = Vector2.new(92 / 282, 28 / 160), -- owned check, on the plate corner
	BadgeSize = Vector2.new(32 / 282, 32 / 160),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	PlateGradient = Theme.PetCard.PlateGradient,
	PlateTransparency = Theme.PetCard.PlateTransparency,
	NameGradient = Theme.Button.TextGradient,
	SubGradient = Theme.PetCard.NameGradient,
}

-- Currency pack card — portrait, compare-at-a-glance. Nominal 208x264 with a
-- RESERVED ribbon band at the top: every pack keeps the band whether or not it
-- wears a ribbon, so the four cards stay the same height and the BEST VALUE tag
-- can never overlap the art or the price (the classic version of this bug).
-- Vertical: 18 ribbon(35) 4 plate(92) 5 amount(28) 6 price(46) 30 = 264 ✓
-- Horizontal: plate (208-76)/2 = 66 · price (208-148)/2 = 30 · ribbon (208-140)/2 = 34 ✓
Theme.ShopPack = {
	AspectRatio = 208 / 264,
	OuterCorner = 0.14,
	RimPosition = Vector2.new(6 / 208, 8 / 264),
	RimSize = Vector2.new(196 / 208, 230 / 264),
	RimCorner = 0.13,
	FacePosition = Vector2.new(10 / 208, 14 / 264),
	FaceSize = Vector2.new(188 / 208, 220 / 264),
	FaceCorner = 0.12,
	RibbonPosition = Vector2.new(34 / 208, 18 / 264),
	RibbonSize = Vector2.new(140 / 208, 35 / 264),
	PlatePosition = Vector2.new(58 / 208, 57 / 264),
	PlateSize = Vector2.new(92 / 208, 92 / 264),
	IconInset = 0.05,
	AmountPosition = Vector2.new(12 / 208, 153 / 264),
	AmountSize = Vector2.new(184 / 208, 28 / 264),
	PricePosition = Vector2.new(39 / 208, 187 / 264),
	PriceSize = Vector2.new(130 / 208, 46 / 264),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	PlateGradient = Theme.PetCard.PlateGradient,
	PlateTransparency = Theme.PetCard.PlateTransparency,
	AmountGradient = Theme.Button.TextGradient,
	-- Best-value pack swaps to the gold selection accent (PetCard's rule):
	-- gradients change, geometry does not.
	BestOuterGradient = Theme.PetCard.SelectOuterGradient,
	BestRimGradient = Theme.PetCard.SelectRingGradient,
}

-- Full-width GIVE row (the group reward). Nominal 870x176 — a landscape card
-- in the same language as the grid cells: neutral body, ART WINDOW left, info
-- column, price shelf right. It was 870x200 with a white CIRCULAR plate and a
-- fully green face; the circle wasted its corners under `ScaleType.Fit` and a
-- 870-wide field of flat green is the widest possible "button".
-- Horizontal: 18 art(138) 20 column(394) 16 price(266) 18 = 870 ✓
-- Vertical column: title 50..90 (40) · desc 94..122 (28) — pair centred on 86
-- Art window: y 18..156 (138 square) · price y 60..116 (56, 266/56 = 4.75 ✓)
Theme.ShopBanner = {
	AspectRatio = 870 / 176,
	OuterCorner = 0.13,
	FacePosition = Vector2.new(7 / 870, 7 / 176),
	FaceSize = Vector2.new(856 / 870, 159 / 176),
	FaceCorner = 0.115,
	ArtPosition = Vector2.new(18 / 870, 18 / 176),
	ArtSize = Vector2.new(138 / 870, 138 / 176),
	ArtCorner = 0.14,
	ArtFacePosition = Vector2.new(22 / 870, 22 / 176),
	ArtFaceSize = Vector2.new(130 / 870, 130 / 176),
	ArtFaceCorner = 0.13,
	IconPosition = Vector2.new(31 / 870, 31 / 176),
	IconSize = Vector2.new(112 / 870, 112 / 176),
	RibbonPosition = Vector2.new(692 / 870, 10 / 176),
	RibbonSize = Vector2.new(160 / 870, 34 / 176),
	NamePosition = Vector2.new(176 / 870, 50 / 176),
	NameSize = Vector2.new(394 / 870, 40 / 176),
	DescPosition = Vector2.new(176 / 870, 94 / 176),
	DescSize = Vector2.new(394 / 870, 28 / 176),
	PricePosition = Vector2.new(586 / 870, 60 / 176),
	PriceSize = Vector2.new(266 / 870, 56 / 176),
	BadgeCenter = Vector2.new(150 / 870, 34 / 176),
	BadgeSize = Vector2.new(40 / 870, 40 / 176),
	Accent = "Rare", -- a GIVE wears green; the paid hero wears gold
}
-- `accent = "free"` is handled inside ShopBanner (it resolves to the same Rare
-- green as the default), so no override table is needed any more.

-- Price button: icon + amount, the largest coloured element on every cell.
-- Thickness by style-rules §2 on H=48: rim top 3 (6.3%) / bottom 7 (14.6%).
-- Horizontal: 12 icon(26) 6 text(74) 12 = 130 ✓
Theme.ShopPrice = {
	-- Faint light disc behind the price glyph (squint-test
	-- 2026-08-01): the dark Robux mark nearly vanished on the green
	-- shelf; the plate lifts ANY glyph off ANY shelf color.
	-- Pad is PER STYLE so the disc stays inside the Face — icon y 11..37, Face 4.5..39.5 -> 2.5px slack
	-- (nothing light may sit on the button's dark bottom lip).
	IconPlateTransparency = 0.72,
	IconPlatePad = 0.08,
	AspectRatio = 130 / 48,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(3 / 130, 3 / 48),
	RimSize = Vector2.new(124 / 130, 38 / 48),
	RimCorner = 0.18,
	FacePosition = Vector2.new(4.5 / 130, 4.5 / 48),
	FaceSize = Vector2.new(121 / 130, 35 / 48),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(12 / 130, 11 / 48),
	IconSize = Vector2.new(26 / 130, 26 / 48),
	TextPosition = Vector2.new(44 / 130, 11 / 48),
	TextSize = Vector2.new(74 / 130, 26 / 48),
	-- Text-only (OWNED / SOON / FREE): the icon is hidden and the label spans.
	WideTextPosition = Vector2.new(10 / 130, 11 / 48),
	WideTextSize = Vector2.new(110 / 130, 26 / 48),
}
-- Banner variant. Its own fraction table — the same fractions at a different
-- aspect would move every inset (a 130-wide table stretched to 220 is not the
-- same button).
-- Horizontal: 20 icon(32) 8 text(140) 20 = 220 ✓
Theme.ShopPriceWide = {
	AspectRatio = 220 / 58,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(4 / 220, 4 / 58),
	RimSize = Vector2.new(212 / 220, 45 / 58),
	RimCorner = 0.18,
	FacePosition = Vector2.new(6 / 220, 6 / 58),
	FaceSize = Vector2.new(208 / 220, 41 / 58),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(20 / 220, 13 / 58),
	IconSize = Vector2.new(32 / 220, 32 / 58),
	TextPosition = Vector2.new(60 / 220, 14 / 58),
	TextSize = Vector2.new(140 / 220, 30 / 58),
	WideTextPosition = Vector2.new(16 / 220, 14 / 58),
	WideTextSize = Vector2.new(188 / 220, 30 / 58),
}

-- Neutral grey — the same "this is not available to you" language the hex tree
-- uses for a locked node, so the state is learned once and read everywhere. A
-- green button would still say "press me" whatever its label read.
-- ONE table serves both greyed states: they differ in what the shelf SAYS, not
-- in what it looks like, and giving "can't afford yet" its own shade would be a
-- new palette for no new meaning (style-rules §4/§7).
local shopPriceGrey = {
	OutlineColor = Color3.fromRGB(20, 23, 28),
	OuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 54, 64)),
		ColorSequenceKeypoint.new(0.10, Color3.fromRGB(34, 39, 47)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(33, 38, 46)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 34, 42)),
	}),
	RimGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 130, 145)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(150, 160, 175)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(104, 114, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(78, 86, 100)),
	}),
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(126, 136, 150)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(104, 113, 128)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(90, 98, 112)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(60, 66, 78)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 77, 90)),
	}),
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 231, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 184, 198)),
	}),
}

-- "Not enough gems" is its own state, not an alias of "SOON" (UX audit
-- 2026-08-01): grey is overloaded in the genre (disabled / sold out /
-- locked), so a broke player read the whole Boosts tab as dead. Same grey
-- shelf — still not clickable — but the PRICE goes red (dark-maroon outline
-- per the §4 hue rule): price-present-but-red = "need more currency",
-- no-price = "nothing to buy here yet".
local shopPriceCant = {
	OutlineColor = Color3.fromRGB(61, 0, 10),
	OuterGradient = shopPriceGrey.OuterGradient,
	RimGradient = shopPriceGrey.RimGradient,
	FaceGradient = shopPriceGrey.FaceGradient,
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 158, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 110, 104)),
	}),
}

-- OWNED is a STAMP, not a button (three review lenses flagged the raised
-- sky-blue shelf as the most button-looking element on an owned card — a
-- false affordance that also rhymed with the idle tabs). Flat per the tag
-- recipe (style-rules §2c): one muted fill on every layer, no rim flash, no
-- lip; the green check badge on the art corner stays the fast signal.
local shopPriceOwnedFlat = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(104, 128, 160)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(94, 116, 146)),
})

-- Price button state accents. The two grey ones exist because their absence was
-- a silent failure (R8): an unconfigured dev-product id used to render a live
-- BUY button whose purchase the server refused with nothing shown to the
-- player, and a gem card the player could not pay for did the same.
Theme.ShopPriceStates = {
	buy = {
		OutlineColor = Theme.EquipGreen.OutlineColor,
		OuterGradient = Theme.EquipGreen.OuterGradient,
		RimGradient = Theme.EquipGreen.RimGradient,
		FaceGradient = Theme.EquipGreen.FaceGradient,
		TextGradient = Theme.EquipGreen.TextGradient,
	},
	owned = {
		OutlineColor = Color3.fromRGB(20, 42, 70),
		OuterGradient = shopPriceOwnedFlat,
		RimGradient = shopPriceOwnedFlat,
		FaceGradient = shopPriceOwnedFlat,
		TextGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 236, 250)),
		}),
	},
	-- "SOON" — no id yet, so there is no price to show and the label spans the
	-- whole shelf (text-only, no glyph).
	unavailable = shopPriceGrey,
	-- "Not enough gems YET" — grey shelf, KEEPS the gem glyph and the amount
	-- (that number is the information the player needs), and the price is RED
	-- so the state reads "too expensive", never "disabled" (shopPriceCant).
	unaffordable = shopPriceCant,
}

-- Corner tag ("BEST VALUE", "ONE TIME"). Built from the kit's own layer recipe,
-- NOT from the Ribbon*.png art: that art is a square 257x257 rosette, so a
-- 4:1 tag box with ScaleType.Fit renders it as a 40x40 blob behind the label.
-- A dark Outer pill + accent Face + OutlinedText is both correct at this aspect
-- and closer to the kit, which builds chrome from Frame+UICorner+UIGradient and
-- reserves images for icons.
-- ONE fraction table serves both sizes: banner 160x40 and pack 140x35 are the
-- same aspect 4.0.
-- Horizontal: 12 label(136) 12 = 160 ✓ · Vertical: face y 3..33, label y 5..31 ✓
Theme.ShopRibbon = {
	AspectRatio = 4.0,
	OuterCorner = 0.30,
	FacePosition = Vector2.new(3 / 160, 3 / 40),
	FaceSize = Vector2.new(154 / 160, 30 / 40),
	FaceCorner = 0.26,
	LabelPosition = Vector2.new(12 / 160, 5 / 40),
	LabelSize = Vector2.new(136 / 160, 26 / 40),
	Variants = {
		BestValue = {
			Outer = Theme.Rarity.Legendary.Outer,
			Face = Theme.Rarity.Legendary.Face,
			Outline = Theme.Rarity.Legendary.Outline,
			Text = Theme.Rarity.Legendary.Text,
		},
		Limited = {
			Outer = Theme.Exit.OuterGradient,
			Face = Theme.Exit.FaceGradient,
			Outline = Theme.Exit.XOutline,
			Text = Theme.Exit.XGradient,
		},
		New = {
			Outer = Theme.Rarity.Rare.Outer,
			Face = Theme.Rarity.Rare.Face,
			Outline = Theme.Rarity.Rare.Outline,
			Text = Theme.Rarity.Rare.Text,
		},
		Event = {
			Outer = Theme.Rarity.Epic.Outer,
			Face = Theme.Rarity.Epic.Face,
			Outline = Theme.Rarity.Epic.Outline,
			Text = Theme.Rarity.Epic.Text,
		},
	},
}

-- ===== Shop CARDS (2026-07-31 redesign) =====================================
--
-- THE BUG THIS FIXES — "the cards look like stretched buttons".
-- The 2026-07-30 card was drawn with the kit's BUTTON layer recipe
-- (style-rules §2): dark outline ~6% of H at the top and ~12% at the bottom,
-- "the weight that makes elements look physically thick". On a 282x296 cell
-- that is 8px of outline at the top and 30px at the bottom — a 3.75x lip. That
-- lip is the single strongest "I am a pressable slab" signal in the whole kit,
-- and it was under EVERY product. Add a flat single-colour face and content
-- floating on it (also exactly what a button is) and the result is a button
-- that happens to be tall. The rule the kit was missing:
--
--   A BUTTON is a slab: one colour field, bottom-weighted outline.
--   A CARD is a container: EVEN outline, and INTERNAL ZONES.
--
-- So: the outline is now even (7 top/sides, 10 bottom = 1.4x, enough for the
-- kit's physicality, far below the 2x that reads as "press me"), and the card
-- is composed of an ART WINDOW over an INFO block over a PRICE SHELF. Only the
-- price shelf keeps the button recipe — it is the only thing that IS a button.
--
-- WHERE THE COLOUR WENT. Six passes in six saturated hues gave the grid no
-- hierarchy: every cell shouted equally, which is what "cluttered" means. The
-- body is now ONE neutral for every card and the accent lives in the ART
-- WINDOW only. A row then reads as one object with N coloured windows, the
-- product art gets the strongest local contrast on the card, and rarity is
-- still colour-coded.
--
-- This is NOT the rejected "plate behind the icon". Both rejected attempts put
-- a BADGE under the glyph (a white circle; then a recessed well + shelf +
-- gloss + shadow + halo — five layers at once). The art window is the card's
-- top ZONE, full content width, and it is doing a job nothing else can do:
-- `ScaleType.Fit` draws every icon at the shorter side of its box, so art of
-- different aspect (a tall flame vs a wide egg cluster vs a square pack) drew
-- at wildly different visual sizes straight on the face. One window normalises
-- them. Icon area went 13.5% -> 22% of the cell.

-- Card body — ONE palette for every product card, so the accent can live in
-- the art window alone. Derived from the kit's navy outline family (§4): the
-- Outer is the Header's outline curve, the Face is a desaturated blueberry
-- that sits dark against the panel's white-blue fill.
Theme.ShopCardBody = {
	OutlineColor = Color3.fromRGB(8, 26, 48),
	OuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 62, 98)),
		ColorSequenceKeypoint.new(0.06, Color3.fromRGB(8, 36, 62)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(6, 30, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 42, 70)),
	}),
	-- Face recipe (§3): bright at 0, plateau, hard dark lip at 0.93..1.
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 130, 180)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(78, 110, 158)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(62, 90, 136)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(50, 74, 116)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(32, 50, 84)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 62, 100)),
	}),
	TitleGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(232, 243, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 220, 250)),
	}),
	-- The perk line is SECONDARY: same family, one step down in value, so the
	-- title wins the cell without needing a second font size trick.
	PerkGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(188, 210, 238)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(158, 184, 218)),
	}),
	-- Gold frame for `premium` — the kit's existing selection accent (§4), a
	-- gradient swap on the Outer only. Geometry never changes with state.
	PremiumOuterGradient = Theme.PetCard.SelectOuterGradient,
	PremiumOutlineColor = Color3.fromRGB(92, 58, 0),
}

-- Per-item accents. Every one is an EXISTING kit accent set (the six-tier rarity
-- ladder plus the base Button blue) — no new hues, per style-rules §4/§7.
Theme.ShopCardAccents = {
	Blue = {
		OuterGradient = Theme.Button.OuterGradient,
		FaceGradient = Theme.Button.FaceGradient,
		OutlineColor = Theme.Button.OutlineColor,
		TextGradient = Theme.Button.TextGradient,
	},
	Common = {
		OuterGradient = Theme.Rarity.Common.Outer,
		FaceGradient = Theme.Rarity.Common.Face,
		OutlineColor = Theme.Rarity.Common.Outline,
		TextGradient = Theme.Rarity.Common.Text,
	},
	Uncommon = {
		OuterGradient = Theme.Rarity.Uncommon.Outer,
		FaceGradient = Theme.Rarity.Uncommon.Face,
		OutlineColor = Theme.Rarity.Uncommon.Outline,
		TextGradient = Theme.Rarity.Uncommon.Text,
	},
	Rare = {
		OuterGradient = Theme.Rarity.Rare.Outer,
		FaceGradient = Theme.Rarity.Rare.Face,
		OutlineColor = Theme.Rarity.Rare.Outline,
		TextGradient = Theme.Rarity.Rare.Text,
	},
	Epic = {
		OuterGradient = Theme.Rarity.Epic.Outer,
		FaceGradient = Theme.Rarity.Epic.Face,
		OutlineColor = Theme.Rarity.Epic.Outline,
		TextGradient = Theme.Rarity.Epic.Text,
	},
	Legendary = {
		OuterGradient = Theme.Rarity.Legendary.Outer,
		FaceGradient = Theme.Rarity.Legendary.Face,
		OutlineColor = Theme.Rarity.Legendary.Outline,
		TextGradient = Theme.Rarity.Legendary.Text,
	},
	Secret = {
		OuterGradient = Theme.Rarity.Secret.Outer,
		FaceGradient = Theme.Rarity.Secret.Face,
		OutlineColor = Theme.Rarity.Secret.Outline,
		TextGradient = Theme.Rarity.Secret.Text,
	},
}
Theme.ShopCardAccentDefault = "Blue"

-- ===== SHOP CARD — art window · info · price shelf ==========================
--
-- Big card — game passes, 3 across the 870 canvas. Nominal 282x338.
--   3*282 + 2*12 = 870 ✓ exact
-- The cell went 282x296 (0.95, a squat rectangle — the second "button" tell,
-- since buttons are wide and cards are portrait) to 282x338 (0.834).
--
-- CHROME  Outer 0..282 x 0..338 r 0.14
--         Face  7..275 x 7..328 — outline 7 top/sides, 10 bottom (1.4x, NOT
--               the button recipe's 2x+; the old card was 8 vs 30 = 3.75x)
-- VERTICAL inside the face (321):
--   11 · 168 art · 10 · 36 title · 2 · 22 perk · 8 · 52 price · 12 = 321 ✓
--   art 18..186 · title 196..232 · perk 234..256 · price 264..316
-- HORIZONTAL: one content column x 18..264 (246) for art, title, perk and
--   price alike — every zone shares one left and right edge, which is most of
--   why the cell now reads as tidy. ✓ 18 + 246 + 18 = 282
--   ribbon 130 + 140 + 12 ✓ (overhangs the card TOP into the row gap)
-- ART WINDOW: ring 18..264 x 18..186, face inset 4 all round (an even ring —
--   a window, not a bevel). Icon 146² centred = 22% of the cell (was 13.5%).
Theme.ShopCard = {
	AspectRatio = 282 / 338,
	OuterCorner = 0.14,
	FacePosition = Vector2.new(7 / 282, 7 / 338),
	FaceSize = Vector2.new(268 / 282, 321 / 338),
	FaceCorner = 0.123,
	ArtPosition = Vector2.new(18 / 282, 18 / 338),
	ArtSize = Vector2.new(246 / 282, 168 / 338),
	ArtCorner = 0.13,
	ArtFacePosition = Vector2.new(22 / 282, 22 / 338),
	ArtFaceSize = Vector2.new(238 / 282, 160 / 338),
	ArtFaceCorner = 0.12,
	IconPosition = Vector2.new(68 / 282, 29 / 338),
	IconSize = Vector2.new(146 / 282, 146 / 338),
	TitlePosition = Vector2.new(18 / 282, 196 / 338),
	TitleSize = Vector2.new(246 / 282, 36 / 338),
	PerkPosition = Vector2.new(18 / 282, 234 / 338),
	PerkSize = Vector2.new(246 / 282, 22 / 338),
	PricePosition = Vector2.new(18 / 282, 264 / 338),
	PriceSize = Vector2.new(246 / 282, 52 / 338),
	RibbonPosition = Vector2.new(130 / 282, -12 / 338),
	RibbonSize = Vector2.new(140 / 282, 34 / 338),
	BadgeCenter = Vector2.new(240 / 282, 42 / 338), -- art window's top-right corner
	BadgeSize = Vector2.new(44 / 282, 44 / 338),
}

-- Small card — eggs/boosts and gem packs, 4 across. Nominal 208x264 (0.788).
--   4*208 + 3*12 = 868 <= 870 ✓ (2px slack, kit pitfall 6)
-- Same composition at 0.7376 scale, re-rounded to whole px.
-- CHROME  Face 6..202 x 6..255 — outline 6 top/sides, 9 bottom (1.5x)
-- VERTICAL inside the face (249):
--   10 · 126 art · 8 · 28 title · 2 · 16 perk · 8 · 37 price · 14 = 249 ✓
--   art 16..142 · title 150..178 · perk 180..196 · price 204..241
-- HORIZONTAL: content column x 16..192 (176) ✓ 16 + 176 + 16 = 208
--   Icon 110² centred in the window = 22% of the cell — the SAME share as the
--   big card, so the two sizes read as one family.
Theme.ShopCardSmall = {
	AspectRatio = 208 / 264,
	OuterCorner = 0.14,
	FacePosition = Vector2.new(6 / 208, 6 / 264),
	FaceSize = Vector2.new(196 / 208, 249 / 264),
	FaceCorner = 0.123,
	ArtPosition = Vector2.new(16 / 208, 16 / 264),
	ArtSize = Vector2.new(176 / 208, 126 / 264),
	ArtCorner = 0.13,
	ArtFacePosition = Vector2.new(19.5 / 208, 19.5 / 264),
	ArtFaceSize = Vector2.new(169 / 208, 119 / 264),
	ArtFaceCorner = 0.12,
	IconPosition = Vector2.new(49 / 208, 24 / 264),
	IconSize = Vector2.new(110 / 208, 110 / 264),
	TitlePosition = Vector2.new(16 / 208, 150 / 264),
	TitleSize = Vector2.new(176 / 208, 28 / 264),
	PerkPosition = Vector2.new(16 / 208, 180 / 264),
	PerkSize = Vector2.new(176 / 208, 16 / 264),
	PricePosition = Vector2.new(16 / 208, 204 / 264),
	PriceSize = Vector2.new(176 / 208, 37 / 264),
	RibbonPosition = Vector2.new(96 / 208, -9 / 264),
	RibbonSize = Vector2.new(104 / 208, 26 / 264),
	BadgeCenter = Vector2.new(176 / 208, 34 / 264),
	BadgeSize = Vector2.new(38 / 208, 38 / 264),
}

-- The card's PRICE SHELF — the only part of a card that is still drawn with
-- the button recipe, because it is the only part that is a button: rim 3.5,
-- face top 5 / bottom 9 (1.8x weight, §2). One table serves both card sizes:
-- big 246x52 = 4.731 and small 176x37 = 4.757 are the same aspect to 0.5%.
-- Horizontal: 76 icon(30) 8 text(80) — the pair is centred for a 3-digit price
--   (icon 76..106, "349" ≈ 114..162 → group centre 119 vs shelf centre 123).
--   Text is LEFT-aligned after the glyph, so 2- and 4-digit prices drift ±8px
--   on a 246 shelf, which is under 4% and invisible in a grid.
-- WideText (OWNED / SOON / FREE) is centred across 20..226.
Theme.ShopPriceCard = {
	-- Faint light disc behind the price glyph (squint-test
	-- 2026-08-01): the dark Robux mark nearly vanished on the green
	-- shelf; the plate lifts ANY glyph off ANY shelf color.
	-- Pad is PER STYLE so the disc stays inside the Face — icon y 11..41, Face 5..43 -> 2px slack
	-- (nothing light may sit on the button's dark bottom lip).
	IconPlateTransparency = 0.72,
	IconPlatePad = 0.06,
	AspectRatio = 246 / 52,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(4 / 246, 3.5 / 52),
	RimSize = Vector2.new(238 / 246, 41 / 52),
	RimCorner = 0.18,
	FacePosition = Vector2.new(5.5 / 246, 5 / 52),
	FaceSize = Vector2.new(235 / 246, 38 / 52),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(76 / 246, 11 / 52),
	IconSize = Vector2.new(30 / 246, 30 / 52),
	TextPosition = Vector2.new(114 / 246, 12 / 52),
	TextSize = Vector2.new(80 / 246, 28 / 52),
	WideTextPosition = Vector2.new(20 / 246, 12 / 52),
	WideTextSize = Vector2.new(206 / 246, 28 / 52),
}

-- Modal scrim behind every open panel (UX audit 2026-08-01): panels floated
-- over the FULL-BRIGHTNESS world, so the busy scene + colorful HUD icons
-- competed with panel content in every capture — the "hard to read" that no
-- panel-internal fix could reach. Genre-standard dim; lighter than the
-- upgrades overlay's 0.14 (that one replaces the screen, this one sits
-- behind a windowed panel). The scrim is also the tap-outside-to-close
-- surface (AppRoot).
Theme.PanelScrim = {
	Color = Color3.fromRGB(8, 12, 22),
	Transparency = 0.42,
}

-- Hero buy shelf — ShopPriceCard's recipe re-cut for the hero's full-width
-- 576x64 box (the card fractions assume a 246x52 grid; stretched to 576 the
-- icon/text pair drifts apart). Glyph+amount centred as a pair; wide labels
-- (OWNED) span the middle.
-- Horizontal: pair = icon(34) 8 text(100) centred: icon x 217..251, text
--   x 259..359 (pair 217..359, centre 288 ≈ 576/2 ✓)
Theme.ShopPriceHero = {
	-- Faint light disc behind the price glyph (squint-test
	-- 2026-08-01): the dark Robux mark nearly vanished on the green
	-- shelf; the plate lifts ANY glyph off ANY shelf color.
	-- Pad is PER STYLE so the disc stays inside the Face — icon y 15..49, Face 6..53 -> 4px slack
	-- (nothing light may sit on the button's dark bottom lip).
	IconPlateTransparency = 0.72,
	IconPlatePad = 0.10,
	AspectRatio = 576 / 64,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(9 / 576, 4 / 64),
	RimSize = Vector2.new(558 / 576, 51 / 64),
	RimCorner = 0.18,
	FacePosition = Vector2.new(13 / 576, 6 / 64),
	FaceSize = Vector2.new(550 / 576, 47 / 64),
	FaceCorner = 0.17,
	IconPosition = Vector2.new(217 / 576, 15 / 64),
	IconSize = Vector2.new(34 / 576, 34 / 64),
	TextPosition = Vector2.new(259 / 576, 15 / 64),
	TextSize = Vector2.new(100 / 576, 34 / 64),
	WideTextPosition = Vector2.new(60 / 576, 15 / 64),
	WideTextSize = Vector2.new(456 / 576, 34 / 64),
}

-- HERO — the Starter Pack's own cell, full width. Nominal 870x300 (re-cut
-- 2026-08-01 round 3 from 870x260: dropping the art plate left the 168px
-- gift floating in the 206px zone the plate used to fill, and the card read
-- as dead space with a small icon — "very bad sizes and positions". The art
-- is now the plate's OWN size, and the taller card + bigger shelf also fill
-- the single-hero Offers window instead of floating in it: 300 in the 370
-- window leaves 35px symmetric margin).
-- It is not a wide ShopCard: the bundle is the pitch, so the contents render as
-- a ROW OF CHIPS (what you get, one per grant) beside the art and an
-- oversized price shelf. That row is the whole reason this component exists.
-- Same body language as the grid cells minus the art window (ArtPlate =
-- false, below), plus the gold PREMIUM frame — the featured offer is the one
-- cell in the shop allowed to wear it. The info column runs to the card's
-- RIGHT EDGE and the buy shelf is CENTRED under it (packing it into a narrow
-- column left a 160x160 void bottom-right — the old dead-area lesson).
-- Horizontal: 30 art(220) 20 column(576) 24 = 870 ✓
--   chips 4 * 136 + 3 * 10 = 574 ≤ 576 (2px slack, small-card precedent)
--   last chip 270 + 3*146 = 708, +136 = 844; column edge 846
--   shelf spans the FULL column (576x64, own fraction cut: ShopPriceHero)
-- Column vertical: 38 title(46) 4 desc(28) 12 bundle(50) 14 price(64) 44 = 300 ✓
-- Art: x 30..250, y 40..260 (220 square, vertically centred in 300)
Theme.ShopHero = {
	AspectRatio = 870 / 300,
	OuterCorner = 0.09,
	FacePosition = Vector2.new(8 / 870, 8 / 300),
	FaceSize = Vector2.new(854 / 870, 283 / 300),
	FaceCorner = 0.082,
	ArtPosition = Vector2.new(22 / 870, 32 / 300),
	ArtSize = Vector2.new(236 / 870, 236 / 300),
	ArtCorner = 0.13,
	ArtFacePosition = Vector2.new(27 / 870, 37 / 300),
	ArtFaceSize = Vector2.new(226 / 870, 226 / 300),
	ArtFaceCorner = 0.12,
	IconPosition = Vector2.new(30 / 870, 40 / 300),
	IconSize = Vector2.new(220 / 870, 220 / 300),
	TitlePosition = Vector2.new(270 / 870, 38 / 300),
	TitleSize = Vector2.new(576 / 870, 46 / 300),
	DescPosition = Vector2.new(270 / 870, 88 / 300),
	DescSize = Vector2.new(576 / 870, 28 / 300),
	-- Bundle row: 4 * 136 + 3 * 10 = 574 ✓ (chips are laid out by stride)
	BundlePosition = Vector2.new(270 / 870, 128 / 300),
	BundleSize = Vector2.new(136 / 870, 50 / 300),
	BundleStride = 146 / 870,
	BundleColumns = 4,
	-- FULL-WIDTH shelf on the info column's own rails (composition audit
	-- 2026-08-01: title left-aligned, chips justified, button centred on a
	-- third axis read as adrift — and a 576-wide CTA is also the biggest tap
	-- target on the panel). Uses Theme.ShopPriceHero fractions, cut for this
	-- exact 576x64 box.
	PricePosition = Vector2.new(270 / 870, 192 / 300),
	PriceSize = Vector2.new(576 / 870, 64 / 300),
	-- Overhangs the card's TOP edge, exactly like a grid cell's ribbon, instead
	-- of floating inside the face where it needed a void around it to breathe.
	RibbonPosition = Vector2.new(686 / 870, -12 / 300),
	RibbonSize = Vector2.new(160 / 870, 40 / 300),
	BadgeCenter = Vector2.new(250 / 870, 50 / 300),
	BadgeSize = Vector2.new(46 / 870, 46 / 300),
	Accent = "Legendary", -- the paid hero wears gold; the give stays green
	Premium = true,
	-- NO art plate on the hero (2026-08-01, user round 2). The grid card's
	-- accent window earns its keep by normalising MIXED-aspect art across a
	-- grid; a single-item hero has nothing to normalise, so the plate was a
	-- pure attention magnet — first as neon Legendary gold (loudest patch on
	-- the tab), then as "dirty" antique gold. The art now sits directly on
	-- the navy body, where its own dark outlines carry it. Set true (or omit
	-- with an ArtFaceGradient) only for styles that keep a plate.
	ArtPlate = false,
}

-- One bundle chip ("x2 Cal"). Nominal 140x50 — under the 50px threshold, so it
-- drops the Rim and is Outer + Face only (style-rules §2). Re-cut from 188x50
-- when the row went to four chips; every fraction below is of the NEW 140 grid,
-- because the old ones would have squashed a 34px icon into a 25px slot.
-- Horizontal (icon-first re-cut below): 6 icon(34) 6 text(86) 8 = 140 ✓ · Vertical: face 3..44,
--   icon y 11..39 (28 square, centred in 50), text y 12..38 ✓
-- CHIP COPY IS A LAYOUT CONSTRAINT, and a tighter one than before: TextScaled
-- binds on WIDTH, and the text zone lost 38px. At the kit's measured Fredoka
-- advance (~0.75 x font size per glyph — the constant that reproduces both
-- published limits: 15 chars in the card's 176px perk zone, 9 glyphs in the
-- 185px tab label), a 90px zone renders N characters at 90 / (0.75 N) px:
--   3 chars "200"      -> capped at the 26px zone height
--   6 chars "x2 Cal"   -> 20px
--   5 chars "Bite+"    -> 24px
--   8 chars "x2 Speed" -> 15px  <- the floor; longer copy reads as noise
-- So bundle text is capped at 8 characters. Anything longer belongs in the
-- product's own card, not on a chip.
-- The face is a LIGHT slate, not the Chip recipe's deep blue: the hero's body
-- is navy now, and a dark chip on a dark body was invisible (it was designed
-- against the old gold face).
Theme.ShopHeroItem = {
	AspectRatio = 140 / 50,
	OuterCorner = 0.24,
	FacePosition = Vector2.new(3 / 140, 3 / 50),
	FaceSize = Vector2.new(134 / 140, 41 / 50),
	FaceCorner = 0.22,
	-- Icon grown 28 -> 34 (squint-test 2026-08-01: the chips' GLYPHS are
	-- the bundle contents for a non-reader; the icon is the carrier, the
	-- text reinforces). Horizontal: 6 icon(34) 6 text(86) 8 = 140 ✓ — the
	-- ~8-char copy cap stands (86px zone vs the old 90).
	IconPosition = Vector2.new(6 / 140, 8 / 50),
	IconSize = Vector2.new(34 / 140, 34 / 50),
	TextPosition = Vector2.new(46 / 140, 12 / 50),
	TextSize = Vector2.new(86 / 140, 26 / 50),
	-- A FLAT TAG, not a button (round 2), and a DARK ENGRAVED one (round 4):
	-- the light flat pill still rhymed with the idle tabs, and the gem chip
	-- ("<gem> 200") in that style could be misread as a second price in the
	-- first five seconds (UX audit 2026-08-01). Engraved = one fill on BOTH
	-- layers, DARKER than the card face (dL* ~ −12) — an inset well is the
	-- one surface language that can never read as pressable — with the kit's
	-- self-contained sticker text on top (white + full-dark outline) so
	-- readability holds on the dark fill. style-rules §2c.
	OuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 66, 98)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 58, 88)),
	}),
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 66, 98)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 58, 88)),
	}),
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(228, 240, 252)),
	}),
	-- FULL-STRENGTH dark outline: the kit's sticker text is self-contained
	-- (white glyph + dark outline reads on ANY face). Round 2 softened this
	-- to mid-navy "to match the flat tag" and the labels washed out — the
	-- flatness lives in the FILL, never in the text.
	OutlineColor = Color3.fromRGB(8, 26, 48),
}

-- Kit-styled text input (dark well + light groove face). Nominal 418x84.
Theme.TextInput = {
	AspectRatio = 418 / 84,
	OuterCorner = 0.22,
	OuterGradient = Theme.Toggle.OuterGradient,
	GroovePosition = Vector2.new(6 / 418, 6 / 84),
	GrooveSize = Vector2.new(406 / 418, 68 / 84),
	GrooveCorner = 0.20,
	GrooveGradient = Theme.Scrollbar.GrooveGradient,
	TextPosition = Vector2.new(22 / 418, 20 / 84),
	TextSize = Vector2.new(374 / 418, 44 / 84),
	TextColor = Color3.fromRGB(23, 74, 110),
	PlaceholderColor = Color3.fromRGB(122, 168, 200),
}

-- Codes window geometry (portrait Panel family). Vertical zones (content
-- region y 128..691 like settings rows): input 180..264, button 300..384,
-- status 410..470.
Theme.CodesLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = 0.7,
	InputPosition = Vector2.new(47 / 512, 180 / 727),
	InputSize = Vector2.new(418 / 512, 84 / 727),
	ButtonPosition = Vector2.new(97 / 512, 300 / 727),
	ButtonSize = Vector2.new(318 / 512, 84 / 727),
	StatusPosition = Vector2.new(47 / 512, 410 / 727),
	StatusSize = Vector2.new(418 / 512, 60 / 727),
	StatusOkGradient = Theme.EquipGreen.TextGradient,
	StatusErrorGradient = Theme.Exit.XGradient,
}

-- Social offer window (Invite Friends / community reward — features/referrals.md,
-- features/group-reward.md). Portrait Panel family, nominal 512x727, content
-- region y 128..691 (563 tall) exactly like the settings rows and the codes
-- dialog. It is the genre's "one offer, one button" archetype: a big piece of
-- art carries the offer, two text zones explain it, a status line answers the
-- press, and a single CTA sits at the bottom where the thumb already is.
-- Vertical check-sum inside the content region:
--   22 art(180) 14 headline(44) 10 body(84) 14 status(52) 18 button(84) 41 = 563 ✓
-- The art zone is SQUARE (180x180): ScaleType.Fit draws at the shorter side, so
-- a wide zone would throw its width away (ui-kit gotcha).
Theme.SocialLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = 0.7,
	ArtPosition = Vector2.new(166 / 512, 150 / 727),
	ArtSize = Vector2.new(180 / 512, 180 / 727),
	HeadlinePosition = Vector2.new(47 / 512, 344 / 727),
	HeadlineSize = Vector2.new(418 / 512, 44 / 727),
	BodyPosition = Vector2.new(47 / 512, 398 / 727),
	BodySize = Vector2.new(418 / 512, 84 / 727),
	StatusPosition = Vector2.new(47 / 512, 496 / 727),
	StatusSize = Vector2.new(418 / 512, 52 / 727),
	ButtonPosition = Vector2.new(97 / 512, 566 / 727),
	ButtonSize = Vector2.new(318 / 512, 84 / 727),
	HeadlineGradient = Theme.Header.TitleGradient,
	TextOutlineColor = Theme.Colors.TextOutline,
	-- DARK ink, because this body sits on the portrait Panel's near-WHITE fill
	-- (252,253,255 -> 166,219,253). The pale blue the hex-tree Detail card uses
	-- for the same job is correct THERE (a dark Chip surface) and would be
	-- invisible here — ~1.07:1. Same ink as TextInput, the kit's other
	-- dark-on-light body text.
	BodyColor = Theme.TextInput.TextColor,
	BodyMaxTextSize = 22,
	StatusOkGradient = Theme.EquipGreen.TextGradient,
	StatusErrorGradient = Theme.Exit.XGradient,
	-- Dim the CTA when it cannot be pressed (claimed / a claim already running),
	-- the same recipe the matchmaking START uses — and a CanvasGroup CLIPS, so it
	-- needs the same headroom trick: no pulse rides this button, but
	-- `usePressable`'s HOVER pose is 1.05 and would be shaved on all four sides
	-- inside a group cut to the button's exact size.
	ButtonDisabledTransparency = 0.38,
	ButtonPressHeadroom = 1.10,
}

-- Compact HUD menu button (Button family, centered text). Nominal 170x56.
Theme.MenuButton = {
	AspectRatio = 170 / 56,
	OuterCorner = 0.24,
	RimPosition = Vector2.new(5 / 170, 5 / 56),
	RimSize = Vector2.new(160 / 170, 45 / 56),
	RimCorner = 0.22,
	FacePosition = Vector2.new(7 / 170, 6.5 / 56),
	FaceSize = Vector2.new(156 / 170, 43 / 56),
	FaceCorner = 0.21,
	TextPosition = Vector2.new(14 / 170, 11 / 56),
	TextSize = Vector2.new(142 / 170, 34 / 56),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
}

-- Bare HUD menu button (icon + label BELOW it, NO background — the simulator
-- "icon column" archetype; see Components/HudMenuButton). Zones are fractions
-- of the button (nominal 100x118): icon zone y 0..86, gap 4, label y 90..114
-- (24), bottom margin 4 -> 118 ✓. The button FILLS its layout cell (biggest
-- tap area); the icon (ScaleType.Fit) self-fits a square, so no aspect
-- constraint is needed — the zones hold at whatever shape the cell is. Bigger
-- than the old MenuButton for phones.
Theme.HudMenuButton = {
	IconPosition = Vector2.new(0, 0),
	-- Nominal 100x126: icon 0..96, gap 4, label 100..122, margin 4 = 126 ✓
	-- The icon zone is deliberately near-square (100 wide x 96 tall) — a square
	-- glyph under ScaleType.Fit draws at the zone's shorter side, so a short,
	-- wide zone throws away the width.
	IconSize = Vector2.new(1, 96 / 126),
	IconColor = Color3.new(1, 1, 1), -- no tint (icons are pre-colored)
	LabelPosition = Vector2.new(0, 100 / 126),
	LabelSize = Vector2.new(1, 22 / 126),
	LabelGradient = Theme.Hud.ButtonLabelGradient,
	LabelOutlineColor = Theme.Colors.TextOutline,
	-- Notification dot on the icon's top-right (Badge self-squares from width).
	BadgeAnchor = Vector2.new(0.5, 0.5),
	BadgePosition = Vector2.new(0.80, 0.12),
	BadgeSize = Vector2.new(0.26, 0.26),
}

-- App HUD geometry (template glue): gold pill top-left, menu column under it.
-- Reference screen 1920x1080 (Hud family).
Theme.AppHud = {
	PillAspect = Theme.Hud.PillAspect,
	PillHeight = 64 / 1080,
	PillPosition = Vector2.new(22 / 1920, 24 / 1080),
	MenuPosition = Vector2.new(22 / 1920, 110 / 1080),
	-- Icon GRID (was a single tall column that ran to the bottom of the screen).
	-- Buttons flow left-to-right, wrapping after MenuColumns — the meta menu
	-- becomes a compact block that stops well above mid-screen. Each cell is
	-- comfortable to tap on phones; the HudMenuButton icon self-fits its cell
	-- (no aspect constraint).
	MenuColumns = 2,
	-- 92x100 was too small to read on a phone: the icon drew at 73% of the
	-- button height because ScaleType.Fit letterboxes a square image into the
	-- zone's SHORTER side. Grown ~35% and the icon zone made near-square so the
	-- width is no longer wasted.
	MenuButtonWidth = 124 / 1920,
	MenuButtonHeight = 132 / 1080,
	MenuGap = 14 / 1080, -- vertical gap between rows
	MenuGapX = 14 / 1920, -- horizontal gap between columns
}

-- ===== Eat the Cake game sections =====

-- Belly meter (HUD bottom-center). Nominal 420x64, Chip family: dark outer
-- pill + light groove inset 6 + warm fill. Fill zone x 6..414 (408).
-- Text zone y 16..48 (h 32), centered.
Theme.BellyBar = {
	AspectRatio = 420 / 64,
	OuterCorner = 1,
	OuterGradient = Theme.Toggle.OuterGradient,
	GroovePosition = Vector2.new(6 / 420, 6 / 64),
	GrooveSize = Vector2.new(408 / 420, 52 / 64),
	GrooveCorner = 1,
	GrooveGradient = Theme.Scrollbar.GrooveGradient,
	FillCorner = 1,
	-- Food-warm fill; hue heats up at FULL (glutton).
	FillGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(244, 148, 44)),
	}),
	FullFillGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 130, 92)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(238, 74, 52)),
	}),
	TextPosition = Vector2.new(60 / 420, 16 / 64),
	TextSize = Vector2.new(300 / 420, 32 / 64),
	TextGradient = Theme.PetCard.NameGradient,
	GluttonTextGradient = Theme.PetCard.SelectRingGradient,
}

-- Cake progress bar (HUD top-center). Nominal 560x56, BellyBar recipe:
-- groove inset 5 -> fill zone 550; text y 13..43 (h 30) centered.
Theme.CakeBar = {
	AspectRatio = 560 / 56,
	OuterCorner = 1,
	OuterGradient = Theme.Toggle.OuterGradient,
	RareOuterGradient = Theme.PetCard.SelectOuterGradient, -- golden/rainbow cakes
	GroovePosition = Vector2.new(5 / 560, 5 / 56),
	GrooveSize = Vector2.new(550 / 560, 46 / 56),
	GrooveCorner = 1,
	GrooveGradient = Theme.Scrollbar.GrooveGradient,
	FillCorner = 1,
	FillGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 210)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 110, 175)),
	}),
	BossFillGradient = Theme.Gradients.Close,
	TextPosition = Vector2.new(80 / 560, 13 / 56),
	TextSize = Vector2.new(400 / 560, 30 / 56),
	TextGradient = Theme.PetCard.NameGradient,
}

-- Combo badge (HUD, right of center). Text-only OutlinedText "x7" with a
-- pulse; gradient shifts blue -> gold with combo intensity.
Theme.ComboBadge = {
	AspectRatio = 160 / 90,
	TextHeight = 64 / 90,
	LowGradient = Theme.Button.TextGradient,
	HighGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 170)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 208, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 156, 40)),
	}),
	OutlineColor = Theme.Colors.TextOutline,
	PulseScale = 0.18, -- extra scale at pulse peak
	PulseTime = 0.18,
}

-- ⚠ Theme.BossPrize (the "FIGHTING FOR <squishy>" card) was REMOVED
-- 2026-08-07 together with the prize preview itself — what a cleared cake
-- pays out is a surprise again (features/cake-cycle.md). Its HUD slot
-- (AppHud.BossPrizePosition/Height) went with it.

-- Announce banner (HUD top-center, under the cake bar). One OutlinedText
-- line, gold, auto-hides (duration seconds).
Theme.AnnounceBanner = {
	AspectRatio = 800 / 70,
	TextGradient = Theme.PetCard.SelectRingGradient,
	OutlineColor = Theme.Colors.TextOutline,
	Duration = 3,
}

-- CELEBRATION BANNER (features/food-burst.md) — the three beats that are a
-- MOMENT rather than a notification: a layer cleared, a crumb monster down, and
-- the Cake Monster down. It rides above the HUD in the middle of the food
-- burst.
--
-- ⚠ **No plate.** It shipped for one commit as a gold card and was cut on
-- 2026-08-13 (user request): a slab that size parks a big opaque rectangle over
-- the cake for three seconds, and the kit's own §2c warns that a dark outer pill
-- under a raised lighter face reads PRESSABLE — which on a non-interactive
-- splash, for an audience of pre-readers, is an invitation to tap. What carries
-- it instead is SIZE plus `OutlinedText`'s own thick stroke and shadow copy,
-- the same contrast mechanism the plain AnnounceBanner already relies on, at
-- ~2.7x the height.
--
-- Nominal 900x260, pure type.
-- Vertical:   30 pad, cheer(140), 16 gap, sub(46), 28 pad = 260 ✓
-- Cheer horiz: 20 cheer(860) 20 = 900 ✓
-- Sub horiz:   70 sub(760)   70 = 900 ✓
Theme.CelebrationBanner = {
	AspectRatio = 900 / 260,
	CheerPosition = Vector2.new(20 / 900, 30 / 260),
	CheerSize = Vector2.new(860 / 900, 140 / 260),
	SubPosition = Vector2.new(70 / 900, 186 / 260),
	SubSize = Vector2.new(760 / 900, 46 / 260),

	-- The cheer is the kit's celebration gold — the same gradient the announce
	-- banner uses, so the two beats are visibly the same family at two sizes.
	-- The subtitle is plain white so the hierarchy is unambiguous: gold shouts,
	-- white informs.
	CheerGradient = Theme.PetCard.SelectRingGradient,
	CheerOutlineColor = Theme.Colors.TextOutline,
	SubGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(246, 250, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(222, 238, 255)),
	}),
	SubOutlineColor = Theme.Colors.TextOutline,

	-- MOTION. Slam in, breathe and sway, launch out. With the plate gone the
	-- animation IS the design, so the hold does two things at once rather than
	-- just pulsing. Timeline must fit inside `Duration`, which is what the
	-- caller holds the state for:
	--   0.30 enter + 2.60 hold + 0.34 exit = 3.24 < 3.50 ✓
	-- ⚠ Every property animated here is one React NEVER writes (the UIScale's
	-- Scale, the CanvasGroup's GroupTransparency and Rotation) — ADR-0006. The
	-- HUD re-renders ~14x/second, and a React-controlled property would be
	-- snapped back to its prop value mid-tween on the next bite.
	EnterScale = 0.35,
	EnterTilt = -7, -- degrees; unwinds to 0 as it slams in
	EnterTween = TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	BreathScale = 1.045,
	BreathTween = TweenInfo.new(0.70, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	-- A slow sway across the breathe, so the words feel alive rather than
	-- mechanically pulsing. Small on purpose: past ~2.5 degrees a long cheer
	-- starts to read as crooked rather than bouncy.
	WobbleDegrees = 1.6,
	WobbleTween = TweenInfo.new(0.95, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	-- ⚠ Raised 1.5 -> 2.6 on 2026-08-13: at the old timing the phrase was gone
	-- before it had been read, which for a randomised line is the whole point.
	HoldSeconds = 2.6,
	ExitScale = 1.30,
	ExitTween = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Duration = 3.5,
}

-- Upgrade row (upgrades list archetype). Nominal 418x82, ShopRow family.
-- Horizontal: 16 label(236) 10 buy(140) 16 = 418 ✓.
-- Vertical: name 10..40 (30), sub 44..66 (22); buy button 13..69 (56). 82 ✓.
Theme.UpgradeRow = {
	CellAspectRatio = 418 / 92, -- 10px vertical gap baked into the cell
	ContentHeightInCell = 82 / 92,
	AspectRatio = 418 / 82,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(6 / 418, 6 / 82),
	RimSize = Vector2.new(406 / 418, 66 / 82),
	RimCorner = 0.20,
	FacePosition = Vector2.new(9 / 418, 8 / 82),
	FaceSize = Vector2.new(400 / 418, 62 / 82),
	FaceCorner = 0.19,
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	LabelPosition = Vector2.new(16 / 418, 10 / 82),
	LabelSize = Vector2.new(236 / 418, 30 / 82),
	SubPosition = Vector2.new(16 / 418, 44 / 82),
	SubSize = Vector2.new(236 / 418, 22 / 82),
	BuyPosition = Vector2.new(262 / 418, 13 / 82),
	BuySize = Vector2.new(140 / 418, 56 / 82),
	LabelGradient = Theme.Button.TextGradient,
	SubGradient = Theme.PetCard.NameGradient,
}

-- Upgrades window geometry (portrait Panel family, settings content region).
-- 6 rows: 6*82 + 5*10 = 542 ≤ 563 rows zone ✓ (21 slack at the bottom).
Theme.UpgradesLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = Theme.Layout.PanelMaxViewportFraction,
	ListPosition = Theme.Layout.RowsPosition,
	ListSize = Theme.Layout.RowsSize,
	RowHeight = 82 / 563,
	RowGap = 10 / 563,
}

-- Gym fat-burn overlay (reference screen 1920x1080). RIGHT-THUMB layout for the
-- phone (the user's request): round green TAP button bottom-right at (0.82, 0.70)
-- d 240; a "fat left" bar 260x34 at (0.82, 0.52) and a % label above it. The bar
-- fill tracks the remaining-fat fraction (drains 1 → 0 as you burn).
Theme.GymOverlay = {
	ButtonHeight = 240 / 1080,
	ButtonAspect = 1,
	ButtonPosition = Vector2.new(0.82, 0.70),
	ButtonOuterCorner = 1, -- circle
	ButtonOutline = Theme.EquipGreen.OutlineColor,
	ButtonOuterGradient = Theme.EquipGreen.OuterGradient,
	ButtonRimGradient = Theme.EquipGreen.RimGradient,
	ButtonFaceGradient = Theme.EquipGreen.FaceGradient,
	ButtonTextGradient = Theme.EquipGreen.TextGradient,
	-- Same inset ratios as IconButton, on the button's own nominal 240 grid.
	RimPosition = Vector2.new(15 / 240, 15 / 240),
	RimSize = Vector2.new(210 / 240, 190 / 240),
	FacePosition = Vector2.new(23 / 240, 23 / 240),
	FaceSize = Vector2.new(194 / 240, 174 / 240),
	TextPosition = Vector2.new(33 / 240, 88 / 240),
	TextSize = Vector2.new(174 / 240, 64 / 240),
	BarHeight = 34 / 1080,
	BarAspect = 260 / 34,
	BarPosition = Vector2.new(0.82, 0.52),
	BarOuterGradient = Theme.Toggle.OuterGradient,
	BarGrooveGradient = Theme.Scrollbar.GrooveGradient,
	BarFillGradient = Theme.PetCard.SelectRingGradient,
	BarGrooveInset = Vector2.new(5 / 260, 5 / 34),
	CounterHeight = 34 / 1080,
	CounterPosition = Vector2.new(0.82, 0.455),
	CounterGradient = Theme.Button.TextGradient,
}

-- HUD hold-to-eat button (TOUCH only): a big round candy-pink button in the
-- bottom-right thumb zone. Press & HOLD to keep eating the cake in front of you;
-- a quick tap = one bite (features/cake-sim.md input). Same round-button recipe
-- as the gym TAP button, on the Epic (candy-magenta) palette so it reads as the
-- appetising "EAT" action, not the green gym one. Nominal 240 grid for the
-- Rim/Face/Text insets (identical ratios to GymOverlay's round button).
Theme.EatButton = {
	Height = 220 / 1080, -- viewport-height fraction of the round button
	Aspect = 1, -- circle
	Position = Vector2.new(0.86, 0.66), -- bottom-right, above the default jump button (tuned in Studio)
	OuterCorner = 1, -- circle
	Outline = Color3.fromRGB(46, 0, 38), -- dark magenta (Epic outline hue)
	OuterGradient = Theme.Rarity.Epic.Outer,
	RimGradient = Theme.Rarity.Epic.Rim,
	FaceGradient = Theme.Rarity.Epic.Face,
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 196, 240)),
	}),
	RimPosition = Vector2.new(15 / 240, 15 / 240),
	RimSize = Vector2.new(210 / 240, 190 / 240),
	FacePosition = Vector2.new(23 / 240, 23 / 240),
	FaceSize = Vector2.new(194 / 240, 174 / 240),
	TextPosition = Vector2.new(33 / 240, 88 / 240),
	TextSize = Vector2.new(174 / 240, 64 / 240),
}

-- Pet reveal overlay: full-screen dim + a PetCard blown up + odds footer
-- (Roblox policy: odds visible wherever rolls happen).
Theme.RevealOverlay = {
	DimColor = Color3.new(0, 0, 0),
	DimTransparency = 0.45,
	CardHeight = 0.5, -- viewport fraction
	CardAspect = 140 / 160,
	CardPosition = Vector2.new(0.5, 0.42),
	NamePosition = Vector2.new(0.5, 0.72),
	NameHeight = 0.065,
	SubPosition = Vector2.new(0.5, 0.79),
	SubHeight = 0.04,
	ContinuePosition = Vector2.new(0.5, 0.87),
	ContinueHeight = 0.038,
	OddsPosition = Vector2.new(0.5, 0.955),
	OddsHeight = 0.028,
	NameGradient = Theme.PetCard.SelectRingGradient,
	SubGradient = Theme.PetCard.NameGradient,
	ContinueGradient = Theme.Button.TextGradient,
	OddsGradient = Theme.PetCard.NameGradient,
	SpinDuration = 1.2, -- rarity flash phase before the card lands
	SpinStep = 0.12,
}

-- Rebirth window (confirm-dialog archetype, portrait Panel family).
-- Content y 128..691: stat rows y 150/214/278 (52 + 12 gap ✓), warning
-- 350..410, cost 420..470, button 500..584.
Theme.RebirthLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = 0.7,
	StatPositions = {
		Vector2.new(47 / 512, 150 / 727),
		Vector2.new(47 / 512, 214 / 727),
		Vector2.new(47 / 512, 278 / 727),
	},
	StatSize = Vector2.new(418 / 512, 52 / 727),
	WarnPosition = Vector2.new(47 / 512, 350 / 727),
	WarnSize = Vector2.new(418 / 512, 60 / 727),
	WarnGradient = Theme.Exit.XGradient,
	CostPosition = Vector2.new(47 / 512, 420 / 727),
	CostSize = Vector2.new(418 / 512, 50 / 727),
	CostGradient = Theme.Hud.EnergyTextGradient,
	ButtonPosition = Vector2.new(97 / 512, 500 / 727),
	ButtonSize = Vector2.new(318 / 512, 84 / 727),
}

-- Button styles for non-4.06 zones. Components.Button self-constrains to
-- its style's AspectRatio (FitWithinMaxSize): putting EquipGreen (418/103)
-- into a 140x56 zone renders a 140x34.5 button — every zone needs a style
-- whose aspect MATCHES the zone (the arithmetic in UpgradeRow/RebirthLayout
-- assumes full-height buttons).
local function buttonStyleWithAspect(base, aspect: number)
	local copy = table.clone(base)
	copy.AspectRatio = aspect
	return copy
end
Theme.BuyButton = buttonStyleWithAspect(Theme.EquipGreen, 140 / 56) -- UpgradeRow buy zone
Theme.BuyButtonNeutral = buttonStyleWithAspect(Theme.ActionButton, 140 / 56) -- "MAX"
Theme.ClaimButton = buttonStyleWithAspect(Theme.EquipGreen, 120 / 56) -- 120x56 in-row claim zone
Theme.ClaimButtonNeutral = buttonStyleWithAspect(Theme.ActionButton, 120 / 56)
Theme.RebirthButton = buttonStyleWithAspect(Theme.EquipGreen, 318 / 84) -- RebirthLayout button zone
Theme.CheckpointButton = buttonStyleWithAspect(Theme.EquipGreen, 300 / 64) -- HUD "return to gym" button (features/checkpoint.md)

-- App HUD additions for the game: second currency pill, belly bar,
-- cake progress bar, combo badge, announce banner. Two pills stack at
-- y 24..88 and 96..160; the menu (icon GRID) moves DOWN to clear them:
-- at 2 columns its tallest sane form is 4 rows: 4*132 + 3*14 = 570 ->
-- y 172..742 on the 1080 reference ✓ (it holds up to 8 buttons today: the SIX
-- meta panels plus Invite Friends and the community reward, each of the last two
-- shown only once its server push arrives). ⚠ 8 is the CEILING of that 4-row
-- budget, not headroom: a 9th entry wraps to a 5th row (5*132 + 4*14 = 716 ->
-- y 172..888) straight into the checkpoint button's band at y 897. The roster
-- itself is AppRoot's `menu` table — this comment only owns the arithmetic.
Theme.AppHud.SecondPillPosition = Vector2.new(22 / 1920, 96 / 1080)
Theme.AppHud.MenuPosition = Vector2.new(22 / 1920, 172 / 1080)
Theme.AppHud.BellyPosition = Vector2.new(0.5, 0.955) -- anchor (0.5, 1)
Theme.AppHud.BellyHeight = 56 / 1080
Theme.AppHud.CakeBarPosition = Vector2.new(0.5, 26 / 1080) -- anchor (0.5, 0)
Theme.AppHud.CakeBarHeight = 48 / 1080
Theme.AppHud.ComboPosition = Vector2.new(0.82, 0.40)
Theme.AppHud.ComboHeight = 84 / 1080
Theme.AppHud.AnnouncePosition = Vector2.new(0.5, 92 / 1080)
Theme.AppHud.AnnounceHeight = 52 / 1080
-- Celebration splash: centred, anchored at its MIDDLE (unlike the announce
-- banner, which hangs from its top edge) because it scales about that point.
-- ⚠ **`CelebrationHeight` is the lever that actually sizes it, not the width.**
-- The component's UIAspectRatioConstraint leaves `AspectType` at the default
-- `FitWithinMaxSize`, under which BOTH axes bound and the smaller one wins —
-- `DominantAxis` applies only to `ScaleWithParentSize` (same trap already
-- documented for Button above). At 16:9 the height binds: 0.2667x1080 = 288 px
-- tall x 996.9 wide, and width would only take over below 0.5192. The 0.52
-- here sits 1.5 px on the inert side ON PURPOSE — it is the ceiling that stops
-- the splash spanning an ultrawide, not the size. To make it bigger, raise
-- CelebrationHeight.
-- ⚠ The splash and the confetti DO overlap: sprites top out at ~0.31 down the
-- screen with their centres, and the cheer line spans ~0.13..0.27, so the
-- tallest ones cross it. That is why the burst lives in its own ScreenGui one
-- DisplayOrder BELOW UiRoot (FoodBurst.lua) — they pass BEHIND the words.
-- Raising `launchApex` or `sizeRange` costs nothing here; there is no spatial
-- margin to protect, only the layer split. It matters more now the plate is
-- gone: the words' only ground is OutlinedText's stroke, so keep that stroke
-- and never let a future variant drop it.
Theme.AppHud.CelebrationPosition = Vector2.new(0.5, 250 / 1080)
Theme.AppHud.CelebrationWidth = 0.52
Theme.AppHud.CelebrationHeight = 288 / 1080
--- Boss prize card: top-RIGHT, level with the calories pill on the left (same
--- 22px reference margin, same 26px top). Anchor (1, 0). The only free corner
--- during a boss fight — top-centre is the HP bar + announce banner, and
--- bottom-right is the touch EAT button.
-- Return-to-checkpoint button: bottom-center, just ABOVE the belly bar (belly
-- full -> burn is right here). Anchor (0.5, 1); height on the 1080 reference.
Theme.AppHud.CheckpointPosition = Vector2.new(0.5, 897 / 1080)
Theme.AppHud.CheckpointHeight = 52 / 1080
-- The button HIDES when the player is already on/at the checkpoint platform
-- (BodySubsClient proximity check): near = inside the plate's XZ footprint,
-- expanded by this margin. Kept < the loaf→plate `edgeGap` (0.5) so the near
-- zone's inner edge stays outside the loaf and the cake never counts as "on
-- the plate". Studs, world space.
Theme.AppHud.CheckpointHideMarginStuds = 0.4

-- HUD menu button icons (one per panel). Every button MUST be visually
-- distinct — a shared placeholder makes the meta menu unreadable in the first
-- 30 seconds, which is the single worst onboarding bug a simulator can ship.
-- Names resolve through the Icons registry (Icons.lua).
local menuIconPlaceholder = Icons.UiBox
Theme.AppHud.MenuIconPlaceholder = menuIconPlaceholder
Theme.AppHud.MenuIcons = {
	Squishies = Icons.SqRainbowDrop, -- the collection = the game's identity
	Pets = Icons.SqRainbowDrop, -- legacy panel name, same destination
	Shop = Icons.UiShop,
	DailyRewards = Icons.UiGift,
	Codes = Icons.UiCodes,
	Settings = Icons.UiSettings,
	Upgrades = Icons.UiStrength,
	Index = Icons.BadgeStats,
	-- Cake selection (features/cake-select.md). The generic cake glyph, NOT one
	-- of the two cake artworks: the button opens the chooser, so wearing either
	-- product's art would read as "play this one".
	Cakes = Icons.UiCake,
	-- The two social offers. Distinct on purpose: `UiFriend` is a person (send an
	-- invite), `UiHeart` is the LIKE the community reward asks for — the shop's
	-- Free row already wears UiFriend for the group row, so the heart is what
	-- keeps the two menu buttons from reading as the same thing.
	InviteFriends = Icons.UiFriend,
	GroupReward = Icons.UiHeart,
}

--- HUD stat-pill icons, as registry NAMES (resolve with Theme.Icon).
--- ONE source for both the HUD pills and the shop's balance row, so a currency
--- can never show two different glyphs on the same screen — which it did: the
--- GAME HUD still drew StatPill's legacy hand-vectored `bolt`/`coin` shapes from
--- before the icon registry existed, so the GEMS pill wore a COIN while the shop
--- showed the same balance next to a gem. Calories keep a bolt (they are burned
--- energy, and Hud.EnergyTextGradient is built around that reading), in the
--- badge-pack cut, which is heavier and far more readable at pill size.
Theme.AppHud.PillIcons = {
	Calories = "BadgeLightning",
	Gems = "UiGem",
}

-- ===== CAKE SELECTION (features/cake-select.md) =============================
--
-- Archetype: the "teleport / worlds" window — a set of LARGE cards, each an art
-- plate + a name + an unlock requirement, with unavailable cards dimmed under a
-- badge. A BROWSABLE GALLERY: grid + the kit's custom scrollbar, because the
-- catalogue grows (it already carries a "coming soon" slot whose whole job is to
-- say so).
--
-- ⚠ REBUILT 2026-08-11 from two fixed centred cells. That version put 2 cards in
-- a 904 box and left ~160px of dead margin around them, so the panel read as
-- mostly empty chrome and the CAKES — the only thing on it worth looking at —
-- were not the focus. Three columns filling 870 of the 904 fixes exactly that.
--
-- Panel 1000x600. Grid pane 904x396 at x48..952, y132..528 (bottom margin 72).
-- Horizontal: window 870 + gap 12 + bar 22 = 904 ✓
--             cells   3*282 + 2*12 = 870 ✓ exact (CellWidth shaved to 281.5 —
--             an exact-fit grid can wrap its last cell on float rounding)
-- Vertical:   cell 348 + gap 16 = 364 per row; window 396 shows one full row
--             plus 32px of the next, which is what advertises the scroll.
--             4 cakes -> 2 rows -> canvas 1.84x the window -> the bar appears.
--
-- ⚠ ScrollPane HIDES its track when the canvas provably fits (canvasHeightScale
-- <= 1.001) — deliberate: a full-height thumb that cannot move advertises
-- content that is not there. So with a single row of cakes there is no visible
-- scrollbar, BY DESIGN, and it appears by itself at the 4th cake.
--
-- ⚠ The aspect is IDENTICAL to Theme.RewardsLayout, so AppRoot reuses its
-- existing `wideScale` and no new scale state is needed. If this ever diverges,
-- a `cakeScale` must be added in BOTH coupled sites in AppRoot: the useState
-- initializer AND the `refit` body — miss the second and the panel stops
-- resizing with the window.
Theme.CakeSelectLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	ContentZIndex = 5,
	GridPosition = Vector2.new(48 / 1000, 132 / 600),
	GridSize = Vector2.new(904 / 1000, 396 / 600),
	ScrollWindowFraction = 870 / 904,
	ScrollBarWidth = 22 / 904,
	Columns = 3,
	CellWidth = 281.5 / 870,
	CellPaddingX = 12 / 870,
	CellHeightWithGap = 364 / 396,
	-- The card occupies the top of its cell; the remaining 16/364 IS the row gap
	-- (baked into the cell, per the kit's grid math — a UIGridLayout Y padding
	-- would fight the deterministic canvas height).
	CardHeightInCell = 348 / 364,
}

-- The cake card. Nominal 282x348 (0.810 — portrait, inside §2b's 0.78-0.85).
--
-- A CARD IS A FRAME, NOT A BUTTON (style-rules §2b): EVEN outline and internal
-- ZONES, never the button recipe's 2x+ bottom lip. Ratio-transferred from
-- Theme.ShopCard (282x338), minus the price shelf — a cake is chosen, not bought
-- — and with the art window GROWN into the space the shelf freed, because the
-- ART IS THE PRODUCT here and this audience may not read the name at all.
-- Icon 180² = 33% of the cell, against the shop card's 22% on the same width.
--
-- CHROME  Outer 0..282 x 0..348 r 0.14
--         Face  7..275 x 7..338 — outline 7 top/sides, 10 bottom (1.43x ✓, and
--         nowhere near the 2x+ that says "press me")
-- VERTICAL inside the face (331):
--   11 · 210 art · 10 · 38 title · 4 · 32 status · 26 = 331 ✓
--   art 18..228 · title 238..276 · status 280..312
-- HORIZONTAL: one content column x 18..264 (246) shared by art, title and
--   status — the shared left/right edge is most of why a card reads as tidy.
--   ✓ 18 + 246 + 18 = 282
-- ART WINDOW: ring 18..264 x 18..228, face inset an EVEN 5 all round (a window,
--   not a bevel). Icon 180² centred on both the card and the window.
Theme.CakeCard = {
	AspectRatio = 282 / 348,
	OuterCorner = 0.14,
	FacePosition = Vector2.new(7 / 282, 7 / 348),
	FaceSize = Vector2.new(268 / 282, 331 / 348),
	FaceCorner = 0.123,
	ArtPosition = Vector2.new(18 / 282, 18 / 348),
	ArtSize = Vector2.new(246 / 282, 210 / 348),
	ArtCorner = 0.13,
	ArtFacePosition = Vector2.new(23 / 282, 23 / 348),
	ArtFaceSize = Vector2.new(236 / 282, 200 / 348),
	ArtFaceCorner = 0.12,
	IconPosition = Vector2.new(51 / 282, 33 / 348),
	IconSize = Vector2.new(180 / 282, 180 / 348),
	TitlePosition = Vector2.new(18 / 282, 238 / 348),
	TitleSize = Vector2.new(246 / 282, 38 / 348),
	StatusPosition = Vector2.new(18 / 282, 280 / 348),
	StatusSize = Vector2.new(246 / 282, 32 / 348),
	BadgeCenter = Vector2.new(240 / 282, 40 / 348), -- art window's top-right
	BadgeSize = Vector2.new(48 / 282, 48 / 348),
	OutlineColor = Theme.ShopCardBody.OutlineColor,
	OuterGradient = Theme.ShopCardBody.OuterGradient,
	FaceGradient = Theme.ShopCardBody.FaceGradient,
	TitleGradient = Theme.ShopCardBody.TitleGradient,
	StatusGradient = Theme.ShopCardBody.PerkGradient,
	-- SELECTED = the kit's existing gold selection accent as a gradient swap on
	-- the Outer, exactly like PetCard and ShopCard's `premium`. Geometry never
	-- changes with state, and there is NO external ring (it would clip).
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	-- LOCKED. Grey is overloaded in this kit (locked / disabled / sold out /
	-- can't-afford) and has misfired twice before, so the rule here is narrow:
	-- ONLY the locked card goes grey. An unselected-but-UNLOCKED card keeps the
	-- normal navy body — quieting it as well would make "not currently chosen"
	-- and "you cannot have this" look identical.
	-- The art is FADED, not tinted: a full-strength rainbow on a grey card would
	-- become the loudest unselectable object on the panel. It must still read
	-- clearly, because seeing what you have not unlocked yet is the entire point
	-- of showing a locked card at all.
	LockedArtTransparency = 0.4,
	LockedOuterGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 62, 72)),
		ColorSequenceKeypoint.new(0.06, Color3.fromRGB(38, 43, 52)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(34, 39, 47)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(42, 48, 58)),
	}),
	LockedFaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(124, 130, 142)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(108, 114, 126)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(92, 98, 110)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(80, 86, 98)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(58, 63, 74)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(68, 74, 86)),
	}),
	-- The locked card's art WINDOW also leaves the accent family. Keeping a
	-- Legendary-gold window on a grey body would make the one thing the player
	-- cannot pick the brightest object on the panel — the window still reads as
	-- a window because it stays a value step LIGHTER than the body face.
	LockedArtFaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 183, 196)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(150, 157, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(128, 135, 148)),
	}),
	LockedTitleGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 231, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 197, 210)),
	}),
	LockedStatusGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 220, 230)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 188, 202)),
	}),
}

-- Matchmaking's child-first cake tile, nominal 264x292. It is the large card in
-- a 420px horizontal peek carousel: one full card plus half of the next is the
-- direct-manipulation cue. Free-standing 190px art leads; localized names and
-- requirements keep distinct lower zones. Face inset is 6px on every side:
-- even CARD outline, never a button lip.
local matchCakeCard = table.clone(Theme.CakeCard)
matchCakeCard.AspectRatio = 264 / 292
matchCakeCard.OuterCorner = 0.14
matchCakeCard.FacePosition = Vector2.new(6 / 264, 6 / 292)
matchCakeCard.FaceSize = Vector2.new(252 / 264, 280 / 292)
matchCakeCard.FaceCorner = 0.13
matchCakeCard.ShowArtPlate = false
matchCakeCard.ArtPosition = Vector2.new(32 / 264, 8 / 292)
matchCakeCard.ArtSize = Vector2.new(200 / 264, 190 / 292)
matchCakeCard.ArtCorner = 0.14
matchCakeCard.ArtFacePosition = Vector2.new(37 / 264, 13 / 292)
matchCakeCard.ArtFaceSize = Vector2.new(190 / 264, 180 / 292)
matchCakeCard.ArtFaceCorner = 0.13
matchCakeCard.IconPosition = Vector2.new(32 / 264, 8 / 292)
matchCakeCard.IconSize = Vector2.new(200 / 264, 190 / 292)
matchCakeCard.TitlePosition = Vector2.new(6 / 264, 198 / 292)
matchCakeCard.TitleSize = Vector2.new(252 / 264, 44 / 292)
matchCakeCard.StatusPosition = Vector2.new(12 / 264, 244 / 292)
matchCakeCard.StatusSize = Vector2.new(240 / 264, 38 / 292)
matchCakeCard.StatusTextWrapped = true
matchCakeCard.BadgeCenter = Vector2.new(232 / 264, 30 / 292)
matchCakeCard.BadgeSize = Vector2.new(44 / 264, 44 / 292)
-- Gold already says SELECTED everywhere in the kit. Keep the broad Face in the
-- kit's royal-navy card family: it replaces the unrelated flavour/rarity purple,
-- contrasts the pale panel at a squint, and leaves setup's small blue buttons
-- visually secondary.
matchCakeCard.SelectedFaceGradient = Theme.ShopCardBody.FaceGradient
matchCakeCard.DisabledOverlayColor = Color3.fromRGB(8, 20, 34)
matchCakeCard.DisabledOverlayTransparency = 0.38
Theme.MatchCakeCard = matchCakeCard

-- The compact cake strip for the matchmaking window's third band. Nominal
-- 442x60, ratio-transferred from Theme.MatchChoice (288x68) so it sits in the
-- same row family as the difficulty and party tiles: a BUTTON recipe here, not
-- the card recipe, because its siblings in that window are buttons.
-- Face 12..430 x 6..51 — top 6 / bottom 9 (1.5x), matching MatchChoice's weight.
-- Horizontal: thumb 22..62 · label 76..380 · lock badge centred at 404
Theme.CakeChoice = {
	AspectRatio = 442 / 60,
	OuterCorner = 0.22,
	RimPosition = Vector2.new(8 / 442, 4 / 60),
	RimSize = Vector2.new(426 / 442, 49 / 60),
	RimCorner = 0.20,
	FacePosition = Vector2.new(12 / 442, 6 / 60),
	FaceSize = Vector2.new(418 / 442, 45 / 60),
	FaceCorner = 0.19,
	ThumbPosition = Vector2.new(22 / 442, 10 / 60),
	ThumbSize = Vector2.new(40 / 442, 40 / 60),
	TextPosition = Vector2.new(76 / 442, 14 / 60),
	TextSize = Vector2.new(304 / 442, 32 / 60),
	BadgeCenter = Vector2.new(404 / 442, 30 / 60),
	BadgeSize = Vector2.new(34 / 442, 34 / 60),
	LayerColor = Color3.new(1, 1, 1),
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	TextGradient = Theme.Button.TextGradient,
	SelectedOuterGradient = Theme.PetCard.SelectOuterGradient,
	SelectedRimGradient = Theme.PetCard.SelectRingGradient,
	LockedArtTransparency = 0.4,
	DisabledTransparency = 0.32,
}

-- The lock mark. Same geometry as Theme.Badge, different hue on purpose: the
-- default badge is GREEN, which in this kit means owned / claimed / available —
-- precisely the opposite of what this one says.
Theme.CakeLockBadge = {
	AspectRatio = 1,
	RingColor = Color3.fromRGB(24, 28, 36),
	FillGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 158, 172)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(104, 112, 126)),
	}),
	FillPosition = Vector2.new(0.13, 0.13),
	FillSize = Vector2.new(0.74, 0.74),
	IconInset = 0.18,
}

-- ===== Upgrades HEX TREE (features/upgrades.md) =====
-- A full-screen honeycomb overlay. Each node is a flat-top hex SPRITE (white,
-- aspect 512/444) stacked Outer/Rim/Face and tinted per STATE by a vertical
-- UIGradient (the kit's bevel recipe, adapted to a shape UICorner can't make —
-- the one place chrome uses a provided asset id, like Hud.Icons). Locked = gray,
-- available = gold, owned = blue, category = purple, back = teal.
local hexGrayOuter = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 54, 64)),
	ColorSequenceKeypoint.new(0.06, Color3.fromRGB(34, 39, 47)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(33, 38, 46)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 34, 42)),
})
local hexGrayRim = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 130, 145)),
	ColorSequenceKeypoint.new(0.05, Color3.fromRGB(150, 160, 175)),
	ColorSequenceKeypoint.new(0.72, Color3.fromRGB(104, 114, 130)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(78, 86, 100)),
})
local hexGrayFace = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(126, 136, 150)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(104, 113, 128)),
	ColorSequenceKeypoint.new(0.93, Color3.fromRGB(90, 98, 112)),
	ColorSequenceKeypoint.new(0.96, Color3.fromRGB(60, 66, 78)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 77, 90)),
})
local hexGrayText = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 231, 240)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 184, 198)),
})
local hexGoldText = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 236)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 238, 178)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 214, 120)),
})
local hexPurpleText = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(246, 205, 244)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 170, 226)),
})
local hexTealText = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 255, 252)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(206, 246, 238)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 232, 220)),
})

Theme.HexTree = {
	HexImage = "rbxassetid://125037319877300",
	HexAspect = 512 / 444,
	-- Layer stack (centred; inner layers nudged UP so the bottom outline reads
	-- thicker — the kit's "weight" rule for a centred hex).
	RimCenter = Vector2.new(0.5, 0.47),
	RimScale = 0.9,
	FaceCenter = Vector2.new(0.5, 0.45),
	FaceScale = 0.78,
	-- Content zones (inside the hex's safe middle band). TWO cuts: the original
	-- text-only one, and an ICON-FIRST one used whenever the node carries a glyph
	-- (UpgradeTreeConfig.icons). Both are fractions of the sprite's own 512x444
	-- nominal grid.
	NamePosition = Vector2.new(0.15, 0.32),
	NameSize = Vector2.new(0.7, 0.19),
	StatusPosition = Vector2.new(0.17, 0.54),
	StatusSize = Vector2.new(0.66, 0.15),
	-- ── icon-first cut ──────────────────────────────────────────────────
	-- The Face layer is 0.78 of the sprite centred at y 0.45, so its box runs
	-- y 26.8..373.0 of 444. Vertical check-sum inside it:
	--   63 icon(144) 4 name(60) 4 status(52) = 327, leaving 36.2 of margin above
	--   (63 - 26.8) and 46 below (373 - 327) ✓
	-- (the slack sits at the BOTTOM on purpose: a flat-top hex narrows
	-- toward its bottom edge, so the last zone needs more clearance than the
	-- first. Widths follow the same profile — at the status band the hex is only
	-- ~250 wide, which is why that zone is the narrowest of the three.)
	-- The split is MEASURED, not chosen. Both text zones are HEIGHT-bound at node
	-- size (a 10-node sub-tree renders a hex ~70x60 px at 1x), so height moved out
	-- of them goes straight into the glyph — and the glyph is what a non-reader
	-- has. Two cuts were measured off the live instances before this one:
	--   icon 116 / name 68 -> 15px glyph vs 8px text = 1.9:1, a picture beside a
	--     label rather than an icon-first node;
	--   icon 150 / name 56 -> 2.7:1, but the COST on a gold `available` hex fell
	--     to ~6px, and the cost is the whole decision on exactly those nodes.
	-- 144/60 keeps the name at its original rendered size, costs the cost ~12%,
	-- and still reads 2.4:1.
	-- The icon zone is SQUARE in absolute pixels: 144/512 of the width and
	-- 144/444 of the height, on a frame constrained to 512/444, resolve to the
	-- same number of pixels — which matters because ScaleType.Fit draws at the
	-- SHORTER side and would otherwise waste the difference (ui-kit gotcha).
	IconPosition = Vector2.new(184 / 512, 63 / 444), -- centred: (512-144)/2 = 184
	IconSize = Vector2.new(144 / 512, 144 / 444),
	IconNamePosition = Vector2.new(0.15, 211 / 444),
	IconNameSize = Vector2.new(0.7, 60 / 444),
	IconStatusPosition = Vector2.new(0.22, 275 / 444),
	IconStatusSize = Vector2.new(0.56, 52 / 444),
	-- Connector bar between a node and its parent (geometry in UpgradeTreeConfig).
	ConnectorOwnedGradient = Theme.Button.RimGradient,
	ConnectorLockedGradient = hexGrayRim,
	-- Full-screen dim behind the honeycomb.
	ScrimColor = Color3.fromRGB(8, 12, 22),
	ScrimTransparency = 0.14,
	-- Per-state hex visuals. `IconTransparency` fades the node's GLYPH: a locked
	-- tier is gray everywhere else, and a full-strength colour glyph on a gray hex
	-- reads as the brightest thing in the tree — i.e. it advertises exactly the
	-- nodes you cannot buy. Fading rather than tinting keeps the SHAPE readable,
	-- which is the only thing telling a non-reader which stat the wedge belongs
	-- to (UpgradeTreeConfig.icons).
	States = {
		locked = {
			Outer = hexGrayOuter,
			Rim = hexGrayRim,
			Face = hexGrayFace,
			Outline = Color3.fromRGB(24, 28, 34),
			Text = hexGrayText,
			IconTransparency = 0.45,
		},
		available = {
			Outer = Theme.Rarity.Legendary.Outer,
			Rim = Theme.Rarity.Legendary.Rim,
			Face = Theme.Rarity.Legendary.Face,
			Outline = Color3.fromRGB(74, 48, 0),
			Text = hexGoldText,
		},
		owned = {
			Outer = Theme.Button.OuterGradient,
			Rim = Theme.Button.RimGradient,
			Face = Theme.Button.FaceGradient,
			Outline = Theme.Button.OutlineColor,
			Text = Theme.Button.TextGradient,
		},
		category = {
			Outer = Theme.Rarity.Epic.Outer,
			Rim = Theme.Rarity.Epic.Rim,
			Face = Theme.Rarity.Epic.Face,
			Outline = Color3.fromRGB(54, 0, 45),
			Text = hexPurpleText,
		},
		back = {
			Outer = Theme.Rarity.Uncommon.Outer,
			Rim = Theme.Rarity.Uncommon.Rim,
			Face = Theme.Rarity.Uncommon.Face,
			Outline = Color3.fromRGB(0, 52, 48),
			Text = hexTealText,
		},
	},
	-- Tooltip card (nominal 260x150), Chip-family dark surface.
	Tooltip = {
		AspectRatio = 260 / 150,
		OuterGradient = Theme.Toggle.OuterGradient,
		OuterCorner = 0.12,
		FaceGradient = Theme.Chip.FaceGradient,
		FaceInset = Vector2.new(5 / 260, 5 / 150),
		FaceCorner = 0.1,
		TitlePosition = Vector2.new(16 / 260, 12 / 150),
		TitleSize = Vector2.new(228 / 260, 30 / 150),
		DescPosition = Vector2.new(16 / 260, 50 / 150),
		DescSize = Vector2.new(228 / 260, 58 / 150),
		StatusPosition = Vector2.new(16 / 260, 112 / 150),
		StatusSize = Vector2.new(228 / 260, 26 / 150),
		TitleGradient = Theme.Button.TextGradient,
		DescColor = Color3.fromRGB(206, 232, 250),
	},
	-- Calories chip + Close button placement on the overlay (1920x1080 ref).
	CurrencyPosition = Vector2.new(30 / 1920, 30 / 1080),
	CurrencyHeight = 64 / 1080,
	-- Honeycomb canvas: upper-centre (square, fraction of the shorter axis) so
	-- the bottom detail panel + top bar stay clear.
	CanvasCenter = Vector2.new(0.5, 0.42),
	CanvasMaxViewportFraction = 0.64,
	-- Close = red X top-right (anchor 0.5,0.5).
	CloseCenter = Vector2.new(0.955, 74 / 1080),
	CloseHeight = 78 / 1080,
	-- Zoom controls: bottom-right vertical stack of +/-/reset (anchor 0.5,0.5).
	ZoomButtonHeight = 66 / 1080,
	ZoomInCenter = Vector2.new(0.955, 0.63),
	ZoomOutCenter = Vector2.new(0.955, 0.725),
	ResetCenter = Vector2.new(0.955, 0.82),
	MinZoom = 0.6,
	MaxZoom = 3.2,
	ZoomStep = 1.25, -- per +/- press or wheel notch
	-- Canvas holds the tree at rest; zoom/pan is applied on a WORLD frame inside.
	-- Detail card is positioned NEXT TO the tapped hex (screen space).
	DetailWidth = 0.32, -- fraction of the shorter viewport axis
	Detail = {
		AspectRatio = 300 / 200,
		OuterGradient = Theme.Toggle.OuterGradient,
		OuterCorner = 0.09,
		FaceGradient = Theme.Chip.FaceGradient,
		FaceInset = Vector2.new(6 / 300, 6 / 200),
		FaceCorner = 0.075,
		TitlePosition = Vector2.new(18 / 300, 14 / 200),
		TitleSize = Vector2.new(264 / 300, 40 / 200),
		DescPosition = Vector2.new(18 / 300, 60 / 200),
		DescSize = Vector2.new(264 / 300, 66 / 200),
		StatusPosition = Vector2.new(18 / 300, 140 / 200),
		StatusSize = Vector2.new(264 / 300, 42 / 200),
		BuyPosition = Vector2.new(66 / 300, 134 / 200),
		BuySize = Vector2.new(168 / 300, 54 / 200),
		TitleGradient = Theme.Button.TextGradient,
		DescColor = Color3.fromRGB(210, 234, 252),
		StatusGradient = Theme.PetCard.NameGradient,
	},
	-- Red circular "!" notifier badge. `Center` is its centre as a fraction of the
	-- NODE box (0.5, 0.5 = the hex centre); `Size` is its diameter as a fraction
	-- of the node WIDTH, on both axes, so it stays round inside a square World.
	-- ⚠ These were dead until 2026-08-04 — HexTreeOverlay carried its own
	-- 0.28/0.30/0.46 literals (iron rule 2), which is why the two disagreed.
	-- Pushed OUT to 0.83 when the nodes gained glyphs: the badge used to hang over
	-- empty face, and it now overlaps the icon zone's right edge instead. At 0.83
	-- the overlap is ~11% of the glyph (was ~33%), and hanging further outside the
	-- hex costs nothing — the badge is drawn in its own TOP layer precisely so
	-- packed neighbours cannot cover it.
	Notifier = {
		Center = Vector2.new(0.83, 0.20),
		Size = 0.44,
		OuterGradient = Theme.Exit.OuterGradient,
		FaceGradient = Theme.Exit.FaceGradient,
		MarkGradient = Theme.Exit.XGradient,
		Outline = Theme.Exit.XOutline,
	},
	-- Attention PULSE for a hex the player can act on RIGHT NOW: a tier whose
	-- next buy is AFFORDABLE, and a category node holding one (its "!" badge
	-- breathes on the same clock, since the badge is drawn in the overlay's own
	-- top layer rather than as a child of the node).
	-- Gentler than Theme.Feel.Pulse (1.10) on purpose: `UpgradeTreeConfig.hex
	-- .nodeFill = 1` packs the comb edge-to-edge, so a node grows straight INTO
	-- its neighbours — at 1.10 the overlap reads as a z-order bug, at 1.06 it
	-- reads as a breath.
	-- ⚠ Gold (`available`) is NOT the trigger. Gold means the tier is UNLOCKED —
	-- priced, but not necessarily payable (features/upgrades.md) — while a pulse
	-- PROMISES a purchase, so it rides the same affordability predicate the Buy
	-- button and the world "N Available" sign use.
	Pulse = {
		Scale = 1.06,
		Tween = TweenInfo.new(0.72, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		StopTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
}
Theme.HexTree.BuyButton = buttonStyleWithAspect(Theme.EquipGreen, 168 / 54)
Theme.HexTree.ZoomButton = buttonStyleWithAspect(Theme.ActionButton, 1)

-- ===== ONBOARDING / TUTORIAL (features/tutorial.md) =========================

-- ── 1. Story slides: the 4-panel COMIC board ────────────────────────────────
-- Archetype (not in window-archetypes.md — reasoned from the genre): a Roblox
-- sim's first-session intro is a full-bleed scrim + a centred content block +
-- ONE bottom-centre CTA. The content here is four sequential comic panels read
-- TL -> TR -> BL -> BR.
--
-- A panel is a CARD, not a button (§2b): EVEN outline + internal zones. Applying
-- the button bevel here would make four comic frames read as four huge buttons —
-- the exact failure the shop shipped in July.
--
-- PANEL nominal 440x336 (source art is 716x535 = 1.3383; the art window is cut
-- to match so nothing letterboxes):
--   Outer 0..440 x 0..336, r 0.10
--   Rim   inset 8   -> 424x320   (even ring, the "window frame" read)
--   Art   inset 14  -> 412x308   412/308 = 1.3377 ≈ 1.3383 ✓ (0.04% drift)
--   Order badge d44 centred (42, 42) — icon-first: this audience may not read
--   the title, but 1-2-3-4 is universal.
--
-- BOARD 900x958:
--   width   440 + 20 gap + 440 = 900 ✓
--   height  64 title + 18 + 692 board + 64 + 120 skip = 958 ✓
--   board   336 + 20 gap + 336 = 692 ✓
--   skip    centred: (900 - 420) / 2 = 240 -> x 240..660 ✓
-- The 22 -> 64 gap under the board and the 76 -> 120 CTA height are MEASURED
-- changes, not taste. The board is a big BRIGHT block and the button's face
-- sits in the same value band (L* 53 vs 59), so in GRAYSCALE at a squint the
-- two merged into one mass however green the button was -- iron rule 5: hue is
-- not hierarchy. Only a gap and a core wider than the blur kernel separate
-- them, which is what these two numbers buy.
Theme.TutorialSlides = {
	-- Own dim, like HexTreeOverlay/PetRevealOverlay: this overlay does NOT ride
	-- AppRoot's panel Scrim (it is not an `openPanel`, deliberately — see the
	-- AppRoot note next to `eatButtonVisible`).
	-- 0.35 -> 0.24 (tonal audit): at 0.35 the lit factory floor behind the board
	-- still held enough value that the comic panels measured +4 dL* under blur —
	-- the art was competing with the room instead of sitting on it.
	DimColor = Color3.new(0, 0, 0),
	DimTransparency = 0.24,
	BoardAspect = 900 / 958,
	BoardMaxViewportFraction = 0.90,
	TitlePosition = Vector2.new(0, 0),
	TitleSize = Vector2.new(900 / 900, 64 / 958),
	TitleGradient = Theme.Header.TitleGradient,
	-- Panel cells, top-left corners on the 900x958 board grid.
	PanelSize = Vector2.new(440 / 900, 336 / 958),
	PanelPositions = {
		Vector2.new(0 / 900, 82 / 958), -- 1 top-left
		Vector2.new(460 / 900, 82 / 958), -- 2 top-right
		Vector2.new(0 / 900, 438 / 958), -- 3 bottom-left
		Vector2.new(460 / 900, 438 / 958), -- 4 bottom-right
	},
	-- Grown 300x76 -> 420x120 and moved onto the GREEN accent (below). As a
	-- 300x76 blue ActionButton it measured attention rank #9 and vanished
	-- under blur, which is fatal for the ONLY control on the screen; the width
	-- is what buys squint survival (the squint-test levers are colour, tone
	-- and SIZE — never an outline, which blurs away first).
	SkipPosition = Vector2.new(240 / 900, 838 / 958),
	SkipSize = Vector2.new(420 / 900, 120 / 958),
}

-- The comic panel itself, on its OWN nominal 440x336 grid.
Theme.TutorialPanel = {
	AspectRatio = 440 / 336,
	OuterCorner = 0.10,
	OutlineColor = Theme.ShopCardBody.OutlineColor,
	OuterGradient = Theme.ShopCardBody.OuterGradient,
	RimPosition = Vector2.new(8 / 440, 8 / 336),
	RimSize = Vector2.new(424 / 440, 320 / 336),
	RimCorner = 0.09,
	-- Light "window frame" ring, same family as the shop card's art ring.
	RimGradient = Theme.Panel.FillGradient,
	ArtPosition = Vector2.new(14 / 440, 14 / 336),
	ArtSize = Vector2.new(412 / 440, 308 / 336),
	ArtCorner = 0.085,
	-- Order badge. It began as the kit's GOLD selection accent and measured as
	-- the screen's #1 attention magnet — a level-3 reading aid out-shouting the
	-- comic it numbers (tonal audit: `attention-sink`). Quieted on the two
	-- levers that matter: AREA (56 -> 44) and VALUE (gold fill -> the panel's
	-- own dark navy, cream numeral). It is decor, not a control, so flattening
	-- it costs no affordance (style-rules §2c).
	BadgeCenter = Vector2.new(42 / 440, 42 / 336),
	BadgeSize = Vector2.new(44 / 440, 44 / 336),
	BadgeRingColor = Theme.ShopCardBody.OutlineColor,
	BadgeFillGradient = Theme.ShopCardBody.OuterGradient,
	BadgeTextInset = 0.20,
	BadgeTextGradient = Theme.ShopCardBody.TitleGradient,
	BadgeTextOutline = Theme.ShopCardBody.OutlineColor,
}

-- ── 2. Instruction popup ("eat the cake") ───────────────────────────────────
-- Archetype: the small centred dialog row of window-archetypes, minus the
-- confirm/cancel PAIR — a hint has one way out.
--
-- ⚠ It brings NO full-screen click catcher. PC eating is a global
-- `UserInputService.InputBegan` guarded by `gameProcessed` (CakeSubsClient), so
-- a catcher over this popup would swallow the very left-click it is teaching.
-- Only the CTA is a TextButton; everything else is inert.
--
-- NOMINAL 620x260 (card recipe, even outline 10):
--   HORIZONTAL  26 · 150 glyph · 24 · 394 text column · 26 = 620 ✓
--   VERTICAL    44 · 52 title · 8 · 64 body · 14 · 56 cta · 22 = 260 ✓
--               title 44..96 · body 104..168 · cta 182..238
--   glyph plate d150 at y 55..205 (centre 130 = 260/2 ✓)
Theme.TutorialHint = {
	Aspect = 620 / 260,
	MaxViewportFraction = 0.52,
	-- Vertically centred-ish, and the Y is load-bearing in BOTH directions.
	-- ABOVE: the card's top edge is a constant viewport fraction, but the HUD
	-- CakeBar's bottom edge is inside the topbar-INSET Hud frame and so slides
	-- DOWN as the window gets shorter. At 0.30 the two cleared by 7px at the
	-- 1920x1080 reference and COLLIDED on every smaller window (at 800x450 the
	-- card covered ~90% of the bar).
	-- ⚠ RE-SOLVED 2026-08-09 for the safe-area inset (Theme.SafeArea): the Hud
	-- layer now starts at max(GetGuiInset().Y, TopbarInset.Max.Y) + TopPadPx
	-- instead of GetGuiInset().Y, which pushed the CakeBar ~30px further down
	-- while this card — a FULL-BLEED child — did not move, and 0.40 went from
	-- clearing by 4px to covering the bar outright on a phone. The clearance is
	--   P·H  -  cardH/2  ≥  topInset + 0.024·(H−topInset) + barH
	-- worst at the SHORTEST viewport (the card is height-capped at 0.52·H, the
	-- bar is a near-fixed pixel strip). Solved at 896x414 with topInset 68:
	-- bar bottom 94.3, card half-height 97.7 → P ≥ 0.483. 0.50 keeps ~15px.
	-- BELOW: the card's bottom must stay off the bottom-centre belly bar / TO
	-- CHECKPOINT button and off the bottom-right touch EAT button, which on
	-- phones is the control this very card is pointing at. At 0.50 the card
	-- bottom is 304.7 of 414 on a phone (belly bar starts 377.9) and 749 of 1080
	-- at the reference — clear at both ends.
	Position = Vector2.new(0.5, 0.50), -- anchor (0.5, 0.5)
	OuterCorner = 0.14,
	OutlineColor = Theme.ShopCardBody.OutlineColor,
	OuterGradient = Theme.ShopCardBody.OuterGradient,
	FacePosition = Vector2.new(10 / 620, 10 / 260),
	FaceSize = Vector2.new(600 / 620, 240 / 260),
	FaceCorner = 0.12,
	FaceGradient = Theme.ShopCardBody.FaceGradient,
	GlyphPosition = Vector2.new(26 / 620, 55 / 260),
	GlyphSize = Vector2.new(150 / 620, 150 / 260),
	TitlePosition = Vector2.new(200 / 620, 44 / 260),
	TitleSize = Vector2.new(394 / 620, 52 / 260),
	TitleGradient = Theme.ShopCardBody.TitleGradient,
	BodyPosition = Vector2.new(200 / 620, 104 / 260),
	BodySize = Vector2.new(394 / 620, 64 / 260),
	BodyGradient = Theme.ShopCardBody.PerkGradient,
	ButtonPosition = Vector2.new(394 / 620, 182 / 260),
	ButtonSize = Vector2.new(200 / 620, 56 / 260),
}

-- Input glyph (the popup's hero). Two modes, both drawn from kit primitives —
-- there is no mouse/finger art in the registry, and the kit's tradition is to
-- vector small glyphs (the HUD bolt, the badge check, the close X).
--   "mouse" — rounded body, TOP-LEFT quadrant lit = the left button, plus a
--             wheel pill. Fractions of the glyph's own square box.
--   "tap"   — a MINIATURE of the real EAT button (same Epic-pink recipe) inside
--             a white ripple ring: "press THAT button", not "press something".
Theme.TutorialGlyph = {
	MouseOutline = Theme.Colors.Outline,
	MouseBodyPosition = Vector2.new(0.235, 0.10),
	MouseBodySize = Vector2.new(0.53, 0.80),
	MouseBodyCorner = 0.42,
	MouseBodyGradient = Theme.Panel.FillGradient,
	-- BOTH top buttons are drawn, and only the left one is lit. A single lit
	-- rectangle floating on a white blob reads as "a blob with a sticker";
	-- the pair plus the seam between them is what makes it read as a MOUSE,
	-- and therefore what makes "the LEFT one" mean anything.
	MouseButtonPosition = Vector2.new(0.255, 0.125),
	MouseButtonSize = Vector2.new(0.235, 0.315),
	MouseButtonCorner = 0.30,
	MouseButtonGradient = Theme.Rarity.Epic.Face,
	MouseRightPosition = Vector2.new(0.510, 0.125),
	MouseRightSize = Vector2.new(0.235, 0.315),
	MouseRightGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 230, 244)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(186, 208, 228)),
	}),
	MouseWheelPosition = Vector2.new(0.484, 0.155),
	MouseWheelSize = Vector2.new(0.032, 0.155),
	MouseWheelCorner = 1,
	MouseWheelColor = Color3.fromRGB(52, 74, 104),
	-- Touch: ripple ring + the EAT button's own face.
	TapRingPosition = Vector2.new(0.06, 0.06),
	TapRingSize = Vector2.new(0.88, 0.88),
	TapRingThickness = 0.055, -- fraction of the box, UIStroke ScaledSize
	TapRingColor = Color3.fromRGB(255, 236, 250),
	TapButtonPosition = Vector2.new(0.20, 0.20),
	TapButtonSize = Vector2.new(0.60, 0.60),
	TapOutline = Theme.EatButton.Outline,
	TapOuterGradient = Theme.EatButton.OuterGradient,
	TapFaceInset = Vector2.new(0.10, 0.10),
	TapFaceGradient = Theme.EatButton.FaceGradient,
	-- The real button's own word, so the glyph is a MINIATURE of the control
	-- rather than a generic pink dot. Caller passes the same locale string the
	-- HUD button uses; without it the disc simply renders wordless.
	TapLabelPosition = Vector2.new(0.28, 0.40),
	TapLabelSize = Vector2.new(0.44, 0.20),
	TapLabelGradient = Theme.EatButton.TextGradient,
	TapLabelOutline = Theme.EatButton.Outline,
}

-- ── 3. Hint arrow (world-tracking objective pointer) ────────────────────────
-- On-screen target: bobs ABOVE it pointing down. Off-screen: pins to the
-- viewport edge and rotates toward it — the standard objective marker.
-- Sizes are viewport-height fractions (the GymOverlay convention).
Theme.TutorialArrow = {
	ArrowHeight = 96 / 1080,
	ArrowAspect = 1,
	ArrowIcon = "UiArrowRight", -- rotated; 0deg points +X
	ArrowColor = Color3.fromRGB(255, 236, 250),
	-- Screen-edge keep-out so a pinned arrow never sits half off the viewport.
	EdgePadding = 0.075,
	-- Vertical offset above the target while it is on screen (viewport fraction)
	-- and the idle bob applied on top of it.
	OnScreenLift = 0.085,
	BobAmplitude = 0.014,
	BobPeriod = 1.15,
	LabelOffset = 0.055, -- below the arrow, viewport fraction
	LabelHeight = 34 / 1080,
	LabelAspect = 320 / 34,
	LabelOuterGradient = Theme.Chip.OuterGradient,
	LabelFaceGradient = Theme.Chip.FaceGradient,
	LabelFaceInset = Vector2.new(4 / 320, 4 / 34),
	LabelTextGradient = Theme.Button.TextGradient,
}

-- Button styles for the tutorial's two CTA zones (a style's AspectRatio must
-- MATCH its zone or Components.Button letterboxes itself inside it).
-- GREEN, not the blue ActionButton: on a 76%-opaque black scrim the blue face
-- sat in the same value band as the dimmed world and dissolved at a squint —
-- and this button is the screen's only exit.
Theme.TutorialSkipButton = buttonStyleWithAspect(Theme.EquipGreen, 420 / 120)
Theme.TutorialHintButton = buttonStyleWithAspect(Theme.EquipGreen, 200 / 56)

-- Attention PULSE for an existing button (Components.Button `pulse` prop).
-- Reverses forever, so the tween is the only writer of that UIScale's Scale
-- (ADR-0006) and a `pulse = false` render simply cancels it back to 1.
Theme.Feel.Pulse = {
	Scale = 1.10,
	Tween = TweenInfo.new(0.62, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	StopTween = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}
table.freeze(Theme.Feel.Pulse)

-- Staggered ENTRANCE for a fixed set of sibling cards (the onboarding comic).
-- A child is HIDDEN until its turn, then pops from ClosedScale — otherwise every
-- piece is already on screen (0.68 is fully opaque) and the board only *grows*
-- in sequence instead of arriving one piece at a time. Each child owns its own
-- effect, tween and cleanup, so a stagger cannot leave one piece behind; the
-- tween is the ONLY writer of those UIScales, and React writes `Visible` exactly
-- once with a constant (ADR-0006 — no `Scale` prop is ever passed).
--
-- ⚠ ClosedScale is bounded by the board's own gaps, not by taste. Back-out
-- overshoots to ~1 + 0.10 * travel, and the growth lands HALF on each side:
-- a comic panel is 440 of 900 nominal px with a 20 px gap to its neighbour, so
-- two adjacent panels at peak may each grow at most 10 px.
--   travel 1 - 0.68 = 0.32  ->  peak ~1.032  ->  440 * 0.032 / 2 = 7.0 px  ✓
-- Lowering ClosedScale past ~0.60 makes neighbours touch at the peak.
-- ⚠ StepSeconds > the tween's duration, ON PURPOSE (retuned 2026-08-09 after the
-- first cut read as "they all appear at once"): at a 0.12 s step against a
-- 0.36 s pop, four panels were mid-flight simultaneously and the eye saw one
-- event, not four. A step LONGER than the pop means each piece has landed
-- before the next one starts, which is what "one after another" has to mean.
-- It also removes the overshoot coupling entirely — two neighbours can no
-- longer peak at the same time.
Theme.Feel.SlideIn = {
	ClosedScale = 0.68,
	Tween = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	-- Scrims fade on their OWN tween: Back's overshoot is the point on a scale
	-- and a defect on a transparency, where it drives the value past the target
	-- (a 0.24 dim dips to ~0.16, and anything under ~0.09 would clip at 0 and
	-- flash fully opaque).
	FadeTween = TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- A beat after the loading screen clears before anything moves, so the first
	-- pop is not already underway on the player's first rendered frame.
	LeadDelay = 2.0, -- the board title goes first
	StepSeconds = 0.85, -- gap between consecutive children (> Tween's 0.32)
	TailDelay = 0.30, -- extra beat before the trailing CTA
	-- Resulting choreography, measured from the moment the session is ON SCREEN
	-- (see the game.Loaded gate in TutorialSlides): title 0.25, panels at
	-- 0.80 / 1.35 / 1.90 / 2.45, CTA at 3.20, everything landed by 3.52 s.
	-- 0.12 then 0.38 were both still read as simultaneous by the author of the
	-- request: the gap has to be long enough to be COUNTED, not merely measured.
}
table.freeze(Theme.Feel.SlideIn)

table.freeze(Theme.Rarity.Uncommon)
table.freeze(Theme.Rarity.Secret)
table.freeze(Theme.BuyButton)
table.freeze(Theme.BuyButtonNeutral)
table.freeze(Theme.ClaimButton)
table.freeze(Theme.ClaimButtonNeutral)
table.freeze(Theme.RebirthButton)
table.freeze(Theme.CheckpointButton)
table.freeze(Theme.BellyBar)
table.freeze(Theme.CakeBar)
table.freeze(Theme.ComboBadge)
table.freeze(Theme.AnnounceBanner)
table.freeze(Theme.CelebrationBanner)
table.freeze(Theme.UpgradeRow)
table.freeze(Theme.UpgradesLayout)
table.freeze(Theme.GymOverlay)
table.freeze(Theme.EatButton)
table.freeze(Theme.RevealOverlay)
table.freeze(Theme.RebirthLayout.StatPositions)
table.freeze(Theme.RebirthLayout)
table.freeze(Theme.SocialLayout)
table.freeze(Theme.MatchChoice)
table.freeze(Theme.MatchModeCard)
for _, accent in pairs(Theme.MatchModeAccents) do
	table.freeze(accent)
end
table.freeze(Theme.MatchModeAccents)
table.freeze(Theme.MatchDifficultyChoice)
table.freeze(Theme.MatchPartyChoice)
table.freeze(Theme.MatchCakeChoice)
table.freeze(Theme.MatchmakingCloseButton)
table.freeze(Theme.MatchmakingHeader)
table.freeze(Theme.MatchmakingStartButton)
table.freeze(Theme.MatchmakingLayout)
table.freeze(Theme.HexTree.States.locked)
table.freeze(Theme.HexTree.States.available)
table.freeze(Theme.HexTree.States.owned)
table.freeze(Theme.HexTree.States.category)
table.freeze(Theme.HexTree.States.back)
table.freeze(Theme.HexTree.States)
table.freeze(Theme.HexTree.Tooltip)
table.freeze(Theme.HexTree.Detail)
table.freeze(Theme.HexTree.Notifier)
table.freeze(Theme.HexTree.Pulse)
table.freeze(Theme.HexTree.BuyButton)
table.freeze(Theme.HexTree.ZoomButton)
table.freeze(Theme.HexTree)
table.freeze(Theme.TutorialSlides.PanelPositions)
table.freeze(Theme.TutorialSlides)
table.freeze(Theme.TutorialPanel)
table.freeze(Theme.TutorialHint)
table.freeze(Theme.TutorialGlyph)
table.freeze(Theme.TutorialArrow)
table.freeze(Theme.TutorialSkipButton)
table.freeze(Theme.TutorialHintButton)

table.freeze(Theme.Feel)
table.freeze(Theme.Colors)
table.freeze(Theme.Gradients)
table.freeze(Theme.Toggle)
table.freeze(Theme.Panel)
table.freeze(Theme.PanelScrim)
table.freeze(Theme.Header)
table.freeze(Theme.Button)
table.freeze(Theme.Exit)
table.freeze(Theme.Layout)
table.freeze(Theme.PanelWide)
table.freeze(Theme.HeaderWide)
table.freeze(Theme.IconButton)
table.freeze(Theme.ActionButton)
table.freeze(Theme.Scrollbar)
table.freeze(Theme.HorizontalScrollbar)
table.freeze(Theme.Rarity.Order)
table.freeze(Theme.Rarity.Common)
table.freeze(Theme.Rarity.Rare)
table.freeze(Theme.Rarity.Epic)
table.freeze(Theme.Rarity.Legendary)
table.freeze(Theme.Rarity)
table.freeze(Theme.PetCard)
table.freeze(Theme.Chip)
table.freeze(Theme.PetsLayout)
table.freeze(Theme.Inspector.StatPositions)
table.freeze(Theme.Inspector)
table.freeze(Theme.StatRow)
table.freeze(Theme.EquipGreen)
table.freeze(Theme.UnequipRed)
table.freeze(Theme.PetsInspectLayout)
table.freeze(Theme.Hud.PillYs)
table.freeze(Theme.Hud.ButtonYs)
table.freeze(Theme.Hud.Icons)
table.freeze(Theme.Hud)
table.freeze(Theme.Badge)
table.freeze(Theme.DayCard)
table.freeze(Theme.RewardsLayout)
table.freeze(Theme.ShopRow)
table.freeze(Theme.ShopSectionHeader)
table.freeze(Theme.ShopTile)
table.freeze(Theme.ShopPack)
table.freeze(Theme.ShopBanner)
table.freeze(Theme.ShopPrice)
table.freeze(Theme.ShopPriceWide)
table.freeze(Theme.ShopPriceStates.buy)
table.freeze(Theme.ShopPriceStates.owned)
table.freeze(Theme.ShopPriceStates.unavailable)
table.freeze(Theme.ShopPriceStates.unaffordable)
table.freeze(Theme.ShopPriceStates)
table.freeze(Theme.ShopRibbon.Variants)
table.freeze(Theme.ShopRibbon)
table.freeze(Theme.ShopLayout)
for _, accent in pairs(Theme.ShopCardAccents) do
	table.freeze(accent)
end
table.freeze(Theme.ShopCardAccents)
table.freeze(Theme.ShopCard)
table.freeze(Theme.ShopCardSmall)
table.freeze(Theme.ShopPriceCard)
table.freeze(Theme.ShopPriceHero)
table.freeze(Theme.ShopCardBody)
table.freeze(Theme.ShopTab)
table.freeze(Theme.ShopTabStates.selected)
table.freeze(Theme.ShopTabStates.idle)
table.freeze(Theme.ShopTabStates)
table.freeze(Theme.ShopHero)
table.freeze(Theme.ShopHeroItem)
table.freeze(Theme.TextInput)
table.freeze(Theme.CodesLayout)
table.freeze(Theme.MenuButton)
table.freeze(Theme.HudMenuButton)
table.freeze(Theme.AppHud.MenuIcons)
table.freeze(Theme.AppHud.PillIcons)
table.freeze(Theme.AppHud)
table.freeze(Theme.CakeSelectLayout)
table.freeze(Theme.CakeCard)
table.freeze(Theme.MatchCakeCard)
table.freeze(Theme.CakeChoice)
table.freeze(Theme.CakeLockBadge)

Theme.Icons = table.freeze(Icons)

-- Every menu icon must resolve. A nil here falls back to the generic
-- placeholder and the button becomes unreadable — the precise failure this
-- registry exists to prevent, and one that a retired icon name reintroduces
-- silently (R8: never let it pass unreported).
for panel, id in pairs(Theme.AppHud.MenuIcons) do
	if id == nil or id == "" then
		Log.Warn(
			"UIKit",
			`AppHud.MenuIcons.{panel} does not resolve — the button will render the generic placeholder. `
				.. `Point it at a name that exists in Icons.lua.`
		)
	end
end

-- PillIcons hold NAMES, not ids (one source shared by the HUD pills and the
-- shop's balance row), so they are checked against the registry here rather than
-- for nil — otherwise a typo would only surface as a fallback glyph at runtime.
for slot, name in pairs(Theme.AppHud.PillIcons) do
	if Icons[name] == nil then
		Log.Warn(
			"UIKit",
			`AppHud.PillIcons.{slot} = '{tostring(name)}' is not in the icon registry — `
				.. `that pill will render the fallback glyph. See src/shared/UIKit/Icons.lua.`
		)
	end
end

--API
-- Resolve a shop-card accent NAME to its gradient set. Same contract as
-- Theme.Icon: an unknown key warns ONCE and falls back to the default, because
-- the alternative — a card that quietly renders in the wrong colour — reads as
-- a design choice rather than a typo in the catalogue (R8).
function Theme.ShopAccent(name: string?)
	local accent = Theme.ShopCardAccents[name or Theme.ShopCardAccentDefault]
	if accent then
		return accent
	end
	Log.Once(
		"UIKit",
		`shop-accent-{tostring(name)}`,
		`unknown shop accent '{tostring(name)}' — falling back to {Theme.ShopCardAccentDefault}. `
			.. `Valid keys are the Theme.ShopCardAccents tiers; set it in ShopData.`
	)
	return Theme.ShopCardAccents[Theme.ShopCardAccentDefault]
end

--API
-- Resolve match-mode presentation metadata to an art-window accent. Unknown
-- names warn once and fall back to Easy green; a silent fallback would make a
-- mistyped difficulty look intentionally wrong (R8).
function Theme.MatchModeAccent(name: string?)
	local accent = Theme.MatchModeAccents[name or "easy"]
	if accent then
		return accent
	end
	Log.Once(
		"UIKit",
		`match-mode-accent-{tostring(name)}`,
		`unknown match mode accent '{tostring(name)}' — falling back to easy. `
			.. `Valid keys are easy, medium, hard; set it in MatchConfig.`
	)
	return Theme.MatchModeAccents.easy
end

--API
-- Resolve an icon NAME to an asset id. R8: an unknown name warns ONCE and
-- renders a visible "something is wrong" glyph — never a silently blank
-- ImageLabel, which is indistinguishable from a layout bug.
function Theme.Icon(name: string?): string
	if name == nil then
		return Icons.UiShocked
	end
	local id = Icons[name]
	if id then
		return id
	end
	Log.Once("UIKit", `icon-{name}`, `unknown icon '{name}' — see src/shared/UIKit/Icons.lua`)
	return Icons.UiShocked
end

return table.freeze(Theme)
