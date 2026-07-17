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
| `upgrades` | `ProfileSchema/UpgradesSection.lua` | `features/upgrades.md` |
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
`src/client/data/SettingsData.lua`.

## Shop keys / codes / boosts / eggs

Products: `starterpack`, `lucky-egg`, `mega-egg`, `instant-burn`,
`boost-15m`, `gems-s/m/l/xl`; gamepasses: `x2calories`, `x2gems`, `autoeat`,
`autogym`, `capacity2`, `vip` (`ShopData.lua`). Codes: `WELCOME`, `EATCAKE`,
`SWEETTOOTH` (`CodesData.lua`). Boost ids: `golden-slice`, `boost-15m`
(`TreasureConfig.boosts`). Egg types: `cycle`, `lucky`, `mega`, `epic7`
(`PetConfig.eggs`). Row-id prefixes over the wire: `product:` / `pass:` /
`group`. Quest ids: `eat-cakes`, `burn-calories`, `collect-finds`
(`QuestsData.lua`).

## Shared config modules (ADR-0004)

`CakeConfig`, `UpgradeConfig`, `BodyConfig`, `PetConfig`, `TreasureConfig`,
`JuiceConfig` — `src/shared/config/`.

## Locale keys

Source of truth: `src/client/data/LocaleData.lua` (the strings table — the
full list lives there, not here; add new keys there and note the feature).
Reserved (celebration hook pending): `toast-claimed`, `toast-claimed-gold`.

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
