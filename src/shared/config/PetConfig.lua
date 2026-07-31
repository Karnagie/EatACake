--[[
	PetConfig — the SQUISHY roster, rarity odds and egg types (GDD §9).

	"Pets" are squishies: squishy toys shaped like food. The module name, the
	remote names and every `id` below keep the pet-* naming ON PURPOSE — an `id`
	is a DataStore key inside the profile's `pets.owned` map, so renaming one
	orphans a player's collection. Only DISPLAY names changed; ids are forever.
	Adding a NEW id is safe and needs no migration (it is simply absent from
	everyone's `owned` map) — which is how this roster grew from 12 to 30.

	ODDS ARE PLAYER-FACING: the UI must display them verbatim (Roblox policy
	for paid random rewards; good practice for free ones). PetService is the
	ONLY consumer of the weights — rolls happen on the server, never on the
	client (GDD §13). Adding squishies to a tier does NOT change that tier's
	odds; it splits the tier's share across more entries.

	Duplicates merge automatically: owning N copies = pet level N, bonus is
	scaled by (1 + mergeBonusPerCopy * (N - 1)).

	`icon` is a Theme.Icons key (src/shared/UIKit/Icons.lua), named explicitly
	instead of derived from the id, so a typo warns instead of silently
	rendering the fallback glyph.

	`model` is the name of a child of PLACE-AUTHORED `ReplicatedStorage.Assets.
	Squishes` (ADR-0007 content, not Rojo content) — the 3D body the follower
	flies with (`PetFollowers`). Named explicitly for the same reason as `icon`:
	`PetFollowers` warns ONCE per unknown name instead of silently rendering
	nothing. ⚠ The 48 assignments below are a VISUAL best-effort match of the
	50 authored models to the 48 `Sq*` icons (the two sets ship from the same
	art pack but the models are named "Squishy N", so nothing in the data links
	them). The distinctive ones — crown, halo, rainbow, devil, void cup,
	officer, firefighter, viking, sombrero, suit, galaxy ring, stripe shell,
	butter cup, shades, straw hat, ember, both bonsai — are exact; the plain
	colour drops are matched by hue and are the ones worth re-checking. Fixing
	one is a ONE-FIELD edit here and nothing else. Models 34 and 48 are unused.
]]

local PetConfig = {}

-- Displayed as percentages in the reveal / egg UI. Must sum to 100.
-- Colour is NOT here: Theme.Rarity is the single source of rarity colour, and
-- this second palette disagreed with it (it called Common grey while the kit
-- drew Common blue). Verified unused — PetService and LocalPetsService read
-- only `.id` and `.weight`.
PetConfig.rarities = {
	{ id = "common", weight = 60 },
	{ id = "uncommon", weight = 25 },
	{ id = "rare", weight = 10 },
	{ id = "epic", weight = 4 },
	{ id = "legendary", weight = 0.9 },
	{ id = "secret", weight = 0.1 },
}

-- bonus values are PERCENT (0.05 = +5%), aggregated over equipped pets by
-- StatsService. `look` (shape: "ball"|"cube"|"donut", color) is the FALLBACK
-- primitive the follower flies with when `model` cannot be resolved from
-- `ReplicatedStorage.Assets.Squishes` — a visible wrong shape beats an
-- invisible pet (R8). The real body is `model`.
-- The primary stat ROTATES within each tier (calories -> eatSpeed -> gems) so
-- no tier is a dead end for a build and Equip-Best always has a real choice.
PetConfig.pets = {
	-- ===== common — the pick-and-mix shelf =====
	{ id = "crumb-mouse", nameKey = "pet-crumb-mouse", model = "Squishy 3", icon = "SqIceCup", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(190, 160, 130) } },
	{ id = "sugar-chick", nameKey = "pet-sugar-chick", model = "Squishy 4", icon = "SqIceCupWink", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(255, 230, 120) } },
	{ id = "jelly-slug", nameKey = "pet-jelly-slug", model = "Squishy 5", icon = "SqIceCupCalm", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(220, 90, 110) } },
	{ id = "berry-gummy", nameKey = "pet-berry-gummy", model = "Squishy 9", icon = "SqAquaDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(228, 62, 82) } },
	{ id = "lime-gummy", nameKey = "pet-lime-gummy", model = "Squishy 12", icon = "SqMintDrop", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(120, 220, 110) } },
	{ id = "lemon-gummy", nameKey = "pet-lemon-gummy", model = "Squishy 22", icon = "SqBlushPink", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(250, 220, 90) } },
	{ id = "loop-pop", nameKey = "pet-loop-pop", model = "Squishy 27", icon = "SqOceanDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(255, 150, 200) } },

	-- ===== uncommon — the bakery counter =====
	{ id = "frosting-cat", nameKey = "pet-frosting-cat", model = "Squishy 10", icon = "SqLilacDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "donut", color = Color3.fromRGB(255, 200, 225) } },
	{ id = "cocoa-pup", nameKey = "pet-cocoa-pup", model = "Squishy 11", icon = "SqSunsetDrop", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(120, 75, 45) } },
	{ id = "candy-crab", nameKey = "pet-candy-crab", model = "Squishy 40", icon = "SqStoneLoaf", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(255, 120, 90) } },
	{ id = "top-muffin", nameKey = "pet-top-muffin", model = "Squishy 36", icon = "SqPeachGlow", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(196, 150, 105) } },
	{ id = "flake-crescent", nameKey = "pet-flake-crescent", model = "Squishy 23", icon = "SqCreamWink", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(235, 190, 120) } },
	{ id = "blue-drop", nameKey = "pet-blue-drop", model = "Squishy 29", icon = "SqMintGlow", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(110, 190, 255) } },
	{ id = "peppermint-stick", nameKey = "pet-peppermint-stick", model = "Squishy 8", icon = "SqGrapeDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "cube", color = Color3.fromRGB(255, 255, 255) } },

	-- ===== rare — the patisserie =====
	{ id = "caramel-fox", nameKey = "pet-caramel-fox", model = "Squishy 31", icon = "SqPlumSparkle", rarity = "rare", bonus = { calories = 0.2, eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(220, 140, 50) } },
	{ id = "waffle-owl", nameKey = "pet-waffle-owl", model = "Squishy 16", icon = "SqStrawHat", rarity = "rare", bonus = { eatSpeed = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(235, 190, 110) } },
	{ id = "rose-macaron", nameKey = "pet-rose-macaron", model = "Squishy 19", icon = "SqLeafSprout", rarity = "rare", bonus = { gems = 0.2, calories = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(255, 170, 200) } },
	{ id = "sky-macaron", nameKey = "pet-sky-macaron", model = "Squishy 21", icon = "SqBonsaiPot", rarity = "rare", bonus = { calories = 0.2, gems = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(150, 205, 255) } },
	{ id = "swirl-roll", nameKey = "pet-swirl-roll", model = "Squishy 30", icon = "SqSkyBeam", rarity = "rare", bonus = { eatSpeed = 0.2, calories = 0.05 }, look = { shape = "donut", color = Color3.fromRGB(210, 150, 90) } },
	{ id = "stack-cakes", nameKey = "pet-stack-cakes", model = "Squishy 20", icon = "SqPastelArc", rarity = "rare", bonus = { gems = 0.2, eatSpeed = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(225, 175, 105) } },

	-- ===== epic — the diner (savoury food in a cake game: the joke tier, and
	-- the one players screenshot) =====
	{ id = "gummy-dragon", nameKey = "pet-gummy-dragon", model = "Squishy 14", icon = "SqCoolShades", rarity = "epic", bonus = { calories = 0.35, gems = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(120, 230, 120) } },
	{ id = "eclair-unicorn", nameKey = "pet-eclair-unicorn", model = "Squishy 2", icon = "SqBonsaiTwist", rarity = "epic", bonus = { eatSpeed = 0.35, calories = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(240, 220, 255) } },
	{ id = "slice-supreme", nameKey = "pet-slice-supreme", model = "Squishy 6", icon = "SqEmberDrop", rarity = "epic", bonus = { gems = 0.35, eatSpeed = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(230, 140, 70) } },
	{ id = "crunch-taco", nameKey = "pet-crunch-taco", model = "Squishy 17", icon = "SqVisorVoid", rarity = "epic", bonus = { calories = 0.35, eatSpeed = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(240, 200, 110) } },
	{ id = "triple-scoop", nameKey = "pet-triple-scoop", model = "Squishy 13", icon = "SqStormCloud", rarity = "epic", bonus = { eatSpeed = 0.35, gems = 0.15 }, look = { shape = "ball", color = Color3.fromRGB(255, 210, 230) } },

	-- ===== legendary — the showpiece shelf =====
	{ id = "golden-whale", nameKey = "pet-golden-whale", model = "Squishy 15", icon = "SqCrownGold", rarity = "legendary", bonus = { calories = 0.5, eatSpeed = 0.3, gems = 0.2 }, look = { shape = "donut", color = Color3.fromRGB(255, 200, 40) } },
	{ id = "the-cake", nameKey = "pet-the-cake", model = "Squishy 7", icon = "SqHaloCup", rarity = "legendary", bonus = { eatSpeed = 0.5, gems = 0.3, calories = 0.2 }, look = { shape = "cube", color = Color3.fromRGB(255, 235, 205) } },
	{ id = "cloud-floss", nameKey = "pet-cloud-floss", model = "Squishy 26", icon = "SqRainbowDrop", rarity = "legendary", bonus = { gems = 0.5, calories = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(255, 170, 235) } },
	{ id = "ruby-berry", nameKey = "pet-ruby-berry", model = "Squishy 1", icon = "SqVoidCup", rarity = "legendary", bonus = { calories = 0.5, gems = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(240, 60, 80) } },

	-- ===== secret =====
	{ id = "void-muffin", nameKey = "pet-void-muffin", model = "Squishy 18", icon = "SqDevilWing", rarity = "secret", bonus = { calories = 1.0, eatSpeed = 0.5, gems = 0.5 }, look = { shape = "donut", color = Color3.fromRGB(40, 20, 60) } },

	-- ===== costumed set (added with the render pack; new ids need no
	-- migration, they are simply absent from every existing profile) =====
	{ id = "snow-drop", nameKey = "pet-snow-drop", model = "Squishy 25", icon = "SqSnowDrop", rarity = "common", bonus = { calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(236, 244, 250) } },
	{ id = "stripe-shell", nameKey = "pet-stripe-shell", model = "Squishy 39", icon = "SqStripeShell", rarity = "common", bonus = { eatSpeed = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(230, 240, 250) } },
	{ id = "butter-cup", nameKey = "pet-butter-cup", model = "Squishy 37", icon = "SqButterCup", rarity = "common", bonus = { gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(250, 220, 90) } },
	{ id = "lavender-drop", nameKey = "pet-lavender-drop", model = "Squishy 28", icon = "SqLavenderDrop", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(216, 196, 240) } },
	{ id = "lime-glow", nameKey = "pet-lime-glow", model = "Squishy 38", icon = "SqLimeGlow", rarity = "uncommon", bonus = { eatSpeed = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(200, 240, 120) } },
	{ id = "amber-drop", nameKey = "pet-amber-drop", model = "Squishy 35", icon = "SqAmberDrop", rarity = "uncommon", bonus = { gems = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(250, 190, 120) } },
	{ id = "blossom", nameKey = "pet-blossom", model = "Squishy 24", icon = "SqBlossom", rarity = "uncommon", bonus = { calories = 0.1 }, look = { shape = "ball", color = Color3.fromRGB(255, 170, 200) } },
	{ id = "sombrero", nameKey = "pet-sombrero", model = "Squishy 47", icon = "SqSombrero", rarity = "rare", bonus = { calories = 0.2, eatSpeed = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(240, 210, 130) } },
	{ id = "viking-helm", nameKey = "pet-viking-helm", model = "Squishy 41", icon = "SqVikingHelm", rarity = "rare", bonus = { eatSpeed = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(190, 160, 120) } },
	{ id = "green-blade", nameKey = "pet-green-blade", model = "Squishy 43", icon = "SqGreenBlade", rarity = "rare", bonus = { gems = 0.2, calories = 0.05 }, look = { shape = "ball", color = Color3.fromRGB(120, 220, 110) } },
	{ id = "suit", nameKey = "pet-suit", model = "Squishy 49", icon = "SqSuit", rarity = "rare", bonus = { calories = 0.2, gems = 0.05 }, look = { shape = "cube", color = Color3.fromRGB(60, 70, 100) } },
	{ id = "officer", nameKey = "pet-officer", model = "Squishy 45", icon = "SqOfficer", rarity = "epic", bonus = { calories = 0.35, gems = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(60, 90, 180) } },
	{ id = "firefighter", nameKey = "pet-firefighter", model = "Squishy 46", icon = "SqFirefighter", rarity = "epic", bonus = { eatSpeed = 0.35, calories = 0.15 }, look = { shape = "cube", color = Color3.fromRGB(220, 60, 60) } },
	{ id = "hazard-core", nameKey = "pet-hazard-core", model = "Squishy 42", icon = "SqHazardCore", rarity = "epic", bonus = { gems = 0.35, eatSpeed = 0.15 }, look = { shape = "donut", color = Color3.fromRGB(230, 200, 60) } },
	{ id = "ember-rage", nameKey = "pet-ember-rage", model = "Squishy 44", icon = "SqEmberRage", rarity = "epic", bonus = { calories = 0.35, eatSpeed = 0.15 }, look = { shape = "ball", color = Color3.fromRGB(255, 130, 40) } },
	{ id = "alien", nameKey = "pet-alien", model = "Squishy 33", icon = "SqAlien", rarity = "legendary", bonus = { gems = 0.5, calories = 0.3, eatSpeed = 0.2 }, look = { shape = "ball", color = Color3.fromRGB(170, 230, 120) } },
	{ id = "nebula-drop", nameKey = "pet-nebula-drop", model = "Squishy 50", icon = "SqNebulaDrop", rarity = "legendary", bonus = { calories = 0.5, eatSpeed = 0.3, gems = 0.2 }, look = { shape = "donut", color = Color3.fromRGB(150, 90, 220) } },
	{ id = "galaxy-ring", nameKey = "pet-galaxy-ring", model = "Squishy 32", icon = "SqGalaxyRing", rarity = "secret", bonus = { calories = 1.0, eatSpeed = 0.5, gems = 0.5 }, look = { shape = "donut", color = Color3.fromRGB(20, 10, 40) } },
}

