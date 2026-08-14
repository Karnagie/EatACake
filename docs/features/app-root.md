# AppRoot (composed UI root: HUD + panels + overlays)

## What it does
The ONE React tree rendered through `UiRoot.Render` (single-root contract,
`docs/features/ui-kit.md`). Game HUD: calories + gems StatPills, CakeBar,
BellyBar, checkpoint/eat controls, the boss prize card and game overlays. Lobby
meta HUD: icon GRID — Pets, Shop, DailyRewards, Codes, Settings, **Cakes**,
**InviteFriends, GroupReward** — bare icon
+ label-BELOW buttons, NO background (`HudMenuButton`; badges: Daily-claimable,
the unclaimed community reward, and an affordable BOOST on Shop — see
"Affordability cues"). The menu is a
`UIGridLayout` (`Theme.AppHud.MenuColumns`, default 2) — 8 entries = 4 rows,
y 172→742 on the 1080 reference, the tallest form its arithmetic was cut for.
Rows are derived from `#menu`, so an entry costs no layout edit and usually no
height either: at 2 columns 5 and 6 entries are both 3 rows, 7 and 8 both 4 —
adding **Cakes** (`features/cake-select.md`) left the block's height unchanged.
⚠ Cakes sits AFTER the established five and BEFORE the conditional social pair,
so it keeps a fixed slot whether or not those render. Unlike them it is NOT
gated on a server push (cake #1 is always unlocked) — the button always works.
⚠ The two social buttons are APPENDED, never inserted: the established four have
years of muscle memory attached. Each is gated on its own server push
(`referral` for Invite, `group.configured` for the reward) — a button whose only
possible answer is "not available" is worse than no button, and neither push
happens in the game place.
The GAME place gets its OWN menu in that same slot (`GameMenu`, `Visible =
showGame`, 2026-08-13): **Upgrades / Shop / Squishies / Settings** — 4 entries at
2 columns = 2 rows, `2*132 + 14 = 278` → y 172..450 on the 1080 reference, clear
of the checkpoint button's band at y 897. It is a SEPARATE frame from the meta
menu, not a branch inside it: that frame is lobby-gated because its other
handlers are lobby subs, while these four have server owners in BOTH places
(`ShopSubs` / `PetSubs` + `PassOwnershipSubs` / `SettingsSubs`, all COMMON).
It replaced the lone `GameSettingsBtn`; **Settings moved to the last cell** — it
was the game HUD's only button, but it is the one entry a player never needs
mid-run. Both menus are built by ONE `menuBlock(items)` helper, so the grid
arithmetic exists once. See "Affordability cues" below and
`features/upgrades.md` (the tree's second opener). CakeBar (top
center, phase-aware — **hidden during normal eating**, shown only for
boss/spawn/reward), BellyBar (bottom center, glutton state), ComboBadge,
AnnounceBanner, TO CHECKPOINT button (bottom-center, shown only when away from
the checkpoint — see `features/checkpoint.md`), EAT button (`EatButton`, bottom-
right thumb zone, **TOUCH devices only** — hold to eat / tap for one bite; shown
in eating/boss phases, hidden while a panel or the gym overlay is up; see
`features/cake-sim.md` input). Panels toggled by ONE `openPanel` (zIndex 50):
Pets (PetsInspectPanel), Upgrades (hex-tree overlay), Shop, DailyRewards, Codes,
Settings, Matchmaking, **Cakes** (`CakeSelectPanel`, lobby-only but NOT
push-gated — it renders the catalogue default until `CakeSelectUpdate` lands),
**InviteFriends + GroupReward** (both `SocialPanel`, both
lobby-only — `features/referrals.md`, `features/group-reward.md`).
Overlays: GymOverlay (40), PetRevealOverlay (90).
The shared modal scrim is pointer-active but `Selectable = false`; controller
focus stays on actionable panel controls and closes through each panel's X.
The cake view-model (`cakeOptions`) and `onSelectCake` feed TWO surfaces: that
panel and the matchmaking window's full-width horizontal `CakeCard` carousel,
so the two can never disagree. The carousel is presentation only — the selection never enters
the panel's session state and never rides the queue request
(`features/cake-select.md`, `features/lobby-matchmaking.md`).
`GameUiData` / `LobbyUiData` partition markers gate place-specific presentation:
the lobby hides cake/belly/checkpoint/eat/game overlays, shows its meta menu,
and can show the matchmaking selector or chocolate-triggered Shop. The game
hides lobby/meta UI because those handlers are lobby-only.
The hex-tree overlay is opened through `onToggleUpgrades` by the game menu's
Upgrades button (2026-08-13) **and** by the checkpoint's `UpgradeStation`
ProximityPrompt (`features/upgrades.md`) — both routes go through that one
callback so neither can bypass the modal wiring UpgradesSubsClient owns (world
blur, frozen camera, movement lock, world prompts off).
⚠ The button was REMOVED on 2026-07-30 with the reasoning "you stand at the
checkpoint after every belly burn, so a HUD button is a second door into the same
room". That was true and is no longer the whole story: a second door is exactly
what makes the tree reachable *while you are still eating*, which is where the
affordability cue below wants to reach the player. The button lives in the GAME
place only — the tree is RUN-scoped (ADR-0013), so in the lobby it is always a
tier-0 tree on a wiped balance.

## Affordability cues — a badge AND a breathe (2026-08-13)
A menu entry BADGES (`HudMenuButton` `badge`) and BREATHES (its `pulse` prop,
`Theme.Feel.Pulse`) when there is something behind it the player can afford RIGHT
NOW. Two channels for one fact, because the audience is children who may not read
the labels at all (`squint-test` skill): a dot survives a squint, motion survives
a glance, a number survives neither at icon size.
- **Upgrades** ← `LocalUpgradeTree.AnyAffordable(upgrades, calories)`
- **Shop** ← `LocalShopService.AffordableBoostCount(shop, gems) > 0` — BOOSTS
  only, in **both** places. Gem packs are bought with Robux and every Robux card
  is always "affordable", so a badge over those would be lit all session and mean
  nothing; boosts are the only cards whose state flips with a balance the player
  earns by playing (`features/boosts.md`, `features/shop.md`).
Both are the SHARED predicates their own windows use, so an icon can never
advertise a purchase the panel then refuses — the same one-way guarantee the
upgrade station's world sign has. Memoised on their inputs (neither balance moves
per bite: calories are banked at the gym, gems drop on a find).
⚠ **The cues are gated by PLACE, not only by affordability.** BOTH rosters mount
in both places (only the parent frame's `Visible` differs) and `Theme.Feel.Pulse`
repeats forever, so an ungated cue leaves TweenService driving UIScales on
invisible buttons for the whole session.
⚠ They sequence with onboarding for free and were left alone deliberately: at
tutorial step `path` the player has banked nothing, so Upgrades is quiet while
the TO CHECKPOINT button pulses; at step `upgrades` they have banked, so the
checkpoint pulse stops exactly as the Upgrades cue starts.

## Two layers: `Hud` (inset) and everything else (full-bleed)
The root ScreenGui is **full-bleed** since 2026-07-30 (`UiRoot`:
`IgnoreGuiInset = true` / `ScreenInsets = DeviceSafeInsets`) so panels, overlays
and their dim SCRIMS cover the whole screen — they used to stop below Roblox's
topbar, leaving a bright strip over a "modal" tree.
So the HUD gets its own child frame, `Hud`, offset down by the resolved safe-area
inset and shortened by the same amount. Every HUD child (pills, menu, CakeBar,
BellyBar, checkpoint, EAT, combo, announce) is built into `hudChildren` and lives
in that layer; panels/overlays are direct children of `App`.

**Covering the screen and PLACING on it are two different contracts** (2026-08-09).
Full-bleed was only half the rule, and the missing half shipped a real bug: the
hex tree's calories chip is a full-bleed child at `y = 30/1080`, i.e. under
Roblox's topbar at every viewport size — measured half-buried under the unibar
chip. Roblox's CoreGui is drawn above every player GUI and cannot be moved or
switched off, so:
- **Scrims/dims stay `Size (1,1)`.** Never inset them, never revert the root.
- **Anything that places a CONTROL carries the safe area.** AppRoot is the only
  reader of the engine APIs; `Theme.SafeArea` holds the numbers and the
  measurement behind them (R1/R2). Two families, and the suffix IS the unit:
  `…Px` for children of the shortened `Hud` layer (only pixels are exact there),
  `…01` as a fraction of the root for full-bleed overlays (whose height IS the
  root's). Consumers: `HexTreeOverlay` (`topInset01`, `bottomReserve01`),
  `GymOverlay` (`bottomReserve01`), `EatButton` (`bottomReservePx`), and the
  matchmaking panel fit/centre (ordinary viewport fit capped inside the usable
  region below `topInset`; its shared scrim remains full-bleed).
- ⚠ **`GuiService:GetGuiInset()` is the LEGACY inset** and can under-report the
  modern unibar. `resolveTopInset` takes `max(GetGuiInset().Y,
  GuiService.TopbarInset.Max.Y)` — `TopbarInset` is a **Rect**, whose `Max.Y` is
  the strip's bottom edge and whose `Min.X` is where Roblox's own left chip ends
  — clamps it against a nonsense report, then adds `SafeArea.TopPadPx`.
  This is why the old claim "the inset fix moved no HUD element" is no longer
  true: every HUD element sits `TopPadPx` lower, deliberately. The old margin was
  a viewport FRACTION of the region under the bar, so it collapsed from ~23 px at
  1080p to ~8 px on a phone while the bar stayed a fixed pixel height.
- ⚠ **Roblox's touch JUMP button owns the bottom-right corner** and is sized off
  the SHORTER viewport axis, while our controls were placed by viewport fraction
  tuned at one aspect — so they only cleared on a wide window. `touchReserve` is
  0 on PC and `min(0.20·shorterAxis, 120)·1.75 + pad` on touch.
- The inset is tracked in state (`TopbarInset` + `MenuIsOpen` changes, the
  viewport refit, and one late re-read a second after mount) — it is not a
  constant, the topbar can hide, and both APIs can answer 0 for a beat at boot.
- ⚠ The safe-area FRACTIONS divide by the root's height, which is read from the
  `App` frame's own `AbsoluteSize` — **not** `Camera.ViewportSize`, which is
  legitimately `(1,1)` for a session's first frames (and stays there in a Studio
  session driven over MCP). Dividing an inset by 1 parked the hex tree's chip
  40,000 px down the screen; below the threshold the safe area is reported as 0.
- ⚠ Anything that mixes pointer coordinates with `AbsolutePosition` must not
  assume an inset root. `ScrollPane`'s track click did exactly that
  (`GetMouseLocation() - GetGuiInset()`) and had to move to `InputBegan`'s
  `input.Position`, which is in `AbsolutePosition` space in either mode.

## Contract for feature subs
- Data IN: `AppRoot.Set(patch)` — fields: `calories, gems, settings, daily,
  shop, group, codesStatus, cake, cakes, stomach, gym, upgrades, pets,
  petReveal (+petRevealCount), combo, announceKey, celebration,
  matchmaking, checkpointFar, openPanel, referral, inviteStatus, groupClaim`.
  The last three are the social offers: `referral` is a server snapshot
  (`{rewarded, rewardGems}`) and doubles as the Invite button's gate, while
  `inviteStatus` / `groupClaim` are CLIENT-owned transient status written by
  `SocialSubsClient` — the reward's red "wait" line has to appear on the press,
  a round-trip before the server has said anything. Works pre-mount. `checkpointFar` (default true;
  fed by BodySubsClient's proximity check) hides the TO CHECKPOINT button when
  false.
- ⚠ **`cake` and `cakes` are DIFFERENT fields and both are live.** `cake` = the
  in-run cycle snapshot that drives the CakeBar (CakeSubsClient). `cakes` = the
  LOBBY selection `{ selected = cakeId, unlocked = { [cakeId] = true } }`, owned
  end-to-end by `CakeSelectSubsClient` (which converts the wire's unlocked ARRAY
  into that set). nil until the first push — the chooser renders anyway, showing
  the catalogue default with every conditional cake LOCKED. `features/cake-select.md`.
- **⚠ `Set` cannot CLEAR a field** — `{ field = nil }` is a silent no-op
  (`pairs` skips nils). Use `AppRoot.Clear(key)`; panel switching uses
  `AppRoot.Open(name?)` (assigns openPanel directly, nil closes).
- Actions OUT: `AppRoot.SetCallbacks({...})` (merges): onClaimDaily,
  onToggleSetting, onShopActivated, onRedeem, onBuyUpgrade,
  onInviteFriends, onClaimGroupReward,
  onEquipPet(petId, equip), onSelectCake(cakeId), onToggleUpgrades, onGymTap,
  onDismissReveal, onReturnCheckpoint, onEatDown/onEatUp (EAT button hold —
  CakeSubsClient drives `eating`), onCloseUpgrades (routes the hex-tree close
  through UpgradesSubsClient so blur + E-binding stay in sync). Wire to remotes
  in the feature's subs (R4).
- `onPanelChanged(panel|nil)` is NOT an action — AppRoot fires it whenever
  `openPanel` changes (never on mount) so ONE listener can react to every
  open/close. `AudioSubsClient` uses it for the panel whoosh
  (`features/audio.md`); a new panel cannot forget to fire it.
- Lobby actions: `onConfigureMatch(difficulty, maxPlayers)`, `onCancelMatch()`;
  `LobbySubsClient` owns their queue remote wiring.
- Feature subs NEVER call `UiRoot.Render` — `AppSubsClient` mounts once.

## View-models (R7)
`LocalRewardsService` (cards), `LocalShopService` (`BuildTabs(shop, group, gems)`
— the shop is a landscape TABBED grid window; the GEM BALANCE is an argument, not
decoration: it is what decides `buy` vs `unaffordable` on a gem-priced card,
`features/shop.md`. AppRoot also feeds the panel `balances`, which render inside
the shop's HEADER band, so gem packs have a balance anchor on screen),
`LocalSettingsService` (rows), `LocalPetsService` (pets panel props,
reveal props, odds line), `LocalStatsService` (upgrade costs/stat
formulas). AppRoot builds the upgrade rows + CakeBar/BellyBar strings
inline (locale keys `cake-*`, `belly-*`).

## Gotchas
- useEffect deps must never contain nil (jsdotlua positional compare) —
  booleans/counters only.
- ⚠ **A modal is TWO boundaries, and the scrim only closes one.** The scrim stops
  POINTER access to the HUD; controller selection is a separate channel, and
  `HudMenuButton` was the one kit pressable that never set `Selectable` (its
  TextButton defaulted to true). A D-pad could therefore reach a *breathing*
  HUD icon through an open panel's own scrim. Every menu button now takes
  `selectable = <no panel open>`, and `togglePanel` names the blocking panel in
  the console instead of returning silently (R8). The **Upgrades** entry carries
  its own copy of that guard rather than borrowing `togglePanel`'s, because it
  TOGGLES: closing the tree from its own button is legal, opening it over another
  panel is not.
- ⚠ The COMBINED development build maps both markers, so both menus render; the
  game block is offset below the lobby block by the lobby block's measured
  height. Always 0 in a published place (one marker each). It moves when the
  lobby roster gains a row from a late social push — dev-only, and correct.
- **Each panel family needs its own viewport fit.** `calculateScale(aspect,
  maxFraction)` is per-aspect, and every scale must ALSO be recomputed in the
  refit effect or that panel stops resizing with the window. The shop is
  landscape now and has `shopScale`; it used to borrow `portraitScale`.
  Sharing a scale is fine when the ASPECT is identical: `CakeSelectPanel` is
  1000x600 like the rewards window, so it rides `wideScale` and adds no state —
  if `Theme.CakeSelectLayout` ever diverges from `Theme.RewardsLayout`, a
  `cakeScale` must be added in BOTH coupled sites.
- `formatNumber` abbreviates at 10K (`37.1K`, `12.4M`) and stays exact below
  that. The switch-on threshold and the divisor are deliberately different for
  the K tier (10,000 vs 1,000) — collapsing them renders 37,051 as "3.7K".
- Combo state is throttled by CakeSubsClient (Set only on VALUE change);
  announceKey lifetime is `Theme.AnnounceBanner.Duration` (via CakeSubsClient's
pushAnnounce `task.delay`), Clear via `false`.
- `celebration` (`{cheerKey, subKey?, seq}`) is the BIG splash for the two
  celebration beats — a layer cleared and the Cake Monster down
  (`features/food-burst.md`). It is MUTUALLY EXCLUSIVE with `announceKey`: both
  are written by CakeSubsClient off one shared sequence number, and each clears
  the other. Lifetime `Theme.CelebrationBanner.Duration`, clear via `false`. It
  carries KEYS, not resolved text, so the rolled phrase survives the HUD's ~14
  re-renders/second and the locale-ready repaint without rerolling. Its element
  is a SIBLING of `Hud` at zIndex 30 (free 4-39 band), not a HUD child — `Hud`
  is shortened by `topInset` and would bias a centred splash downward.
- petReveal uses `false` (not nil) for "dismissed"; `petRevealCount`
  increments per roll so back-to-back reveals re-spin.
- Layout numbers live in `Theme.AppHud` (+ new sections) — not in code. Menu
  columns = `Theme.AppHud.MenuColumns`; AppRoot derives rows/size from it.
- **Currency icons come from `Theme.AppHud.PillIcons`** (registry NAMES, checked
  against `Icons.lua` at load), shared with the shop's balance row so one currency
  can never show two glyphs on one screen. The game HUD was the last caller of
  `StatPill`'s legacy hand-vectored `bolt`/`coin` shapes — which is how the GEMS
  pill ended up wearing a COIN. `StatPill` still accepts the old `icon` strings
  for API compatibility; don't use them.
- Interaction juice is in the KIT, not here: press feedback in the button
  components, open/close pop in `PanelShell`, badge/bar/toggle animation in their
  components (all off `Theme.Feel`, ADR-0006). Don't re-add animation in AppRoot.
- Published project files map exactly one place marker. The combined development
  build maps both; `LobbySubs` still suppresses the lobby map when game
  `MapService` is present.

## Files
`modules/AppRoot.lua`, `modules/UiRoot.lua`, `subscriptions/AppSubsClient.lua`;
`subscriptions/BodySubsClient.lua` (feeds `checkpointFar`); kit components:
`HudMenuButton` (bare icon+label menu button), BellyBar, CakeBar (+`visible`),
ComboBadge, AnnounceBanner (⚠ `BossPrizeCard` / `Theme.BossPrize` / the
`AppHud.BossPrize*` slot were REMOVED 2026-08-07 with the prize preview — the
top-right corner during a boss is deliberately empty; `features/cake-cycle.md`),
UpgradeRow/UpgradesPanel, GymOverlay, EatButton
(touch hold-to-eat, `Theme.EatButton`), PetRevealOverlay,
MatchmakingPanel (+ `CakeCard` carousel, `MatchDifficultyChoice`,
`MatchPartyChoice`, `ScrollPane`), CakeSelectPanel/CakeCard,
StatRow (extracted). Shared press/hold feel: `Interaction`
(`usePressable` now also exposes `onPressStart`/`onPressEnd` HOLD callbacks).
Lobby contract: `features/lobby-matchmaking.md`; cake chooser (catalogue,
remotes, unlock rule, ⚠ the rainbow cake is selectable but NOT yet playable):
`features/cake-select.md`.
