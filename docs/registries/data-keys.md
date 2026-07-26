# Registry: data keys

> Uniqueness index ONLY — check here before naming something new. Field
> shapes and semantics live in the owning file (source of truth) and the
> feature doc, not here.

## Profile sections

| Key | Source of truth | Feature doc |
|---|---|---|
| `core` | `ProfileSchema/CoreSection.lua` | `features/settings.md` (settings map) |
| `economy` | `ProfileSchema/EconomySection.lua` (v2: calories+gems) | `features/economy.md` |
| `stomach` | `ProfileSchema/StomachSection.lua` | `features/body-gym.md` |
| `upgrades` | `ProfileSchema/UpgradesSection.lua` (v2: level→tier rescale) | `features/upgrades.md` |
| `pets` | `ProfileSchema/PetsSection.lua` | `features/pets.md` |
| `progress` | `ProfileSchema/ProgressSection.lua` | `features/rebirth.md` |
| `quests` | `ProfileSchema/QuestsSection.lua` | `features/quests.md` |
| `dailyRewards` | `ProfileSchema/DailyRewardsSection.lua` | `features/daily-rewards.md` |
| `timeRewards` | `ProfileSchema/TimeRewardsSection.lua` | `features/time-rewards.md` |
| `social` | `ProfileSchema/SocialSection.lua` | `features/group-reward.md` |
| `shop` | `ProfileSchema/ShopSection.lua` | `features/shop.md` |
| `codes` | `ProfileSchema/CodesSection.lua` | `features/promo-codes.md` |

Reserved: `__schema` (managed by PersistenceService).

## Reward descriptor kinds

| Kind | Registered by | Doc |
|---|---|---|
| `calories` | `RewardGrantSubs` (built-in) | ADR-0002, `features/economy.md` |
| `gems` (`rawAmount` opt) | `RewardGrantSubs` (built-in) | `features/economy.md` |
| `boost` (`boostId`) | `RewardGrantSubs` (built-in) | `features/treasures.md` (boost defs) |
| `burn` | `BodySubs` | `features/body-gym.md` |
| `egg` (`eggType`) | `PetSubs` | `features/pets.md` |

## Setting ids (profile `core.settings` = the whitelist)

`music-enabled`, `sfx-enabled` — must match in `CoreSection.lua` AND
`src/client/common/data/SettingsData.lua`.

## Shop keys / codes / boosts / eggs

Products: `starterpack`, `lucky-egg`, `mega-egg`, `instant-burn`,
`boost-15m`, `gems-s/m/l/xl`; gamepasses: `x2calories`, `x2gems`, `autoeat`,
`autogym`, `capacity2`, `vip` (`ShopData.lua`). Codes: `WELCOME`, `EATCAKE`,
`SWEETTOOTH` (`CodesData.lua`). Boost ids: `golden-slice`, `boost-15m`
(`TreasureConfig.boosts`). Egg types: `cycle`, `lucky`, `mega`, `epic7`
(`PetConfig.eggs`). Row-id prefixes over the wire: `product:` / `pass:` /
`group`. Shop section ids (client grouping): `featured`, `passes`, `eggs`,
`gems`, `free`; cell kinds: `banner`, `tile`, `pack`; price-button states:
`buy`, `owned`, `unavailable`. Quest ids: `eat-cakes`, `burn-calories`,
`collect-finds` (`QuestsData.lua`).

## Icon names (`src/shared/UIKit/Icons.lua` = source of truth)

Flat `name -> rbxassetid`, resolved via `Theme.Icon(name)` (warns once + visible
fallback on a miss). Prefixes: `Ui*` UI glyphs · `Badge*` heavier line glyphs ·
`Pass*` gamepass badges · `RarityDisc*` / `RarityStar*` per tier · `Ribbon*`
(square rosette art — NOT usable as a 4:1 sash) · `GemPack{S,M,L,XL}`,
`CoinPack{S,M,L,XL}`, `Egg1..8` · `Sq*` the squishy roster. Add new rows there,
not here.

## Shared config modules (ADR-0004)

`CakeConfig`, `UpgradeConfig`, `UpgradeTreeConfig` (honeycomb layout),
`BodyConfig`, `PetConfig`, `TreasureConfig`, `JuiceConfig`, `PlaceConfig`,
`MatchConfig` — `src/shared/config/`.
Shared util: `HexUtil` (axial hex math, sibling to `GridUtil`).

## ProximityPrompt names (unique — clients filter PromptTriggered by name)

`GymPrompt` (gym start, server `BodySubs`), `UpgradeStation` (open the upgrades
hex-tree, client `UpgradesSubsClient`) — both defined in
`MapConfigData.checkpoint` (`promptName` / `upgradePromptName`).

## Locale keys

Source of truth: `src/client/common/data/LocaleData.lua` (the strings table — the
full list lives there, not here; add new keys there and note the feature).
Reserved (celebration hook pending): `toast-claimed`, `toast-claimed-gold`.
Lobby/game addition: `match-*` group + `announce-match-lost`
(`features/lobby-matchmaking.md`, `features/game-round.md`).
Squishy re-theme: `pet-<id>` display names pair 1:1 with `PetConfig` ids (30
entries — the KEY never changes, only the string); shop additions `btn-soon`,
`ribbon-best-value`, `ribbon-one-time`, `shop-section-gems`,
`shop-section-eggs` (`shop-section-gold` is legacy, kept for the retired
ShopRow list).

## Cross-place protocol ids

Persistence metadata: `teleport-release-nonce` (`PersistenceService`,
`features/persistence.md`). Difficulties: `easy`, `medium`, `hard`; queue actions:
`configure`, `leave`; queue updates: `open`, `close`, `error`, `busy`; teleport
kind: `match-result`; results: `win`, `loss` (ADR-0010 / matchmaking docs).
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
| `QuestsData` | `features/quests.md` |
| `DailyRewardsData` | `features/daily-rewards.md` |
| `TimeRewardsData` | `features/time-rewards.md` |
| `SocialData` | `features/group-reward.md` |
| `ShopData` | `features/shop.md` |
| `CodesData` | `features/promo-codes.md` |
| `SettingsData` (client) | `features/settings.md` |
| `LobbyQueueData` (lobby runtime) | `features/lobby-matchmaking.md` |
| `RoundStateData` (game runtime) | `features/game-round.md` |
| `TeleportData` (common runtime) | `features/persistence.md` |
| `PlayerControlData` (client movement-lock runtime) | `features/persistence.md` |
| `LobbyUiData` / `GameUiData` (client place markers) | `features/lobby-matchmaking.md` |
| `MatchConfig` (shared queue/round contract) | `features/lobby-matchmaking.md` |
