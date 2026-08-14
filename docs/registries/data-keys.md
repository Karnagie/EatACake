# Registry: data keys

> Uniqueness index ONLY — check here before naming something new. Field
> shapes and semantics live in the owning file (source of truth) and the
> feature doc, not here.

## Profile sections

| Key | Source of truth | Feature doc |
|---|---|---|
| `core` | `ProfileSchema/CoreSection.lua` | `features/settings.md` (settings map) |
| `economy` | `ProfileSchema/EconomySection.lua` (v2: calories+gems) | `features/economy.md` — ⚠ `calories` is RUN-scoped (reset each load, ADR-0013); `gems` is meta |
| `stomach` | `ProfileSchema/StomachSection.lua` | `features/body-gym.md` — RUN-scoped (ADR-0013) |
| `upgrades` | `ProfileSchema/UpgradesSection.lua` (v2: level→tier rescale) | `features/upgrades.md` — ⚠ RUN-scoped: `levels` wiped on every profile load (ADR-0013) |
| `pets` | `ProfileSchema/PetsSection.lua` | `features/pets.md` |
| `progress` | `ProfileSchema/ProgressSection.lua` | `features/game-round.md` (`rebirths` legacy/always 0; `foundKinds` = buried-find discovery set, `features/treasures.md`; `activeBoosts`, `features/boosts.md`; `lifetimeGems` + `bestCakeMillis` feed the in-world boards, `features/leaderboards.md` — added 2026-08-14 with defaults, no version bump per P2) |
| `dailyRewards` | `ProfileSchema/DailyRewardsSection.lua` | `features/daily-rewards.md` |
| `social` | `ProfileSchema/SocialSection.lua` (v1; `referredBy` + `referralsRewarded` ADDED with defaults — no migration, P2) | `features/group-reward.md` + `features/referrals.md` |
| `shop` | `ProfileSchema/ShopSection.lua` | `features/shop.md` |
| `codes` | `ProfileSchema/CodesSection.lua` | `features/promo-codes.md` |
| `tutorial` | `ProfileSchema/TutorialSection.lua` | `features/tutorial.md` — one-time `done` flag; deliberately NOT run-scoped (ADR-0013) |
| `cakes` | `ProfileSchema/CakesSection.lua` | `features/cake-select.md` — NOT run-scoped (survives the teleport); ⚠ no `unlocked` key here, entitlement is DERIVED per push |

Reserved: `__schema` (managed by PersistenceService).

## DataStore names (NOT profile stores)

| Name | Owner | Doc |
|---|---|---|
| `PersistenceData.storeName` (the ProfileStore store) | `PersistenceService` | `features/persistence.md` |
| `EatACakeTop_gems_v1` / `EatACakeTop_speedrun_v1` / `EatACakeTop_cakes_v1` | `GlobalLeaderboardService` (the ONLY direct `DataStoreService` user besides ProfileStore — ADR-0022) | `features/leaderboards.md` |

⚠ Built as `<storePrefix><board id>_v<storeVersion>` in `GlobalLeaderboardData`.
The version suffix is the ONLY way to wipe a board; bump it if a stat's units
change, never reuse an old name for different units.
Retired 2026-07-31, do NOT reuse the key: `quests`, `timeRewards` (still present
as orphan top-level keys in old saves — `features/persistence.md`).

## Reward descriptor kinds

| Kind | Registered by | Doc |
|---|---|---|
| `calories` | `RewardGrantSubs` (built-in) | ADR-0002, `features/economy.md` |
| `gems` (`rawAmount` opt) | `RewardGrantSubs` (built-in) | `features/economy.md` |
| `boost` (`boostId`) | `RewardGrantSubs` (built-in) | `features/boosts.md` |
| `burn` | `BodySubs` | `features/body-gym.md` |
| `eatlayer` | `CakeSubs` (GAME partition only) | `features/checkpoint.md` — clears the active cake layer + pays its calories |
| `egg` (`eggType`) | `PetSubs` | `features/pets.md` |

## Setting ids (profile `core.settings` = the whitelist)

`music-enabled`, `sfx-enabled` — must match in `CoreSection.lua` AND
`src/client/common/data/SettingsData.lua`.

## Shop keys / codes / boosts / eggs

