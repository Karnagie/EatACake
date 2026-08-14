# 2026-08-14: In-world lobby leaderboards (gems / speedrun / cakes)

Tags: leaderboards, persistence, lobby, economy, cake-cycle, progress, datastore

## Task

The user authored three leaderboard screens under
`ReplicatedStorage.Assets.LobbyEnvironment` — `TopGems` (total lifetime gems
collected), `TopSpeedrunners` (fastest cake, showing the time) and
`TopCakeCount` (most cakes eaten) — each with a `ScrollingFrame` and a
`FrameRank` row template, and asked for them to be implemented.

## Context

- `LeaderboardSubs` (COMMON) already existed but is the Roblox **player-list**
  `leaderstats`, not a board. Nothing in the repo ranked players across servers.
- `progress.cakesEaten` existed (`CakeCycleSubs.rewardPlayers`, boss win).
  Lifetime gems and any notion of cake DURATION did not.
- The boards ride the authored lobby clone, so the binding pattern was already
  there: `LobbySubs` builds the map and hands it to `LobbyQueueSubs.Bind`
  (`features/lobby-matchmaking.md`).

## Plan

1. Read the authored assets out of Studio and treat their shape as the
   contract (no re-authoring, no `.model.json`).
2. Add the two missing numbers to the `progress` profile section (defaults
   only → no version bump, P2), counted at the single existing choke point for
   each.
3. One COMMON service owning `OrderedDataStore` (the only cross-server ranking
   primitive Roblox has), one COMMON sub publishing, one LOBBY sub rendering.
4. Verify live in the lobby place with seeded rows, then remove the seeds.

## Changes

**Created:**
- `server/common/data/GlobalLeaderboardData.lua` — board defs (model name,
  value-label name, stat key, sort order, format), store naming + version,
  cadence, authored GUI names, all runtime state
- `server/common/services/GlobalLeaderboardService.lua` — publish / fetch /
  name-cache / value formatting; the only direct `DataStoreService` user
  besides ProfileStore
- `server/common/subscriptions/GlobalLeaderboardSubs.lua` — publishes changed
  values on profile load + every 120 s
- `server/lobby/subscriptions/LobbyLeaderboardSubs.lua` — `Bind(map)`, row
  cloning, 60 s refresh, rendering
- `docs/decisions/0022-ordered-datastore-global-leaderboards.md`
- `docs/features/leaderboards.md`

**Modified:**
- `ProfileSchema/ProgressSection.lua` — `lifetimeGems`, `bestCakeMillis`
  (+ sanitize)
- `ProgressService.lua` — `RecordCakeTime` (minimum-only), both new fields in
  `Summary`
- `RewardGrantSubs.lua` — the `gems` handler counts lifetime gems
- `CakeStateData.lua` — `cakeStartedAt`, `cakeStartRoster`
- `CakeCycleSubs.lua` — stamps the cake clock in `SpawnNewCake`, records the
  time in `rewardPlayers`
- `LobbySubs.lua` — binds the boards before the queue pads, never gated on them
- `CLAUDE.md` — P5 now names its sole exemption (ADR-0022)
- `MAP.md`, `registries/data-keys.md`

## Decisions

**OrderedDataStore, and P5 amended rather than quietly broken (ADR-0022).**
Cross-server ranking has no ProfileStore answer — a profile is session-locked to
one player on one server and there is no "sort all profiles" at any price. The
stores are a **projection**: written only from the profile, never read back into
one, keyed by userId, one number each. That makes publishing idempotent, which
is what let the rest of the design stay simple. P5's rule is unchanged in
substance and now says so out loud; leaving the constitution contradicting the
code would have invited a future agent to "fix" the violation.

**Zero is not a score.** Every fresh account has `bestCakeMillis = 0`, and the
speedrun board sorts ASCENDING — a published zero takes first place forever.
`Publish` drops non-positive values, so "no record" is the ABSENCE of a row.
Verified in the playtest: the joining player's three zeroes wrote nothing, and
after redeeming a 25-gem code exactly **one** board value published.

**No publish on `PlayerRemoving`.** It is the obvious hook and it is a race:
`PlayerLifecycleSubs` unloads the profile on that same event and the order of
two handlers on one event is not a contract. The next profile LOAD publishes
instead — which covers the player who quit straight out of a match, because the
profile they load next carries what the last session ended with.

