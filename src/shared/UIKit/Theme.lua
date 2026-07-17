-- Layout values are normalized Scale ratios. SourceRects are raster sampling coordinates only.
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
	Common = {
		Outer = Theme.Button.OuterGradient,
		Rim = Theme.Button.RimGradient,
		Face = Theme.Button.FaceGradient,
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
	PlatePosition = Vector2.new(32 / 140, 26 / 160),
	PlateSize = Vector2.new(76 / 140, 76 / 160),
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
Theme.Badge = {
	AspectRatio = 1,
	RingColor = Theme.Toggle.KnobOnOutlineColor,
	FillGradient = Theme.Toggle.KnobOnGradient,
	FillPosition = Vector2.new(0.13, 0.13),
	FillSize = Vector2.new(0.74, 0.74),
}

-- Day/milestone card (rewards grids). Nominal 118x135, PetCard family
-- (fractions ratio-transferred from PetCard 140x160: rim inset 6/118≈7/140,
-- face inset 8.5/118≈10/140). Vertical zones: 10 title(26) 16 reward(30)
-- 10 sub(24) 19 = 135 ✓.
Theme.DayCard = {
	AspectRatio = 118 / 135,
	OuterCorner = 0.14,
	RimPosition = Vector2.new(6 / 118, 6 / 135),
	RimSize = Vector2.new(106 / 118, 117 / 135),
	RimCorner = 0.13,
	FacePosition = Vector2.new(8.5 / 118, 8 / 135),
	FaceSize = Vector2.new(101 / 118, 111 / 135),
	FaceCorner = 0.12,
	TitlePosition = Vector2.new(10 / 118, 10 / 135),
	TitleSize = Vector2.new(98 / 118, 26 / 135),
	RewardPosition = Vector2.new(8 / 118, 52 / 135),
	RewardSize = Vector2.new(102 / 118, 30 / 135),
	SubPosition = Vector2.new(8 / 118, 92 / 135),
	SubSize = Vector2.new(102 / 118, 24 / 135),
	TitleGradient = Theme.Button.TextGradient,
	RewardGradient = Theme.PetCard.NameGradient,
	-- Claimable accent: gold Outer/Rim swap (PetCard selection rule).
	ClaimableOuterGradient = Theme.PetCard.SelectOuterGradient,
	ClaimableRimGradient = Theme.PetCard.SelectRingGradient,
	BadgeCenter = Vector2.new(100 / 118, 24 / 135),
	BadgeSize = Vector2.new(26 / 118, 26 / 135),
	BadgeOutlineColor = Theme.Toggle.KnobOnOutlineColor,
	BadgeGradient = Theme.Toggle.KnobOnGradient,
	CheckColor = Color3.new(1, 1, 1),
	DisabledTransparency = 0.22,
}

-- Rewards window geometry (daily + time share it). Nominal 1000x600.
-- Vertical: header 120, gap 30, grid 360 (y150..510), gap 10, footer 48,
-- margin 32 -> 120+30+360+10+48+32 = 600 ✓. Horizontal: 48+904+48 = 1000 ✓.
-- Grid: 7 columns -> 7*118 + 6*13 = 826+78 = 904 ✓.
Theme.RewardsLayout = {
	PanelAspect = 1000 / 600,
	PanelMaxViewportFraction = 0.9,
	HeaderHeight = 120 / 600,
	GridPosition = Vector2.new(48 / 1000, 150 / 600),
	GridSize = Vector2.new(904 / 1000, 360 / 600),
	Columns = 7,
	-- 117.5, not 118: exact-fit grids can wrap the last cell on float
	-- rounding (kit pitfall) — shave the cell width a hair.
	CellWidth = 117.5 / 904,
	CellPaddingX = 13 / 904,
	CellHeight = 135 / 360,
	FooterPosition = Vector2.new(48 / 1000, 520 / 600),
	FooterSize = Vector2.new(904 / 1000, 48 / 600),
	FooterGradient = Theme.Header.TitleGradient,
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

-- Shop window list geometry (portrait Panel family, same content region as
-- the settings rows: x 47..465, y 128..691). Section label 40, row 88.
Theme.ShopLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = Theme.Layout.PanelMaxViewportFraction,
	ListPosition = Theme.Layout.RowsPosition,
	ListSize = Theme.Layout.RowsSize,
	-- Section header cell (gap baked into the aspect, same recipe as rows —
	-- NO scale Padding inside an AutomaticCanvasSize list).
	SectionCellAspect = 418 / 50,
	SectionContentHeight = 40 / 50,
	SectionGradient = Theme.Header.TitleGradient,
	ScrollWindowFraction = 0.96,
	ScrollBarWidth = 0.05,
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

-- App HUD geometry (template glue): gold pill top-left, menu column under it.
-- Reference screen 1920x1080 (Hud family).
Theme.AppHud = {
	PillAspect = Theme.Hud.PillAspect,
	PillHeight = 64 / 1080,
	PillPosition = Vector2.new(22 / 1920, 24 / 1080),
	MenuPosition = Vector2.new(22 / 1920, 110 / 1080),
	MenuWidth = 220 / 1920,
	MenuButtonHeight = 56 / 1080,
	MenuGap = 12 / 1080,
	-- Badge sits on the button's top-right corner.
	BadgeAnchor = Vector2.new(0.5, 0.5),
	BadgePosition = Vector2.new(0.94, 0.08),
	BadgeSize = Vector2.new(24 / 170, 24 / 56),
}

-- ===== Eat the Cake game sections =====

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
Theme.Rarity.Secret = {
	Outer = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 0, 34)),
		ColorSequenceKeypoint.new(0.10, Color3.fromRGB(30, 0, 27)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(32, 0, 29)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 0, 32)),
	}),
	Rim = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(215, 60, 130)),
		ColorSequenceKeypoint.new(0.05, Color3.fromRGB(255, 105, 170)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(235, 85, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 50, 115)),
	}),
	Face = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 30, 95)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(96, 22, 76)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(84, 18, 66)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(55, 8, 44)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(66, 12, 52)),
	}),
}

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

