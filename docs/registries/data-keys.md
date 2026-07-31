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
| `progress` | `ProfileSchema/ProgressSection.lua` | `features/game-round.md` (`rebirths` legacy/always 0; `foundKinds` = buried-find discovery set, `features/treasures.md`; `activeBoosts`, `features/boosts.md`) |
| `dailyRewards` | `ProfileSchema/DailyRewardsSection.lua` | `features/daily-rewards.md` |
| `social` | `ProfileSchema/SocialSection.lua` | `features/group-reward.md` |
| `shop` | `ProfileSchema/ShopSection.lua` | `features/shop.md` |
| `codes` | `ProfileSchema/CodesSection.lua` | `features/promo-codes.md` |

Reserved: `__schema` (managed by PersistenceService).
Retired 2026-07-31, do NOT reuse the key: `quests`, `timeRewards` (still present
as orphan top-level keys in old saves — `features/persistence.md`).

## Reward descriptor kinds

| Kind | Registered by | Doc |
|---|---|---|
| `calories` | `RewardGrantSubs` (built-in) | ADR-0002, `features/economy.md` |
| `gems` (`rawAmount` opt) | `RewardGrantSubs` (built-in) | `features/economy.md` |
| `boost` (`boostId`) | `RewardGrantSubs` (built-in) | `features/boosts.md` |
| `burn` | `BodySubs` | `features/body-gym.md` |
| `egg` (`eggType`) | `PetSubs` | `features/pets.md` |

## Setting ids (profile `core.settings` = the whitelist)

`music-enabled`, `sfx-enabled` — must match in `CoreSection.lua` AND
`src/client/common/data/SettingsData.lua`.

## Shop keys / codes / boosts / eggs

Products: `starterpack`, `boost-15m`, `boost-bite`, `boost-speed`,
`boost-capacity`, `gems-s/m/l/xl`; gamepasses: `x2calories`, `x2gems`,
`autoeat`, `autogym`, `capacity2`, `vip` (`ShopData.lua`). Codes: `WELCOME`,
`EATCAKE`, `SWEETTOOTH` (`CodesData.lua`). Boost DEF ids (≠ the product keys):
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
`shop-section-boosts` (`shop-section-gold` is legacy, kept for the retired
ShopRow list; `shop-section-eggs` was DELETED with the eggs). Shop tabs
(2026-07-31): `shop-tab-featured` ("Offers"), `shop-tab-passes`,
`shop-tab-boosts`, `shop-tab-gems`, plus `price-robux-short` ("{n}") and
`price-gems-short` ("{n}") — the glyph-less amounts the card price shelf uses,
because the shelf draws the currency icon itself. `price-robux` ("R$ {n}") is
now RESERVED: no call site, kept for a future glyph-less context (a chat
message, a toast).
Boost names (`TreasureConfig.boosts[*].nameKey`, one per def):
`boost-15m`, `boost-bite`, `boost-speed`, `boost-capacity`
(`features/boosts.md`; `label-boost` is the shorter daily-card alias for the
calories one).
Buried finds: `announce-find-rare` / `-epic` / `-legendary` (rare+ only — a
banner per find would be noise); `find-<id>` names pair 1:1 with
`TreasureConfig.finds` ids (`features/treasures.md`).
Cake rhythm: `announce-layer-cleared` (fires once per band the layer gate steps
down — `features/cake-cycle.md`); `cake-finds` ("FINDS n/N", the per-cake goal
the HUD bar carries while eating — `features/treasures.md`).
Boss: `boss-prize-caption` (the caption on the boss PRIZE card — the squishy at
stake during the fight; `features/cake-cycle.md`, `UIKit/BossPrizeCard`).

## Authored instance names (place-authored, resolved by exact name)

`Workspace.Items` → migrated to `ReplicatedStorage.Assets.Items` on boot: the
buried-find MODEL LIBRARY, one Model/BasePart per child; a child's NAME is what
`TreasureConfig.finds[].model` pins (`features/treasures.md`, ADR-0012).
`ReplicatedStorage.Assets.Environment` / `.Checkpoint` — MapService (ADR-0007).

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
| `DailyRewardsData` | `features/daily-rewards.md` |
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
