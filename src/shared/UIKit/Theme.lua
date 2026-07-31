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
	TrackOuterGradient = Theme.Toggle.OuterGradient,
	GrooveGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 246, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 225, 250)),
	}),
	GrooveInset = Vector2.new(4 / 22, 4 / 367),
	ThumbOuterGradient = Theme.Button.OuterGradient,
	ThumbFaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(73, 190, 255)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(70, 160, 250)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(45, 122, 228)),
	}),
	ThumbFaceInset = Vector2.new(3 / 22, 0.02),
	MinThumbFraction = 0.12,
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

-- Selection accent for a pet card: gold Outer/Rim swap (geometry unchanged).
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

local matchmakingStartButton = table.clone(Theme.EquipGreen)
matchmakingStartButton.AspectRatio = 360 / 68
Theme.MatchmakingStartButton = matchmakingStartButton

-- Matchmaking selector: wide configurator archetype, nominal 1000x600.
-- Content is 904x420 at x48..952, y132..552.
-- Vertical: 40+8+68+24+40+8+68+20+44+20+68+12 = 420 ✓.
-- Difficulty: 3*288 + 2*20 = 904 ✓.
-- Players:    4*211 + 3*20 = 904 ✓.
Theme.MatchmakingLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	ContentZIndex = 5,
	ContentPosition = Vector2.new(48 / 1000, 132 / 600),
	ContentSize = Vector2.new(904 / 1000, 420 / 600),
	DifficultyTitlePosition = Vector2.new(0, 0),
	DifficultyTitleSize = Vector2.new(904 / 904, 40 / 420),
	DifficultyRowPosition = Vector2.new(0, 48 / 420),
	DifficultyRowSize = Vector2.new(904 / 904, 68 / 420),
	DifficultyChoiceWidth = 288 / 904,
	DifficultyChoiceGap = 20 / 904,
	DifficultyChoiceAspectRatio = 288 / 68,
	PlayersTitlePosition = Vector2.new(0, 140 / 420),
	PlayersTitleSize = Vector2.new(904 / 904, 40 / 420),
	PlayersRowPosition = Vector2.new(0, 188 / 420),
	PlayersRowSize = Vector2.new(904 / 904, 68 / 420),
	PlayerChoiceWidth = 211 / 904,
	PlayerChoiceGap = 20 / 904,
	PlayerChoiceAspectRatio = 211 / 68,
	StatusPosition = Vector2.new(0, 276 / 420),
	StatusSize = Vector2.new(904 / 904, 44 / 420),
	StartPosition = Vector2.new(272 / 904, 340 / 420),
	StartSize = Vector2.new(360 / 904, 68 / 420),
	HeadingGradient = Theme.Header.TitleGradient,
	StatusGradient = Theme.Button.TextGradient,
	ErrorGradient = Theme.Exit.XGradient,
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
	-- Two card sizes on purpose, so EVERY row is full and the hierarchy is
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
	HeroPx = 260,
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
-- Label only, CENTRED: an icon on the left of a 217-wide pill would push the
-- label off-centre by 8% of the tab, and the section content carries the icons
-- already.
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
}
Theme.ShopTabStates = {
	selected = {
		OutlineColor = Color3.fromRGB(92, 58, 0),
		OuterGradient = Theme.PetCard.SelectOuterGradient,
		RimGradient = Theme.PetCard.SelectRingGradient,
		FaceGradient = Theme.Rarity.Legendary.Face,
		TextGradient = Theme.Rarity.Legendary.Text,
	},
	-- Idle: the Toggle's dark well plus a muted slate face. Deliberately LOW
	-- contrast — an idle tab that competes with the selected one is the same
	-- "everything shouts equally" failure the card colours had.
	idle = {
		OutlineColor = Color3.fromRGB(8, 26, 48),
		OuterGradient = Theme.Toggle.OuterGradient,
		RimGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(118, 148, 186)),
			ColorSequenceKeypoint.new(0.06, Color3.fromRGB(126, 156, 194)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(88, 116, 154)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(66, 92, 128)),
		}),
		FaceGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 126, 166)),
			ColorSequenceKeypoint.new(0.05, Color3.fromRGB(80, 108, 148)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(66, 92, 130)),
			ColorSequenceKeypoint.new(0.93, Color3.fromRGB(56, 80, 116)),
			ColorSequenceKeypoint.new(0.96, Color3.fromRGB(36, 54, 84)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(46, 66, 100)),
		}),
		TextGradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(214, 230, 248)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(178, 200, 226)),
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
		OutlineColor = Theme.Button.OutlineColor,
		OuterGradient = Theme.Button.OuterGradient,
		RimGradient = Theme.Button.RimGradient,
		FaceGradient = Theme.Button.FaceGradient,
		TextGradient = Theme.Button.TextGradient,
	},
	-- "SOON" — no id yet, so there is no price to show and the label spans the
	-- whole shelf (text-only, no glyph).
	unavailable = shopPriceGrey,
	-- "Not enough gems YET" — same grey shelf, but it KEEPS the gem glyph and
	-- the amount, because that number is the information the player needs. It is
	-- simply not clickable; a disabled kit button is correctly silent, so there
	-- is no extra cue.
	unaffordable = shopPriceGrey,
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

