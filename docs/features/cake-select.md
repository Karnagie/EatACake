# Cake selection (choose which cake you play)

## What it does
The lobby lets the player pick a cake from a browsable catalogue. Three ship
today: `cake-classic` (always unlocked, the default), `cake-rainbow` (locked
until the player has finished a cake at least once) and `cake-coming-soon` (a
TEASER — permanently unpickable, present so the catalogue does not read as
"there are two cakes and you have seen both"). Two surfaces, one state: a full
chooser panel from the meta-menu **Cakes** button, and the compact three-card
portrait rail on the right of the matchmaking window.

## Match ownership and game handoff
The selected cake now controls the run. The queue request remains exactly
`(difficulty, maxPlayers)`: at countdown expiry, the server snapshots the
**leader's** persisted `profile.cakes.selected`, validates that it is both a
catalogue entry and a playable `CakeConfig.variants` entry, and writes `cakeId`
into protocol-v2 TeleportData. The destination validates it again, stores it as
`RoundStateData["cake-id"]`, and requires every later arrival to match it.

The leader's choice owns the whole party. Members do not need the same cake
selected or unlocked on their own accounts; the entitlement controlled who
could choose the match, not who may join it. Production direct joins use
`CakeConfig.defaultVariantId` (`cake-classic`); Studio direct/fallback Play uses
`CakeConfig.studioVariantId` when set (currently `cake-rainbow`) so the selected
variant can be tested without changing production defaults or profile data.
Unknown, teaser, or corrupt selections fall back to the validated default in
the lobby; an invalid arrival is rejected in the game place. Runtime differences between classic and rainbow
(fixed colour terraces, height/duration, coating, room and find payout) are the
single-source contract in `features/cake-cycle.md` and ADR-0020.

## Catalogue — `src/shared/config/CakeSelectConfig.lua`
`order` (render order) · `defaultId` · `cakes[id] = { nameKey, iconName, accent,
unlockRule, unlockCakesEaten?, unlockHintKey? }`. Data only: no asset ids (icon
NAMES resolve via `Theme.Icon`), no literal strings (locale KEYS via `locale.T`).

⚠ Ids are `cake-classic` / `cake-rainbow`, **not** the bare flavour:
`CakeConfig.rare.rainbow` and `CakeStateData.rareKind = "rainbow"` already exist
and mean a ~1% roll that re-skins the CURRENT cake. Two different things must
never share a string across configs, payloads and analytics buckets.

`unlockRule` is `"none"`, `"cakes-eaten"` or `"coming-soon"`. A rule the server
does not recognise is treated as **locked** and warned about — never silently
granted.

`"coming-soon"` is a first-class rule, not a hack: the server recognises it and
answers *locked, evaluated* — "this cake does not exist yet" is a real answer,
not a failure to compute one. That keeps it out of the unknown-rule warning and
lets `OnProfileLoaded` correctly coerce a stored selection naming it. Giving the
teaser real art and a real rule turns it into an ordinary entry with **no code
change anywhere**.

## The unlock signal
`profile.progress.cakesEaten >= 1`. That counter already existed
(`ProfileSchema/ProgressSection.lua`) and is incremented in exactly one place —
`CakeCycleSubs.rewardPlayers` — **on a boss WIN**. So "has eaten a cake" means
*beat a cake*, not *played a run*. The `progress` section is not run-scoped
(ADR-0013), so it survives the run reset and the lobby↔game teleport, and the
lobby server can read it with no new plumbing.

**Entitlement is never stored.** It is derived per push, which keeps one source
of truth and means existing accounts need no backfill: a player who has already
eaten a cake is entitled the moment this ships. The threshold lives in the
catalogue (`unlockCakesEaten`), never as a hardcoded `>= 1` in a service.

## State
Profile section `cakes` (COMMON partition — both places load the profile):
`selected: string`, v1, no migration (a new section is materialised from
`defaults` on load). There is deliberately **no `unlocked` set** — see above; a
section's `sanitize` can never read another section anyway, since
`PersistenceService` hands it only its own slice.

## Flow
Join: `CakeSelectSubs.PushInitialState` (auto-discovered by
`PlayerLifecycleSubs`) → `CakeSelectUpdate { selected, unlocked }`.
⚠ `unlocked` is an **ARRAY** of ids on the wire — RemoteEvent serialization
stringifies numeric table keys. The client turns it into a set once per push.

