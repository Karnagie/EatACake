# Audio (SFX + music)

## What it does
Every player-facing sound in both places: kit-wide UI clicks, the per-layer
eating ASMR, feature cues (hatch, purchase, reward, boss, queue) and the
background-music playlist. All client-side. The two settings toggles actually
mute it (`features/settings.md`).

## The contract: samples are PLACE-AUTHORED, the map is code
| Where | What | Owner |
|---|---|---|
| `ReplicatedStorage.SFX` (any nesting) | Sound instances — the samples, their base `Volume`/`PlaybackSpeed`, any SoundEffect children | Studio (authored, saved with the place) |
| `SoundService.BackgroundMusic` | music tracks (Sounds), base `Volume` = mix level | Studio (authored) |
| `shared/config/AudioConfig.lua` | semantic key → `{ asset = "<Sound name>", volume, pitch, cut, throttle, enabled }` | code (Rojo) |

`volume`/`pitch` are MULTIPLIERS on the authored values, so retuning a sample
in Studio still works. `cut` stops playback after N seconds (turns a 2 s
library splat into a 0.3 s bite). `throttle` drops repeats of a key inside N
seconds (for cues driven by high-frequency events). **`enabled = false` switches
a key off** without touching call sites — `SoundPool.Play` early-returns, and
`Init` reports the disabled set ONCE at boot (R8: a deliberately silent cue must
not be indistinguishable from a broken sample).

## ⚠ ONE TAP = ONE BITE SOUND (2026-08-03)
The bite plays the active layer's `sfx` key. Two other things used to stack the
SAME sample on top of it, so a single click fired **4 sound plays** (measured by
hooking `Sound.Played` in a playtest — the only way to settle this):
- `chew` — a deliberate layered mouth sound. Now `enabled = false`; flip it back
  in `AudioConfig.sounds.chew` if the extra layer is ever wanted.
- the WALK CRUNCH (`JuiceConfig.walkCrunch`) — it reuses the layer's bite sample
  at footstep cadence, and a bite DROPS the collision column under you, so the
  settle drift alone clears `minSpeed` while standing still. Muted for
  `walkCrunch.biteSuppressSeconds` (0.8) after any bite; because a held bite
  refreshes that timestamp at the eat-rate, the crunch stays quiet for the whole
  time you are eating (deliberate — while eating you hear bites, not footsteps).

Still expected, and NOT a duplicate bite: the `slump` loop (one looping voice,
volume follows avalanche energy) and the landing `crustCrack`/`land` cue when a
bite drops you into your own fresh crater. Both are distinct events; the landing
one fires once per drop, not per bite.

⚠ **Both folders are place content, not Rojo-synced — the lobby AND game
places each need them.** A missing folder / missing sample name / duplicate
sample name warns ONCE with a pointer and the cue is skipped (R8); the bank is
re-probed ON A MISS (rate-limited) and the music folder on a cadence, so a
late-replicating library heals itself without a rejoin.

`AudioConfig.sounds` IS the key registry — there is no separate registry file
(one owner, and a copy would drift). Cake layers index it via
`CakeConfig.layers[*].sfx`.

## Pieces
| Module | Owns |
|---|---|
| `SoundPool` | the authored bank, the pooled 2D voices (round-robin, pitch jitter, combo pitch ramp), `cut` timers, per-key throttle, the lazily-started slump loop, `SetEnabled` |
| `MusicService` | shuffled playlist over the authored tracks, fade in/out + gap, `SetEnabled`; stepped per frame |
| `AudioSubsClient` | wiring only: injects the kit sound handler, maps `onPanelChanged` → open/close whoosh, drives `MusicService.Step` |
| `UIKit/Interaction` | emits `"press"` / `"hover"` cues from the shared press primitive — so EVERY kit button sounds, from one hook — plus `Interaction.Cue(name)` for clickable components that deliberately skip the primitive |

Templates carrying SoundEffect children get one dedicated clone each (a pooled
voice has no effect chain); everything else rides a pooled voice.

## Contracts worth keeping
- **Kit stays client-free.** Shared code must not require a client module, so
  `Interaction.SetSoundHandler` (re-exported as `UIKit.SetSoundHandler`) is
  injected by `AudioSubsClient`. Unset = a silent, still-correct kit.