Products: `starterpack`, `layer-eater` (HIDDEN — no shop cell; sold by the
checkpoint `LayerEaterPrompt`, `features/checkpoint.md`), `boost-15m`,
`boost-bite`, `boost-speed`,
`boost-capacity`, `gems-s/m/l/xl`; gamepasses: `x2calories`, `x2gems`,
`autoeat`, `autogym`, `capacity2`, `vip` (`ShopData.lua`). Codes: `WELCOME`,
`EATCAKE`, `SIXSEVEN` (`CodesData.lua`). Boost DEF ids (≠ the product keys):
`boost-15m`, `bite-15m`, `speed-15m`, `capacity-15m` (`TreasureConfig.boosts`,
`features/boosts.md`) — the deleted `golden-slice` boost def is NOT free to
reuse as a boostId: the name still belongs to a FIND
(`TreasureConfig.finds`). Egg types: `cycle`, `lucky`,
`mega`, `epic7` (`PetConfig.eggs`). Row-id prefixes over the wire: `product:` /
`pass:` / `group`. Shop section ids (client grouping): `featured`, `passes`,
`boosts`, `gems`, `free`; cell kinds: `banner`, `hero`, `card`, `smallcard`
(+ retired `tile`, `pack`); card accents: `Blue`, `Common`, `Uncommon`, `Rare`,
`Epic`, `Legendary`, `Secret`; price-button states: `buy`, `owned`,
`unavailable`, `unaffordable`. Product currencies: `robux` (default when
`currency` is absent), `gems`.

## Icon names (`src/shared/UIKit/Icons.lua` = source of truth)

Flat `name -> rbxassetid`, resolved via `Theme.Icon(name)` (warns once + visible
fallback on a miss). Prefixes: `Ui*` UI glyphs · `Badge*` heavier line glyphs ·
`Pass*` gamepass badges · `RarityDisc*` / `RarityStar*` per tier · `Ribbon*`
(square rosette art — NOT usable as a 4:1 sash) · `GemPack{S,M,L,XL}`,
`CoinPack{S,M,L,XL}`, `Egg1..8` · `Sq*` the squishy roster · `TutorialSlide1..4` (the onboarding comic — ORDER IS
LOAD-BEARING, they are one story) · `Food*` the 33 celebration-confetti glyphs
(their GROUPING lives in `JuiceConfig.foodBurstGroups`, by name —
`features/food-burst.md`). Add new rows there, not here.

## Shared config modules (ADR-0004)

`CakeConfig`, `UpgradeConfig`, `UpgradeTreeConfig` (honeycomb layout),
`BodyConfig`, `PetConfig`, `TreasureConfig`, `JuiceConfig`, `PlaceConfig`,
`MatchConfig`, `TutorialConfig`, `AnalyticsConfig` — `src/shared/config/`.
Shared util: `HexUtil` (axial hex math, sibling to `GridUtil`).

## Analytics names (`src/shared/config/AnalyticsConfig.lua` = source of truth)

⚠ QUOTA'd experience-wide and spent FOREVER on first send: **100** custom event
names, **10** funnel names. Never write a literal — add a catalog key and pass
the key (`features/analytics.md`, ADR-0017). Occupancy is logged at boot by
`Validate()`.

Funnels: `PlayerFlow`, `Matchmaking`, `Tutorial`, `Match`, `CakeLayers`, `Shop`,
`Upgrades`, `GymBurn`, `Finds` (**1 slot deliberately free** — an 11th funnel is
dropped silently). Flow-step keys are `AnalyticsConfig.flowSteps` (31, ordered);
`CakeLayers` step keys are GENERATED (`l1`..`l{maxLayerDepth}`, N = layers cleared).
Event names, currencies (`Calories`, `Gems`, `Robux`) and transaction types are
`AnalyticsConfig.events` / `.economy`.

## ProximityPrompt names (unique — clients filter PromptTriggered by name)

`GymPrompt` (gym start, server `BodySubs`), `UpgradeStation` (open the upgrades
hex-tree, client `UpgradesSubsClient`; ALSO enters the tutorial's last step —
completion is the first PURCHASE, `features/tutorial.md`), `LayerEaterPrompt`
(offer the 9 R$ `layer-eater`
product, client `ShopSubsClient`, `features/checkpoint.md`) — all three defined
in `MapConfigData.checkpoint` (`promptName` / `upgradePromptName` /
`layerEaterPromptName`). ⚠ A prompt handled CLIENT-side is written down TWICE:
once server-side in `MapConfigData` (which builds it) and once in the client data
module that listens for it (`UpgradesUiData`, `ShopUiData`). Rename in both.

## Authored world-instance contracts read by the CLIENT

Named instances under `workspace.Map.Checkpoint` that a client subscription
resolves by name. Place content (ADR-0007) — none of it is in the repo, so the
NAME is the whole contract.

| Path (under the Checkpoint clone) | Read by | Doc |
|---|---|---|
| `CheckpointPlate` | `BodySubsClient` (near/far), `TutorialSubsClient` (beam target) | `features/checkpoint.md` |
| `GymMachine` + its ProximityPrompt | `BodySubsClient` (local prompt gate) | `features/body-gym.md` |
| `UpgradeStationBody` | `TutorialSubsClient` (arrow target) | `features/tutorial.md` |
| `UpgradeStationBody.AvailableGui.Txt` | `UpgradeStationSubsClient` ("N Available") | `features/upgrades.md` |

