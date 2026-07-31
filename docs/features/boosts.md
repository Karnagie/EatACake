# Boosts — timed stat multipliers

## What it does
A boost is one row in `progress.activeBoosts` — `{ id, stat, mult, expiresAt }` —
that multiplies ONE stat until its unix timestamp passes. Four defs, all 15 min,
all the same price, so the player chooses WHICH one rather than stacking the lot.
Defs live in `Shared/config/TreasureConfig.boosts` (historical: finds used to be
the only source; they pay gems only now — `features/treasures.md`).

| def id | stat | mult | sold / granted as |
|---|---|---|---|
| `boost-15m` | calories | ×2 | shop `boost-15m`, daily day 5, Starter Pack |
| `bite-15m` | biteRadius | ×1.4 | shop `boost-bite`, daily day 2, Starter Pack |
| `speed-15m` | walkSpeed | ×2 | shop `boost-speed`, Starter Pack |
| `capacity-15m` | capacity | ×2 | shop `boost-capacity` |

**Price: 500 gems, uniform** (`ShopData.priceGems`; purchase path in
`features/shop.md`, ADR-0015). That number is the pacing rule — one cleared cake
pays about one boost, whatever the party size or difficulty
(`features/treasures.md` owns the gem income behind it).
⚠ The four PRODUCT keys and the four DEF ids differ and exactly one of them
collides (`boost-15m`), so a copy-paste slip is one token away.

## Which stats a boost can reach
`stat` is a CONTRACT with StatsService and this is the whole list:
**calories | gems | biteRadius | walkSpeed | capacity**. Those five (and only
those) are multiplied by `StatsService.BoostMult`. A def naming anything else is
a boost that silently does NOTHING: it sells, it is granted, it expires, and no
number ever moves. Adding a stat means teaching StatsService about it AND — if
the value is pushed or applied once rather than read per use — adding it to
`BoostSubs.Apply`.

## Three classes of stat (why this is not just a multiply)
| class | stats | what it needs |
|---|---|---|
| read PER USE | calories, gems | nothing — the next read simply stops finding the boost |
| predicted CLIENT-side | biteRadius | mirrored into the **`BiteRadiusMult` player attribute** (attributes replicate themselves: no remote, no payload). The client predicts craters from its replicated upgrade LEVELS alone, which know nothing about boosts, so without the mirror every predicted crater is wrong for 15 minutes (`LocalStatsService`, floored at 1 — over-prediction is the visible failure) |
| PUSHED / applied ONCE | walkSpeed (written onto the Humanoid by `BodySubs.RefreshBody`), capacity (rides `StomachUpdate`) | must be re-applied on grant **and rewritten at expiry** — a speed boost would otherwise never wear off |

## BoostSubs (COMMON — runs in both places)
- **`Apply(player)`** — writes `BiteRadiusMult`, then `BodySubs.RefreshBody` +
  `SendStomach` (in that order: SendStomach drops the whole push when the profile
  isn't loaded, and WalkSpeed must be corrected even then). Idempotent.
- **`PushInitialState`** — join hook. Required, not an optimisation: a boost
  bought in the lobby survives the handoff, but the game place's `Player` is a
  FRESH instance carrying no attributes.
- **Grants don't wait** — `RewardGrantSubs` calls `Apply` directly, so a
  500-gem purchase does something the same frame.
- **Expiry fires no event.** Every `Apply` arms a generation-stamped one-shot
  timer on `StatsService.NextBoostExpiry` (+0.05 s past the boundary), so the
  common case is exact; a `TreasureConfig.boostTickSeconds` (1 s) sweep comparing
  `StatsService.BoostSignature` is the BACKSTOP. Reading the signature also
  PRUNES, so the sweep both detects and effects an expiry.
- **`BodySubs` is resolved through the subscriptions registry and is legitimately
  nil in the LOBBY** (no body, no belly, no cake). There the attribute is still
  written, because the game place re-applies the rest on arrival. R3.

## Lifecycle
- Persisted in `progress.activeBoosts` (`ProfileSchema/ProgressSection`).
  **Offline time counts down** — standard for timed boosts.
- `sanitize` drops expired entries at load; at runtime `StatsService`'s
  `pruneExpired` is what actually retires one (a deliberately IMPURE read).
- **Boosts SURVIVE the run reset** (ADR-0013) alongside gems and squishies. That
  is the whole reason a lobby purchase is worth anything: the lobby→game teleport
  releases and reloads the profile, which wipes upgrades and calories.
- A live entry carries its OWN `stat`/`mult`/`expiresAt`; the def table is read
  only by `GrantBoost`, at grant time. So **deleting a def needs no migration and
  no version bump** — an entry granted from it keeps working and expires normally
  (that is how `golden-slice` was removed).

## GrantBoost EXTENDS a live boost, never resets it
`expiresAt = max(expiresAt, now) + duration`, and `stat`/`mult` are re-stamped so
a retuned def reaches a player already holding the old one.
It used to RESET, which quietly ate the purchase: claim the day-2 Extra Bite,
buy the same boost a minute later for 500 gems — one whole cleared cake — and you
gained 60 seconds. **Nothing in the UI shows a boost is running**, so there was no
way to notice before paying. Extending cannot lose time by construction, which is
why it is the safe default rather than a refusal.

## Validation — a boostId must name a real def
Both the gem path (`ShopSubs.descriptorValid`) and the daily track
(`RewardsSubs.grantable`) prove the descriptor's `boostId` is a key of
`TreasureConfig.boosts`, not merely a non-empty string, BEFORE charging or
consuming a claim; `ShopSubs` also lists offenders once at boot. `GrantBoost`
answers an unknown id with `false`, which on the gem path means the gems were
already spent — and `DailyRewardsData` shipped `boostId = "golden-slice"` (a FIND
id) once already.

## Gotchas
- ⚠ **There is no HUD indicator and no remaining-time readout for a live boost
  anywhere in the game.** The player cannot tell that one is running, which of
  the four it is, or when it ends. Every rule above that protects a re-purchase
  exists because of this gap.
- The capacity boost multiplies AFTER the x2-stomach gamepass, so the two STACK
  (×4) instead of the boost quietly replacing a 249 R$ perk.
- Boosts are the only thing besides passes that can raise `walkSpeed`; a stale
  one is a movement exploit, which is why the expiry re-apply is not optional.

## Files
`Shared/config/TreasureConfig` (`boosts`, `boostTickSeconds`);
`services/StatsService` (`BoostMult`, `BoostSignature`, `NextBoostExpiry`,
`GrantBoost`); `subscriptions/BoostSubs` (COMMON), `RewardGrantSubs` (`boost`
kind — ADR-0002), `ShopSubs` (gem purchases — ADR-0015), `RewardsSubs` (daily);
`ProfileSchema/ProgressSection`; client `LocalStatsService.BiteRadiusMult`.
