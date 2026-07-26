# 2026-07-26: Audio — SFX throughout the game + background music

Tags: audio, juice, ui-kit, settings, app-root, cake-sim, pets, shop, lobby, config

## Task
"Add SFX and music to the game. Make sure the audio is high quality. If you
can't find a suitable sound, ask me or search for one in the Toolbox. Add
sound effects throughout the entire game to make the gameplay feel as
satisfying and enjoyable as possible." Authored containers given by the user:
`ReplicatedStorage.SFX` and `SoundService.BackgroundMusic`.

## Context
The game had a *skeleton* of sound and nothing else:
- `JuiceConfig.sounds` held 13 keys pointing at `rbxasset://` engine
  placeholders (flagged for replacement in `features/juice.md`).
- `SoundPool` was a 16-voice pool that swapped those hardcoded ids.
- Only the cake/gym/pets/rebirth subs played anything; the whole UI, shop,
  rewards, codes, quests, upgrades, economy, lobby and teleport were SILENT.
- There was NO music at all.
- `SettingsSubsClient.applySetting` — the documented effect hook for the
  `music-enabled` / `sfx-enabled` toggles — only `Log.Info`'d. Both toggles
  persisted and did nothing.

The user had already authored a 76-sample library in `ReplicatedStorage.SFX`
and 4 tracks in `SoundService.BackgroundMusic`.

## Plan
1. Treat the authored folders as the sample source (same contract shape as the
   scene assets in ADR-0007: place-authored, resolved BY NAME, R8 on missing).
2. New `AudioConfig` as the single source for the key → sample map + shaping;
   strip sound out of `JuiceConfig` (it keeps particles/camera/combo/squish).
3. Rewrite `SoundPool` around the authored bank; add `MusicService`.
4. Give the KIT one sound hook so every button in the game clicks, without
   shared code depending on a client module.
5. Fill the genuine gaps (there were no eating/bite/chew/goo samples) from the
   Toolbox.
6. Wire a cue at every meaningful moment across all 16 client subs.
7. Make the settings toggles real.

## Changes

**Created:**
- `src/shared/config/AudioConfig.lua` — 49 semantic keys → authored sample
  names + `volume`/`pitch` multipliers, `cut`, `throttle`; pool/jitter/combo
  numbers; slump response; music tuning; `hatchByRarity`
- `src/client/common/modules/MusicService.lua` — shuffled playlist, fade
  in/out + gap, `SetEnabled`, per-frame `Step`
- `src/client/common/subscriptions/AudioSubsClient.lua` — kit sound handler,
  panel whoosh, music stepping
- `docs/features/audio.md`

**Modified:**
- `src/client/common/modules/SoundPool.lua` — rewritten: resolves the authored
  bank by name (rebuild-on-miss, 5 s cooldown), 20 pooled voices, dedicated
  clones for effect-carrying templates, `cut` with a per-voice generation
  stamp, per-key throttle, `SetEnabled`
- `src/shared/config/JuiceConfig.lua` — sound fields removed (moved to
  `AudioConfig`); header repointed
- `src/shared/config/CakeConfig.lua` — `sfx` comment repointed
- `src/shared/UIKit/Interaction.lua` — `SetSoundHandler` + `"press"` (aggregate
  press edge) / `"hover"` cues; `src/shared/UIKit/init.lua` re-exports it
- `src/client/common/modules/AppRoot.lua` — `onPanelChanged` effect on
  `openPanel` (primed so mount is not a close)
- `src/client/common/subscriptions/SettingsSubsClient.lua` — real effect hook
- Cues wired in: `CakeSubsClient` (boss appear/defeat, cake cleared, rare cake,
  next-cake transition, treasure spawn/collect, blocked nudges, chew, gulp),
  `CakeFeelSubsClient` (crust crack, trampoline boing, landing thud),
  `BodySubsClient` (gym start / payout), `PetsSubsClient` (rarity-tiered hatch,
  equip), `ShopSubsClient` (purchase start / granted), `RewardsSubsClient`
  (grant-driven claim cue), `CodesSubsClient`, `QuestsSubsClient`,
  `RebirthSubsClient`, `UpgradesSubsClient`, `EconomySubsClient` (gems only),
  `LobbySubsClient` (queue open / tick / error), `TeleportControlSubsClient`
  (handoff whoosh)
- `docs/features/juice.md`, `docs/features/settings.md`, `docs/MAP.md`

