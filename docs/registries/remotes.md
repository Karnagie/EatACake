# Registry: remotes

> Uniqueness index ONLY — check here before naming a new remote. Payload
> contracts live in the owning feature doc, not here.

## remotes/ (client → server)

| Name | Owner | Contract in |
|---|---|---|
| `ClientReady` | `PlayerLifecycleSubs` | `features/persistence.md` |
| `EatAt` | `CakeSubs` | `features/cake-sim.md` |
| `GymTap` | `BodySubs` | `features/body-gym.md` |
| `ReturnToCheckpoint` | `CakeSubs` | `features/checkpoint.md` |
| `BuyUpgrade` | `UpgradeSubs` (common — both places) | `features/upgrades.md` |
| `EquipPet` | `PetSubs` | `features/pets.md` |
| `ClaimDailyReward` | `RewardsSubs` | `features/daily-rewards.md` |
| `ClaimGroupReward` | `GroupRewardSubs` | `features/group-reward.md` |
| `RequestPurchase` | `ShopSubs` | `features/shop.md` |
| `RequestGemPurchase` | `ShopSubs` | `features/shop.md` |
| `RequestGamepass` | `ShopSubs` | `features/shop.md` |
| `RedeemCode` | `CodesSubs` | `features/promo-codes.md` |
| `SetSetting` | `SettingsSubs` | `features/settings.md` |
| `RequestTeleport` | `TeleportSubs` | ADR-0009 / `features/persistence.md` |
| `LobbyQueueRequest` | `LobbyQueueSubs` | `features/lobby-matchmaking.md` |

## remoteUpdates/ (server → client)

| Name | Owner | Contract in |
|---|---|---|
| `CurrencyUpdate` | `EconomySubs` / grant handlers | `features/economy.md` |
| `CakeSnapshotUpdate` | `CakeSubs` / `CakeCycleSubs` | `features/cake-sim.md` |
| `CakeDeltaUpdate` (Unreliable) | `CakeSimulationSubs` | `features/cake-sim.md` |
| `CakeCycleUpdate` | `CakeCycleSubs` | `features/cake-cycle.md` — ⚠ payload is PER-RECIPIENT while a boss prize exists (`pendingPet`), not a broadcast |
| `StomachUpdate` | `CakeSubs` / `BodySubs` | `features/body-gym.md` |
| `GymUpdate` | `BodySubs` | `features/body-gym.md` |
| `UpgradesUpdate` | `UpgradeSubs` | `features/upgrades.md` |
| `PetsUpdate` | `PetSubs` | `features/pets.md` |
| `PetRollUpdate` | `PetSubs` | `features/pets.md` |
| `TreasureUpdate` | `CakeSimulationSubs` | `features/treasures.md` |
| `DailyRewardUpdate` | `RewardsSubs` | `features/daily-rewards.md` |
| `GroupRewardUpdate` | `GroupRewardSubs` | `features/group-reward.md` |
| `ShopUpdate` | `ShopSubs` | `features/shop.md` |
| `CodeResultUpdate` | `CodesSubs` | `features/promo-codes.md` |
| `SettingsUpdate` | `SettingsSubs` | `features/settings.md` |
| `LobbyQueueUpdate` | `LobbyQueueSubs` | `features/lobby-matchmaking.md` |

## Player attributes (server-written, client-read)

| Attribute | Owner | Meaning |
|---|---|---|
| `StomachFill` | `BodySubs` | 0..1 belly fullness (morph driver) |
| `EquippedPets` | `PetSubs` | csv of equipped petIds (followers) |
| `BiteRadiusMult` | `BoostSubs` | live bite-radius boost multiplier (`features/boosts.md`) — the ONLY channel carrying it to the client |
| `AutoEat` / `AutoGym` | `PassOwnershipSubs` | gamepass perk flags |
| `Teleporting` | `TeleportSubs` | source-place handoff/input guard |