**The speedrun clock belongs to the CAKE, not to a player.** `SpawnNewCake`
stamps `os.clock` and snapshots the roster present at that instant; the win
measures once. The roster snapshot is what makes the number honest: in a
reserved match `beginMatchIfReady` has already waited for every arriving
profile, so it is the final roster; in the endless fallback it excludes anyone
who walks in on a half-eaten cake. Milliseconds in the PROFILE too, not just in
the store — the two must not disagree about what "1297000" means, and the units
are part of the store name's contract.

**Lifetime gems has exactly one call site.** `RewardGrantSubs`' `gems` handler
is the only gem INCOME path in the game (finds, daily, referrals, codes, packs
all produce descriptors). The other `AddGems` caller is ShopSubs' refund of a
failed gem purchase, deliberately NOT counted: the original spend never
decremented the lifetime counter, so crediting the refund would mint gems.

**Row geometry is derived from the template, not hardcoded.** A child's scale
inside a `ScrollingFrame` is relative to the CANVAS. The artist sized the row at
0.02 of a 5.0-window-height canvas — i.e. 0.1 of the window per row, 10 on
screen, 50 of canvas. So `canvas.Y = N * 0.1` and `row.Y = 1/N` reproduces the
authored row height for any `entryCount`, and at the shipped N = 50 the canvas
comes back to exactly the authored `{5,0}` — measured, and a free invariant
check. Two clone-only normalisations, both logged: `AnchorPoint` zeroed (a
`UIListLayout` writes `Position`, so `0.5,0.5` shifts every row half its size
up-left) and `ScrollingDirection` `XY → Y`.

**The value label has a different authored name on each board** (`Kills` /
`Rebirths` / `Strength` — the three screens came from different kits). Mapped in
config rather than renamed in Studio, because renaming would mean the user
re-saving the place; a rename is survived by falling back to "the text label
that is neither Rank nor PlayerName", with a warn naming the config key.

**`AutoLocalize = false` on every written label.** A player's name and a score
are data; leaving auto-translate on runs them through the cloud localization
table (`features/localization.md`). No new locale key was added at all — the
board titles are the authored `Screen2` labels and stay untouched.

**Server-side rendering, no remote.** The boards are instances in
`workspace.LobbyMap`, so text replicates for free. 150 rows exist once and only
their `Text` changes on refresh.

## Verification

Live playtest in the LOBBY place (126172008675265; Rojo-synced source confirmed
by reading `.Source`, never `require`):

- R8 boot clean: `3/3 ordered store(s) resolved (v1)`, `3/3 leaderboard(s)
  bound, 50 rows each`, `OrderedDataStore access OK`, `23/23 subscriptions
  started`, zero `require FAILED`.
- Geometry measured off live instances: canvas `{0,0},{5,0}` (= authored),
  `AbsoluteCanvasSize` 284.15 × 1801.16, every row `AbsoluteSize` 36.0232 (=
  the authored template exactly), stacking 0 / 36.02 / 72.05 / 108.07, anchors
  zeroed, template still `Visible = false`.
- Data path with four seeded accounts: descending gems `999.9B / 1.2M / 98.7K /
  4.3K`, descending cakes `412 / 87 / 9 / 1`, **ascending** speedrun `9:59 →
  21:37 → 35:12 → 1:04:05`, names resolved through `UserService`
  (DisplayName, e.g. `Jane Doe`, `builderman`).
- End-to-end publish: fired the real `RedeemCode` remote from the client
  datamodel → `WELCOME` granted 25 gems → the 120 s tick logged `published 1
  board value(s)` → `EatACakeTop_gems_v1[9489991606] = 25` read back.
- Seeds removed with `RemoveAsync`; the only row left in any store is the
  developer's own genuine 25.
- Second playtest for the JOIN path (the first only proved the tick):
  `profile-loaded hooks (5): AnalyticsSubs, CakeSelectSubs,
  GlobalLeaderboardSubs, ReferralSubs, RunResetSubs` → `published 1 board
  value(s) for userId 9489991606 (join)` → the board renders `#1 karnagiy 25`
  off real profile data. Exactly ONE value published: cakes and speedrun are
  still 0 and were correctly dropped.
- 239-file `luau-compile` parse, all three Rojo project files build.

⚠ No screenshot: Studio's renderer was not drawing frames (`RenderStepped` 0
ticks / `Heartbeat` 90 ticks in 1.5 s) and both `screen_capture` calls timed
out — the known artifact recorded in memory. Everything above is measured off
live instances, which is what that note prescribes.

## Adversarial review (1 CRITICAL + 7 WARN, all fixed)