-- HERO — the Starter Pack's own cell, full width. Nominal 870x260.
-- It is not a wide ShopCard: the bundle is the pitch, so the contents render as
-- a ROW OF CHIPS (what you get, one per grant) beside the art window and an
-- oversized price shelf. That row is the whole reason this component exists.
-- Same body/art-window language as the grid cells, plus the gold PREMIUM frame
-- — the featured offer is the one cell in the shop allowed to wear it.
-- The info column runs to the card's RIGHT EDGE and the buy shelf is CENTRED
-- under it. Packing title/desc/chips into a 416-wide column and parking a
-- 266-wide shelf at its left left a 160x160 void in the bottom-right quadrant —
-- the only dead area in the whole panel. Spread wide, centre the button, and
-- the leftover space becomes symmetric margin instead.
-- Horizontal: 22 art(206) 22 column(596) 24 = 870 ✓
--   chips 4 * 140 + 3 * 12 = 560 + 36 = 596 ✓ (was 3 * 188 + 2 * 16 — the
--   Starter Pack grants four things now, and a bundle whose chip row is capped
--   below its grant count is an offer that under-sells itself)
--   last chip 250 + 3*152 = 706, +140 = 846 = 250 + 596 ✓ closes on the edge
--   shelf 266 centred in the column: 415..681
-- Column vertical: 28 title(46) 4 desc(28) 12 bundle(50) 12 price(56) 24 = 260 ✓
--   (unchanged — the fourth chip is paid for in WIDTH, not height)
-- Art window: y 27..233 (206 square, vertically centred in 260)
Theme.ShopHero = {
	AspectRatio = 870 / 260,
	OuterCorner = 0.105,
	FacePosition = Vector2.new(8 / 870, 8 / 260),
	FaceSize = Vector2.new(854 / 870, 241 / 260),
	FaceCorner = 0.095,
	ArtPosition = Vector2.new(22 / 870, 27 / 260),
	ArtSize = Vector2.new(206 / 870, 206 / 260),
	ArtCorner = 0.13,
	ArtFacePosition = Vector2.new(27 / 870, 32 / 260),
	ArtFaceSize = Vector2.new(196 / 870, 196 / 260),
	ArtFaceCorner = 0.12,
	IconPosition = Vector2.new(41 / 870, 46 / 260),
	IconSize = Vector2.new(168 / 870, 168 / 260),
	TitlePosition = Vector2.new(250 / 870, 28 / 260),
	TitleSize = Vector2.new(596 / 870, 46 / 260),
	DescPosition = Vector2.new(250 / 870, 78 / 260),
	DescSize = Vector2.new(596 / 870, 28 / 260),
	-- Bundle row: 4 * 140 + 3 * 12 = 596 ✓ (chips are laid out by stride)
	BundlePosition = Vector2.new(250 / 870, 118 / 260),
	BundleSize = Vector2.new(140 / 870, 50 / 260),
	BundleStride = 152 / 870,
	BundleColumns = 4,
	PricePosition = Vector2.new(415 / 870, 180 / 260),
	PriceSize = Vector2.new(266 / 870, 56 / 260),
	-- Overhangs the card's TOP edge, exactly like a grid cell's ribbon, instead
	-- of floating inside the face where it needed a void around it to breathe.
	RibbonPosition = Vector2.new(686 / 870, -12 / 260),
	RibbonSize = Vector2.new(160 / 870, 40 / 260),
	BadgeCenter = Vector2.new(222 / 870, 44 / 260),
	BadgeSize = Vector2.new(46 / 870, 46 / 260),
	Accent = "Legendary", -- the paid hero wears gold; the give stays green
	Premium = true,
}

