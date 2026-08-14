# 2026-08-13 — Food-burst celebrations, cheer splash, Boss → Cake Monster

**Tags:** food-burst, juice, ui-kit, app-root, cake-cycle, localization, theme, icons

## What was asked
1. Upload the 33 food images on the user's desktop to Roblox and group them by
   type. When a layer is cleared, pick a random group and throw its foods up
   from below the screen to about halfway up and back down — randomised sizes,
   speeds and vectors, as juicy as possible. Redesign and animate the
   "LAYER CLEARED!" message and replace it with a random eating phrase.
2. Same FX when the boss dies. Replace the word "Boss" everywhere with
   something that fits the game. Remove the boss's HP display above the
   character — it is already in the UI.

## What shipped
| Piece | Where |
|---|---|
| 33 uploaded icons, 5 groups | `Icons.Food*`, `JuiceConfig.foodBurstGroups` |
| the confetti | `client/common/modules/FoodBurst.lua` (own ScreenGui, 80 pooled sprites) |
| the splash | `UIKit/Components/CelebrationBanner.lua` + `Theme.CelebrationBanner` |
| 30 random cheers + the roll | `LocaleData` `announce-{layer,monster}-cheer-N`, `cheerCounts`, `RollCheer` |
| the trigger | `CakeSubsClient.pushCelebration` (layer-cleared, cake-cleared) |
| the state | `AppRoot.state.celebration` = `{cheerKey, subKey?, seq}`, element at zIndex 30 |
| the rename | Boss → **CAKE MONSTER**, mini-boss → **CRUMB MONSTER** (player text only) |
| the removals | `BossView`'s HP billboard + `SetHp`; `MiniBossView`'s HP fill (nameplate kept) |

Full contract: `features/food-burst.md`.

## Decisions worth keeping
- **The rename is PLAYER TEXT ONLY.** Phase strings (`"boss"`, `"miniboss"`),
  announce wire keys, locale KEY names, analytics steps, SFX names and the
  authored `Assets.MiniBosses` rigs all keep their ids. Renaming a locale key
  orphans its cloud row; renaming an analytics step breaks a live dashboard;
  renaming a phase string is a client/server contract break. The one exception
  is `CakeConfig.bossName`, which lost its only render with the billboard and
  is now a server log string.
- **`pet-suit` = "The Boss" was deliberately left alone** — that is a squishy
  wearing a suit (the "big cheese" sense), not the enemy, and it has 16 shipped
  translations. One line to change if that reading is wrong.
- **The splash is a second banner, not a replacement.** `AnnounceBanner` still
  carries every informational announce (`new-cake`, `rare-cake-*`, `miniboss-*`,
  `find-*`, `layer-locked`, `match-lost`). The two share one `announceSeq` and
  each clears the other, because two banners in one frame stomp each other.
- **The cheer travels as a KEY.** The HUD re-renders ~14x/s and there is also a
  locale-ready repaint; resolving in the render would deal a new phrase several
  times per splash. Rolled once at the event, resolved in a memo.
