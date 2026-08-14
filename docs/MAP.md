# MAP — routing index

> One line per entry. Find your feature, read ONLY its doc. Details live in
> the linked doc and in file headers — never here (D3).

## Features

| Feature | Doc (single source) | Entry points (server / client) |
|---|---|---|
| persistence | `features/persistence.md` | PersistenceService, ProfileSchema/, PlayerLifecycleSubs / — |
| economy (calories+gems) | `features/economy.md` | EconomyService, EconomySubs / EconomySubsClient |
| cake-sim (heightfield + per-band terrace footprints) | `features/cake-sim.md` + ADR-0003, ADR-0008, ADR-0020, ADR-0021 | CakeFieldService, CakeCollisionService, CakeSubs, CakeSimulationSubs, CakeCycleSubs / LocalCakeField, CakeRenderer, CakeWaxShell, CakeWrapper, ChunkDebris, EatGestureController, CakeSubsClient, CakeFeelSubsClient |
| cake-cycle (selectable variants, flavour ZONES, pyramid footprints, zone-gate MINI-BOSSES, boss, rare, biomes, PACING CURVE) | `features/cake-cycle.md` + ADR-0011, ADR-0020, ADR-0021 | CakeCycleService, CakeCycleSubs, CakeSimulationSubs / BossView, MiniBossView, CakeSubsClient; `Shared.config.CakeLayersConfig`; authored `ReplicatedStorage.Assets.MiniBosses` + `Assets.Vfx.MiniBossPoof` |
| treasures (buried authored item models) | `features/treasures.md` + ADR-0012 | TreasureService, CakeSimulationSubs / CakeSubsClient; authored `Workspace.Items` → `ReplicatedStorage.Assets.Items` |
| boosts (timed stat multipliers, gem-bought) | `features/boosts.md` | StatsService, BoostSubs, ShopSubs (gem path), RewardGrantSubs / LocalStatsService, LocalShopService |
| body-gym (stomach, morph, roll) | `features/body-gym.md` | StomachService, GymService, BodySubs (server morph) / BallRollController, BodySubsClient, UIKit/GymOverlay |
| checkpoint (gym + active-terrace bridge + upgrade station + paid LAYER EATER platform) | `features/checkpoint.md` + ADR-0021 | MapService, CakeSubs (ReturnToCheckpoint + `eatlayer` grant), CakeFieldService (ClearActiveBand), CakeCycleSubs/CakeSimulationSubs (height/footprint) / BodySubsClient (F key + button), ShopSubsClient (LayerEater prompt) |
| upgrades (hex tier tree, RUN-scoped; world "N Available" sign) | `features/upgrades.md` + ADR-0013, ADR-0019 | UpgradeService, StatsService, UpgradeSubs, RunResetSubs (all COMMON) / LocalStatsService, LocalUpgradeTree, UpgradesSubsClient, UpgradeStationSubsClient, UpgradesUiData, UIKit HexNode/HexTreeOverlay, HexUtil |
| run reset (upgrades+calories+belly wiped per run) | `features/upgrades.md` + ADR-0013 | RunResetSubs (COMMON, `OnProfileLoaded` hook) / — |
| pets (shown as SQUISHIES — display-only rename, ids are DataStore keys) | `features/pets.md` | PetService, PetSubs / PetsSubsClient (owns the follower step, BOTH places), PetFollowers, LocalPetsService; authored `ReplicatedStorage.Assets.Squishes` |
| juice (ASMR layer) | `features/juice.md` | — / ParticlePool, CameraShake, ComboMeter, FloatingNumbers |
| food-burst (layer-clear + Cake Monster celebration: food confetti + random-cheer splash) | `features/food-burst.md` | — / FoodBurst, CakeSubsClient (`pushCelebration`), AppRoot (`state.celebration`), UIKit CelebrationBanner; `JuiceConfig.foodBurst`/`.foodBurstGroups`, `Theme.CelebrationBanner`, `Icons.Food*` |
| audio (SFX + music) | `features/audio.md` | — / SoundPool, MusicService, AudioSubsClient, AudioConfig; authored `ReplicatedStorage.SFX` + `SoundService.BackgroundMusic` |
| map (selectable authored room + stable checkpoint) | file header `services/MapService.lua` + ADR-0007, ADR-0020 | MapService (swaps `ReplicatedStorage.Assets.Environment` / `Environment1`, preserves Checkpoint), MapConfigData / — |
| reward-grants | ADR-0002 + ADR-0018 (`decisions/`) | RewardGrantSubs (kinds: calories, gems, boost, burn, eatlayer, egg; + readiness predicates) / — |
| daily-rewards | `features/daily-rewards.md` | DailyRewardService, RewardsSubs / RewardsSubsClient, LocalRewardsService |
| group-reward (like + join → 15-min boost, 10 s wait) | `features/group-reward.md` | SocialData, SocialService, GroupRewardSubs (lobby) / SocialSubsClient (lobby), AppRoot GroupReward panel, LocalShopService Free row |
| referrals (Invite Friends → 500 gems per friend) | `features/referrals.md` | SocialData, SocialService, ReferralSubs (lobby), PersistenceService message API / SocialSubsClient (lobby), AppRoot InviteFriends panel |
| shop (landscape TABBED grid of product CARDS; Robux + GEM currencies; HIDDEN world-sold products) | `features/shop.md` + ADR-0014, ADR-0015 | ShopService, ShopSubs (ProcessReceipt + gem-purchase owner, COMMON — both places), RewardGrantSubs (grant readiness) / ShopSubsClient, ShopUiData, LocalShopService, UIKit ShopPanel/ShopTab/ShopCard/ShopHeroCard/ShopBanner/ShopSectionHeader/PriceButton/Ribbon |
| promo-codes | `features/promo-codes.md` | CodesService, CodesSubs / CodesSubsClient |
| settings | `features/settings.md` | SettingsSubs / SettingsSubsClient, LocalSettingsService, SettingsData, AppRoot (lobby menu + game HUD button) |
| leaderstats (Roblox player list) | file header `subscriptions/LeaderboardSubs.lua` | LeaderboardSubs / — |
| leaderboards (3 in-world LOBBY boards: gems / speedrun / cakes) | `features/leaderboards.md` + ADR-0022 | GlobalLeaderboardData, GlobalLeaderboardService, GlobalLeaderboardSubs (COMMON), LobbyLeaderboardSubs (lobby, bound by LobbySubs) / —; authored `Assets.LobbyEnvironment.{TopGems,TopSpeedrunners,TopCakeCount}` |
| analytics (31-step player-flow funnel, per-LAYER depth funnel, every tap, economy; QUOTA'd) | `features/analytics.md` + ADR-0017 | AnalyticsSubs + Analytics/{Sink,Session,Ingest} (COMMON; beats pushed from every domain sub) / LocalAnalyticsService, AnalyticsSubsClient, UIKit `SetTrackHandler`; catalog `Shared.config.AnalyticsConfig` |
| app-root (HUD + panels) | `features/app-root.md` | — / AppRoot, AppSubsClient |
| ui-kit | `features/ui-kit.md` + skill `.claude/skills/roblox-ui-kit/` | — / Shared.UIKit, UiRoot, UiInputSubsClient, Shared.UIKit.InputBridge, Shared.UIKit.Icons (`Theme.Icons` / `Theme.Icon`) |
| lobby matchmaking (horizontal cake peek carousel, modes, parties) | `features/lobby-matchmaking.md` + ADR-0010 | LobbyQueueData, LobbyQueueService, LobbyQueueSubs, LobbyMapService, TeleportSubs / LobbyUiData, LobbySubsClient, AppRoot, UIKit/MatchmakingPanel/CakeCard/MatchDifficultyChoice/MatchPartyChoice/ScrollPane |
| game round (roster, difficulty, result return) | `features/game-round.md` + ADR-0010 | RoundStateData, GameRoundService, GameRoundSubs, CakeCycleSubs, TeleportSubs / CakeSubsClient, AppRoot |
| cake-select (lobby chooser; rainbow LOCKED until `progress.cakesEaten >= 1`; leader selection owns the match) | `features/cake-select.md` + ADR-0020 | CakeSelectSubs + LobbyQueue/Launch (lobby), GameRoundService + RoundStateData (game), ProfileSchema/CakesSection, ProgressService / CakeSelectSubsClient, AppRoot, UIKit CakeCard/CakeSelectPanel/ScrollPane; `Shared.config.CakeSelectConfig` |
| tutorial / onboarding (comic slides always; guided steps once per account) | `features/tutorial.md` + ADR-0016 | TutorialSubs (game), TutorialSection / TutorialSubsClient, AppRoot, UIKit TutorialSlides/TutorialHint/InputGlyph/HintArrow, TutorialConfig |
| localization (16 languages, cloud table; T = keys, Tr = catalogue/server text) | `features/localization.md` | — / LocaleData (strings + resolvers + OnReady), LocaleSubsClient (repaint on locale-ready); workbench `tools/robloxloc/` + `localization/` |

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
| cake LAYER LIBRARY + flavour groups (40 classic layers / 10 groups + 7 fixed rainbow layers/groups; `CakeConfig.layers`/`.layerGroups` re-export it) | `src/shared/config/CakeLayersConfig.lua` |
| vendored ProfileStore (never modify) | `src/shared/lib/ProfileStore.luau` |
| ScreenGui resolver | `src/client/common/data/UiData.lua` |
| locale strings + T/Tr resolvers (see `features/localization.md`) | `src/client/common/data/LocaleData.lua` |
| React root owner (kit UI) | `src/client/common/modules/UiRoot.lua` |
| React packages (vendored model → `ReplicatedStorage.Packages`) | `ReactLua-Packages.rbxmx` |
| editable scene models (place-authored → `ReplicatedStorage.Assets`, cloned): game `Environment`/`Environment1`+`Checkpoint` by MapService; lobby `LobbyMapContainer`+`LobbyEnvironment`+`LobbySpawn` by LobbyMapService | Studio-authored (ADR-0007, ADR-0020) |
| **lobby/game place split** — partitions + project files | `src/{server,client}/{common,lobby,game}/…`; `game`/`lobby`/`default`(=combined)`.project.json`; partition-aware bootstrap (ADR-0009) |
| lobby↔game teleport (verified-release handoff) | `TeleportSubs` + `TeleportRetrySubs` (server), `TeleportControlSubsClient` + `PlayerControlService` (client), `PlaceConfig` + `MatchConfig` (shared), queue/result orchestrators (ADR-0009, ADR-0010) |
| gamepass ownership (perks in BOTH places) | `PassOwnershipSubs` (common) |
| lobby hub scene builder | `LobbyMapService` + `LobbySubs` (lobby); authored contract in `features/lobby-matchmaking.md` |
| headless verification (run real modules without Studio) + the Luau syntax gate; `pacing_scenario` measures clear-time/income vs any config change; `analytics_scenario` asserts the analytics budget/trust boundary; `layereater_scenario` proves the PAID layer clear without a receipt | `tools/headless-sim/README.md` |
| pacing + PROGRESSION model (Python/numpy: a run where tiers are BOUGHT mid-run — the clear-time and "tree maxed at X% of the cake" numbers; self-checks against the Lua configs) | `tools/balance-model/README.md` |
| Studio automation: run scripts in the command bar, get structured reports back (no OCR); Rojo/require staleness traps | `tools/studio-bridge/README.md` |
| UI tonal-hierarchy analyzer (L* value bands, saliency, per-region attention ranks, findings, compare gate) — MANDATORY for UI review, wired into the ui-kit ship checklist | `tools/tonal-hierarchy/README.md` + skill `.claude/skills/tonal-hierarchy/` |
| UI squint test (heavy blur gray+color, per-region blur survival, icon-first rules for a non-reading audience) — same tool, `blur` subcommand | skill `.claude/skills/squint-test/` |
| dev hook: force the nearest buried find to the surface in a playtest (`DebugUncoverFind`) | `docs/features/treasures.md` |
| publish readiness: 11 LIVE monetization ids + 1 PENDING (`layer-eater`) + what must exist in BOTH places before going live | `docs/recipes/publish-readiness.md` |
| create/audit the 6 dev products + 6 gamepasses on the universe (cookie auth, idempotent, dry-run by default, writes the ids into ShopData); ⚠ a dev product is CREATE-ONCE — no delete, no update | `tools/monetization/README.md` + `tools/monetization/id_map.json` (the id ledger) |

## Lookup

- Task history: `flow/INDEX.md` — find by feature tag, open at most 1-2 docs
- Name uniqueness (sections, remotes, kinds, locale keys): `registries/`
- Architecture decisions: `decisions/` (NNNN-kebab-title.md) — balance/pacing: ADR-0011, ADR-0019
- How-to patterns: `recipes/` (add-profile-section, harvest-to-template, new-project-from-template)
- Self-improvement: `upstream/QUEUE.md` (capture, U1) + `TEMPLATE_CHANGELOG.md` (harvested changes)
