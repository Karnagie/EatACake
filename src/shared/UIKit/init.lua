--[[ UIKit
	Candy-style ReactRoblox UI kit: Theme (single source of style) + component catalog (the Components table below) + demos.
	HOW to build UI with it (mandatory reading for agents): .claude/skills/roblox-ui-kit/SKILL.md
	Integration contract: docs/features/ui-kit.md
	Requires @jsdotlua react packages in ReplicatedStorage.Packages (vendored as ReactLua-Packages.rbxmx; see feature doc).
]]

local Theme = require(script.Theme)
local Interaction = require(script.Interaction)
local ComponentsFolder = script.Components

local Components = {
	OutlinedText = require(ComponentsFolder.OutlinedText),
	Button = require(ComponentsFolder.Button),
	Toggle = require(ComponentsFolder.Toggle),
	CloseButton = require(ComponentsFolder.CloseButton),
	Header = require(ComponentsFolder.Header),
	PanelShell = require(ComponentsFolder.PanelShell),
	PanelWithHeader = require(ComponentsFolder.PanelWithHeader),
	SettingRow = require(ComponentsFolder.SettingRow),
	SettingsPanel = require(ComponentsFolder.SettingsPanel),
	IconButton = require(ComponentsFolder.IconButton),
	ScrollPane = require(ComponentsFolder.ScrollPane),
	PetCard = require(ComponentsFolder.PetCard),
	PetsPanel = require(ComponentsFolder.PetsPanel),
	PetsInspectPanel = require(ComponentsFolder.PetsInspectPanel),
	StatPill = require(ComponentsFolder.StatPill),
	Hud = require(ComponentsFolder.Hud),
	HudMenuButton = require(ComponentsFolder.HudMenuButton),
	Badge = require(ComponentsFolder.Badge),
	DayCard = require(ComponentsFolder.DayCard),
	RewardsPanel = require(ComponentsFolder.RewardsPanel),
	ShopRow = require(ComponentsFolder.ShopRow), -- retired portrait row, kept for API compat
	ShopPanel = require(ComponentsFolder.ShopPanel),
	-- Landscape sectioned shop (grids per category)
	ShopSectionHeader = require(ComponentsFolder.ShopSectionHeader),
	ShopTab = require(ComponentsFolder.ShopTab),
	ShopTile = require(ComponentsFolder.ShopTile), -- retired button-style cell
	ShopPackCard = require(ComponentsFolder.ShopPackCard), -- retired button-style cell
	ShopBanner = require(ComponentsFolder.ShopBanner),
	ShopCard = require(ComponentsFolder.ShopCard),
	ShopHeroCard = require(ComponentsFolder.ShopHeroCard),
	PriceButton = require(ComponentsFolder.PriceButton),
	Ribbon = require(ComponentsFolder.Ribbon),
	TextInput = require(ComponentsFolder.TextInput),
	CodesPanel = require(ComponentsFolder.CodesPanel),
	-- Eat the Cake additions
	StatRow = require(ComponentsFolder.StatRow),
	BellyBar = require(ComponentsFolder.BellyBar),
	CakeBar = require(ComponentsFolder.CakeBar),
	ComboBadge = require(ComponentsFolder.ComboBadge),
	AnnounceBanner = require(ComponentsFolder.AnnounceBanner),
	BossPrizeCard = require(ComponentsFolder.BossPrizeCard),
	UpgradeRow = require(ComponentsFolder.UpgradeRow),
	UpgradesPanel = require(ComponentsFolder.UpgradesPanel),
	HexNode = require(ComponentsFolder.HexNode),
	HexTreeOverlay = require(ComponentsFolder.HexTreeOverlay),
	GymOverlay = require(ComponentsFolder.GymOverlay),
	EatButton = require(ComponentsFolder.EatButton),
	PetRevealOverlay = require(ComponentsFolder.PetRevealOverlay),
	MatchChoice = require(ComponentsFolder.MatchChoice),
	MatchmakingPanel = require(ComponentsFolder.MatchmakingPanel),
	-- Onboarding / tutorial (features/tutorial.md)
	InputGlyph = require(ComponentsFolder.InputGlyph),
	TutorialSlides = require(ComponentsFolder.TutorialSlides),
	TutorialHint = require(ComponentsFolder.TutorialHint),
	HintArrow = require(ComponentsFolder.HintArrow),
}

table.freeze(Components)

return table.freeze({
	Theme = Theme,
	Components = Components,
	-- Inject the player-side click/hover sound layer once (AudioSubsClient).
	-- Shared code cannot require a client module, so the kit takes the handler
	-- instead — see Interaction's SOUND section and docs/features/audio.md.
	SetSoundHandler = Interaction.SetSoundHandler,
	-- Same shape, for telemetry: injected once by AnalyticsSubsClient, it
	-- counts EVERY kit press (live or disabled) with no per-button wiring.
	-- See Interaction's ANALYTICS section and docs/features/analytics.md.
	SetTrackHandler = Interaction.SetTrackHandler,
	-- Demo apps (reference compositions): require lazily, e.g. require(UIKit.Demos.HudDemo)
	Demos = script.Demos,
})