**Authored (place content, NOT in git):** 9 Sounds added to
`ReplicatedStorage.SFX` — `bite_soft`, `bite_wet`, `bite_splat`,
`bite_crunch`, `bite_goo`, `bite_chew`, `gulp`, `crust_crunch`, `slump_loop`.
All from Roblox's free **Pro Sound Effects** library (professionally recorded
— the best objective quality signal available without listening).

## Decisions
- **Samples authored, map in code.** The alternative (asset ids in a Lua
  config) syncs to both places for free, but the user asked for the folders
  and Studio-side auditioning of volume/pitch is worth more than the copy
  step. Cost: the folders are place content and must exist in BOTH places —
  R8 warns loudly if they don't, since "the game is silent" is exactly the
  dangerous-silent-state the rule exists for.
- **`cut` instead of hunting for short samples.** Library samples are 1–2.5 s;
  bites fire up to ~10/s. A per-key `cut` (stop after N seconds) turns a 2.24 s
  "Food Valley" splat into a 0.3 s bite and keeps the whole library usable.
  Guarded by a per-voice generation stamp so a recycled voice is not cut short
  by the previous cue's timer.
- **One kit hook, not per-component props.** `Interaction.usePressable` is
  already the shared press primitive (ADR-0006), so cueing there gives all 11
  pressable components sound at once. Shared code cannot require a client
  module, so the handler is INJECTED (`SetSoundHandler`, no-op by default).
  The cue fires on the AGGREGATE press edge, so multi-touch and drag-off do
  not double-click. Consequence: `BodySubsClient`'s manual per-gym-tap sound
  was deleted (it would have doubled).
- **Panel whoosh from `openPanel`, not from close buttons.** ONE effect in
  AppRoot; a new panel cannot forget to fire it. `primed` swallows the mount
  run (mounting with nothing open is not a close), and the dep uses
  `or false` (jsdotlua nil-in-deps footgun, already documented in this file).
- **First-note gate.** Starting music at spawn and muting it a second later
  when `SettingsUpdate` lands is exactly the bug a "music off" player would
  report. `MusicService` waits for the first `SetEnabled`; a grace timer
  (8 s) starts on the default + R8-warns if settings never arrive.
- **Which events get NO cue** is a design decision worth recording: calories
  (tick every bite → a drone), stomach gain (the floating number carries it),
  the queue `busy` status churn. Gems DO get one (rare, throttled 0.5 s).
- **No `docs/registries/audio-keys.md`.** A registry is a uniqueness index of
  name → owner + doc; every key here has one owner and `AudioConfig.sounds` is
  already that index. A second copy would only drift (D3).
- **Rarity-tiered hatch** (`AudioConfig.hatchByRarity`): the library happened
  to carry `hatchcommon`/`hatchepic`/`hatchlegendary`, and a legendary that
  sounds like a common has no stakes. An unmapped rarity R8-warns rather than
  silently reading as a worthless roll.

## Verification (Studio, lobby place, live play)
- 186 modules require clean; boot log clean (no new warnings).
- `SoundPool` indexed 85 samples; `MusicService` indexed 4 tracks.
- Static check: all 49 keys resolve to a real authored Sound, all 9 cake layers
  map to an existing key, 0 duplicate sample names.
- Live: `GameSfx` + `GameMusic` groups created; 20 pooled voices; `SlumpLoop`
  looping at volume 0; music faded in and playing through `GameMusic`.
- Live click test (menu → panel → same button again) recorded the exact cue
  chain on the pooled voices: `uiHover → uiClick → uiOpen → uiClick → uiClose`,
  with pitch jitter applied and the round-robin advancing.
- Settings path proven end-to-end: the test profile has `sfx-enabled = false`,
  and `GameSfx.Volume` was 0 at boot while music (enabled) played.

## Adversarial review — what it caught (all fixed)
1. **CRITICAL:** chocolate's bite key IS `crack` and its `shatterFx` also
   played `crack` — the same uncut 2 s sample twice per bite, ~10 plays/s
   saturating the 20-voice pool with one waveform. Fixed: `crack` gained a
   `cut`, and the shard burst became a distinct `shatter` key on a different
   sample (asserted in the verify script: no `shatterFx` layer's bite sample
   equals the shatter sample).
2. The `cut` generation stamp was only bumped when the NEW cue had a `cut`, so
   an uncut celebration landing on a recycled voice could be truncated by the
   previous cue's timer. Now bumped on every play.
