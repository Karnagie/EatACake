--[[
	LocaleData — player-facing strings (R1) + the translation resolvers.

	The SINGLE source of every string set from client code. Keys are kebab-case;
	values are the exact English SOURCE templates ({param} braces) that also live
	in the experience's CLOUD LOCALIZATION TABLE (same Key + Source, uploaded by
	`tools/robloxloc/robloxloc.py`, which PARSES this module by regex — keep the
	`LocaleData.strings = { ... }` shape and one `["key"] = "value",` per line).

	  T(key, params?)  -- keyed lookup: Translator:FormatByKey, English fallback
	  Tr(text)         -- source lookup for server-supplied catalogue text
	                      (shop labels, queue messages): Translator:Translate

	Every player-facing string in client code MUST go through T/Tr — never
	hardcode text in modules/subs. Register new keys in
	docs/registries/data-keys.md. Full contract: docs/features/localization.md.

	Never throws, never yields: the translator loads asynchronously and both
	resolvers serve the English template until (and if) it lands, so a slow or
	offline cloud table degrades to English instead of stalling a render.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Log = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Log"))

local SCOPE = "LocaleData"

local LocaleData = {}

local translator -- Translator for the local player; nil until the async load lands

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
	["menu-cakes"] = "Cakes",
	-- Menu labels sit in a 22px-tall zone under the icon and TextScaled binds on
	-- WIDTH, so they are kept to ONE short word — "Invite Friends" renders at
	-- roughly half the size of "Shop" beside it.
	["menu-invite"] = "Invite",
	["menu-group"] = "Reward",
	-- window titles
	["title-settings"] = "Settings",
	["title-daily-rewards"] = "Daily Rewards",
	["title-shop"] = "Shop",
	["title-codes"] = "Codes",
	["title-pets"] = "Squishies",
	["title-upgrades"] = "Upgrades",
	["title-cakes"] = "Choose a Cake",
	-- Cake selection (features/cake-select.md). This is the ONLY requirement copy
	-- for a locked choice: the portrait chooser puts it in-card, while matchmaking
	-- shows it once in the contextual gallery notice. It names how to earn access;
	-- the BADGE GLYPH carries the locked state, so there is no generic "Locked"
	-- label and this feature does not use `btn-locked`.
	["cake-name-classic"] = "Classic Cake",
	["cake-name-rainbow"] = "Rainbow Cake",
	["cake-unlock-hint"] = "Finish a cake to unlock!",
	-- The teaser slot. "???" is the NAME on purpose (it reads in every language
	-- and needs no translation to work); the status line carries the message.
	["cake-name-soon"] = "???",
	["cake-status-soon"] = "Coming Soon!",
	-- lobby match selector
	["match-title"] = "Choose a Match",
	["match-difficulty-heading"] = "Difficulty",
	["match-players-heading"] = "Party Size",
	["match-cake-heading"] = "Cake",
	["match-difficulty-easy"] = "Easy",
	["match-difficulty-medium"] = "Medium",
	["match-difficulty-hard"] = "Hard",
	["match-difficulty-easy-detail"] = "Relaxed pace",
	["match-difficulty-medium-detail"] = "More layers, better rewards",
	["match-difficulty-hard-detail"] = "Most layers, best rewards",
	["match-reward-multiplier"] = "{n}x",
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
	-- ⚠ "BOSS" / "MINI-BOSS" were retired 2026-08-13: generic arcade words in a
	-- game about eating cake. The finale is the CAKE MONSTER, a zone gate is a
	-- CRUMB MONSTER. Only the PLAYER-FACING words changed — the phase strings
	-- ("boss"/"miniboss"), announce keys, analytics steps, SFX names and the
	-- authored `Assets.MiniBosses` rigs all keep their ids on purpose.
	["cake-boss"] = "CAKE MONSTER! {timer}s",
	-- ZONE GATE (features/cake-cycle.md). NO timer in the copy: a crumb monster
	-- is untimed on purpose, and a countdown would read as a fight you can lose.
	["cake-miniboss"] = "CRUMB MONSTER! EAT IT!",
	["cake-reward"] = "SQUISHY TIME!",
	["cake-spawning"] = "NEW CAKE IN {timer}s",
	["announce-new-cake"] = "A fresh cake rolled in!",
	["announce-rare-cake-golden"] = "GOLDEN CAKE! x3 calories!",
	["announce-rare-cake-rainbow"] = "RAINBOW CAKE! Epic squishy guaranteed!",
	["announce-boss-spawned"] = "The Cake Monster wakes up!",
	-- Kept as the SUBTITLE under the random cheer (features/food-burst.md): the
	-- cheer is the feeling, this line is the fact that you just earned something.
	["announce-cake-cleared"] = "Cake cleared! Everyone gets a squishy!",
	["announce-layer-locked"] = "Eat the top layer first!",
	-- ⚠ FALLBACK ONLY since 2026-08-13. A layer clear normally shows one of the
	-- `announce-layer-cheer-*` rolls below; this generic line is what
	-- `LocaleData.RollCheer` returns when a cheer list is empty, so the beat is
	-- never silent (R8).
	["announce-layer-cleared"] = "LAYER CLEARED!",
	-- Zone gates (features/cake-cycle.md): a crumb monster bursts out of the cake
	-- between two flavour zones and the cake stays locked until it is beaten.
	["announce-miniboss-spawned"] = "SOMETHING BURST OUT OF THE CAKE!",
	-- ⚠ FALLBACK ONLY since 2026-08-13: a crumb monster's death now takes the
	-- celebration splash and rolls `announce-crumb-cheer-*` (of which this is
	-- also cheer 1). Kept as its own key because `RollCheer` needs a fallback.
	["announce-miniboss-defeated"] = "CRUMB MONSTER DOWN! DIG DEEPER!",
	-- CHEERS (features/food-burst.md). The layer-clear beat fires ~28-42 times
	-- per cake, so ONE fixed line goes stale inside the first ten minutes: the
	-- banner rolls one of these instead. They are deliberately short — the
	-- banner sets them at one line, and a long phrase shrinks to unreadable on
	-- a phone. Adding a cheer = add the key AND bump the count in
	-- `LocaleData.cheerCounts`; the roll walks 1..count and a gap would show the
	-- raw key on screen.
	["announce-layer-cheer-1"] = "LAYER DEMOLISHED!",
	["announce-layer-cheer-2"] = "NOM NOM NOM!",
	["announce-layer-cheer-3"] = "ONE LAYER DOWN!",
	["announce-layer-cheer-4"] = "NOTHING BUT CRUMBS!",
	["announce-layer-cheer-5"] = "LICKED CLEAN!",
	["announce-layer-cheer-6"] = "THAT WAS DELICIOUS!",
	["announce-layer-cheer-7"] = "BIG BITE!",
	["announce-layer-cheer-8"] = "SUGAR RUSH!",
	["announce-layer-cheer-9"] = "GONE IN SECONDS!",
	["announce-layer-cheer-10"] = "MORE CAKE, PLEASE!",
	["announce-layer-cheer-11"] = "CRUMBS EVERYWHERE!",
	["announce-layer-cheer-12"] = "TASTY!",
	["announce-layer-cheer-13"] = "KEEP DIGGING!",
	["announce-layer-cheer-14"] = "WHAT A MOUTHFUL!",
	["announce-layer-cheer-15"] = "SWEET!",
	["announce-layer-cheer-16"] = "ATE THE WHOLE THING!",
	["announce-layer-cheer-17"] = "YUMMY!",
	["announce-layer-cheer-18"] = "LAYER WIPED OUT!",
	["announce-layer-cheer-19"] = "SO GOOD!",
	["announce-layer-cheer-20"] = "ANOTHER ONE EATEN!",
	-- A CRUMB MONSTER (zone gate) dying is the mid-tier beat: it happens 4x a
	-- cake, so it needs its own voice — "dig deeper" energy rather than the
	-- finale's "it's over" energy. `announce-miniboss-defeated` is cheer 1 AND
	-- the fallback, so the two can never disagree.
	["announce-crumb-cheer-1"] = "CRUMB MONSTER DOWN! DIG DEEPER!",
	["announce-crumb-cheer-2"] = "GATE SMASHED!",
	["announce-crumb-cheer-3"] = "ATE IT WHOLE!",
	["announce-crumb-cheer-4"] = "THE CAKE IS OPEN AGAIN!",
	["announce-crumb-cheer-5"] = "OUT OF MY WAY!",
	["announce-crumb-cheer-6"] = "CRUNCHED!",
	["announce-crumb-cheer-7"] = "NEXT LAYER, PLEASE!",
	["announce-crumb-cheer-8"] = "THAT ONE WAS CHEWY!",
	["announce-crumb-cheer-9"] = "GUARD? WHAT GUARD?",
	["announce-crumb-cheer-10"] = "KEEP EATING DOWN!",
	-- The Cake Monster dying is rarer and bigger, so it gets its own list.
	["announce-monster-cheer-1"] = "MONSTER MUNCHED!",
	["announce-monster-cheer-2"] = "YOU ATE THE MONSTER!",
	["announce-monster-cheer-3"] = "CAKE MONSTER DOWN!",
	["announce-monster-cheer-4"] = "TASTES LIKE VICTORY!",
	["announce-monster-cheer-5"] = "CHOMPED!",
	["announce-monster-cheer-6"] = "MONSTER? MORE LIKE DESSERT!",
	["announce-monster-cheer-7"] = "EATEN IN ONE SITTING!",
	["announce-monster-cheer-8"] = "THE CAKE IS YOURS!",
	["announce-monster-cheer-9"] = "MONSTER DEVOURED!",
	["announce-monster-cheer-10"] = "NOT A CRUMB LEFT!",
	-- Flavour ZONE names (CakeLayersConfig.groups[].nameKey) — shown over the
	-- mini-boss guarding the zone you are about to reach.
	["zone-chocolate"] = "CHOCOLATE",
	["zone-jelly"] = "JELLY",
	["zone-butter"] = "BUTTER",
	["zone-cheese"] = "CHEESE",
	["zone-jam"] = "JAM",
	["zone-sponge"] = "SPONGE",
	["zone-cream"] = "CREAM",
	["zone-candy"] = "CANDY",
	["zone-caramel"] = "CARAMEL",
	["zone-crumb"] = "CRUMBS",
	["zone-rainbow-red"] = "RED",
	["zone-rainbow-orange"] = "ORANGE",
	["zone-rainbow-yellow"] = "YELLOW",
	["zone-rainbow-green"] = "GREEN",
	["zone-rainbow-blue"] = "BLUE",
	["zone-rainbow-indigo"] = "INDIGO",
	["zone-rainbow-violet"] = "VIOLET",
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
	-- World sign over the checkpoint's upgrade computer (UpgradeStationSubsClient).
	-- Its board is hidden entirely at 0, so this string never has to read as "none".
	["station-available"] = "{n} Available",
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
	-- The shop's Free row is an ENTRY POINT into the community-reward panel now,
	-- not a claim — so its copy advertises the boost the panel explains.
	["sub-group-reward"] = "Like + join for a free boost!",
	["sub-group-join-first"] = "Join the group, then claim again!",
	-- Invite Friends (features/referrals.md)
	["title-invite"] = "Invite Friends",
	["invite-headline"] = "{n} Gems Per Friend!",
	["invite-body"] = "Invite a friend. When they join the game, you get {n} Gems — no limit.",
	["invite-button"] = "INVITE FRIENDS",
	["invite-count"] = "{n} friends joined so far",
	["invite-count-none"] = "No friends have joined yet",
	["invite-sent"] = "Invites sent! Gems land when they join.",
	["invite-unavailable"] = "Invites aren't available right now.",
	-- Community + like reward (features/group-reward.md)
	["title-group-reward"] = "Free Boost",
	["group-headline"] = "Like + Join = Free Boost",
	["group-body"] = "Like the game and join our community to get a 15 minute x2 Calories boost!",
	["group-button"] = "GET REWARD",
	-- The one message the reward is built around. Shown in RED on every claim —
	-- for a member and a non-member alike — because Roblox exposes no way to
	-- verify a like, so the wait IS the verification (features/group-reward.md).
	["group-wait"] = "Like the game and wait {n} seconds.",
	["group-not-in-group"] = "Join the community first, then try again.",
	["group-granted"] = "Boost activated! Enjoy your x2 Calories.",
	["group-claimed"] = "Already claimed — thanks for the support!",
	["group-unconfigured"] = "This reward isn't available right now.",
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

--API
-- How many `announce-<kind>-cheer-N` rolls exist per celebration kind
-- (features/food-burst.md). It lives here, next to the strings it counts, so
-- adding a cheer is ONE file: a count that drifts above the real number puts a
-- raw `announce-layer-cheer-21` on screen.
LocaleData.cheerCounts = {
	layer = 20,
	crumb = 10,
	monster = 10,
}

-- Keys FormatByKey has already failed on. Two jobs: it keeps R8's "warn once
-- per key" honest, and it skips a pcall-that-always-throws on the render path
-- (AppRoot issues ~100 T calls per pass). Cleared when the translator lands,
-- since a different translator has a different answer.
local formatMissing: { [string]: boolean } = {}
local missingSummaryShown = false

local readyCallbacks: { () -> () } = {}

--API
-- `true` once the translator has landed. Before that every string is English.
LocaleData.ready = false

--API
-- Run `fn` when the translator lands (immediately if it already has). The UI
-- MUST re-render at that point: anything painted earlier is English and would
-- stay English until an unrelated state patch happened to repaint it — for a
-- non-English player that is the whole first screen. Consumed by
-- LocaleSubsClient, which owns the actual re-render (R4).
function LocaleData.OnReady(fn: () -> ())
	if LocaleData.ready then
		task.spawn(fn)
		return
	end
	table.insert(readyCallbacks, fn)
end

function LocaleData.Init()
	-- Async: the cloud table download takes a moment, and legitimately fails in
	-- an unpublished/offline place. Until it lands, T/Tr serve the English
	-- templates above — a render path must NEVER block on translation.
	-- R8: "everything is English" is a dangerous silent state, so every way of
	-- reaching it is reported — the throw below, and the HANG via GraceOnce
	-- (GetTranslatorForPlayerAsync yields; if it never returns, neither branch
	-- of the pcall runs and nothing would otherwise be logged at all).
	Log.GraceOnce(SCOPE, "locale-translator-late", 15, function()
		return translator == nil
	end, "no translator after 15s — ALL text stays English (docs/features/localization.md)")
	task.spawn(function()
		local ok, result = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
		end)
		if ok and result ~= nil then
			translator = result
			table.clear(formatMissing)
			LocaleData.ready = true
			Log.Info(SCOPE, `translator ready — locale '{result.LocaleId}'`)
			for _, fn in ipairs(readyCallbacks) do
				local fired, err = pcall(fn)
				if not fired then
					Log.Warn(SCOPE, `locale-ready callback FAILED — UI may stay English: {err}`)
				end
			end
			table.clear(readyCallbacks)
		else
			Log.Warn(SCOPE, `no translator ({result}) — ALL text stays English`)
		end
	end)