- **First-note.** `MusicService` does not start until the saved
  `music-enabled` arrives (`SettingsSubsClient` calls `SetEnabled`), so a
  "music off" player never hears a note. If it never arrives, the grace
  (`AudioConfig.settingsGraceSeconds`) expires, R8-warns and starts on
  the default rather than staying silent forever.
- **Mute is one property.** `sfx-enabled` → `GameSfx` SoundGroup volume;
  `music-enabled` → `GameMusic` volume *and* stops playback (no point
  streaming an inaudible track). A muted `SoundPool.Play` returns immediately —
  a muted player pays nothing for the bite-rate cue path.
- **Settings gate applies to BOTH.** SFX start muted for the same reason music
  starts stopped; the same grace releases either on the defaults if the
  settings push never lands.
- **Cue the GRANT, not the click.** Upgrades, shop grants and daily rewards all
  cue from their `*Update` payload, so a refused or duplicate action stays silent
  and a spam-clicker earns one sound per grant.
  Purchases are the exception: `purchaseStart` deliberately cues the REQUEST (on
  the Robux route it is the handoff to the prompt; on the gem route the server
  may still refuse), and `purchaseOk` the grant.
- **Panel whoosh has ONE source**: AppRoot's `openPanel` effect, never the
  individual close buttons — a panel cannot forget to fire it.

## Gotchas
- A button that is `enabled = false` has no pointer handlers, so it is
  correctly silent — do not "fix" that.
- **Not every clickable thing uses `usePressable`.** Toggle, PetCard, DayCard,
  the reveal overlay's dismiss catcher and the hex tree's NODES own their own
  motion (or, for the hex tree, are hit-tested through one pan surface rather
  than rendered as buttons) and were therefore SILENT; they call
  `Interaction.Cue("press")` from their activation handler instead. When adding
  a clickable component, do one or the other — never both, or it clicks twice.
  (`ScrollPane`'s scrollbar is deliberately silent: a drag is not a click.)
  Audit with: for each Components/*.lua that builds a Text/ImageButton, it must
  either call `usePressable` or `Interaction.Cue`.
- **A silent button is usually a DISABLED button, not a missing cue.** Shop
  cells make no sound while their dev-product / gamepass ids are unconfigured,
  and gem-priced cells make none while the player cannot afford them
  (`LocalShopService.priceState` → `"unavailable"` / `"unaffordable"` →
  `enabled = false` → `Active = false`): the button is intentionally inert, so it
  must be silent. Check `Active` on the instance before hunting for a missing cue.
- **A REFUSAL is not automatically a cue.** The layer gate refuses a bite you
  take constantly while clearing a layer, so its cue became a stutter of buzzes
  and was REMOVED (user req, 2026-07-31): the `layer-locked` banner carries it
  alone. Do NOT add `SoundPool.Play` back there. The full-belly refusal keeps its
  `blocked` cue because it is a different, rare event — frequency is what decides,
  not "it was refused".
- Cues on per-bite / per-tick events need `cut` AND usually `throttle`, or a
  high eat-rate turns the whole voice pool into one waveform. Calories
  deliberately have NO cue (they tick every bite); gems do (throttled).
- A layer whose `shatterFx` cue used the SAME key as its own bite key played it
  twice per bite — keep `shatter` on a different sample from any layer's `sfx`.
- Two cues that map to the same asset must not fire in the same frame (the
  matchmaking panel once played `queueOpen` alongside the panel whoosh): same
  waveform twice = double amplitude, not a richer sound.
- Joining mid-boss plays `bossAppear` off the join snapshot. That is
  deliberate — the boss does appear on *your* screen — and is the only
  snapshot-driven cue in the layer.
- The pool must outlast the longest `cut`; raising `cut` without raising
  `AudioConfig.poolSize` starts cutting live cues short.

## Files
`src/shared/config/AudioConfig.lua`; `src/client/common/modules/{SoundPool,
MusicService}.lua`; `src/client/common/subscriptions/AudioSubsClient.lua`;
`src/shared/UIKit/Interaction.lua` (SOUND section). Cues are fired from the
domain subscriptions (cake, body, pets, shop, rewards, codes,
upgrades, economy, lobby, teleport).