**CRITICAL — Studio's `DebugClearLayer` would have written an unbeatable world
record to the LIVE speedrun board.** The latch that exists precisely to stop a
debug-skipped cake mutating profiles (`state.debugSuppressFindRewards`, honoured
by `CakeSimulationSubs`) was never checked by `rewardPlayers`. Studio runs
against the real profile store (`useMockInStudio = false`), a debug-cleared cake
reaches the boss in ~1 minute against an honest ~35, and `bestCakeMillis` is a
MINIMUM on an ASCENDING store — so that row could never be displaced by any real
run, and the only remedy would have been a `storeVersion` bump wiping all three
boards. The speedrun write now checks the latch; `cakesEaten` deliberately still
counts there (monotonic, and QA uses it to unlock the rainbow cake).

Also fixed:

- **`Publish` returned a COUNT, so a partial failure marked every changed board
  as published.** With gems + a first-ever cake time in one batch and the
  speedrun `SetAsync` throttled, that time would never be retried — a first
  record never changes again unless it is beaten. It now returns the SET of
  committed board ids and only those are marked.
- **`useMockInStudio` had a hole**: the flag promises "nothing is written to
  live DataStore keys" but covered ProfileStore only, so flipping it would have
  left Studio writing the live boards with debug-shortened cakes behind it.
  Mirrored in the service.
- **A renamed value label warned once PER ROW** (50–150 warns burying the boot
  report). The label is now resolved once per board off the template.
- **`Bind` was not idempotent on the SAME map** despite its docstring: old rows
  stayed parented and `rowFraction` was re-derived from a `CanvasSize` the
  previous bind had already rewritten, compounding for any `entryCount ≠ 50`
  (the shipped 50 round-trips, which hid it). Rows.Build now clears the previous
  generation and reuses the fraction captured at first bind. Proven live —
  fresh-required a parallel copy at `entryCount = 20` and bound the live map
  three times: 20 rows each time, canvas `{2,0}` each time, row height
  36.023159 unchanged across all three.
- `entryCount` was clamped on the READ side only, so >100 built rows that could
  never fill; clamped and warned at build.
- Both busy latches could wedge and go silent forever; past three periods they
  force-clear with a warn.
- The scheduling accumulators were module locals while the data module carried
  dead `last-*-at` fields (R1); moved onto the data module.
- R7: the lobby sub was 345 lines → split into `LobbyLeaderboard/Rows.lua`
  (219 + 235), following the `LobbyQueue/` precedent.
- Plus: duplicate-board-model warn, combined-build log no longer claims a
  feature that structurally cannot fire, `AddStat` warns once on an unknown key
  (it silently no-opped, and `lifetimeGems` now depends on it), R2 literals in
  the service removed, D3 duplication trimmed out of the registry.

Re-verified after the refactor: `3/3 leaderboard(s) bound, 50 rows each`, row =
0.100 of the window, canvas `{5,0}`, row `AbsoluteSize` 36.0232 — identical to
the pre-refactor measurement — and the board still renders `#1 karnagiy 25`.
239-file parse + three builds green.

The reviewer's clean-bill categories worth recording: every vendored/Roblox API
call site (receiver form, `pcall` shape, `DataStorePages` row shape), NaN/inf
rejection on both write and read, the `lifetimeGems` completeness trace across
every `AddGems` caller and every `{kind="gems"}` producer, P1–P5 compliance,
start-order (`GlobalLeaderboardSubs` < `LobbyLeaderboardSubs` < `LobbySubs` <
`PlayerLifecycleSubs`), `Log.Once` key-space collisions, and exploit surface
(no new remote, no client-supplied number).

## Open Questions / Followups

- **The speedrun time is raw.** Difficulty, party size and cake variant are not
  normalised, so a 4-player hard run will out-rank a solo one. One board, one
  number was the deliberate call; splitting it means a store per bucket.
- An **empty board renders as bare screens** (rows hidden, title still shown).
  A "Be the first!" line would need a new locale key and therefore a
  localization `push`, so it was left out.
- `bestCakeMillis` only ever gets written on a boss WIN, so a cake abandoned at
  99 % scores nothing. Correct for a "finished the cake" board; worth knowing.

## Related
- Feature: `docs/features/leaderboards.md`
- ADRs: ADR-0022 (new), ADR-0007 (authored scene assets), ADR-0009 (place split)
- Prior flow: `docs/flow/2026-07-22_lobby-matchmaking-rounds.md`