-- One bundle chip ("x2 Cal"). Nominal 140x50 — under the 50px threshold, so it
-- drops the Rim and is Outer + Face only (style-rules §2). Re-cut from 188x50
-- when the row went to four chips; every fraction below is of the NEW 140 grid,
-- because the old ones would have squashed a 34px icon into a 25px slot.
-- Horizontal: 8 icon(28) 6 text(90) 8 = 140 ✓ · Vertical: face 3..44,
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
	IconPosition = Vector2.new(8 / 140, 11 / 50),
	IconSize = Vector2.new(28 / 140, 28 / 50),
	TextPosition = Vector2.new(42 / 140, 12 / 50),
	TextSize = Vector2.new(90 / 140, 26 / 50),
	-- Dark Outer pill (the Chip recipe) over a RAISED slate face — one value step
	-- lighter than the card body, so the contents row separates from it. The
	-- original deep-blue Chip face was chosen against a gold hero; on the navy
	-- body it was navy-on-navy and the chips disappeared.
	OuterGradient = Theme.Chip.OuterGradient,
	FaceGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(134, 168, 212)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(116, 150, 196)),
		ColorSequenceKeypoint.new(0.60, Color3.fromRGB(98, 130, 176)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(84, 114, 158)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 98, 140)),
	}),
	TextGradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(222, 236, 252)),
	}),
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

-- Boss PRIZE card (HUD top-right, boss phase only). The stake of the fight: the
-- squishy this player is playing for, decided server-side when the boss opens
-- (features/cake-cycle.md). The finale used to be a blind tap race — you could
-- not see what you were fighting for until it was already yours.
-- ARCHETYPE: not a window — a HUD "reward on offer" strip, the plate-left /
-- text-column-right shape ShopTile uses, ratio-transferred to HUD height. It
-- wears the PRIZE'S OWN rarity accent (Theme.Rarity), so a Legendary on offer
-- reads across the room without reading the label.
-- Nominal 300x92.
-- Horizontal: 12 plate(68) 10 column(198) 12 = 300 ✓
-- Vertical plate:  12 plate(68) 12 = 92 ✓
-- Vertical column: 14 caption(24) 2 name(38) 14 = 92 ✓
-- Layers on H=92 (style-rules §2: ~6% top, ~2x that at the bottom):
--   outer top 5 (5.4%) / bottom 10 (10.9%);  rim ring 4 top / 4 bottom
Theme.BossPrize = {
	AspectRatio = 300 / 92,
	OuterCorner = 0.16,
	RimPosition = Vector2.new(7 / 300, 5 / 92),
	RimSize = Vector2.new(286 / 300, 77 / 92),
	RimCorner = 0.15,
	FacePosition = Vector2.new(11 / 300, 9 / 92),
	FaceSize = Vector2.new(278 / 300, 69 / 92),
	FaceCorner = 0.14,
	PlatePosition = Vector2.new(12 / 300, 12 / 92),
	PlateSize = Vector2.new(68 / 300, 68 / 92),
	IconInset = 0.06, -- the squishy nearly fills the plate (ShopTile's value)
	CaptionPosition = Vector2.new(90 / 300, 14 / 92),
	CaptionSize = Vector2.new(198 / 300, 24 / 92),
	NamePosition = Vector2.new(90 / 300, 40 / 92),
	NameSize = Vector2.new(198 / 300, 38 / 92),
	PlateGradient = Theme.PetCard.PlateGradient,
	PlateTransparency = Theme.PetCard.PlateTransparency,
	-- The caption is the quiet line, the NAME is the prize: neutral card text for
	-- the label, the rarity's own text colour for the name (Theme.Rarity carries
	-- `Text`, so this needs no new palette — iron rule 7).
	CaptionGradient = Theme.PetCard.NameGradient,
}