- **Confetti below the UI, splash above it.** Sprites live in their own
  ScreenGui at `DisplayOrder = 99` (one under `UiRoot`'s 100); the splash is a
  sibling of `Hud` at zIndex 30. Food must be felt, the phrase must be read.
- **Tune the apex, derive the speed.** Everything in the burst is a screen
  fraction and screen-heights/s, so the arc survives a phone and a 21:9 monitor.

## What verification actually showed
- 235-file `luau-compile` parse: clean.
- Playtest boot: `FoodBurst.Init ok`, `ready — 80 pooled sprites across 5 food
  groups`, `18/18 subscriptions started`, no `require FAILED`.
- The real integrator, stepped at a fixed dt (no renderer needed): three bursts
  rolled three DIFFERENT groups (`tropical`/`bakery`/`candy`), each using
  exactly its own icon roster (7/7, 6/6, 8/8 distinct) — group coherence works.
  Apex y **0.330–0.343**, lowest y ~1.08 (fully off the bottom), fully retired
  in **2.06–2.11 s** (layer) and **2.74 s** (monster), `ActiveCount()` back to
  **0** every time — no leak.
- Splash, measured live off the instances: aspect **3.461** (= 900/260), plate
  outline **2.4 px top / 2.4 bottom / 2.4 left** — EVEN, i.e. the CARD recipe
  (§2b), not the button bevel; rolled cheer `"BIG BITE!"` on a layer clear and
  `"CAKE MONSTER DOWN!"` + subtitle `"Cake cleared! Everyone gets a squishy!"`
  on a monster kill, with the plain announce banner **absent** in both — the
  mutual exclusion holds.
- Boss model in workspace during the boss phase: **6 parts, zero GUI
  descendants, zero TextLabels** — the billboard is gone, while the HUD bar
  still shows HP + timer.

## What adversarial review caught (4 reviewers + 4 refuters)
Two CRITICALs in the burst, both invisible on a 60 Hz dev machine and both
"the celebration is thinner than it should be" rather than a crash:

1. **Sprites spawned BELOW their own recycle line.** Launch is `1 + spawnBelow`
   = 1.09; the exit test fired above ~1.05 for most sizes, so any sprite whose
   FIRST integrated frame did not clear the line was killed before it was ever
   drawn. That deleted ~21% of every burst at 60 Hz and **57-63% at 144 Hz** —
   silently, and WORSE on better hardware. Fixed by gating the exit on
   `vy > 0`: only a falling sprite can be gone. My own pre-fix measurement had
   already shown the symptom (peak 15-18 of a 22-28 burst) and I had
   mis-attributed it to the launch stagger.
2. **`ScaleType.Fit` threw the squash & stretch away.** `Fit` keeps the SOURCE
   image's aspect and draws at the frame's shorter side, so a squashed frame
   only letterboxed: every sprite drew square, ~23-30% smaller than
   `sizeRange` said. Fixed to `Stretch` — the aspect worry that makes `Fit`
   tempting is already covered by `SizeConstraint.RelativeYY`.

Also fixed: `vx` was in screen-HEIGHTS but integrated into `x`, which is a
WIDTH fraction (drift ran 1.8x fast on 16:9, 2.4x on 21:9); `popOvershoot`
needed a value **> 2** to overshoot at all, so the shipped 1.35 was just a
slower ramp; `driftInward` was named the inverse of what it did; `Init` never
reset `liveCount`/`cursor`, so a re-Init stranded the count and made
`ActiveCount()` — the verification hook — lie forever; a typo'd `groupId`
fell back silently.

On the UI side the kit's own documented hazard: the entry pose was written in a
passive `useEffect`, so the plate painted at **full size and fully opaque for a
frame** before every slam-in — 28-42 flickers a run. `useLayoutEffect` is the
kit's established fix (`TutorialSlides`, `Badge`, `Toggle`, `ScrollPane` all
use it for exactly this). Two Theme comments were also wrong: the aspect
constraint is HEIGHT-bound at 16:9 (`AspectType` defaults to
`FitWithinMaxSize`, where `DominantAxis` does not apply), and the confetti does
NOT clear the banner spatially — it passes behind it, which is what the
DisplayOrder split is for.

Two deliberate calls that review flagged as opinions rather than defects, kept
anyway: a rare FIND no longer pushes its banner over a live celebration (its
ring, shake and floating number still fire), and the splash is suppressed under
the tutorial comic, whose dim is only ~76% opaque.

⚠ **Not fixed: R7.** `CakeSubsClient.lua` is now 1041 lines against the ~300
rule. It was already 758 before this change; splitting it by sub-domain is a
real refactor and is left as its own task.

**Re-measured at 144 Hz after the fixes** — layer bursts render **27 and 28**
of 22-28, monster bursts **48 and 42** of 40-48, every launched sprite drawn,
`ActiveCount()` back to 0, apex y 0.318-0.34, gone in 2.15-2.75 s.

