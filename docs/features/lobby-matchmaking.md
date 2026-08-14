# Lobby matchmaking

## Player flow

The lobby clones `ReplicatedStorage.Assets.LobbyEnvironment` into
`workspace.LobbyMap`. Entering any direct
`Touchers/<Model>/GroupToucher` admits the player to that pad. The first
admitted player is the leader and receives the kit `MatchmakingPanel`; they
choose a cake, `easy` / `medium` / `hard`, and a maximum party size from 1–4.
The 1000x600 selector uses a calm 904x432 split body: a 452px setup column, a
real 32px empty gutter, and a 420px cake carousel. Difficulty is three 142x112
portrait/icon-first tiles. Party Size is separately labelled with four larger
101x84 controls: the numeral is large on the left and the group glyph is large
on the right. Their centred headings share one gradient, and 48px of air
separates the Difficulty row from the Party Size heading. Reward prose and
passive backing wells are absent. The right has a 28px title, 12px gap, and a
420x300 horizontal `ScrollPane` containing 264x292 cake cards. Its exact
840px canvas opens with Classic fully visible and exactly half of Rainbow
visible; selecting an available Rainbow card scrolls it to the middle, fully
visible. The rainbow card persistently owns its wrapped, localized unlock
requirement; the coming-soon title + clock are not repeated as a second status
sentence. The old text row above START is absent. Busy and error feedback replace
the START label inside the button itself, and the centred 760x76 START finishes
the window directly beneath the groups. **The selector
opens on `MatchConfig.defaults` (Easy / 1 Player)**, so a
solo run is ONE tap and START is live on the first frame. Defaults are applied
per SESSION; rendered state is stored as `{sessionKey,value}` so a newly opened
pad reads its validated defaults synchronously instead of exposing the prior
session for one effect-delayed frame. A matching synchronous choice ref is
updated before React redraws, so a rapid setup tap + START dispatches the newly
tapped pair rather than the previously rendered pair. One not currently offered
(above the pad cap or retired) is ignored. The cake carousel opens on the
persisted selection: Classic clamps to the authored one-full-plus-half-Rainbow
opening, while a persisted available Rainbow selection is centred.
START **breathes** (`Components.Button` `pulse`) exactly while live;
its clipping CanvasGroup is inflated by
`MatchmakingLayout.StartPulseHeadroom` while the button is inversely deflated,
so rest geometry is unchanged. The cake gallery edits the leader's persistent
account preference rather than queue-local state — see *Cake gallery* below.

The full-bleed modal scrim still covers CoreUI, but AppRoot fits and centres the
panel itself inside the usable region below Roblox's resolved topbar inset. The
ordinary 90%-of-viewport size is preserved when it fits; short landscape phones
may use up to 98% of the remaining safe height so the large controls do not
collapse merely to create redundant outer margin.
⚠ A preselection is REPORTED like a tap (`onSelectDifficulty(id, isDefault)` /
`onSelectPlayers(n, isDefault)`): the `difficulty-pick` / `party-pick` flow steps
sit between `selector-open` and `start-press`, so leaving them unreported would
show every one-tap start as a drop-off (`features/analytics.md`). Whether the
player actually CHOSE is still visible — the kit counts the `Difficulty_*` /
`Players_*` presses themselves, and those only exist when a finger lands on one.
The effect reports only for a real `sessionKey`; the panel is mounted (hidden)
for the whole lobby visit and must not beat on mount.
A valid choice starts a server-owned countdown whose length depends on PARTY SIZE
(`Core.CountdownSeconds`): **5 s solo, 15 s for 2+** — a solo player is only
waiting on themselves. Picked once, when START is pressed, so a late joiner
rides the remaining time rather than resetting it. Players standing in the same
toucher are reconciled by overlap scan, up to the selected cap; stepping out
removes them after the configured grace period.

At expiry the current admitted roster is profile-released and sent by one
`TeleportAsync` call to a reserved server in place `136881957250247`. The finite
roster/difficulty/result contract is `features/game-round.md`; profile handoff
guarantees and retries are `features/persistence.md`. The public return lobby is
place `126172008675265` (ADR-0010).

## Authored lobby contract

Under `ReplicatedStorage.Assets.LobbyEnvironment`:

- `Touchers` contains one or more direct Models. Each has direct
  `GroupToucher` (`BasePart`) and `GroupToucherVisual`.
- `GroupToucherVisual.PlayerCount.Txt` shows `present/max`.
- `GroupToucherVisual.WaitingStatus.Txt` shows waiting/configuration,
  `<Mode> - <seconds>s`, teleporting, or failure state. Legacy `ChestStatus` is
  normalized to `WaitingStatus`; legacy scripts under each toucher clone are
  removed before it enters Workspace.