PetConfig.mergeBonusPerCopy = 0.2
PetConfig.equipSlots = 3
PetConfig.equipSlotsVip = 5 -- with the VIP gamepass

-- Follower flight (client `PetFollowers`, BOTH places). Equipped squishies FLY
-- BEHIND the player on a shallow arc: they trail with a lag so a turn swings
-- them around, bob out of phase with each other, and bank into the turn.
--
-- Slot k of n sits at angle `(k - (n+1)/2) * spreadRadians` measured from
-- straight-behind, so the arc stays centred whatever the equipped count is
-- (3 base slots, 5 with VIP). `+Z` is BEHIND in Roblox object space — that is
-- why the slot offset uses `+cos`, and why the old code (which used
-- `math.pi * 0.75 + …`) actually parked every squishy in FRONT of the player.
PetConfig.follow = {
	radiusStuds = 5.0, -- distance behind the torso (clears the full-belly morph)
	spreadRadians = 0.62, -- angle between neighbouring slots along the arc
	-- BELOW the torso centre (~knee height), not above it. The gameplay camera
	-- sits behind and above the player, so a formation at chest height or higher
	-- parks itself between the camera and the character — measured in play: at
	-- +3.0 the squishies hid the player completely, at +0.8 they still covered
	-- the torso. Low and wide is also what the genre does.
	heightStuds = -0.6,

	-- Trailing. Exponential follow, framerate-independent: LOWER = laggier =
	-- more "flying after you". The whole feature lives in this number — a rigid
	-- offset reads as a part welded to the player, not as a pet.
	followRate = 5.5,

	-- Idle motion.
	bobStuds = 0.42,
	bobSpeed = 2.6,
	bobPhase = 1.7, -- radians between consecutive pets, so they never bob in sync

	-- Bank into the turn, driven by how far the squishy still is from its slot
	-- SIDEWAYS (which is exactly how hard it is currently cornering).
	bankDegreesPerStud = 9.0,
	maxBankDegrees = 28,
	bankSmoothing = 8.0,

	-- Snap instead of flying across the map: respawn, the checkpoint teleport
	-- and the lobby->game handoff all move the character discontinuously.
	snapDistanceStuds = 30,

	-- Turn to LOOK AT the player when standing still, fly facing forward when
	-- moving. Blended on the player's flat speed, so the squishies swivel round
	-- as you stop. (Forward-only shows nothing but blob backs while idle;
	-- camera-facing-only reads as flying backwards. This is why games in the
	-- genre do both.) `faceForwardSpeedStuds` is the speed at which they are
	-- fully forward-facing — WalkSpeed is 16, so this trips almost at once.
	faceForwardSpeedStuds = 6,
	facingSmoothing = 5.0,

	-- Body. `sizeStuds` is the target LARGEST bounding-box dimension; the
	-- authored models are ~10 studs, so every one is scaled to a common size.
	-- `yawOffsetDegrees` corrects where the authored FACE sits on the model.
	-- `CFrame.lookAt` puts the model's local -Z along the travel direction, and
	-- the player's RIGHT is that frame's +X. Under the old 180° offset the axis
	-- that ended up pointing at +X — what the player reads as "facing right" —
	-- was the model's -X, so the authored face lives on -X, NOT on +Z as the old
	-- note assumed. Solving R_y(theta) * (-1, 0, 0) = (0, 0, -1) gives -90°.
	-- If it comes out mirrored in play (faces backwards), +90 is the only other
	-- root of that equation, so the correction is one sign flip either way.
	-- One number fixes both poses: PetFollowers builds its yaw as
	-- `yawOffsetDegrees + 180 * (1 - facing)`, so the moving pose (facing = 1)
	-- and the idle look-at-the-player swivel (facing = 0) both ride this offset.
	sizeStuds = 2.4,
	yawOffsetDegrees = -90,
	assetsFolder = "Squishes", -- child of ReplicatedStorage.Assets (ADR-0007)
}

-- Egg types: rarity odds overrides (nil weight = use base). Lucky/Mega are
-- dev products (see ShopData); "cycle" is the FREE end-of-cake roll.
PetConfig.eggs = {
	cycle = { nameKey = "egg-cycle" }, -- base odds
	lucky = {
		nameKey = "egg-lucky",
		weights = { common = 35, uncommon = 30, rare = 20, epic = 10, legendary = 4, secret = 1 },
	},
	mega = {
		nameKey = "egg-mega",
		-- guaranteed Rare+
		weights = { common = 0, uncommon = 0, rare = 70, epic = 24, legendary = 5, secret = 1 },
	},
	epic7 = {
		nameKey = "egg-epic7",
		-- day-7 daily streak: guaranteed Epic+ (GDD §12.2)
		weights = { common = 0, uncommon = 0, rare = 0, epic = 90, legendary = 9, secret = 1 },
	},
}

return PetConfig
