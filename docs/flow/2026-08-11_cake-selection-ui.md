# 2026-08-11: Cake selection UI

Tags: cake-select, app-root, lobby-matchmaking, ui-kit, persistence, localization, theme

## Task
"Add a rainbow cake that can be selected after the player has eaten the default
cake. For now, do not add the cake itself. Only create the cake selection UI in
the main menu. The rainbow cake should remain locked until the player has eaten
the first cake at least once. Also add cake selection to the window where the
player chooses the difficulty and number of players." Cake art: current
`116652893791245`, rainbow `94925525153721`. First cake selected by default; the
player must still SEE the second cake exists and what unlocks it.

Session opened with a different question — whether the Studio MCP was safe to
drive while the user had a SECOND Studio (`Defenders_DontPublish`) open. It was
not, by default: the proxy reported *"The active Studio instance is not yet set.
A heuristic will be used"* with Defenders listed first. Pinned via
`set_active_studio` and verified by IDENTITY (`game.PlaceId` 126172008675265 +
`ServerScriptService.Server.Lobby` present), not by display name. The user then
disconnected the other Studio's MCP, leaving one instance.

## Context
Nothing recorded the chosen cake — the feature is entirely new. What already
existed and decided the design: `progress.cakesEaten` (ProgressSection),
incremented in exactly ONE place (`CakeCycleSubs.rewardPlayers`, on a boss win),
not run-scoped, surviving the teleport. So the unlock signal needed no new
counter and no backfill — only replication, since no remoteUpdate carries any
`progress.*` field and the sole client-visible copy is a 10-second-heartbeat
leaderstat.

## Plan
Recon first (6 parallel readers over lobby menu / matchmaking panel / UI kit /
persistence / localization+analytics / flow history), then two decisions put to
the user because each changed work that is expensive to redo:
- **Unlock bar** → "beat the boss" (reuse `cakesEaten`), over the looser
  "finish a run", which has no persisted signal and would need a new write site.
- **Rainbow once unlocked** → fully selectable (two-state card), over a
  temporary SOON state (three-state card + throwaway copy).

Then: shared catalogue → backend (profile section, remotes, subs) in parallel
with the UI (Theme, three kit components, matchmaking band, AppRoot).

## Changes

**Created:**
- `src/shared/config/CakeSelectConfig.lua` — the catalogue (order, defaultId, per-cake rule)
- `src/server/common/data/ProfileSchema/CakesSection.lua` — profile section `cakes`
- `src/server/lobby/subscriptions/CakeSelectSubs.lua` — push + validated selection
- `src/client/lobby/subscriptions/CakeSelectSubsClient.lua` — client state bridge
- `src/shared/remotes/SelectCake.model.json`, `src/shared/remoteUpdates/CakeSelectUpdate.model.json`
- `src/shared/UIKit/Components/CakeCard.lua`, `CakeChoice.lua`, `CakeSelectPanel.lua`
- `docs/features/cake-select.md`

**Modified:**
- `src/shared/UIKit/Theme.lua` — `CakeSelectLayout` / `CakeCard` / `CakeChoice` / `CakeLockBadge` (+ freeze lines), `AppHud.MenuIcons.Cakes`, `MatchmakingLayout` re-budgeted 904x420 → 904x432 (444 in round 1, corrected below), `MatchmakingStartButton.AspectRatio` 360/68 → 360/58
- `src/shared/UIKit/Icons.lua` — `CakeClassic`, `CakeRainbow`
- `src/shared/UIKit/init.lua` — registered the three components
- `src/shared/UIKit/Components/MatchmakingPanel.lua` — third band (optional props only)
- `src/client/common/modules/AppRoot.lua` — `cakes` state, view model, menu entry, panel, matchmaking props
- `src/client/common/data/LocaleData.lua` — 8 keys (6 in round 1, 2 for the teaser slot)
- `src/server/common/services/ProgressService.lua` — `CakesEaten(userId)`

## Decisions
- **Ids are `cake-classic` / `cake-rainbow`, not the bare flavour.**
  `CakeConfig.rare.rainbow` and `CakeStateData.rareKind = "rainbow"` already
  exist and mean a ~1% re-skin of the CURRENT cake. Two unrelated things sharing
  the string `rainbow` would be indistinguishable in configs, payloads and
  analytics buckets.