end

--API
-- Translated + formatted string for a LocaleData key. `params` is a dictionary
-- matching the {braces} in the template. Never throws; falls back to English.
function LocaleData.T(key: string, params: { [string]: any }?): string
	-- Keys come from config fields (`def.nameKey`, `difficulty.labelKey`); a
	-- producer that forgets one would otherwise throw on the `formatMissing[key]`
	-- write BELOW — inside a React render, taking the whole tree down over one
	-- label. Degrade to empty text instead.
	if type(key) ~= "string" or key == "" then
		Log.Once(SCOPE, "locale-nil-key", `T() called with a non-string key ({typeof(key)}) — a config field is missing its *Key`)
		return ""
	end
	local text = LocaleData.strings[key]
	if text == nil then
		-- Once per key: dynamic keys (announce-*, pet-*) resolve inside
		-- React renders — an unregistered id would otherwise warn-spam.
		-- Namespaced: Log's once-keyspace is GLOBAL and shared with the
		-- pet/rarity ids LocalPetsService fires on.
		Log.Once(SCOPE, `locale-missing-{key}`, `missing string key '{key}'`)
		return key
	end
	-- FormatByKey renders a raw NUMBER param as "250.00" (locale decimal
	-- formatting), so numbers are stringified first. Into a COPY: callers pass
	-- tables they still own and read, and mutating them in place is a trap.
	local args
	if params then
		args = {}
		for k, v in pairs(params) do
			args[k] = if type(v) == "number" then tostring(v) else v
		end
	end
	if translator ~= nil and not formatMissing[key] then
		-- Throws on: unknown key, wrong args shape, missing param, and
		-- (surprising) sources with no translatable words such as "{n}".
		-- Every one of those falls through to the English template below.
		local ok, res = pcall(translator.FormatByKey, translator, key, args)
		if ok and type(res) == "string" and res ~= "" then
			return res
		end
		-- R8: a translator that resolved but answers nothing is the dangerous
		-- silent state here — the console would otherwise say "translator ready"
		-- while every single string fell back to English. The FIRST miss says
		-- what to do about it; after that it is one line per key.
		formatMissing[key] = true
		if not missingSummaryShown then
			missingSummaryShown = true
			Log.Warn(
				SCOPE,
				`FormatByKey found no cloud row for '{key}' — if this repeats for every key the localization table was never pushed (run: python tools/robloxloc/robloxloc.py push). Falling back to English.`
			)
		else
			Log.Once(SCOPE, `locale-fmt-{key}`, `no cloud row for key '{key}' — English fallback`)
		end
	end
	if args then
		text = string.gsub(text, "{(%w[%w_%-]*)}", function(name)
			local value = args[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	end
	return text
end

--API
-- Source-string translation for catalogue text that arrives as DATA rather than
-- as a key: shop labels/descriptions (ShopData), queue status and error
-- messages (LobbyQueue.Protocol). Those sources live in the cloud table as
-- keyless rows — see localization/static_entries.json and the `catalogues`
-- harvest rule. Falls back to the text itself.
function LocaleData.Tr(text: string?): string?
	if type(text) ~= "string" or text == "" or translator == nil then
		return text
	end
	local ok, res = pcall(translator.Translate, translator, game, text)
	if ok and type(res) == "string" and res ~= "" then
		return res
	end
	return text
end

--API
-- Rolls one celebration cheer and returns its ANNOUNCE SUFFIX — e.g.
-- `"layer-cheer-7"`, which the banner resolves as `announce-layer-cheer-7`
-- (features/food-burst.md). Returns a suffix rather than the finished text on
-- purpose: the announce pipeline carries a KEY through React state, so the
-- phrase must survive a re-render and a locale-ready repaint without rerolling
-- — a resolved string would be re-picked on every repaint and the banner would
-- flicker through four phrases while it is on screen.
--
-- `fallbackKey` is what a caller shows if the list is empty or miscounted; the
-- beat is a rhythm beat and must never go silent (R8).
function LocaleData.RollCheer(kind: string, fallbackKey: string): string
	local count = LocaleData.cheerCounts[kind]
	if type(count) ~= "number" or count < 1 then
		Log.Once(
			SCOPE,
			`locale-cheer-{kind}`,
			`no cheer list for '{kind}' — falling back to '{fallbackKey}' (add one to LocaleData.cheerCounts)`
		)
		return fallbackKey
	end
	return `{kind}-cheer-{math.random(count)}`
end

return LocaleData
