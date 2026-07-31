# MAP — routing index

> One line per entry. Find your feature, read ONLY its doc. Details live in
> the linked doc and in file headers — never here (D3).

## Features

| Feature | Doc (single source) | Entry points (server / client) |
|---|---|---|
| persistence | `features/persistence.md` | PersistenceService, ProfileSchema/, PlayerLifecycleSubs / — |
| economy (calories+gems) | `features/economy.md` | EconomyService, EconomySubs / EconomySubsClient |
| cake-sim (heightfield) | `features/cake-sim.md` + ADR-0003, ADR-0008 | CakeFieldService, CakeCollisionService, CakeSubs, CakeSimulationSubs, CakeCycleSubs / LocalCakeField, CakeRenderer, CakeWaxShell, CakeWrapper, ChunkDebris, EatGestureController, CakeSubsClient, CakeFeelSubsClient |
| cake-cycle (boss, rare, biomes, PACING CURVE) | `features/cake-cycle.md` + ADR-0011 | CakeCycleService, CakeCycleSubs, CakeSimulationSubs / BossView, CakeSubsClient |
| treasures (buried authored item models) | `features/treasures.md` + ADR-0012 | TreasureService, CakeSimulationSubs / CakeSubsClient; authored `Workspace.Items` → `ReplicatedStorage.Assets.Items` |
| boosts (timed stat multipliers, gem-bought) | `features/boosts.md` | StatsService, BoostSubs, ShopSubs (gem path), RewardGrantSubs / LocalStatsService, LocalShopService |
| body-gym (stomach, morph, roll) | `features/body-gym.md` | StomachService, GymService, BodySubs (server morph) / BallRollController, BodySubsClient, UIKit/GymOverlay |
| checkpoint (gym + upgrade station platform) | `features/checkpoint.md` | MapService, CakeSubs (ReturnToCheckpoint), CakeCycleSubs/CakeSimulationSubs (height) / BodySubsClient (F key + button) |
| upgrades (hex tier tree, RUN-scoped) | `features/upgrades.md` + ADR-0013 | UpgradeService, StatsService, UpgradeSubs, RunResetSubs (all COMMON) / LocalStatsService, LocalUpgradeTree, UpgradesSubsClient, UpgradesUiData, UIKit HexNode/HexTreeOverlay, HexUtil |
| run reset (upgrades+calories+belly wiped per run) | `features/upgrades.md` + ADR-0013 | RunResetSubs (COMMON, `OnProfileLoaded` hook) / — |
| pets (shown as SQUISHIES — display-only rename, ids are DataStore keys) | `features/pets.md` | PetService, PetSubs / PetsSubsClient (owns the follower step, BOTH places), PetFollowers, LocalPetsService; authored `ReplicatedStorage.Assets.Squishes` |
| juice (ASMR layer) | `features/juice.md` | — / ParticlePool, CameraShake, ComboMeter, FloatingNumbers |
| audio (SFX + music) | `features/audio.md` | — / SoundPool, MusicService, AudioSubsClient, AudioConfig; authored `ReplicatedStorage.SFX` + `SoundService.BackgroundMusic` |
| map (factory scene) | file header `services/MapService.lua` + ADR-0007 | MapService (clones `ReplicatedStorage.Assets` Environment+Checkpoint), MapConfigData / — |
| reward-grants | ADR-0002 (`decisions/`) | RewardGrantSubs (kinds: calories, gems, boost, burn, egg) / — |
| daily-rewards | `features/daily-rewards.md` | DailyRewardService, RewardsSubs / RewardsSubsClient, LocalRewardsService |
| group-reward | `features/group-reward.md` | SocialService, GroupRewardSubs / ShopSubsClient (Free row) |
| shop (landscape TABBED grid of product CARDS; Robux + GEM currencies) | `features/shop.md` + ADR-0014, ADR-0015 | ShopService, ShopSubs (ProcessReceipt + gem-purchase owner, COMMON — both places) / ShopSubsClient, LocalShopService, UIKit ShopPanel/ShopTab/ShopCard/ShopHeroCard/ShopBanner/ShopSectionHeader/PriceButton/Ribbon |
| promo-codes | `features/promo-codes.md` | CodesService, CodesSubs / CodesSubsClient |
| settings | `features/settings.md` | SettingsSubs / SettingsSubsClient, LocalSettingsService, SettingsData |
| leaderstats | file header `subscriptions/LeaderboardSubs.lua` | LeaderboardSubs / — |
| analytics (retention funnel + session length) | `features/analytics.md` | AnalyticsSubs (COMMON; beats pushed from CakeSubs, CakeSimulationSubs, BodySubs, UpgradeSubs) / — |
| app-root (HUD + panels) | `features/app-root.md` | — / AppRoot, AppSubsClient |
| ui-kit | `features/ui-kit.md` + skill `.claude/skills/roblox-ui-kit/` | — / Shared.UIKit, UiRoot, Shared.UIKit.Icons (`Theme.Icons` / `Theme.Icon`) |
| lobby matchmaking (pads, modes, parties) | `features/lobby-matchmaking.md` + ADR-0010 | LobbyQueueData, LobbyQueueService, LobbyQueueSubs, LobbyMapService, TeleportSubs / LobbyUiData, LobbySubsClient, AppRoot, UIKit/MatchmakingPanel |
| game round (roster, difficulty, result return) | `features/game-round.md` + ADR-0010 | RoundStateData, GameRoundService, GameRoundSubs, CakeCycleSubs, TeleportSubs / CakeSubsClient, AppRoot |

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
| ScreenGui resolver | `src/client/common/data/UiData.lua` |
| locale stub (T/Tr) | `src/client/common/data/LocaleData.lua` |
| React root owner (kit UI) | `src/client/common/modules/UiRoot.lua` |
| React packages (vendored model → `ReplicatedStorage.Packages`) | `ReactLua-Packages.rbxmx` |
| editable scene models (place-authored → `ReplicatedStorage.Assets`, cloned): game `Environment`+`Checkpoint` by MapService; lobby `LobbyMapContainer`+`LobbyEnvironment`+`LobbySpawn` by LobbyMapService | Studio-authored (ADR-0007) |
| **lobby/game place split** — partitions + project files | `src/{server,client}/{common,lobby,game}/…`; `game`/`lobby`/`default`(=combined)`.project.json`; partition-aware bootstrap (ADR-0009) |
| lobby↔game teleport (verified-release handoff) | `TeleportSubs` + `TeleportRetrySubs` (server), `TeleportControlSubsClient` + `PlayerControlService` (client), `PlaceConfig` + `MatchConfig` (shared), queue/result orchestrators (ADR-0009, ADR-0010) |
| gamepass ownership (perks in BOTH places) | `PassOwnershipSubs` (common) |
| lobby hub scene builder | `LobbyMapService` + `LobbySubs` (lobby); authored contract in `features/lobby-matchmaking.md` |
| headless verification (run real modules without Studio) + the Luau syntax gate; `pacing_scenario` measures clear-time/income vs any config change | `tools/headless-sim/README.md` |
| pacing + PROGRESSION model (Python/numpy: a run where tiers are BOUGHT mid-run — the clear-time and "tree maxed at X% of the cake" numbers; self-checks against the Lua configs) | `tools/balance-model/README.md` |
| Studio automation: run scripts in the command bar, get structured reports back (no OCR); Rojo/require staleness traps | `tools/studio-bridge/README.md` |
| dev hook: force the nearest buried find to the surface in a playtest (`DebugUncoverFind`) | `docs/features/treasures.md` |
| publish readiness: the 11 LIVE monetization ids + what must exist in BOTH places before going live | `docs/recipes/publish-readiness.md` |
| create/audit the 5 dev products + 6 gamepasses on the universe (cookie auth, idempotent, dry-run by default, writes the ids into ShopData); ⚠ a dev product is CREATE-ONCE — no delete, no update | `tools/monetization/README.md` + `tools/monetization/id_map.json` (the id ledger) |

## Lookup

- Task history: `flow/INDEX.md` — find by feature tag, open at most 1-2 docs
- Name uniqueness (sections, remotes, kinds, locale keys): `registries/`
- Architecture decisions: `decisions/` (NNNN-kebab-title.md) — balance/pacing: ADR-0011
- How-to patterns: `recipes/` (add-profile-section, harvest-to-template, new-project-from-template)
- Self-improvement: `upstream/QUEUE.md` (capture, U1) + `TEMPLATE_CHANGELOG.md` (harvested changes)