- **Entitlement is DERIVED per push, never stored.** One source of truth, no
  migration, and existing accounts are entitled on ship. A section's `sanitize`
  cannot read another section anyway.
- **`isUnlocked` returns `(unlocked, evaluated)`.** Found by the adversarial
  pass and worth the extra return value: failing closed is correct on the push
  path (card renders locked, self-heals) but `OnProfileLoaded` WRITES into an
  auto-saving profile — so a config typo (`unlockRule = "gamepass"`, a string
  threshold) would have silently wiped the stored pick of every player who chose
  that cake, unrecoverably. Only an explicit evaluated-false coerces.
- **The cake band is presentation only.** It does not enter MatchmakingPanel's
  session state, `sessionRef`, the readiness gate, the status ladder or
  `onStart`, and it does NOT ride `LobbyQueueRequest`. Recorded as an explicit
  NEGATIVE in `features/lobby-matchmaking.md` so it is not re-litigated.
- **The matchmaking budget was bought from the existing bands, not from a
  taller panel.** The old 420 closed exactly, so every band shrank. A taller
  nominal panel renders NARROWER at the fixed height fraction and would have
  shrunk all the type.
- **Only the LOCKED card goes grey.** Grey is this kit's locked language and has
  misfired twice on shop tabs; an unselected-but-unlocked card keeps the normal
  navy body, or "not chosen" and "cannot have" look identical. The locked art is
  faded, not tinted, and its window leaves the accent family so a Legendary-gold
  window does not make the unselectable card the brightest thing on the panel.
- **Deleted `ProgressService.HasEatenACake`** (written by a subagent, unused):
  it hardcoded `>= 1`, duplicating the threshold the catalogue owns.
- Menu entry added as the 6th base row: at 2 columns, 5 and 6 entries are both
  3 rows and 7 and 8 are both 4, so the block's height never changed.

## Verification
- `luau-compile` clean on all 14 touched Lua files; `rojo build` clean on
  `lobby`, `game` and `default` project files.
- Rojo confirmed live-synced by reading `.Source` markers in Studio (never
  `require`, which caches per session and makes a stale module look synced).