-- Gym mash overlay (reference screen 1920x1080): round green TAP button at
-- (0.5, 0.74) d 220; timer bar 360x40 at (0.5, 0.60); counter above it.
Theme.GymOverlay = {
	ButtonHeight = 220 / 1080,
	ButtonAspect = 1,
	ButtonPosition = Vector2.new(0.5, 0.74),
	ButtonOuterCorner = 1, -- circle
	ButtonOutline = Theme.EquipGreen.OutlineColor,
	ButtonOuterGradient = Theme.EquipGreen.OuterGradient,
	ButtonRimGradient = Theme.EquipGreen.RimGradient,
	ButtonFaceGradient = Theme.EquipGreen.FaceGradient,
	ButtonTextGradient = Theme.EquipGreen.TextGradient,
	-- Same inset ratios as IconButton, on the button's own nominal 220 grid.
	RimPosition = Vector2.new(14 / 220, 14 / 220),
	RimSize = Vector2.new(192 / 220, 174 / 220),
	FacePosition = Vector2.new(21 / 220, 21 / 220),
	FaceSize = Vector2.new(178 / 220, 160 / 220),
	TextPosition = Vector2.new(30 / 220, 80 / 220),
	TextSize = Vector2.new(160 / 220, 60 / 220),
	TimerHeight = 40 / 1080,
	TimerAspect = 360 / 40,
	TimerPosition = Vector2.new(0.5, 0.60),
	TimerOuterGradient = Theme.Toggle.OuterGradient,
	TimerGrooveGradient = Theme.Scrollbar.GrooveGradient,
	TimerFillGradient = Theme.PetCard.SelectRingGradient,
	TimerGrooveInset = Vector2.new(5 / 360, 5 / 40),
	CounterHeight = 36 / 1080,
	CounterPosition = Vector2.new(0.5, 0.545),
	CounterGradient = Theme.Button.TextGradient,
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

-- Quest row (quests list archetype). Nominal 418x96 (cell bakes 10 gap).
-- Vertical: name 8..34 (26), bar 40..62 (22), reward 66..90 (24);
-- claim button 20..76 (56). Horizontal: 16 text(254) 12 claim(120) 16 = 418 ✓.
Theme.QuestRow = {
	CellAspectRatio = 418 / 106,
	ContentHeightInCell = 96 / 106,
	AspectRatio = 418 / 96,
	OuterCorner = 0.20,
	RimPosition = Vector2.new(6 / 418, 6 / 96),
	RimSize = Vector2.new(406 / 418, 78 / 96),
	RimCorner = 0.18,
	FacePosition = Vector2.new(9 / 418, 8 / 96),
	FaceSize = Vector2.new(400 / 418, 74 / 96),
	FaceCorner = 0.17,
	OutlineColor = Theme.Button.OutlineColor,
	OuterGradient = Theme.Button.OuterGradient,
	RimGradient = Theme.Button.RimGradient,
	FaceGradient = Theme.Button.FaceGradient,
	NamePosition = Vector2.new(16 / 418, 8 / 96),
	NameSize = Vector2.new(254 / 418, 26 / 96),
	NameGradient = Theme.Button.TextGradient,
	BarPosition = Vector2.new(16 / 418, 40 / 96),
	BarSize = Vector2.new(254 / 418, 22 / 96),
	BarOuterGradient = Theme.Toggle.OuterGradient,
	BarGrooveGradient = Theme.Scrollbar.GrooveGradient,
	BarGrooveInset = Vector2.new(3 / 254, 3 / 22),
	BarFillGradient = Theme.Toggle.KnobOnGradient,
	BarTextGradient = Theme.PetCard.NameGradient,
	RewardPosition = Vector2.new(16 / 418, 66 / 96),
	RewardSize = Vector2.new(254 / 418, 24 / 96),
	RewardGradient = Theme.PetCard.NameGradient,
	ClaimPosition = Vector2.new(282 / 418, 20 / 96),
	ClaimSize = Vector2.new(120 / 418, 56 / 96),
}

-- Quests window geometry: 3 rows: 3*96 + 2*10 = 308 ≤ 563 ✓.
Theme.QuestsLayout = {
	PanelAspect = Theme.Layout.PanelAspect,
	PanelMaxViewportFraction = Theme.Layout.PanelMaxViewportFraction,
	ListPosition = Theme.Layout.RowsPosition,
	ListSize = Theme.Layout.RowsSize,
	RowHeight = 96 / 563,
	RowGap = 10 / 563,
}

-- Button styles for non-4.06 zones. Components.Button self-constrains to
-- its style's AspectRatio (FitWithinMaxSize): putting EquipGreen (418/103)
-- into a 140x56 zone renders a 140x34.5 button — every zone needs a style
-- whose aspect MATCHES the zone (the arithmetic in UpgradeRow/QuestRow/
-- RebirthLayout assumes full-height buttons).
local function buttonStyleWithAspect(base, aspect: number)
	local copy = table.clone(base)
	copy.AspectRatio = aspect
	return copy
end
Theme.BuyButton = buttonStyleWithAspect(Theme.EquipGreen, 140 / 56) -- UpgradeRow buy zone
Theme.BuyButtonNeutral = buttonStyleWithAspect(Theme.ActionButton, 140 / 56) -- "MAX"
Theme.ClaimButton = buttonStyleWithAspect(Theme.EquipGreen, 120 / 56) -- QuestRow claim zone
Theme.ClaimButtonNeutral = buttonStyleWithAspect(Theme.ActionButton, 120 / 56)
Theme.RebirthButton = buttonStyleWithAspect(Theme.EquipGreen, 318 / 84) -- RebirthLayout button zone

-- App HUD additions for the game: second currency pill, belly bar,
-- cake progress bar, combo badge, announce banner. Two pills stack at
-- y 24..88 and 96..160; the menu moves DOWN to clear them:
-- 9 rows: 9*56 + 8*12 = 600 -> y 172..772 on the 1080 reference ✓.
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

table.freeze(Theme.Rarity.Uncommon)
table.freeze(Theme.Rarity.Secret)
table.freeze(Theme.BuyButton)
table.freeze(Theme.BuyButtonNeutral)
table.freeze(Theme.ClaimButton)
table.freeze(Theme.ClaimButtonNeutral)
table.freeze(Theme.RebirthButton)
table.freeze(Theme.BellyBar)
table.freeze(Theme.CakeBar)
table.freeze(Theme.ComboBadge)
table.freeze(Theme.AnnounceBanner)
table.freeze(Theme.UpgradeRow)
table.freeze(Theme.UpgradesLayout)
table.freeze(Theme.GymOverlay)
table.freeze(Theme.RevealOverlay)
table.freeze(Theme.RebirthLayout.StatPositions)
table.freeze(Theme.RebirthLayout)
table.freeze(Theme.QuestRow)
table.freeze(Theme.QuestsLayout)

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
table.freeze(Theme.ShopLayout)
table.freeze(Theme.TextInput)
table.freeze(Theme.CodesLayout)
table.freeze(Theme.MenuButton)
table.freeze(Theme.AppHud)
return table.freeze(Theme)
