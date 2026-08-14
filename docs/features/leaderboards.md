# Leaderboards (in-world lobby boards)

Three authored screens in the lobby hub rank players across every server and
every session (ADR-0022). Not to be confused with the Roblox player-list
`leaderstats` — that is `LeaderboardSubs` (own row in `MAP.md`).

| Board | Model | Stat (profile) | Order | Shown as |
|---|---|---|---|---|
| Top Gems | `TopGems` | `progress.lifetimeGems` | highest first | abbreviated count (`1.2M`) |
| Top Speed Runners | `TopSpeedrunners` | `progress.bestCakeMillis` | **lowest** first | `M:SS` / `H:MM:SS` |
| Top Cake Eaters | `TopCakeCount` | `progress.cakesEaten` | highest first | abbreviated count |

Everything is SERVER-side: the boards are instances in `workspace.LobbyMap`, so
the text simply replicates. No remote, no client module, no locale key.

## The three numbers

- **`lifetimeGems`** — gems ever COLLECTED, not the spendable `economy.gems`
  balance. Counted in exactly one place: the `gems` handler in
  `RewardGrantSubs`, which is the only gem INCOME path (finds, daily rewards,
  referrals, codes, gem packs). Never decremented — a spend does not un-earn,
  and ShopSubs' refund of a failed gem purchase is deliberately not counted
  (crediting it would mint lifetime gems).
- **`cakesEaten`** — unchanged; `CakeCycleSubs.rewardPlayers` on a boss WIN.
- **`bestCakeMillis`** — the fastest single cake, in ms, minimum-only
  (`ProgressService.RecordCakeTime`). `0` = never finished a cake.
  - The clock belongs to the CAKE, not to a player: `CakeCycleSubs.SpawnNewCake`
    stamps `CakeStateData.cakeStartedAt` (`os.clock`) and snapshots
    `cakeStartRoster`; `rewardPlayers` measures once at the win.
  - Only the spawn roster gets a time. In a reserved match that is the final
    roster (`beginMatchIfReady` has already waited for every arriving profile);
    in the endless fallback it excludes anyone who walked in on a half-eaten
    cake.
  - ⚠ The time is RAW: difficulty, party size, cake variant and the PAID
    `layer-eater` product (`features/checkpoint.md` — 9 R$ clears a whole band
    instantly, and it is the largest distortion available, because a player can
    buy it repeatedly) are all un-normalised, so a 4-player hard run with layer
    eaters naturally beats a solo one. Deliberate — one board, one number.
    Splitting it would mean a store per bucket.
  - A **`DebugClearLayer` cake records nothing** (`CakeCycleSubs.rewardPlayers`
    checks `state.debugSuppressFindRewards`). Studio runs against the LIVE
    profile store, a debug-skipped cake reaches the boss in ~1 minute, and this
    board is ascending + minimum-only — that row would be unbeatable forever
    and only a `storeVersion` bump could remove it. `cakesEaten` deliberately
    still counts there: it is monotonic, and QA uses it to unlock the rainbow
    cake.

## Storage and cadence (ADR-0022)

`GlobalLeaderboardService` owns every direct `DataStoreService` call — the one
documented carve-out from P5. One `OrderedDataStore` per board, named
`EatACakeTop_<board id>_v<store-version>`, keyed by `userId`.

| Direction | When | Cost |
|---|---|---|
| publish | `OnProfileLoaded` + every `publishSeconds` (120 s), CHANGED values only | ≤1 `SetAsync` per changed board per player |
| read | every `refreshSeconds` (60 s), first read `firstRefreshDelaySeconds` after bind | 1 `GetSortedAsync` per board |

- **Zero is not a score** — `Publish` drops non-positive values, so "no record
  yet" is the ABSENCE of a row. Without this, every fresh account would tie for
  first place on the ascending speedrun board.
- `Publish` returns the SET of board ids that committed, and only those are
  marked as published. A count would be a lie the caller cannot detect: with
  two boards changed and one `SetAsync` throttled, marking both would strand
  the failed value for the life of the server — a first-ever cake time never
  changes again unless it is beaten, so it would simply never appear.
- **`PersistenceData.useMockInStudio` is mirrored here.** That flag promises
  "nothing is written to live DataStore keys" in Studio; it used to cover
  ProfileStore only, so flipping it would have left Studio running a mock
  profile while still writing the LIVE boards. With it on, leaderboard writes
  are suppressed and say so once.
- Both async ticks (publish sweep, board refresh) carry a busy latch with a
  start stamp: past three periods the latch is force-cleared with a warn, so a
  wedged sweep cannot stop the feature while the console stays quiet.
- Publishing is idempotent (the profile is the source of truth), which is why
  there is no publish on `PlayerRemoving`: `PlayerLifecycleSubs` unloads the
  profile on that same event and handler order is not a contract. The player's
  next profile LOAD publishes their final numbers instead.
- A failed read keeps the last good page rather than blanking a live board. The
  first failure is a loud warn naming the Studio API-access fix (R8); the rest
  are `Log.Once`.
- Names are resolved once per userId and cached for the life of the server:
  one batched `UserService:GetUserInfosByUserIdsAsync`, falling back to
  `Players:GetNameFromUserIdAsync`, falling back to `?` (cached too, so a
  deleted account is not re-requested every tick). DisplayName preferred.

