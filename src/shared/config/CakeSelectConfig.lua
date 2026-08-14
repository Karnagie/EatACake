--[[
	CakeSelectConfig -- the catalogue of SELECTABLE cakes and how each unlocks.

	The lobby and game places load this exact module, so a cake id can never mean
	two things across the split (ADR-0009). It is DATA ONLY: no functions, and no
	asset id or display string lives here — the icon is a NAME resolved through
	Theme.Icon (src/shared/UIKit/Icons.lua) and every player-facing word is a
	locale KEY resolved through LocaleData.T, exactly like MatchConfig's
	`labelKey`. Feature doc: docs/features/cake-select.md.

	⚠ NAMING. Ids are `cake-<flavour>`, NOT the bare flavour, because
	`CakeConfig.rare.rainbow` / `CakeStateData.rareKind = "rainbow"` already exist
	and mean something completely different (a ~1% roll that re-skins the CURRENT
	cake). A selectable cake and a rare modifier sharing the string `rainbow`
	would be indistinguishable in configs, remote payloads and analytics buckets.
	The module is likewise `CakeSelectConfig`, not `CakesConfig`, so it never
	reads as a sibling of the simulation's `CakeConfig`.

	Shape:
	  order      : { cakeId } — render order, first entry is the catalogue's head
	  defaultId  : cakeId — what a fresh profile selects, and the coercion target
	                 for any unknown/locked stored selection
	  cakes[id]  : {
	      nameKey        : locale key for the display name
	      iconName       : Icons.lua registry NAME (never an asset id)
	      accent         : Theme.ShopCardAccents key — the art window's hue
	      unlockRule     : "none" | "cakes-eaten"
	      unlockCakesEaten : number  — required only by the "cakes-eaten" rule
	      unlockHintKey  : locale key shown on the locked card
	    }

	⚠ `unlockRule` is evaluated SERVER-SIDE (CakeSelectSubs) against the profile;
	the client only renders the answer it is pushed. Adding a rule kind means
	teaching that subscription about it — a rule it does not recognise is treated
	as LOCKED and warned about, never silently granted.
]]

local CakeSelectConfig = {}

CakeSelectConfig.order = { "cake-classic", "cake-rainbow", "cake-coming-soon" }

CakeSelectConfig.defaultId = "cake-classic"

CakeSelectConfig.cakes = {
	["cake-classic"] = {
		nameKey = "cake-name-classic",
		iconName = "CakeClassic",
		accent = "Blue",
		unlockRule = "none",
	},
	-- Playable after one completed cake. The queue leader's persisted selection
	-- is snapshotted into the match launch and validated again in the game place.
	["cake-rainbow"] = {
		nameKey = "cake-name-rainbow",
		iconName = "CakeRainbow",
		accent = "Legendary",
		unlockRule = "cakes-eaten",
		unlockCakesEaten = 1,
		unlockHintKey = "cake-unlock-hint",
	},
	-- A DELIBERATE TEASE, not a real cake. Its whole job is to tell the player
	-- that the rainbow is not the end of the list — without it, a two-card panel
	-- reads as "there are two cakes in this game, and you have seen both".
	-- `unlockRule = "coming-soon"` is a first-class rule the server RECOGNISES
	-- and always answers LOCKED for (it is never an "unknown rule" warning, and
	-- an evaluated answer, so a stored selection naming it is correctly coerced).
	-- ⚠ `iconName` is a chrome glyph on purpose — a mystery box, because there is
	-- no art for a cake that does not exist yet. Give it real art and a real
	-- unlock rule and this becomes an ordinary catalogue entry with no code
	-- change anywhere.
	["cake-coming-soon"] = {
		nameKey = "cake-name-soon",
		iconName = "UiBox",
		accent = "Common",
		unlockRule = "coming-soon",
		unlockHintKey = "cake-status-soon",
	},
}

return CakeSelectConfig
