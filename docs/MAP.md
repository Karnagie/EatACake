# MAP — routing index

> One line per entry. Find your feature, read ONLY its doc. Details live in
> the linked doc and in file headers — never here (D3).

## Features

| Feature | Doc (single source) | Entry points (server / client) |
|---|---|---|
| persistence | `features/persistence.md` | PersistenceService, ProfileSchema/, PlayerLifecycleSubs / — |
| economy (calories+gems) | `features/economy.md` | EconomyService, EconomySubs / EconomySubsClient |
| cake-sim (heightfield) | `features/cake-sim.md` + ADR-0003 | CakeFieldService, CakeCollisionService, CakeSubs / LocalCakeField, CakeRenderer, CakeWaxShell, EatGestureController, CakeSubsClient, CakeFeelSubsClient |
| cake-cycle (boss, rare, biomes) | `features/cake-cycle.md` | CakeCycleService, CakeSubs / BossView, CakeSubsClient |
| treasures (finds) | `features/treasures.md` | TreasureService, CakeSubs / CakeSubsClient |
| body-gym (stomach, morph, roll) | `features/body-gym.md` | StomachService, GymService, BodySubs (server morph) / BallRollController, BodySubsClient, GymOverlay |
| upgrades + stats | `features/upgrades.md` | UpgradeService, StatsService, UpgradeSubs / LocalStatsService, UpgradesSubsClient |
| pets | `features/pets.md` | PetService, PetSubs / PetsSubsClient, PetFollowers, LocalPetsService |
| rebirth + biomes | `features/rebirth.md` | ProgressService, RebirthSubs / RebirthSubsClient |
| quests | `features/quests.md` | QuestService, QuestsSubs / QuestsSubsClient |
| juice (ASMR layer) | `features/juice.md` | — / SoundPool, ParticlePool, CameraShake, ComboMeter, FloatingNumbers |
| map (factory scene) | file header `services/MapService.lua` | MapService, MapConfigData / — |
| reward-grants | ADR-0002 (`decisions/`) | RewardGrantSubs (kinds: calories, gems, boost, burn, egg) / — |
| daily-rewards | `features/daily-rewards.md` | DailyRewardService, RewardsSubs / RewardsSubsClient, LocalRewardsService |
| time-rewards | `features/time-rewards.md` | TimeRewardService, RewardsSubs / RewardsSubsClient, LocalRewardsService |
| group-reward | `features/group-reward.md` | SocialService, GroupRewardSubs / ShopSubsClient (Free row) |
| shop | `features/shop.md` | ShopService, ShopSubs (ProcessReceipt owner) / ShopSubsClient, LocalShopService |
| promo-codes | `features/promo-codes.md` | CodesService, CodesSubs / CodesSubsClient |
| settings | `features/settings.md` | SettingsSubs / SettingsSubsClient, LocalSettingsService, SettingsData |
| leaderstats | file header `subscriptions/LeaderboardSubs.lua` | LeaderboardSubs / — |
| app-root (HUD + panels) | `features/app-root.md` | — / AppRoot, AppSubsClient |
| ui-kit | `features/ui-kit.md` + skill `.claude/skills/roblox-ui-kit/` | — / Shared.UIKit, UiRoot |

## Infrastructure (no feature doc — the file header IS the doc)

| Piece | File |
|---|---|
| server bootstrap | `src/server/ServerBootstrap.server.lua` |
| client bootstrap (+ ClientReady send) | `src/client/LocalBootstrap.client.lua` |
| networking resolver | `src/shared/Net.lua` |
| console transparency, R8 | `src/shared/Log.lua` |
| grid math (both sides) | `src/shared/GridUtil.lua` |
| shared bite math (prediction contract) | `src/shared/CakeOps.lua` |
| shared game configs (ADR-0004) | `src/shared/config/*.lua` |
| vendored ProfileStore (never modify) | `src/shared/lib/ProfileStore.luau` |
| ScreenGui resolver | `src/client/data/UiData.lua` |
| locale stub (T/Tr) | `src/client/data/LocaleData.lua` |
| React root owner (kit UI) | `src/client/modules/UiRoot.lua` |
| React packages (vendored model → `ReplicatedStorage.Packages`) | `ReactLua-Packages.rbxmx` |

## Lookup

- Task history: `flow/INDEX.md` — find by feature tag, open at most 1-2 docs
- Name uniqueness (sections, remotes, kinds, locale keys): `registries/`
- Architecture decisions: `decisions/` (NNNN-kebab-title.md)
- How-to patterns: `recipes/` (add-profile-section, harvest-to-template, new-project-from-template)
- Self-improvement: `upstream/QUEUE.md` (capture, U1) + `TEMPLATE_CHANGELOG.md` (harvested changes)