- `Forest.Chocolate["Meshes/chocolate"]` is a `BasePart`; touching its runtime
  clone opens the existing Shop panel.
- `LobbySpawn` is the invisible authored `SpawnLocation` at `(0, 0.5, 90.5)`.
- `TopGems` / `TopSpeedrunners` / `TopCakeCount` are the three leaderboard
  screens; their own contract is `features/leaderboards.md`. `LobbySubs` binds
  them from the same clone, BEFORE the queue pads and never gated on them —
  neither half may take the other down.

`ReplicatedStorage.Assets.LobbyMapContainer` is an empty authored Folder cloned
as `workspace.LobbyMap`; the environment clone is parented beneath it. If the
container/environment is missing, the existing Workspace is preserved and the
map/queue bind warns instead of creating runtime fallback view objects.

Missing authored dependencies warn and degrade without stalling (R8). Pads are
ordered left-to-right by model pivot X and keep independent sessions.

## Network and authority

| Direction | Remote | Contract |
|---|---|---|
| client → server | `LobbyQueueRequest` | `(action, sessionKey, difficulty?, maxPlayers?)`; `action` is `configure` or `leave`. Rate-limited, session-correlated, leader-only. |
| server → client | `LobbyQueueUpdate` | `(kind, payload?)`; `open`, `close`, `error`, or `busy`. `open` carries `{sessionKey,currentPlayers,maxPlayers}`. |

The client never chooses a destination, roster, countdown, cake, or reward.
Game join data must match protocol version, universe/lobby source, round id,
difficulty, playable `cakeId`, contiguous unique roster, count, and arriving
user. The cake is NOT an argument of `LobbyQueueRequest`: cake taps use the
separate `SelectCake` remote. At launch the server reads the leader's persisted
selection and adds it to protocol-v2 TeleportData:
`{version, roundId, difficulty, cakeId, expectedUserIds, expectedCount,
sourcePlaceId, analytics?}` (`features/cake-select.md`,
`features/game-round.md`).

## Cake gallery

The matchmaking window's right cake gallery edits the persisted ACCOUNT preference
owned by `CakeSelectSubs` (`features/cake-select.md`), not a per-session field
owned by the queue panel. The server snapshots the leader's value only when the
launch is created.
Verified against `MatchmakingPanel` and the queue code; do not re-derive:

| Claim | Status |
|---|---|
| rides `LobbyQueueRequest` | no — `onStart` still sends exactly `(difficulty, maxPlayers)`; taps leave on `SelectCake` |
| in the queue record / launch teleport data | queue launch carries `leaderUserId`; `Launch` resolves it to authoritative `cakeId` in TeleportData |
| `GameRoundService.validateLobbyJoin` | validates `cakeId` against playable variants; later arrivals must match the established cake |
| panel state | no cake-selection state — not in `sessionRef` and not reset with difficulty/party; an optional legacy-layout notice id is presentation-only, while the default layout renders the earnable requirement on its card |
| readiness gate / status ladder / START pulse | unaffected — both still count difficulty + party size only |

Props `cakeOptions`, `cakeTitle`, `onSelectCake` are OPTIONAL. The 420x300
`ScrollPane` runs on X with no track or scrollbar. Three fixed 264x292 cards,
two 16px gaps, and 8px side padding make an exact 840px canvas:
`8 + 3*264 + 2*16 + 8 = 840 = 2*420`. At offset zero Classic occupies
x8..272 and Rainbow occupies x288..552, so x288..420 exposes exactly 132px —
half of Rainbow — as the direct-manipulation cue. Card placement and tap
hit-testing share the same carousel helpers, so visual and interactive geometry
cannot drift. Mouse/touch drags begin on a transparent capture surface over the
cards; an 8px threshold classifies the
gesture before dispatch. A confirmed unlocked tap cues and selects exactly
once; locked/busy taps emit one dead press; a drag emits no cue, analytics, or
selection. Wheel input also scrolls. The pointer surface is not controller
selectable; the real `CakeCard` buttons remain underneath. Unlocked controller
activation selects; locked/soon cards remain focusable and route non-pointer
activation to one dead-press beat. The earnable requirement is already visible
on the rainbow card, while the teaser title and clock explain its state. Tap
hit-testing uses the same two-dimensional card geometry at both press origin
and release, so gaps do nothing and a small gap-to-card drift cannot manufacture
a choice. The deterministic reset target is the selected card centre minus half
the 420px window, clamped to the X range; Rainbow lands at offset 210 and is
fully visible in the middle. The reset key includes the session and selected
cake id, so the same mounted pane follows the authoritative persisted selection
after a tap. Pass no options and the cake title/pane are omitted. Choosing a
cake persists immediately; the value present at launch controls the round for
every roster member (`features/cake-select.md`). The default layout has no
status row above START: card requirements stay on their cards and busy/error
feedback appears inside START. A legacy/custom layout may explicitly opt back
into a contextual notice or status slot without changing the default contract.