-- Announce banner (HUD top-center, under the cake bar). One OutlinedText
-- line, gold, auto-hides (duration seconds).
Theme.AnnounceBanner = {
	AspectRatio = 800 / 70,
	TextGradient = Theme.PetCard.SelectRingGradient,
	OutlineColor = Theme.Colors.TextOutline,
	Duration = 3,
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
-- y 172..742 on the 1080 reference ✓ (it holds 5 buttons today).
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
--- Boss prize card: top-RIGHT, level with the calories pill on the left (same
--- 22px reference margin, same 26px top). Anchor (1, 0). The only free corner
--- during a boss fight — top-centre is the HP bar + announce banner, and
--- bottom-right is the touch EAT button.
Theme.AppHud.BossPrizePosition = Vector2.new(1 - 22 / 1920, 26 / 1080)
Theme.AppHud.BossPrizeHeight = 76 / 1080 -- taller than a 64/1080 stat pill: it is a prize
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
	-- Content zones (inside the hex's safe middle band).
	NamePosition = Vector2.new(0.15, 0.32),
	NameSize = Vector2.new(0.7, 0.19),
	StatusPosition = Vector2.new(0.17, 0.54),
	StatusSize = Vector2.new(0.66, 0.15),
	-- Connector bar between a node and its parent (geometry in UpgradeTreeConfig).
	ConnectorOwnedGradient = Theme.Button.RimGradient,
	ConnectorLockedGradient = hexGrayRim,
	-- Full-screen dim behind the honeycomb.
	ScrimColor = Color3.fromRGB(8, 12, 22),
	ScrimTransparency = 0.14,
	-- Per-state hex visuals.
	States = {
		locked = {
			Outer = hexGrayOuter,
			Rim = hexGrayRim,
			Face = hexGrayFace,
			Outline = Color3.fromRGB(24, 28, 34),
			Text = hexGrayText,
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
	-- Red circular "!" notifier badge (fractions of the hex node).
	Notifier = {
		Center = Vector2.new(0.77, 0.16),
		Size = 0.34,
		OuterGradient = Theme.Exit.OuterGradient,
		FaceGradient = Theme.Exit.FaceGradient,
		MarkGradient = Theme.Exit.XGradient,
		Outline = Theme.Exit.XOutline,
	},
}
Theme.HexTree.BuyButton = buttonStyleWithAspect(Theme.EquipGreen, 168 / 54)
Theme.HexTree.ZoomButton = buttonStyleWithAspect(Theme.ActionButton, 1)

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
table.freeze(Theme.UpgradeRow)
table.freeze(Theme.UpgradesLayout)
table.freeze(Theme.GymOverlay)
table.freeze(Theme.EatButton)
table.freeze(Theme.RevealOverlay)
table.freeze(Theme.RebirthLayout.StatPositions)
table.freeze(Theme.RebirthLayout)
table.freeze(Theme.MatchChoice)
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
table.freeze(Theme.HexTree.BuyButton)
table.freeze(Theme.HexTree.ZoomButton)
table.freeze(Theme.HexTree)

table.freeze(Theme.Feel)
table.freeze(Theme.Colors)
table.freeze(Theme.Gradients)
table.freeze(Theme.Toggle)
table.freeze(Theme.Panel)
table.freeze(Theme.Header)
table.freeze(Theme.Button)
table.freeze(Theme.Exit)
table.freeze(Theme.Layout)
table.freeze(Theme.PanelWide)
table.freeze(Theme.HeaderWide)
table.freeze(Theme.IconButton)
table.freeze(Theme.ActionButton)
table.freeze(Theme.Scrollbar)
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
-- NOT frozen again: `unaffordable` IS `unavailable` (one shared grey table), and
-- table.freeze errors on an already-frozen table.
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