## Authored GUI contract

Under `ReplicatedStorage.Assets.LobbyEnvironment`, cloned into
`workspace.LobbyMap` by `LobbyMapService` (ADR-0007) and wired by
`LobbyLeaderboardSubs.Bind(map)` from `LobbySubs`:

```
<Board Model>
  Screen1.SurfaceGui.MainFrame.ScrollingFrame
    UIListLayout                 (required — without it rows stack)
    FrameRank                    row TEMPLATE, authored Visible = false
      Rank                       TextLabel  "#1"
      PlayerName                 TextLabel
      <value label>              TextLabel  the number
      <icon>                     ImageLabel, cloned untouched
  Screen2.SurfaceGui.TextLabel   the board TITLE (static, never touched)
```

⚠ The three boards were authored from different kit sources, so the **value
label has a different name on each**: `Kills` (gems), `Rebirths` (speedrun),
`Strength` (cakes). `GlobalLeaderboardData.boards[].valueLabelName` carries the
mapping; renaming one in Studio falls back to "the text label that is neither
Rank nor PlayerName" and warns.

Missing model / incomplete GUI / missing `UIListLayout` → that board warns and
stays blank; the other two still bind, and the queue pads are never affected.

### Row geometry is derived, never hardcoded

A child's scale inside a `ScrollingFrame` is relative to the **canvas**, not the
window. The artist sized the template as `0.02` of a canvas `5.0` window-heights
tall, i.e. **one row = 0.1 of the window, 10 rows on screen, 50 rows of canvas**.
So for `entryCount = N`:

```
canvas.Y.Scale = N * (template.Size.Y.Scale * authored canvas.Y.Scale)   -- N * 0.1
row.Size.Y.Scale = 1 / N
```

which reproduces the authored row height for any `N` and leaves the scroll range
exactly one canvas long. At the shipped `N = 50` the canvas comes back to the
authored `5.0` — a free invariant check. `entryCount` is clamped to 1..100 with
a warn, because `GetSortedAsync` pages at 100 and rows past that would be dead
scroll forever.

`rowFraction` is captured at the FIRST bind and kept on the bound record:
re-deriving it from a `CanvasSize` that a previous bind already rewrote would
shrink every row by a further factor on each re-bind. `Rows.Build` also destroys
the previous generation of rows, so `Bind` is idempotent on the SAME map, not
only on a rebuilt one.

Two properties are normalised on the clone (logged, not silent): the row
`AnchorPoint` is zeroed (a `UIListLayout` writes `Position`, so an anchor of
`0.5,0.5` shifts every row half its size up-left) and `ScrollingDirection`
`XY → Y`. Rank/name/value get `AutoLocalize = false` — a player's name is data,
not a translatable string (`features/localization.md`).

## Files

| Piece | File |
|---|---|
| board defs, store naming, cadence, GUI names, runtime state | `server/common/data/GlobalLeaderboardData.lua` |
| OrderedDataStore publish/fetch, name cache, value formatting | `server/common/services/GlobalLeaderboardService.lua` |
| publishing (COMMON — gems are earned in both places) | `server/common/subscriptions/GlobalLeaderboardSubs.lua` |
| binding + the two async ticks (LOBBY) | `server/lobby/subscriptions/LobbyLeaderboardSubs.lua` |
| board lookup, row geometry, rendering | `server/lobby/subscriptions/LobbyLeaderboard/Rows.lua` |
| the three numbers | `ProfileSchema/ProgressSection.lua`, `ProgressService` (`RecordCakeTime`, `Summary`) |
| gem income counter | `RewardGrantSubs` (`gems` handler) |
| speedrun clock | `CakeStateData.cakeStartedAt` / `.cakeStartRoster`, `CakeCycleSubs` |

⚠ The boards read their value straight off `ProgressService.Summary` by the
`statKey` in `GlobalLeaderboardData.boards` — renaming a field in that table
silently empties a board.

## Tuning

All of it is `GlobalLeaderboardData["board-config"]`: `entryCount` (50; hard cap
100, one `GetSortedAsync` page), `refreshSeconds`, `publishSeconds`,
`firstRefreshDelaySeconds`, the authored GUI names, the count suffixes and
`storeVersion`.

**Bumping `storeVersion` starts every board empty** and is the only way to wipe
one. Do it if a stat's units or meaning ever change.

## Verified

`flow/2026-08-14_lobby-leaderboards.md` — live lobby playtest (place
126172008675265): clean R8 boot, `3/3 ordered store(s) resolved`, `3/3
leaderboard(s) bound, 50 rows each`, canvas back at the authored `{5,0}`, rows at
36.02 px each stacking 0/36.02/72.05/108.07, ordering and formatting exact
(`999.9B` / `1.2M` / `98.7K`; `9:59` → `21:37` → `35:12` → `1:04:05` ascending),
names resolved through `UserService`. Join-publish proven separately:
`profile-loaded hooks (5): ... GlobalLeaderboardSubs ...` -> `published 1 board
value(s) ... (join)` -> the board renders `#1 karnagiy 25` from the real profile.
