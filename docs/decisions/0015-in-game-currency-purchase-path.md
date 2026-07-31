# ADR-0015 — A second purchase path: our server is the cashier for gems

Date: 2026-07-31
Status: accepted
Builds on ADR-0014 (common, idempotent receipts), ADR-0002 (grant registry).
Supersedes nothing.

## Context

Boosts stopped being a random find drop and became something the player BUYS with
gems (500 each, `features/boosts.md`). Gems are earned in-game, so there is no
Roblox transaction behind the purchase: the shop now has **two checkout paths**
running side by side in the same subscription —

| | Robux (`ProcessReceipt`) | Gems (`RequestGemPurchase`) |
|---|---|---|
| who charges | Roblox | **us** |
| a failed delivery | is **re-delivered forever** until we return `PurchaseGranted` | is **gone** — nothing re-delivers spent gems |
| so the hard problem is | not granting the same receipt twice | not charging for a no-op |
| "defer and retry later" | the correct answer | not an available answer |

Every guarantee ADR-0014 gets for free from the retry contract has to be written
out by hand on the gem path, and two of them invert. In particular the
mid-teleport-release case — `PersistenceService.Save` is a no-op while a release
nonce is set — is *deferred* on the receipt path because Roblox will bring the
receipt back; on the gem path a deferral would simply lose the gems.

The trigger for getting this exactly right: `StatsService.GrantBoost` answers an
unknown `boostId` with `false`, the four shop keys and the four def ids
deliberately differ, and `DailyRewardsData` had already shipped a `boostId` that
named a FIND. On the gem path that combination spends the gems and grants nothing.

## Decision

1. **One remote, handled where `ProcessReceipt` already lives.** `ShopSubs` owns
   both paths, so both read one catalogue, one validator (`grantableList` →
   `descriptorValid`) and one payload builder. A gem product is an ordinary
   `ShopData.products` entry.
2. **`currency` is the discriminator, read only through
   `ShopData.IsGemProduct`.** Never "has no `devProductId`": a Robux product whose
   dashboard id is still 0 must not read as a gem product. Each remote refuses the
   other currency's key — the Robux one quietly (a drifted UI route), the gem one
   with a `Log.Warn` per attempt, because a Robux key arriving there is someone
   trying to buy a 2000 R$ pack for nothing and the COUNT matters.
3. **Validate the WHOLE grants list BEFORE spending.** Including that a `boost`
   descriptor names a real `TreasureConfig.boosts` def. The money must never be
   taken for a no-op, and there is no retry that would put it back.
4. **The spend is ATOMIC** — `EconomyService.TrySpendGems(userId, price)` checks
   and deducts inside the service. A read-then-subtract in the handler leaves a
   window where a second click passes the same balance check.
5. **No yields between the spend and the grants**, so the profile can never be
   observed with the gems gone and the reward missing.
6. **A late decline is COMPENSATED.** If a pre-validated grant still returns nil,
   the price is refunded, the balance re-pushed and the failure warned. "Should be
   impossible" is not a guarantee a currency path may rest on. The refund is
   all-or-nothing AT THE PRICE, so a gem product with more than one grant would
   refund in full while keeping the grants that succeeded — boot warns loudly if
   one ever appears.
7. **Refuse, don't defer, mid-teleport-release** (and when the profile isn't
   loaded). The player is told to buy again after the handoff; that is the honest
   answer when nothing will re-deliver.
8. **Every refusal answers with a full catalogue re-push**, so a stale client
   corrects itself instead of showing an affordable card that does nothing; a
   SUCCESS additionally re-pushes the balance (`EconomySubs.SendCurrency`),
   because `RewardGrantSubs` pushes `CurrencyUpdate` when it GRANTS gems and a
   SPEND has no such push.
9. **A per-player BURST BUCKET** (`gemPurchaseBurst` per
   `gemPurchaseWindowSeconds`) gates the remote before any push or warn. It
   started as the flat cooldown `RedeemCode` carries and that was WRONG here:
   `RedeemCode` answers a throttled attempt with a `cooldown` status, and this
   remote answers with nothing — so a player tapping two different boosts inside
   the window silently got one. A bucket lets a human buy the whole row while
   still clamping a Heartbeat spammer.
   Points 6 and 8 are exactly what turn an ungated remote into a weapon against
   the server it runs on.
10. **The boot report understands both currencies.** A gem product is never listed
    as "NOT ON SALE" (it needs no dashboard id — that would be a permanent false
    positive, which R8 forbids); its equivalent misconfiguration is a missing
    `priceGems`, reported separately, and its cards render "SOON".

## Consequences

- Anything sellable for both currencies must keep passing through
  `grantableList`; a validation rule added for one path is a rule for both.
- `configured` in the `ShopUpdate` payload means "nonzero dashboard id" for a
  Robux product and "nonzero price" for a gem one. The client routes the click by
  the `currency` field it was sent — dropping either field from the payload
  whitelist silently renders a gem card as an unpriced Robux product.
- The gem path needs **no receipt ledger**: with no re-delivery there is nothing
  to be idempotent against. Its equivalent risk is the double-click, covered by
  the atomic spend plus the cooldown.
- Gem products must never reach the Creator Dashboard, or the same item is on sale
  twice at two unrelated prices. `tools/monetization/create_monetization.py` is
  Robux-only and hard-exits on a gem-priced key.
- A boost priced in gems can be bought in the LOBBY and used in the GAME place
  only because timed boosts survive the run reset (ADR-0013).

## Alternatives rejected

- **Reuse `ProcessReceipt` with a 0-Robux dev product.** Rejected: it needs a
  dashboard id per boost, opens a Roblox purchase modal and a network round trip
  for an in-game click, and inherits a retry/consumption contract whose whole
  premise — Roblox re-delivers what it charged for — does not apply to a currency
  Roblox never touched.
- **Read the balance, then subtract.** Rejected: two clicks inside one frame pass
  the same check; the second spend either drives the balance negative or grants
  twice for one price. The atomic service call costs nothing and closes it.
- **Grant first, charge after.** Rejected: the failure mode is free loot, and
  unlike a receipt there is nothing to reconcile against afterwards.
- **Defer mid-teleport-release, mirroring the receipt path.** Rejected: the
  symmetry is superficial. A deferred receipt comes back; deferred gems do not.
- **A separate `GemShopSubs`.** Rejected for the same reason ADR-0014 rejected a
  minimal `ReceiptSubs`: it would need `ShopData`, `ShopService`, the same
  validator and the same catalogue push — a seam with no owner.
- **Trust the client's affordability check** (the card is greyed when the player
  cannot pay). Rejected: R6. Reaching the server unaffordable is a stale client or
  a race, and it is a refusal the console has to show, not a silent no-op.