## Gotchas found on the way
- ⚠ **Editing English in `LocaleData` does NOT change the game until the cloud
  table is pushed and pruned.** `T()` asks the translator FIRST, and the cloud
  row for `cake-boss` still holds "BOSS! {timer}s" — measured live on an
  `en-us` client, while the brand-new cheer keys (absent from the cloud)
  correctly served the new English. Row identity is `(key, context, source)`,
  so a changed source is a NEW row and the old one lingers serving the same
  key. **The four renamed strings need `pull` FIRST, then `push --prune`** —
  `push` alone re-keys the four (it deletes the old key identity before
  inserting), but only `pull` writes the `orphan=yes` column that `--prune`
  reads, and the keyless "Cake Guardian" row needs that prune.
- ⚠ **Studio stopped drawing frames**, which is the documented MCP-playtest
  trap: `RenderStepped` counted 0 ticks in 0.6 s, and `screen_capture` /
  `user_mouse_input` both wedged (they need a frame), while `execute_luau`
  stayed healthy — so the FX was verified numerically instead of visually.
  Two useful new facts: **React-lua commits WITHOUT frames** (the whole `App`
  tree mounts and the splash appears on a state push), and **TweenService does
  not advance** (the banner sat exactly at its entry pose — `Scale 0.35`,
  `Rotation -7`, `GroupTransparency 1` — which is itself proof the effect ran).
- ⚠ **The real 1 Hz `CakeCycleUpdate` overwrites an injected phase**, so
  probing the boss phase from the server datamodel means re-firing faster than
  that.

## Still open
- The four renamed strings are English-in-code only until
  `python tools/robloxloc/robloxloc.py pull` → `push --prune` runs (needs the
  cookie). The 30 new cheer keys go up in the same pass and machine-translate.
- No screenshot of the FX: Studio's renderer was wedged. Tonal-hierarchy and
  squint passes on the splash are therefore NOT done and should run once a
  capture is possible.

## Follow-up pass (same day, user feedback)
| Ask | Change |
|---|---|
| bigger sprites | `sizeRange` x1.5 → `{0.078, 0.1875}`; pool 80 → 88 (worst overlap is now 48 + 36) |
| text too fast | `HoldSeconds` 1.5 → 2.6, `Duration` 2.4 → 3.5. `LAYER_CLEAR_PRIORITY_SECONDS` derives from `Duration`, so the nag/find hold-back window followed it automatically |
| no background | The gold plate (Outer/Rim/Face) is GONE — the splash is pure animated type. The cheer went gold-on-nothing with `OutlinedText`'s stroke as its only ground, and grew from ~37% to ~55% of the banner height in the process. Added a slow SWAY (±1.6°) across the breathe, so the words carry the motion the plate used to carry |
| mini-boss gets everything the boss gets | `miniboss-defeated` now routes to `pushCelebration("crumb", …)`: its own 10-cheer list, a 30-36 sprite burst and a 0.32 camera punch, sitting between the layer beat and the finale. Both SPAWN beats deliberately stay plain announcements — they are warnings, not rewards |

**Verified after the pass:** 235-file parse clean; all three cheer lists roll
every declared index and every roll resolves to a real phrase (400 rolls each,
zero unresolvable); the rendered banner has **zero** GuiObjects with a
background (`opaqueBackgrounds = []`), children are exactly `Pop:UIScale` +
`Cheer` (+ `Sub` when given), aspect 3.461, cheer = 55.3% of banner height,
`HoldSeconds` 2.6 / `Duration` 3.5 live off the frozen Theme.

The tutorial gate added in the review pass proved itself by accident: the
crumb-monster splash refused to render in a fresh playtest, and the cause was
`tutorialSlidesUp` — the comic plays on EVERY entry and is client-owned (only
its SKIP button clears it), so the splash was correctly suppressed behind it.

⚠ **Why Studio stopped drawing frames** (correcting the note above): not a
Studio or MCP fault — a fullscreen game had the foreground on the machine, so
Studio throttled its renderer. `execute_luau` keeps working throughout, and
`screen_capture` / `user_mouse_input` do not. Editor rendering resumed on its
own once focus returned, and the banner's tween values were observed advancing
(scale 1.027 mid-breath, rotation −0.40 mid-sway) — live proof the timeline runs.
