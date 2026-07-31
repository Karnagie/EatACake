# 2026-07-31: Gem-priced boosts, and cutting three features out

Tags: shop, economy, boosts, treasures, daily-rewards, quests, time-rewards, pets, audio, monetization, ui-kit

## Task
Nine requests in one pass:
1. Boosts purchasable with **GEMS**, priced so one whole cake buys exactly one.
2. Squishy followers face FORWARD, not right.
3. Drop Instant Burn / Lucky Egg / Mega Egg; add three 15-minute boosts
   (Extra Bite Size, 2x Speed, 2x Stomach Capacity).
4. Remove **time rewards** entirely.
5. Retune daily rewards (day 2 = bite boost, day 3 = gems, day 5 = x2 Calories,
   day 7 unchanged).
6. Starter Pack: Lucky Egg → Extra Bite Size + 2x Speed (4 bundle chips).
7. Finds drop **only gems**.
8. Remove **quests** entirely.
9. No sound when a bite is refused by the layer gate (banner stays; the
   full-belly cue stays).

## Context
The shop had exactly one checkout path — `MarketplaceService.ProcessReceipt`,
made COMMON and idempotent the day before (ADR-0014) — and gems had nothing to
buy: they were a find drop with no sink. Boosts were the opposite, a random drop
with no choice attached, documented as a paragraph inside `features/treasures.md`
because finds were their only source. Quests and time rewards were two full
feature triads (data + service + subs + profile section + remotes + kit panel)
that no request had touched since they shipped.
Prior flow: `2026-07-30_squishy-followers-shop-cards-purchases.md` (the money
path), `2026-07-31_shop-cards-tabs-redesign.md` (the cards these products render
in), `2026-07-26_buried-item-finds.md` (the find economy being repriced).

## Plan
Make gems the currency that buys the CHOICE: finds pay gems only, boosts leave
the find table and become a priced row. Then price everything off one measured
number — a cleared cake — so "one cake = one boost" is a rule, not a feel. Build
the gem checkout as its own path rather than bending the receipt path around a
currency Roblox never sees. Cut quests and time rewards by deletion, not by
disabling them.

## Changes

**Created:**
- `src/server/common/subscriptions/BoostSubs.lua` — re-applies every value a live
  boost feeds, on grant AND on expiry (COMMON).
- `src/shared/remotes/RequestGemPurchase.model.json` — the in-game-currency
  checkout.
- `docs/features/boosts.md`, `docs/decisions/0015-in-game-currency-purchase-path.md`.

**Modified (the load-bearing ones):**
- `ShopData` — `currency` + `priceGems` + `ShopData.IsGemProduct`; section
  `eggs` → `boosts` end to end; four boost products at 500 gems; Starter Pack
  bundle/grants rewritten; the `gemPurchaseWindowSeconds`/`gemPurchaseBurst`
  rate limit.
- `ShopSubs` — the whole gem path (see Decisions); `descriptorValid` now proves a
  boost id names a real def; boot report split per currency.
- `TreasureConfig` — finds pay gems only; `boosts` retuned to four 15-min defs;
  `golden-slice` boost def deleted; `boostTickSeconds`.
- `StatsService` — boosts reach `biteRadius` / `walkSpeed` / `capacity`;
  `GrantBoost` EXTENDS instead of resetting; `BoostMult`, `BoostSignature`,
  `NextBoostExpiry`.
- `CakeConfig.composition.coopFinds` + `CakeStateData.findPayoutScale` +
  `CakeCycleService.ScaleFindReward` — find gems pay per head.
- `DailyRewardsData` — 250 gems across the week + two boost days.
- `PetConfig.follow.yawOffsetDegrees` 180 → **-90**.
- `CakeSubsClient` — the layer-gate refusal is now silent (banner only).
- `AppRoot` — HUD left menu is 5 buttons (Pets, Shop, DailyRewards, Codes,
  Settings).
- `tools/monetization/create_monetization.py` — Robux-only catalogue (5 products
  + 6 passes = 11 ids, was 15); hard-exits on a gem-priced key;
  `--include-instant-burn` gone.

**Deleted:**
- Quests: `QuestsData`, `QuestService`, `QuestsSubs`, `QuestsSection`,
  `QuestsSubsClient`, `QuestsPanel`, `QuestRow`, `ClaimQuest`, `QuestsUpdate`.
- Time rewards: `TimeRewardsData`, `TimeRewardsSection`, `TimeRewardService`,
  `ClaimTimeReward`, `TimeRewardUpdate`.

## Decisions