- ⚠ **Play mode would not start over the MCP** (timeout, then "hasn't finished
  yet" x2, `get_studio_state` stuck on Edit) while `execute_luau`,
  `screen_capture` and `get_studio_state` all worked. Verified in EDIT mode
  instead, through the clone-require preview harness, by MEASURING live
  instances — which is what the kit checklist demands anyway, since the
  card-vs-button regression is invisible to the eye on a whole-panel screenshot:
  - `CakeCard`: outline bottom/top **1.44x** (CARD recipe; the shop's shipped
    defect was 3.75x), even 7.4px side/top outline, aspect **0.81**, icon 30.8%
    of the cell. Classic at `ImageTransparency 0` with no lock badge and no
    status line; rainbow at **0.4** with both.
  - `MatchmakingPanel` at render scale 0.822: every band landed within 0.2px of
    its nominal position, CakeRow 220.4..269.8 (expected 220.3..269.6), and the
    row closes horizontally 363 + 17 + 363 = 743 ✓. Lock badge and the 0.32 dim
    on the rainbow strip only.
  - Harness cleaned up (`CoreGui.CakePreview`, `Shared.UIKitPreview` both gone).
- NOT yet done: a real playtest (console vs the R8 boot contract, a select
  round-tripping through the server), and the tonal-hierarchy / squint passes.

## Round 2 — "the UX is very poor" (same session)
User feedback after the first build: **the cakes should be the main focus**, add
a **scrollbar** to browse them, and add a **"Coming Soon" cake** so players
understand the second cake is not the last one.

What was wrong: two fixed cards centred in a 904-wide box left ~160px of dead
margin, so the panel read as mostly empty chrome around the only thing worth
looking at. Fixed by turning the showcase into a **browsable gallery**:
- `CakeSelectPanel` rebuilt as a 3-column grid in the kit's `ScrollPane`
  (deterministic rows → `canvasHeightScale`, `FillDirectionMaxCells` always set,
  cell wrapper carrying the baked row gap). Cards fill 870 of the 904 pane.
- `Theme.CakeCard` re-cut 350x432 → **282x348**, and the art window GREW into the
  space the (never-present) price shelf freed: icon is now **33%** of the cell vs
  the shop card's 22% at the same width. Same card recipe — measured 1.43x
  bottom/top outline.
- Third catalogue entry `cake-coming-soon` with a first-class
  `unlockRule = "coming-soon"` the server RECOGNISES and always answers
  *locked, evaluated* for. Not a special case in the UI: it is `locked` like any
  unearned cake and differs only by badge glyph (clock vs padlock) and copy, so
  the two never become separate card types. It borrows the `UiBox` mystery-box
  glyph — a cake that does not exist has no art.
- The matchmaking band now **auto-fits its count** — a fixed tile width would
  have overflowed the row the day a cake was added. At n=3 the cake tiles measure
  231px, identical to the difficulty tiles above them.

⚠ **The scrollbar is invisible at 3 cakes and that is deliberate**, not an
omission: `ScrollPane` drops its track when the canvas provably fits, because a
thumb that cannot move advertises content that is not there. Proven both ways in
Studio — 3 cakes: track absent, canvas 317 == window 317; 5 cakes: track present,
canvas 584 vs window 317, scrollable true. It appears by itself at the 4th cake.

Measured after the rebuild: cards 225x278 on screen (aspect **0.809**) at
x 0 / 235 / 471, last edge 696 inside the 698 window — no float-wrap, no collapsed
cells. Band: 3 x 231 + 2 x 16 = **725** = the row width exactly.

### Round-2 fix from adversarial review: the panel FLOOR is 573, not 600
The first cut of the cake band budgeted the matchmaking content box against the
**nominal 1000x600**, growing it to 904x444 at y132..576 and calling the leftover
"bottom margin 24". But `Theme.PanelWide`'s visible BODY FILL ends at y **573**
(`FillPosition 96/600` + `FillSize 477/600`); below it is the dark border ring
(86..583), which content draws OVER at zIndex 5. So only 21 px were ever body,
and START's bottom 3 nominal px (~5 real px at 1080p) sat on the ring.

Re-budgeted to 904x**432** at y132..**564** — the floor every peer wide layout
already respects (Rewards footer 564, Shop pane 564; PetsInspect 559). The 12 px
came out of the HEADINGS (32 → 28, three of them) rather than the tiles: a
heading is a label, a tile is a hit target. New check-sum
`(28+8+60+14)*3 + 34 + 10 + 58 = 432 ✓`.

Re-measured: fill bottom 573 nominal · content bottom 564 · START bottom 564,
`startInsideFill = true`, clearing the fill edge by ~7 real px. Bands still close
exactly (DifficultyRow 36..96, PlayersRow 146..206, CakeRow 256..316, Status
330..364).

⚠ **The lesson worth keeping: a wide panel's usable height is its FILL, not its
nominal grid.** Budgeting a content box against `1000x600` silently buys px that
are border ring. Two other stale-comment findings from the same review were also
fixed (the HUD menu-capacity comment in Theme still said 7 buttons / five meta
panels; and both `LocaleData` and `data-keys.md` claimed this feature reuses
`btn-locked`, which grep disproves — the lock is a badge GLYPH and the only copy
is the hint line).

## Open Questions / Followups
- **Play mode via MCP is stuck** — needs a human press, or a Studio restart.
  The R8 console check and the live select round-trip are still outstanding.
- **The chosen cake does not reach the run.** By scope. When the rainbow cake
  exists, read `profile.cakes.selected` at match launch.
- Localization: the 8 new keys need `robloxloc.py pull` → `push` → `pull` to
  reach the other 15 languages; until then they render English (a `T` miss
  returns the key). `cake-name-soon` is `"???"`, which reads in every language.
- No "you unlocked a cake!" moment. The rainbow simply appears unlocked. The
  `HudMenuButton` badge mechanism exists but currently means "claimable"
  (Daily / Group Reward) and reusing it would broaden that meaning.

## Related
- Feature: `docs/features/cake-select.md`
- Also updated: `features/app-root.md`, `features/lobby-matchmaking.md`, `features/ui-kit.md`
- ADRs touched: none (ADR-0009 partitions and ADR-0013 run-scoping both held as-is)
- Prior flow: `docs/flow/2026-08-09_arrow-until-purchase-safe-area-slide-entrance.md`
