--[[
	LocaleData — player-facing strings (R1). STUB implementation.

	API mirrors the Dices localization layer so a full cloud-localization
	toolchain can be dropped in later without touching feature code:
	  T(key, params?)  -- static UI string by key, `{x}` placeholders
	  Tr(text)         -- translate a server-supplied display name (pass-through here)

	Every player-facing string in client code MUST go through T/Tr — never
	hardcode text in modules/subs. Register new keys in
	docs/registries/data-keys.md.
]]

local LocaleData = {}

LocaleData.strings = {
	-- shared reward-card states
	["btn-claim"] = "Claim!",
	["btn-claimed"] = "Claimed",
	["btn-tomorrow"] = "Tomorrow",
	["btn-locked"] = "Locked",
	["label-day-n"] = "Day {n}",
	["label-gold-n"] = "+{n} Gold",
	["label-gems-n"] = "+{n} Gems",
	["label-calories-n"] = "+{n} Cal",
	["label-egg"] = "Free Egg",
	["label-egg-epic"] = "EPIC Egg!",
	-- Generic boost label: the fallback for a boostId nothing has named yet, and
	-- what the daily card still uses for the ORIGINAL x2-calories boost (8 chars
	-- vs 11 — see the budget note below).
	["label-boost"] = "x2 Boost",
	-- Per-boost names (TreasureConfig.boosts nameKeys).
	-- ⚠ These are LENGTH-CONSTRAINED by the daily-reward DayCard, whose reward
	-- line sits beside the art in a 96px zone — ~9 characters before it renders
	-- under 14px, which is where "+100 Gems" and "EPIC Egg!" already sit.
	-- "Extra Bite Size" (15) would render at ~8.5px there, the same unreadable
	-- failure "One squishy, better odds" hit on a shop card.
	-- "x2" prefix, matching ShopData labels exactly — ONE name per perk
	-- everywhere (the shop card and the daily card must never disagree;
	-- copy convention unified 2026-08-01).
	["boost-bite"] = "Extra Bite",
	["boost-speed"] = "x2 Speed",
	["boost-capacity"] = "x2 Stomach",
	-- The calories boost's own name, for the nameKey contract. The daily card
	-- deliberately shows `label-boost` for it instead: same perk, three
	-- characters shorter in a zone that is short of them.
	["boost-15m"] = "x2 Calories",
	["status-code-ok-gems"] = "Code redeemed! +{n} Gems",
	-- HUD menu
	["menu-daily"] = "Daily",
	["menu-shop"] = "Shop",
	["menu-codes"] = "Codes",
	["menu-settings"] = "Settings",
	["menu-pets"] = "Squishies",
	["menu-upgrades"] = "Upgrades",
	-- window titles
	["title-settings"] = "Settings",
	["title-daily-rewards"] = "Daily Rewards",
	["title-shop"] = "Shop",
	["title-codes"] = "Codes",
	["title-pets"] = "Squishies",
	["title-upgrades"] = "Upgrades",
	-- lobby match selector
	["match-title"] = "Choose a Match",
	["match-difficulty-heading"] = "Difficulty",
	["match-players-heading"] = "Party Size",
	["match-difficulty-easy"] = "Easy",
	["match-difficulty-medium"] = "Medium",
	["match-difficulty-hard"] = "Hard",
	["match-player-one"] = "1 Player",
	["match-player-many"] = "{n} Players",
	["match-start"] = "START",
	["match-starting"] = "STARTING...",
	["match-status-choose"] = "Choose difficulty and party size",
	["match-status-partial"] = "Choose one more option",
	["match-status-ready"] = "{current}/{max} players here - ready to launch!",
	["match-status-starting"] = "Starting the match...",
	["match-error-start"] = "Couldn't start the match. Try again.",
	["match-error-session-lost"] = "That match session ended. Step in again.",
	["match-error-invalid-choice"] = "Choose a valid difficulty and party size.",
	-- HUD chips
	["belly-label"] = "BELLY {fill}/{cap}",
	["belly-glutton"] = "FULL! GLUTTON x2",
	["cake-progress"] = "CAKE {pct}%",
	["cake-finds"] = "FINDS {found}/{total}",
	["cake-boss"] = "BOSS! {timer}s",
	-- Caption on the boss PRIZE card: the squishy at stake in the fight
	-- (UIKit/BossPrizeCard, features/cake-cycle.md).
	["boss-prize-caption"] = "FIGHTING FOR",
	["cake-reward"] = "SQUISHY TIME!",
	["cake-spawning"] = "NEW CAKE IN {timer}s",
	["announce-new-cake"] = "A fresh cake rolled in!",
	["announce-rare-cake-golden"] = "GOLDEN CAKE! x3 calories!",
	["announce-rare-cake-rainbow"] = "RAINBOW CAKE! Epic squishy guaranteed!",
	["announce-boss-spawned"] = "The Cake Guardian awakens!",
	["announce-cake-cleared"] = "Cake cleared! Everyone gets a squishy!",
	["announce-layer-locked"] = "Eat the top layer first!",
	["announce-layer-cleared"] = "LAYER CLEARED!",
	-- Buried finds (features/treasures.md) — only rare+ earn a banner
	["announce-find-new"] = "NEW DISCOVERY!",
	["announce-find-rare"] = "RARE FIND!",
	["announce-find-epic"] = "EPIC FIND!",
	["announce-find-legendary"] = "LEGENDARY FIND!",
	["announce-match-lost"] = "Match lost! Returning to the lobby...",
	-- upgrades
	["upgrade-capacity"] = "Stomach Capacity",
	["upgrade-bite-radius"] = "Bite Radius",
	["upgrade-bite-depth"] = "Bite Depth",
	["upgrade-eat-speed"] = "Eat Speed",
	["upgrade-gym-eff"] = "Gym Efficiency",
	["upgrade-burn-speed"] = "Burn Speed",
	["upgrade-burn-per-tap"] = "Burn Per Tap",
	["upgrade-instant-burn"] = "Instant Burn",
	["upgrade-run-speed"] = "Run Speed",
	["label-level-n"] = "Lv {n}/{cap}",
	["btn-max"] = "MAX",
	["price-calories"] = "{n} cal",
	-- upgrades hex-tree (features/upgrades.md)
	["cat-eating"] = "Eating",
	["cat-body"] = "Body",
	["cat-gym"] = "Gym",
	["hex-name-capacity"] = "Belly",
	["hex-name-biteRadius"] = "Bite",
	["hex-name-biteDepth"] = "Depth",
	["hex-name-eatSpeed"] = "Eat",
	["hex-name-gymEff"] = "Gym",
	["hex-name-burnSpeed"] = "Speed",
	["hex-name-burnPerTap"] = "Tap",
	["hex-name-instantBurn"] = "Instant",
	["hex-name-runSpeed"] = "Run",
	["upgrade-capacity-desc"] = "Bigger belly — hold more cake before the gym.",
	["upgrade-bite-radius-desc"] = "Wider bites — clear more cake per chomp.",
	["upgrade-bite-depth-desc"] = "Deeper bites — dig further into the cake.",
	["upgrade-eat-speed-desc"] = "Faster chewing — more bites per second.",
	["upgrade-gym-eff-desc"] = "Better workout — more calories banked per burn.",
	["upgrade-burn-speed-desc"] = "Faster passive burn — fat melts quicker while you work out.",
	["upgrade-burn-per-tap-desc"] = "Each tap torches more fat — fewer taps to empty the belly.",
	["upgrade-instant-burn-desc"] = "Burn a slice of fat the instant you start — max tier clears it all!",
	["upgrade-run-speed-desc"] = "Zippier legs — run around the cake faster.",
	["hex-owned"] = "Owned",
	["hex-locked"] = "Locked",
	["hex-open"] = "Open",
	["hex-back"] = "Back",
	["hex-logo"] = "UPGRADES",
	["hex-progress"] = "{owned}/{total} tiers",
	["hex-open-desc"] = "Open this branch of upgrades.",
	["hex-tip-cost"] = "Costs {n} calories",
	["hex-tip-max"] = "Maxed out!",
	["hex-tip-locked"] = "Buy the previous tier first.",
	["hex-close"] = "Close [E]",
	-- eat input (touch hold-to-eat HUD button, features/cake-sim.md)
	["eat-button"] = "EAT",
	-- gym (fat-burn overlay)
	["gym-tap"] = "TAP!",
	["gym-fat-left"] = "{n}% FAT",
	["hud-burn-fat"] = "TO CHECKPOINT",
	-- pets / reveal
	["btn-equip"] = "Equip",
	["btn-unequip"] = "Unequip",
	["btn-equip-best"] = "Equip Best",
	["label-select-pet"] = "Pick a squishy",
	["reveal-new"] = "NEW SQUISHY!",
	["reveal-copies"] = "Level {n}",
	["reveal-continue"] = "Tap to continue",
	-- Squishy roster (keys pair 1:1 with PetConfig ids — the ids are DataStore
	-- keys and never change, so a re-theme edits ONLY the right-hand side).
	-- common — plain drops & cups
	["pet-crumb-mouse"] = "Vanilla Cup",
	["pet-sugar-chick"] = "Wink Cup",
	["pet-jelly-slug"] = "Calm Cup",
	["pet-berry-gummy"] = "Aqua Drop",
	["pet-lime-gummy"] = "Mint Drop",
	["pet-lemon-gummy"] = "Blush",
	["pet-loop-pop"] = "Ocean Drop",
	-- uncommon
	["pet-frosting-cat"] = "Lilac Drop",
	["pet-cocoa-pup"] = "Sunset Drop",
	["pet-candy-crab"] = "Stone Loaf",
	["pet-top-muffin"] = "Peach Glow",
	["pet-flake-crescent"] = "Cream Wink",
	["pet-blue-drop"] = "Mint Glow",
	["pet-peppermint-stick"] = "Grape Drop",
	-- rare
	["pet-caramel-fox"] = "Plum Sparkle",
	["pet-waffle-owl"] = "Sun Hat",
	["pet-rose-macaron"] = "Leaf Sprout",
	["pet-sky-macaron"] = "Bonsai",
	["pet-swirl-roll"] = "Sky Beam",
	["pet-stack-cakes"] = "Pastel Arc",
	-- epic — costumed
	["pet-gummy-dragon"] = "Cool Shades",
	["pet-eclair-unicorn"] = "Ancient Bonsai",
	["pet-slice-supreme"] = "Ember",
	["pet-crunch-taco"] = "Visor",
	["pet-triple-scoop"] = "Thunderhead",
	-- legendary
	["pet-golden-whale"] = "King",
	["pet-the-cake"] = "Angel Cup",
	["pet-cloud-floss"] = "Prism",
	["pet-ruby-berry"] = "Void Cup",
	-- secret
	["pet-void-muffin"] = "DEMON",
	-- costumed set
	["pet-snow-drop"] = "Snow Drop",
	["pet-stripe-shell"] = "Stripe Shell",
	["pet-butter-cup"] = "Butter Cup",
	["pet-lavender-drop"] = "Lavender Drop",
	["pet-lime-glow"] = "Lime Glow",
	["pet-amber-drop"] = "Amber Drop",
	["pet-blossom"] = "Blossom",
	["pet-sombrero"] = "Siesta",
	["pet-viking-helm"] = "Raider",
	["pet-green-blade"] = "Green Blade",
	["pet-suit"] = "The Boss",
	["pet-officer"] = "Officer",
	["pet-firefighter"] = "Firefighter",
	["pet-hazard-core"] = "Hazard Core",
	["pet-ember-rage"] = "Ember Rage",
	["pet-alien"] = "Visitor",
	["pet-nebula-drop"] = "Nebula",
	["pet-galaxy-ring"] = "COSMOS",
	-- pet stats / rarities / biomes
	["stat-calories"] = "Calories",
	["stat-eat-speed"] = "Eat Speed",
	["stat-gems"] = "Gems",
	["rarity-common"] = "Common",
	["rarity-uncommon"] = "Uncommon",
	["rarity-rare"] = "Rare",
	["rarity-epic"] = "Epic",
	["rarity-legendary"] = "Legendary",
	["rarity-secret"] = "Secret",
	["biome-factory"] = "Cake Factory",
	["biome-donut"] = "Donut Plant",
	["biome-candy"] = "Candy World",
	-- settings rows
	["label-music"] = "Music",
	["label-sound-effects"] = "Sound Effects",
	-- rewards footers
	["footer-daily-claim"] = "Claim today's reward!",
	["footer-daily-tomorrow"] = "Come back tomorrow for the next reward!",
	-- shop
	["shop-section-featured"] = "Featured",
	["shop-section-passes"] = "Game Passes",
	["shop-section-gold"] = "Gems", -- legacy key, kept for the retired ShopRow list
	["shop-section-gems"] = "Gems",
	-- Was "shop-section-eggs" / "Eggs & Boosts". The section sells no eggs any
	-- more, and a header naming content it does not hold is the drift D3 bans.
	["shop-section-boosts"] = "Boosts",
	["shop-section-free"] = "Free Stuff",
	-- Tab labels: SHORT on purpose — a 217px tab holds ~9 glyphs before
	-- TextScaled shrinks them below the section headers they replace.
	-- "Offers", not "Featured": that tab holds the Free Stuff and Featured
	-- SECTIONS, and a tab whose label repeats one of its own section headers
	-- reads as a rendering bug.
	["shop-tab-featured"] = "Offers",
	["shop-tab-passes"] = "Passes",
	["shop-tab-boosts"] = "Boosts",
	["shop-tab-gems"] = "Gems",
	["btn-soon"] = "SOON",
	["ribbon-best-value"] = "BEST VALUE",
	["ribbon-one-time"] = "ONE TIME",
	["label-group-reward"] = "Group Reward",
	["sub-group-reward"] = "Join our group!",
	["sub-group-join-first"] = "Join the group, then claim again!",
	["btn-free"] = "FREE",
	["btn-owned"] = "Owned",
	["price-robux"] = "R$ {n}",
	-- The card's price shelf draws the Robux GLYPH, so its label is the bare
	-- amount. `price-robux` kept the "R$" prefix AND the glyph was drawn beside
	-- it, so every card read "⬡ R$ 199".
	["price-robux-short"] = "{n}",
	-- Same rule on the gem row: the shelf draws the gem glyph, so the label is
	-- the bare amount. It is a separate key from the Robux one because a
	-- translation may want a different numeral format per currency.
	["price-gems-short"] = "{n}",
	-- codes
	["placeholder-code"] = "Enter code...",
	["btn-redeem"] = "Redeem",
	["status-code-ok"] = "Code redeemed!",
	["status-code-ok-gold"] = "Code redeemed! +{n} Gold",
	["status-code-invalid"] = "Invalid code",
	["status-code-expired"] = "This code has expired",
	["status-code-already"] = "Already redeemed",
	["status-code-cooldown"] = "Please wait a moment...",
	-- onboarding / tutorial (features/tutorial.md)
	["tutorial-title"] = "THE CHALLENGE",
	["tutorial-skip"] = "LET'S GO!",
	["tutorial-eat-title"] = "EAT THE CAKE!",
	-- Two bodies, one per input device (AppRoot picks by IS_TOUCH). Kept SHORT:
	-- the hint card's body zone is 394x64 nominal and TextScaled binds on WIDTH,
	-- so a third line renders at a size this audience will not read.
	["tutorial-eat-body-pc"] = "Hold the LEFT MOUSE BUTTON to eat what's in front of you.",
	["tutorial-eat-body-touch"] = "Hold the pink EAT button to eat what's in front of you.",
	["tutorial-eat-ok"] = "GOT IT!",
	["tutorial-arrow-upgrades"] = "UPGRADES",
	-- reserved (celebration hook not implemented yet)
	["toast-claimed"] = "Claimed!",
	["toast-claimed-gold"] = "+{n} Gold!",
}

local missingWarned: { [string]: boolean } = {}

--API
function LocaleData.T(key: string, params: { [string]: any }?): string
	local text = LocaleData.strings[key]
	if text == nil then
		-- Once per key: dynamic keys (announce-*, pet-*) resolve inside
		-- React renders — an unregistered id would otherwise warn-spam.
		if not missingWarned[key] then
			missingWarned[key] = true
			warn(`[LocaleData] Missing string key '{key}'`)
		end
		return key
	end
	if params then
		text = string.gsub(text, "{(%w+)}", function(name)
			local value = params[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	end
	return text
end

--API
function LocaleData.Tr(text: string?): string?
	return text
end

return LocaleData