⚠ `UpgradeStationBody` holds TWO BillboardGuis and BOTH their TextLabels are
named `Txt` (the other is the static "Upgrades" nameplate). Resolve by explicit
chain; a recursive `FindFirstChild("Txt", true)` relabels the wrong sign.

## Locale keys

Source of truth: `src/client/common/data/LocaleData.lua` (the strings table — the
full list lives there, not here; add new keys there and note the feature).
⚠ Keys are ALSO cloud-table identifiers now — a key rename is a table rename.
Charset is `[A-Za-z0-9_-]` (not kebab-only: `hex-name-<statId>` keys are built by
concatenation and carry camelCase). Adding a key means `push`;
`features/localization.md`.
Reserved (celebration hook pending): `toast-claimed`, `toast-claimed-gold`.
Lobby/game addition: `match-*` group (including
`match-difficulty-{easy,medium,hard}-detail` and `match-reward-multiplier`) + `announce-match-lost`
(`features/lobby-matchmaking.md`, `features/game-round.md`).
Squishy re-theme: `pet-<id>` display names pair 1:1 with `PetConfig` ids (30
entries — the KEY never changes, only the string); shop additions `btn-soon`,
`ribbon-best-value`, `ribbon-one-time`, `shop-section-gems`,
`shop-section-boosts` (`shop-section-gold` is legacy, kept for the retired
ShopRow list; `shop-section-eggs` was DELETED with the eggs). Shop tabs
(2026-07-31): `shop-tab-featured` ("Offers"), `shop-tab-passes`,
`shop-tab-boosts`, `shop-tab-gems`, plus `price-robux-short` ("{n}") and
`price-gems-short` ("{n}") — the glyph-less amounts the card price shelf uses,
because the shelf draws the currency icon itself. `price-robux` ("R$ {n}") is
now RESERVED: no call site, kept for a future glyph-less context (a chat
message, a toast). Upgrade station sign (2026-08-05): `station-available`
("{n} Available") — the world BillboardGui over the checkpoint computer,
`features/upgrades.md`.
Boost names (`TreasureConfig.boosts[*].nameKey`, one per def):
`boost-15m`, `boost-bite`, `boost-speed`, `boost-capacity`
(`features/boosts.md`; `label-boost` is the shorter daily-card alias for the
calories one).
Buried finds: `announce-find-rare` / `-epic` / `-legendary` (rare+ only — a
banner per find would be noise); `find-<id>` names pair 1:1 with
`TreasureConfig.finds` ids (`features/treasures.md`).
Cake rhythm: `announce-layer-cleared` (FALLBACK only since 2026-08-13 — a layer
clear normally rolls one of `announce-layer-cheer-1..20`); `cake-finds`
("FINDS n/N", the per-cake goal the HUD bar carries while eating —
`features/treasures.md`).
Celebration cheers (`features/food-burst.md`): `announce-layer-cheer-1..20`,
`announce-crumb-cheer-1..10` (zone gate) and `announce-monster-cheer-1..10`
(the finale), rolled by `LocaleData.RollCheer`. ⚠ The count of
each list is declared in `LocaleData.cheerCounts` — adding a phrase means adding
the key AND bumping that number, or the roll can land on a key that is not there.
Boss: `cake-boss` / `cake-miniboss` are the HUD bar labels — player-facing text
became CAKE MONSTER / CRUMB MONSTER on 2026-08-13; the KEY names still say boss
on purpose (renaming them would orphan every cloud row). No timer in the
mini-boss copy: a crumb monster is untimed. Also `announce-boss-spawned`,
`announce-miniboss-spawned`, `announce-miniboss-defeated`, and the ten ZONE names
`zone-{chocolate,jelly,butter,cheese,jam,sponge,cream,candy,caramel,crumb}`
(`CakeLayersConfig.groups[].nameKey`, shown over the boss guarding that zone).
Selectable rainbow zones add
`zone-rainbow-{red,orange,yellow,green,blue,indigo,violet}`
(`CakeLayersConfig.rainbowGroups`, `features/cake-cycle.md`).
⚠ `boss-prize-caption` was RETIRED 2026-08-07 with the prize preview — do not
re-add it; the fight no longer advertises what it pays (`features/cake-cycle.md`).
Social offers (2026-08-05): `menu-invite`, `menu-group` (ONE short word each —
the menu label zone is 22px tall and TextScaled binds on width); Invite Friends
`title-invite`, `invite-headline`, `invite-body`, `invite-button`,
`invite-count`, `invite-count-none`, `invite-sent`, `invite-unavailable`
(`features/referrals.md`); community reward `title-group-reward`,
`group-headline`, `group-body`, `group-button`, `group-wait` ("Like the game and
wait {n} seconds." — `{n}` comes from the server's `waitSeconds`, never
hardcoded), `group-not-in-group`, `group-granted`, `group-claimed`,
`group-unconfigured` (`features/group-reward.md`).
Onboarding (`features/tutorial.md`): `tutorial-title`, `tutorial-skip`,
`tutorial-eat-title`, `tutorial-eat-body-pc` / `-touch` (one per input device,
picked by `IS_TOUCH`), `tutorial-eat-ok`. The touch glyph re-uses `eat-button`
so the hint and the real HUD button can never disagree.
⚠ `tutorial-arrow-upgrades` is ORPHANED since 2026-08-09 (the HintArrow it
labelled was replaced by a world beam). Kept in `LocaleData` on purpose: it is
already in the pushed cloud table, and deleting a key is a `localization/`
baseline change, not a code one — remove both together or not at all.
Cake select (`features/cake-select.md`): `menu-cakes`, `title-cakes`,
`match-cake-heading` (grouped with the other `match-*` keys in `LocaleData`),
`cake-name-classic`, `cake-name-rainbow`, `cake-unlock-hint`,
`cake-name-soon`, `cake-status-soon` (the teaser slot). ⚠ This feature does NOT
use `btn-locked` — a locked cake card shows its badge glyph plus its own
`cake-unlock-hint`/`cake-status-soon` line, never the bare word "Locked".