**One cleared cake = one boost, and that had to survive co-op.** The find table
was repriced so a solo cake's 40 finds pay ~496 gems against a 500-gem boost.
Review caught that this held for solo ONLY: the find COUNT comes from cake
volume, which is roster-independent, and a find is consumed by whoever reaches it
first — so a 4-player cake paid each player ~124 gems, **one boost per four
cakes**. Fixed with the per-head rule calories already had
(`coopFinds = 0.62` → `findPayoutScale` → `ScaleFindReward`): 496 / 402 / 371 /
355 gems per player at 1-4 players. Deliberately NOT multiplied by the difficulty
premium — difficulty already pays in calories, and excluding it keeps the rule
true on every difficulty.

**The gem checkout is a second path, not a reuse of the first** (ADR-0015). The
two have opposite failure semantics: Roblox re-delivers a failed receipt forever,
and nothing re-delivers spent gems. So the gem path validates the whole grants
list before spending, spends atomically inside `EconomyService.TrySpendGems`,
never yields between the spend and the grants, COMPENSATES with a refund if a
pre-validated grant still declines, and **refuses outright** mid-teleport-release
where the receipt path merely defers.

**`currency` is the discriminator, never "has no devProductId".** A Robux product
whose dashboard id is still 0 — which is all of them until publish — would
otherwise read as a gem product and be sold for free. `ShopData.IsGemProduct` is
the single predicate the payload, both remotes and the boot report share.

**A boostId must name a real def, not just be a non-empty string.** The four shop
keys and the four def ids differ and exactly one collides, `GrantBoost` answers an
unknown id with `false`, and `DailyRewardsData` had already shipped a `boostId`
naming a FIND. On the gem path that spends the gems and grants nothing, so both
the shop and the daily track now check it, and boot lists offenders.

**`GrantBoost` EXTENDS a live boost instead of resetting it.** Claim the day-2
Extra Bite, buy the same boost a minute later for 500 gems — one whole cleared
cake — and the reset version gave you 60 seconds. Nothing in the UI shows a boost
is running, so there is no way to notice before paying; extending cannot lose time
by construction.

**Three stats needed a subscription; two did not.** `calories`/`gems` are read per
use and simply stop finding the boost. `biteRadius` is PREDICTED client-side from
upgrade levels alone, so it is mirrored through the `BiteRadiusMult` player
attribute; `walkSpeed`/`capacity` are pushed once and stick, so they must be
rewritten at expiry — and an expiry fires no event. Hence `BoostSubs`: a one-shot
timer on the soonest expiry plus a 1 s signature sweep as the backstop.

**Deleting the `golden-slice` boost def needed no migration.** A granted boost
carries its own `stat`/`mult`/`expiresAt` and the def table is read only by
`GrantBoost`, so a live entry keeps working and expires normally.
Same story for the orphaned `quests` and `timeRewards` profile keys:
`PersistenceService.applySchema` iterates only the schema's sections and preserves
unknown top-level keys verbatim (nothing calls ProfileStore's `Reconcile`), so no
version bump and no migration.

**A catalogue-driven tool must brick loudly on a key it can no longer resolve.**
`read_shopdata_prices()` runs before every branch of the monetization tool
(including `--verify` and the dry run) and exits on the first key with no
`devProductId` — so leaving the now-gem-priced boosts in `PRODUCT_COPY` did not
create four unwanted products, it disabled the only supported way to create the
ids the shop is blocked on. The tool now also hard-exits if a `currency = "gems"`
key is listed at all.

**The layer-gate refusal went silent.** The gate refuses a bite you take
constantly while clearing a layer, so the refusal sound was a stutter of buzzes.
The banner alone carries it; the full-belly refusal is a different, rare event and
keeps its cue.

## Open Questions / Followups
- **No HUD indicator for a live boost** — no icon, no remaining time, nowhere.
  Every rule above that protects a re-purchase exists to paper over this gap; a
  small boost strip near the HUD pills is the real fix.
- Boost balance is a paper number: the four 15-min defs were priced to be equal,
  never played against each other. `capacity` ×2 and `walkSpeed` ×2 are probably
  not worth the same as `biteRadius` ×1.4.
- The co-op gem figures are arithmetic on the measured solo number, not five-seed
  simulation runs like the pacing model produces.
- `RewardGrantSubs` still registers the `egg` kind (daily day 7 + the cycle roll);
  nothing sells one any more.

## Related
- Features: `docs/features/boosts.md` (new), `docs/features/treasures.md`,
  `docs/features/shop.md`, `docs/features/cake-cycle.md`,
  `docs/features/daily-rewards.md`, `docs/features/pets.md`
- ADRs: **ADR-0015** (new), ADR-0014 (receipts), ADR-0013 (run reset — boosts
  survive it), ADR-0012 (finds), ADR-0002 (reward descriptors)
- Prior flow: `docs/flow/2026-07-30_squishy-followers-shop-cards-purchases.md`,
  `docs/flow/2026-07-31_shop-cards-tabs-redesign.md`,
  `docs/flow/2026-07-26_buried-item-finds.md`
