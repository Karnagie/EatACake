# Food burst + celebration banner (client)

## What it does
The game's three CELEBRATION beats — a cake layer cleared, a crumb monster
down, and the Cake Monster down — stopped being a one-line notification and
became a moment:

1. **Food confetti** — a whole GROUP of food sprites (all fruit, or all candy,
   or all bakery…) launches from below the bottom edge of the screen, arcs to
   roughly mid-screen and falls back off. Sizes, speeds, spin, drift and launch
   order are all rolled per sprite.
2. **A splash banner** with a RANDOM cheer phrase instead of the fixed
   "LAYER CLEARED!" — the beat fires ~28-42 times per cake, so one fixed line
   goes stale inside the first ten minutes. It is PURE TYPE: no plate, no card,
   no background (see the gotcha below).

All three beats use the same FX at three sizes, each with its own cheer list, so
a zone gate never congratulates you in the finale's words.

## Pieces
| Piece | Owns |
|---|---|
| `client/common/modules/FoodBurst.lua` | the confetti: its own ScreenGui, an 88-sprite pool, the per-frame integration |
| `shared/UIKit/Components/CelebrationBanner.lua` | the splash: gold cheer + optional white subtitle, slam-in / breathe+sway / launch-out. No background. |
| `shared/config/JuiceConfig.foodBurst` | ALL burst tuning (arc, sizes, counts, stagger) |
| `shared/config/JuiceConfig.foodBurstGroups` | which foods belong to which group, by icon NAME |
| `shared/UIKit/Icons.lua` `Food*` | the 33 uploaded 64x64 food glyphs |
| `shared/UIKit/Theme.CelebrationBanner` | the splash's geometry, gold palette and motion timings |
| `LocaleData` `announce-{layer,crumb,monster}-cheer-N` + `cheerCounts` + `RollCheer` | the 40 phrases and the roll |
| `CakeSubsClient.pushCelebration` | the only trigger, for all three beats (R4) |
| `AppRoot` `state.celebration` | `{ cheerKey, subKey?, seq }` → the banner element |

## The two triggers
Both live in `CakeSubsClient`'s `CakeCycleUpdate` handler, keyed on `announce`:

| `announce` | cheer list | subtitle | burst | camera |
|---|---|---|---|---|
| `layer-cleared` | `layer` (20 phrases) | — | `counts.layer` = 22-28 | 0.22 |
| `miniboss-defeated` | `crumb` (10 phrases) | — | `counts.crumb` = 30-36 | 0.32 |
| `cake-cleared` | `monster` (10 phrases) | `announce-cake-cleared` ("everyone gets a squishy") | `counts.monster` = 40-48 | 0.42 |

Every OTHER announce (`new-cake`, `rare-cake-*`, `boss-spawned`,
`miniboss-spawned`, `find-*`, `layer-locked`, `match-lost`) still takes the
plain `AnnounceBanner`, unchanged — including both SPAWN beats, which are
warnings rather than rewards.

## Layering — where each half draws
| Surface | Where | Why |
|---|---|---|
| food sprites | own ScreenGui `PlayerGui.FoodBurst`, `DisplayOrder = 99` | ONE BELOW `UiRoot`'s 100, so food flies in front of the world but BEHIND the HUD and the banner. The phrase must stay readable. |
| the splash | inside `UiRoot`, sibling of `Hud` under `App`, `zIndex = 30` | the free 4-39 band: above every HUD element (1-3), below the modal scrim (40), so an open panel buries it |

It is a SIBLING of `Hud`, not a child: `Hud` is shortened by `topInset`, which
would bias a centred splash downward by the unibar height on exactly the phones
with the least room. Being a sibling also means `Hud`'s
`Visible = not tutorialSlidesUp` gate does NOT reach it, so the splash re-applies
that gate itself — the onboarding comic's dim is only ~76% opaque and a gold
plate behind it reads as a leak.

## The two banners never share the screen
`pushAnnounce` and `pushCelebration` share ONE `announceSeq`, and each clears
the other's state as it fires. Two banners in one frame stomp each other — the
same rule the mini-boss announce already follows (`features/cake-cycle.md`).

Newest-wins is the rule for every key EXCEPT two, which are held back while a
celebration owns the screen (`celebrationOwnsScreen`, window =
`max(2.5, CelebrationBanner.Duration)`):
- `layer-locked`, the "eat the top layer first" nag — it fires in the same frame
  the layer ends, which is what the window was originally added for;
- `find-*`, because uncovering something on the last bite of a band is routine,
  and a one-line "EPIC FIND!" replacing a 2.4 s splash mid-slam (with its
  confetti still in the air) reads as a bug. The find's ring, camera shake and
  floating reward number all still fire.

## Gotchas
- ⚠ **Everything in the burst is a SCREEN FRACTION, never pixels.** `x`/`y` are
  UDim2 scale (y = 0 is the TOP edge) and velocities are screen-heights/second,
  so the arc is identical on a phone and a monitor. Sprites size on
  `SizeConstraint.RelativeYY` so a wide screen cannot stretch an apple into a
  melon.