## Authored instance names (place-authored, resolved by exact name)

`Workspace.Items` → migrated to `ReplicatedStorage.Assets.Items` on boot: the
buried-find MODEL LIBRARY, one Model/BasePart per child; a child's NAME is what
`TreasureConfig.finds[].model` pins (`features/treasures.md`, ADR-0012).
`ReplicatedStorage.Assets.Environment` / `.Environment1` / `.Checkpoint` —
MapService (ADR-0007, ADR-0020). The selected clone is always mounted at
`workspace.Map.Environment`; its template name is runtime state, not a path.
`ReplicatedStorage.Assets.GuidanceTemplates.HintBeam` — the Beam the tutorial
CLONES for its guidance line (`features/tutorial.md`); `CheckpointPlate` is its
target and `UpgradeStationBody` the arrow's.
`ReplicatedStorage.Assets.LobbyEnvironment.{TopGems,TopSpeedrunners,TopCakeCount}`
— the three in-world leaderboards, owner `LobbyLeaderboardSubs`; the row-template
path and the per-board label names are `features/leaderboards.md`.

## Cross-place protocol ids

Persistence metadata: `teleport-release-nonce` (`PersistenceService`,
`features/persistence.md`). Difficulties: `easy`, `medium`, `hard`; queue actions:
`configure`, `leave`; queue updates: `open`, `close`, `error`, `busy`; teleport
kind: `match-result`; results: `win`, `loss` (ADR-0010 / matchmaking docs).
Selectable cake ids: `cake-classic`, `cake-rainbow`; `cake-coming-soon` is a
catalogue-only teaser and not a playable variant. Protocol-v2 lobby→game
TeleportData carries `cakeId`; game runtime stores it as `RoundStateData` key
`cake-id` (`features/cake-select.md`, ADR-0020).
Client movement-lock reasons: `teleport-handoff`, `upgrade-overlay`
(`PlayerControlData`, `features/persistence.md`).

## Config modules

| Module | Doc |
|---|---|
| `PersistenceData` | `features/persistence.md` |
| `CakeConfigData` (+anti-cheat) | `features/cake-sim.md` |
| `CakeStateData` (runtime) | `features/cake-sim.md` |
| `MapConfigData` | header of `services/MapService.lua` |
| `PlayerRuntimeData` (runtime) | `features/body-gym.md` |
| `DailyRewardsData` | `features/daily-rewards.md` |
| `SocialData` (lobby) | `features/group-reward.md` + `features/referrals.md` |
| `ShopData` | `features/shop.md` |
| `CodesData` | `features/promo-codes.md` |
| `SettingsData` (client) | `features/settings.md` |
| `LobbyQueueData` (lobby runtime) | `features/lobby-matchmaking.md` |
| `RoundStateData` (game runtime) | `features/game-round.md` |
| `TeleportData` (common runtime) | `features/persistence.md` |
| `PlayerControlData` (client movement-lock runtime) | `features/persistence.md` |
| `LobbyUiData` / `GameUiData` (client place markers) | `features/lobby-matchmaking.md` |
| `MatchConfig` (shared queue/round contract) | `features/lobby-matchmaking.md` |