Select (`SelectCake`, one arg — the cake id):
1. Profile loaded? (else `Log.Once`, no write — the one path that cannot
   re-push, because there is nothing to build a push from).
2. R6 validation: a string, a catalogue key, **and unlocked for this account**.
   Every rejection RE-PUSHES the authoritative state, so a desynced or modified
   client is corrected rather than left believing its own lie.
3. Write `profile.cakes.selected` via `PlayerProfileData` (P4). No explicit
   `PersistenceService.Save`: a preference auto-saves while the session is live;
   `Save` is reserved for Robux milestones (P5).
4. Confirming push.

`OnProfileLoaded` repairs a stored selection that is unknown **or no longer
unlocked** (a rule tightened after the fact) — entitlement can only be checked
here, where `progress` is visible.

## Gotchas
- ⚠ **`cake` and `cakes` are different AppRoot state fields and both are live.**
  `cake` is the in-run cycle snapshot driving the CakeBar; `cakes` is this
  feature's `{ selected, unlocked }`.
- ⚠ **A config error must never destroy a saved pick.** `isUnlocked` returns
  `(unlocked, evaluated)`. Failing closed is right on the push path (render the
  card locked — recoverable) but `OnProfileLoaded` WRITES to an auto-saving
  profile, so it coerces only on an explicit `evaluated = true, unlocked =
  false`. An unknown rule / bad threshold / missing `ProgressService` leaves the
  stored value alone and warns. Reverting a bad config could not undo a save.
- ⚠ **Do not read `leaderstats.Cakes` as a shortcut** for the unlock. That
  IntValue is written on a 10 s heartbeat (`LeaderboardSubs`), so a player who
  just cleared their first cake would watch the rainbow stay locked for up to ten
  seconds after earning it.
- ⚠ **Grey means LOCKED in this kit, and only that.** An unselected-but-unlocked
  card keeps the normal navy body. Quieting it too would make "not currently
  chosen" and "you cannot have this" look identical — a failure this project has
  already shipped twice on shop tabs.
- ⚠ The locked card's art is **faded (`ImageTransparency`), not tinted**, and
  stays clearly readable. Seeing what you have not unlocked is the entire point
  of rendering a locked card.
- The panel and the matchmaking gallery share one view model and one callback, so
  the two surfaces cannot disagree about what is selected.
- `cake-coming-soon` is catalogue-only: it deliberately has no
  `CakeConfig.variants` entry and therefore cannot cross the launch boundary.
- `CakeConfig.studioVariantId` is a Studio-only test switch. Set it to nil to
  restore ordinary classic direct/fallback Play; it never overrides a real
  lobby match's explicit protocol-v2 `cakeId`.
- In a COMBINED build, `CakeCycleSubs` rewards `Players:GetPlayers()` in the
  endless/dev fallback, so a Studio playtest can unlock the rainbow for a player
  who ate nothing. Not a bug in this feature.

## UI
Panel `Cakes` → `UIKit/CakeSelectPanel`: landscape 1000x600, a **3-column grid
in the kit's ScrollPane**. Cells are `CakeCard` (282x348, CARD recipe per
style-rules §2b — measured outline bottom/top **1.43x**, aspect 0.809, icon 33%
of the cell against the shop card's 22% on the same width, because the ART IS
THE PRODUCT here).

⚠ **The scrollbar is invisible until there are 4 cakes, by design.** `ScrollPane`
drops its track when the canvas provably fits (`canvasHeightScale <= 1.001`) — a
full-height thumb that cannot move advertises content that is not there. Grid
window 870 shows one full row (348) plus 32px of the next; a 4th cake makes two
rows, canvas 1.84x the window, and the bar appears on its own. Both states were
measured (3 cakes → track absent, canvas == window; 5 cakes → track present,
canvas 584 vs window 317).

Inside `MatchmakingPanel`, `CakeCard` uses the large portrait
`Theme.MatchCakeCard` style in a right-side 420x300 horizontal `ScrollPane`.
Three fixed 264x292 cards sit on an exact 840px canvas with 16px gaps, 8px side
padding, and 4px cross-axis padding. At offset zero Classic is fully visible and
exactly half of Rainbow is visible, teaching direct scrolling without a track.
The 190px rendered cake art is free-standing on the card Face: matchmaking sets
`ShowArtPlate = false`, while the standalone portrait chooser keeps its art
window unchanged. Mouse/touch drag directly on the card surface and wheel input
moves X. Selecting an available Rainbow card resets the mounted pane to offset
210, placing that full card in the middle; reopening uses the persisted cake id
as the same semantic centring target.

