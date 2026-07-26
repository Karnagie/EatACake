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
	ShopTile = require(ComponentsFolder.ShopTile),
	ShopPackCard = require(ComponentsFolder.ShopPackCard),
	ShopBanner = require(ComponentsFolder.ShopBanner),
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
	UpgradeRow = require(ComponentsFolder.UpgradeRow),
	UpgradesPanel = require(ComponentsFolder.UpgradesPanel),
	HexNode = require(ComponentsFolder.HexNode),
	HexTreeOverlay = require(ComponentsFolder.HexTreeOverlay),
	GymOverlay = require(ComponentsFolder.GymOverlay),
	EatButton = require(ComponentsFolder.EatButton),
	PetRevealOverlay = require(ComponentsFolder.PetRevealOverlay),
	RebirthPanel = require(ComponentsFolder.RebirthPanel),
	QuestRow = require(ComponentsFolder.QuestRow),
	QuestsPanel = require(ComponentsFolder.QuestsPanel),
	MatchChoice = require(ComponentsFolder.MatchChoice),
	MatchmakingPanel = require(ComponentsFolder.MatchmakingPanel),
}

table.freeze(Components)

return table.freeze({
	Theme = Theme,
	Components = Components,
	-- Inject the player-side click/hover sound layer once (AudioSubsClient).
	-- Shared code cannot require a client module, so the kit takes the handler
	-- instead — see Interaction's SOUND section and docs/features/audio.md.
	SetSoundHandler = Interaction.SetSoundHandler,
	-- Demo apps (reference compositions): require lazily, e.g. require(UIKit.Demos.HudDemo)
	Demos = script.Demos,
})