While START is busy, every selector, START, the panel X and the outside scrim
are inert. The cake capture surface stays present but freezes scrolling so a
confirmed tap reports one dead press and a drag reports nothing. START first
sets a synchronous per-session launch latch; every setup/cake/close callback
consults it until authoritative busy has been seen and later returns false.
This closes the one-render window in which a second held pointer could otherwise
change a choice, close the panel, or fire START twice. The same transition guard
is enforced by AppRoot's matchmaking closer, its shared cake/setup callbacks,
and HUD panel replacement; background HUD toggles are inert behind every modal,
and the chocolate Shop trigger never replaces a busy selector.
Configure is ordered before leave, so allowing any of those paths to hide the
panel would make the server reject the late leave while its countdown continued
invisibly.
Logical close disables every controller target immediately and places a
transparent full-panel pointer blocker above the still-visible close tween; no
late tap can change setup, persist a cake, or start an invisible countdown.

## Visual hierarchy and verification

Final annotation contract: START L1; selected cake/card mass, selected setup
controls, group headings, and conventional close/header title L2; unselected
setup controls plus locked/soon cards L3; panel and future-row cue L4. The header uses the shared
`HeaderWide` family. Unlocked/unselected cake bodies stay navy; locked/soon
cards alone use graphite with recognizable but faded art. Selection is the
shared gold perimeter around a royal-navy card Face — no flavour/rarity purple
and no redundant check disk. START is the only large green field and the first
non-reader target.

Heavy colour and grey Squint retain START and the cake masses while setup
controls merge into their column. The panel contains short labels and
icon/count controls; repeated requirements, reward/multiplier prose, art plates,
passive group wells, and the cake scrollbar are absent.

The current peek-carousel/party-control verification is recorded in
`flow/2026-08-12_matchmaking-peek-carousel.md`. The prior grouping/card-text
pass is in `flow/2026-08-12_matchmaking-grouping-polish.md` (IMPROVED, zero
final critical findings). The child-first baseline is in
`flow/2026-08-11_matchmaking-child-first-cleanup.md`; its prior composition is
preserved in `flow/2026-08-11_matchmaking-cake-gallery.md`.

## Place/UI contract

`LobbyUiData` and `GameUiData` are project-mapped partition markers. In the
lobby, AppRoot hides the cake HUD, belly, checkpoint button, eat control, game
overlays, and gameplay input subscriptions; the lobby meta menu, matchmaking,
and chocolate Shop flows remain active. During any verified-release handoff,
the server `Teleporting` attribute holds a reason-keyed client movement lock;
recovery releases it without racing other modals. In the game, lobby/meta UI
and touch wiring are absent. The combined
development build maps both markers but intentionally does not build the lobby
map while `MapService` is present.

## Tuning and files

`Shared.config.MatchConfig` is the single contract for modes, `defaults`
(the selector's opening pick), cap, countdown,
arrival/result timings, authored names, and teleport retry limits. Difficulty
presentation (`ui["icon-name"]`, `ui.accent`, `ui["description-key"]`) also
lives on each difficulty definition; AppRoot localizes the icon, label and
reward cue for the stacked control (the description remains config-compatible
copy, but is deliberately omitted from this setup rail). Difficulty scales
eating WORK, the calorie payout and boss HP/time —
**not cake height**
(`cakeHeightMultiplier` is gone: a bite clears to the band floor, so height never
moved clear time). Authoritative profile/economy state never travels in teleport
data.

Server: `LobbyQueueData`, `LobbyQueueService` + `services/LobbyQueue/*`,
`LobbyQueueSubs` + `subscriptions/LobbyQueue/*`, `GameRoundService`,
`GameRoundSubs`, `CakeCycleSubs`, `TeleportSubs`, `TeleportRetrySubs`.
Client/kit: `LobbyUiData`, `LobbySubsClient`, `AppRoot`, `MatchmakingPanel`,
`MatchDifficultyChoice`, `MatchPartyChoice`, `CakeCard`, `ScrollPane`,
`PlayerControlData`, `PlayerControlService`,
`TeleportControlSubsClient`.