States: selected = gold Outer plus a royal-navy Face mass in the matchmaking
style, with no redundant green check disk or flavour/rarity purple · unlocked = normal navy body ·
locked = grey body + faded art + **padlock** badge · comingSoon = the same grey
language with a **clock** badge. One unavailable visual language, two messages.
The rainbow card owns its wrapped localized earnable requirement. Matchmaking
has no shared text row above START; busy/error feedback replaces the text inside
START itself. The teaser's title and clock already say coming soon, so
matchmaking does not repeat that sentence in another status block. The portrait
chooser retains its grey art window; only the matchmaking variant removes that
nested plate.

⚠ The full chooser's locked card is a **real disabled pressable**, not an inert
Frame: `usePressable({ enabled = false })` reports a dead press. Matchmaking
adds a transparent pointer capture surface above the same real cards so a drag
cannot leak pointer-down sound/analytics/activation: after the 8px classifier,
an unlocked tap cues+selects once, locked/busy taps report dead once, and a drag
reports nothing. Both press origin and release must resolve to the same tile, so
sub-threshold jitter from a gutter cannot select. The surface is not controller-selectable; underlying cards
remain controller buttons, including unavailable cards: non-pointer activation
on a locked/soon tile records one dead press, while persistent card/title copy
already explains the unavailable state. `CakeCard` passes `analyticsId` explicitly. The
exported `CakeChoice` is legacy and has no live caller; `MatchChoice` likewise
no longer powers this screen.

The matchmaking budget is exact: 452px setup + 32px empty gutter + 420px cake
carousel = 904. The upper configuration is 340px. Left:
`28 + 12 + 112 + 48 + 28 + 12 + 84 + 16 = 340`; the four 101x84 Party
controls close horizontally as `4*101 + 3*16 = 452`. Right:
`28 + 12 + 300 = 340`. Footer: `340 + 8 + 76 + 8 = 432`, with no status
row. Cakes close as `8 + 3*264 + 2*16 + 8 = 840 = 2*420`; Classic is one
full card and the 132px Rainbow preview is exactly half a card.
Easy/1 synchronous session defaults, busy gating, and the exact two-argument
`onStart(difficulty, maxPlayers)` contract are unchanged.

⚠ **That window's floor is y564, and its usable height is the panel's FILL, not
its nominal 1000x600.** `Theme.PanelWide`'s body fill ends at y573; below it is
the dark border ring, which content draws over at zIndex 5. The first cut of this
band budgeted against the 600 nominal, reached y576, and put START's bottom 3
nominal px on the ring. Any future growth starts from y564, not y576 — the
arithmetic in `Theme.MatchmakingLayout`'s header block is the source.
Growing the nominal PANEL instead is the other trap: the fit is height-driven, so
a taller panel renders NARROWER and shrinks all its type.

## Files
Shared: `config/CakeSelectConfig`, `remotes/SelectCake`,
`remoteUpdates/CakeSelectUpdate`.
Server (COMMON): `ProfileSchema/CakesSection`, `ProgressService.CakesEaten`.
Server (LOBBY): `CakeSelectSubs`, `LobbyQueue/Lifecycle`, `LobbyQueue/Launch`.
Server (GAME): `GameRoundService`, `RoundStateData`, `CakeCycleService`.
Client (LOBBY): `CakeSelectSubsClient`. Client (COMMON): `AppRoot` (`cakes`
state, `Cakes` panel + menu entry, `onSelectCake`), `LocaleData`.
Kit: `CakeCard`, `CakeChoice`, `CakeSelectPanel`, `ScrollPane`, `Theme.CakeCard`
/ `.MatchCakeCard` / `.CakeChoice` / `.CakeLockBadge` / `.CakeSelectLayout`, `Icons.CakeClassic` /
`.CakeRainbow` (`Icons.UiLock` and `Icons.BadgeClock` were already there —
`UiLock` was unused until now; the teaser card borrows the `UiBox` mystery-box
glyph because a cake that does not exist has no art).