- ⚠ **Tune the APEX, not the launch speed.** `launchApex` picks the arc and the
  speed is derived (`v = sqrt(2gh)`). A tuned speed does not survive an aspect
  change; a tuned apex does. Measured: sprites top out between 33% and 57% down
  the screen and are fully gone in ~2.1 s (layer) / ~2.7 s (monster). Sprite
  size was scaled x1.5 on 2026-08-13; nothing else in the arc depends on it.
- ⚠ **No plate, and that is deliberate** (2026-08-13, user request). A gold
  card that size parks an opaque rectangle over the cake for three and a half
  seconds, and the kit's §2c warns that a dark outer pill under a lighter face
  reads PRESSABLE — bad on a non-interactive splash for an audience of
  pre-readers. Readability comes from SIZE (the cheer is 140/260 of the banner,
  ~55% of its height) plus `OutlinedText`'s own stroke and shadow copy. **Never
  drop that stroke** — it is the words' only ground.
- ⚠ **The phrase travels as a KEY, never as resolved text.** The HUD re-renders
  ~14x/second while the splash is up; rolling inside the render would deal a new
  phrase on every bite, and a locale-ready repaint would deal another.
- ⚠ **ADR-0006 applies to the banner.** `Pop.Scale`, `Group.GroupTransparency`
  and `Group.Rotation` are animated by TweenService and are therefore never
  written by React. Adding a React-controlled `Rotation`/`Scale` prop to those
  instances would snap them back mid-tween on the next bite.
- ⚠ **A sprite is only retired while it is FALLING (`vy > 0`).** It launches at
  `1 + spawnBelow` = 1.09, which is already past its own exit line for every
  size under ~0.117 — without that gate an ascending sprite was killed on its
  first integrated frame whenever that frame did not lift it clear. It deleted
  ~21% of every burst at 60 Hz and **57-63% at 144 Hz**: silently, and worse on
  better hardware, so it never reproduced on a locked-60 dev machine.
- ⚠ **`ScaleType` must be `Stretch`, never `Fit`.** `Fit` keeps the SOURCE
  image's aspect and draws at the frame's shorter side, so a squashed frame only
  letterboxes: the squash & stretch disappears and every sprite draws ~25%
  smaller than `sizeRange` says. The aspect worry that makes `Fit` tempting is
  already handled by `SizeConstraint.RelativeYY`.
- ⚠ **`popOvershoot` must exceed 2 to overshoot at all** — `pop(t) = A·t +
  (1−A)·t²` is monotonic below that. Peak is `A²/(4(A−1))`.
- ⚠ **`Step` is the only thing that retires a sprite.** A client that is not
  drawing frames (a Studio playtest driven purely over MCP — see the
  environment notes) leaves fired sprites live and invisible until frames
  resume. It cannot leak: `Fire` reuses the pool round-robin and never
  allocates, and `liveCount` only counts a sprite once.
- Adding a cheer = add the key **and** bump `LocaleData.cheerCounts`. The roll
  walks `1..count`, so a gap puts a raw `announce-layer-cheer-21` on screen.
- Adding a food = upload it, add the id to `Icons.lua` as `Food<Name>`, and put
  the NAME in a group in `JuiceConfig.foodBurstGroups`. Names resolve through
  `Theme.Icon`, which warns once on a miss instead of silently drawing the
  fallback glyph.

## Food groups
One burst = ONE group, so every celebration reads as a theme.

| id | foods |
|---|---|
| `orchard` | apple, pear, peach, cherry, strawberry, raspberry, blueberry, watermelon |
| `tropical` | banana, mango, pineapple, kiwi, orange, lemon, avocado |
| `bakery` | cake, cheesecake, doughnut, pancakes, pie, waffle |
| `candy` | 3 wrapped candies, candy floss, lollipop, 3 gummy bears |
| `creamery` | ice cream, popsicle, yogurt, chocolate |

## Verification hooks (Studio)
`FoodBurst.ActiveCount()` is the live sprite count. To exercise the whole path
without eating a real layer, fire the real remote from the SERVER datamodel —
`ReplicatedStorage.Shared.remoteUpdates.CakeCycleUpdate:FireClient(player,
{ phase = "eating", announce = "layer-cleared" })` — and read the consequence
off `PlayerGui.FoodBurst` and `PlayerGui.UiRoot.App.CelebrationBanner`.
⚠ The real 1 Hz broadcast overwrites an injected phase, so a phase probe has to
re-fire faster than that.

## Files
`client/common/modules/FoodBurst.lua`, `shared/UIKit/Components/CelebrationBanner.lua`,
`shared/config/JuiceConfig.lua`, `shared/UIKit/Theme.lua` (`CelebrationBanner`,
`AppHud.Celebration*`), `shared/UIKit/Icons.lua`, `client/common/data/LocaleData.lua`,
`client/common/modules/AppRoot.lua`, `client/common/subscriptions/CakeSubsClient.lua`.
Juice family: `features/juice.md`. Beat definitions: `features/cake-cycle.md`.