3. `bossDefeat` (a victory sting) played on a LOST boss fight — the payload
   already carried `announce == "match-lost"`. Added `bossLost`.
4. SFX had no settings gate (music did): a `sfx-enabled = false` player heard
   the first seconds of the session. The group now starts muted with the same
   grace fallback.
5. `AudioSubsClient`'s early return on a missing `SoundPool` also killed the
   music step, while the warning only mentioned SFX. Wired independently.
6. `queueOpen` played the SAME sample as the panel whoosh in the same frame
   (double amplitude); key deleted, the panel effect owns it.
7. Quest / rebirth / upgrade cues fired on the CLICK, so a refused action
   still sounded successful and a spam-clicker got N jingles for 0 grants.
   All three now cue off their `*Update` payload, matching the contract the
   rewards path already documented. `petEquip` gained a throttle ("Equip Best"
   fires the callback in a loop).
8. Gem / reward cues ran BEFORE the `AppRoot.Set`, so a throwing cue would
   have killed that handler's state pushes for the session. Moved after.
9. `MusicService`: no rebuild-on-miss (a late folder never healed), the only
   recovery path lived inside a `Log.GraceOnce` predicate, `baseVolume` could
   be re-captured from an already-faded track (permanent silence), a silent
   early return on a vanished track, and `shuffle = false` played the playlist
   backwards. All fixed.
10. Muted `SoundPool.Play` still did the full lookup/voice churn; the lobby
    streamed the slump loop forever at volume 0. Now an early return and a
    lazily-started loop.
11. Doc drift: `onPanelChanged`/`onCloseUpgrades` missing from `app-root.md`,
    a stale `SettingsData` path in `settings.md`, tunables duplicated out of
    `AudioConfig` into `audio.md`, and two dead keys (`coinBurst`, `sell`).

Found separately during verification: **Toggle, PetCard, DayCard and the pet
reveal's dismiss catcher do not use `usePressable`** (each owns its own
motion), so the kit hook did not reach them and the settings toggles were
silent. Added `Interaction.Cue(name)` — a public cue with no visual side
effect — and called it from those four activation handlers.

**Follow-up pass ("you didn't add ui sounds"):** the report was accurate and
the cause was the saved `sfx-enabled = false` muting the whole SFX group — but
auditing all 94 clickable surfaces in the live app tree against the two cue
mechanisms turned up ONE more genuine gap: the hex upgrade tree's nodes are
HIT-TESTED through a single pan surface (`handleTap` picks the nearest hex)
rather than rendered as buttons, so `usePressable` never saw a node press and
the entire upgrade screen was silent. Fixed with `Interaction.Cue("press")` on
the branch where a tap actually resolves to a node (tapping empty space
dismisses the detail card and stays silent). Shop tiles were also silent, but
correctly so: every dev-product/gamepass id is still 0, so `priceState` returns
`"unavailable"` and the tiles render `Active = false` — an inert button must
not click. Verified live with SFX enabled: hover/click/open/close across the
menu and four panels, and a daily-reward claim producing click → gemGain →
reward.

## Open Questions / Followups
- **The GAME place needs the same two folders.** Only the lobby Studio was
  open (the second instance had no place loaded), so the game place is
  unverified. Copy `ReplicatedStorage.SFX` + `SoundService.BackgroundMusic`
  there and save, or the game half runs silent (it will say so in the console).
- The 9 new samples are picked on provenance + duration, not by ear. Volumes
  and `cut` values are first-pass — audition and retune in Studio (base
  Volume/PlaybackSpeed on the instance, `cut`/`throttle` in `AudioConfig`).
- No 3D/positional cues yet (everything is 2D). Treasure spawn, boss and the
  chocolate shop trigger are candidates for `PlayAt`-style world sound.
- The dev profile used for verification has `sfx-enabled = false` saved (from
  when the toggle was a no-op). Both toggles were exercised end-to-end and
  then restored to their original values, so the profile is unchanged — but a
  player with that saved value now really does hear nothing until they flip it.

## Related
- Feature: `docs/features/audio.md` (also `juice.md`, `settings.md`)
- ADRs touched: ADR-0006 (the press primitive the kit hook rides), ADR-0007
  (the place-authored-asset contract this mirrors)
- Prior flow: `docs/flow/2026-07-19_hud-juice-and-menu-grid.md`,
  `docs/flow/2026-07-16_eat-the-cake-v1.md`
