# ADR-0014 — ProcessReceipt is COMMON, and every receipt is idempotent

Date: 2026-07-30
Status: accepted
Supersedes nothing. Builds on ADR-0009 (two-place split), ADR-0002 (grant registry).

## Context

`ShopSubs` owned `MarketplaceService.ProcessReceipt` and lived in the LOBBY
partition. That was fine while the shop window was the only way to spend Robux —
but a receipt is not a UI event, it is a delivery obligation, and Roblox decides
where and when it surfaces:

- the in-experience Store can complete a purchase in a GAME server;
- a receipt is re-delivered until the server returns `PurchaseGranted`, and the
  retry can land anywhere the player is;
- a purchase completed as the player teleports surfaces on the destination.

In the game place there was no `ProcessReceipt` at all, so those receipts were
dropped with **no console trace**. Roblox retries forever, so no money was
stolen — but the player saw nothing happen, and nothing in the boot report said
the money path was missing (an R8 violation on the most expensive path in the
game). The absence was invisible in Studio, because the combined dev project
maps both partitions flat.

Three further defects were latent only because no real money flowed yet:

1. **Re-delivery double-granted consumables.** A server that granted and then
   died hands the SAME `PurchaseId` to the next one. `oneTime` products were
   protected by `shop.oneTimePurchased`; every gem pack, egg and boost was not.
2. **Granting mid-handoff silently lost the reward.** `PersistenceService.Save`
   is a no-op while a teleport release nonce is set, so a receipt in that window
   returned `PurchaseGranted`, took the Robux and released the session with the
   grant unsaved.
3. **The descriptor guard tested a kind this game does not have** (`gold`), so
   `{ kind = "gems", amount = 0 }` passed validation and produced
   `PurchaseGranted` for nothing.

## Decision

1. **`ShopSubs` and `ShopService` move to `src/server/{common}`.** Receipts are
   handled wherever the player is. Neither module had a lobby-only dependency —
   both read only `PlayerProfileData`, `ShopData` and common subs — so the move
   is a partition change, not a rewrite. The shop WINDOW is still lobby-only;
   this is about DELIVERY, not display.
2. **A grant kind that only one partition registers is deferred, not failed.**
   `burn` is registered by the game partition's `BodySubs`. A receipt for it in
   the lobby returns `NotProcessedYet`, and Roblox re-delivers it in a game
   server, where the handler exists. Self-healing; boot logs which kinds are
   affected in the current place so the deferral is never a mystery.
3. **Receipts are idempotent by ledger.** `profile.shop.receipts` keeps the last
   `ShopData.receiptLedgerSize` (50) `PurchaseId`s. The id is recorded in the
   same no-yield stretch as the grant, before the save.
4. **No grant while a release is in flight.** The receipt path checks the same
   `PlayerProfileData.releaseNonces` that `Save` refuses on.
5. **`ProcessReceipt` is assigned FIRST in `Start`**, before anything that can
   throw, and logs `Log.Sum` when armed.
6. **`PurchaseGranted` is returned only after the write CONFIRMS.**
   `PersistenceService.Save` is fire-and-forget (ProfileStore's `Profile:Save()`
   is a `task.spawn`), so returning straight after it tells Roblox to stop
   retrying while the grant exists only in memory — a hard crash in that window
   takes the Robux and delivers nothing, permanently, because Roblox already saw
   `PurchaseGranted`. The new `PersistenceService.SaveAndWait(userId, timeout?)`
   waits (bounded, 10 s) on `OnAfterSave` and returns whether a save landed; the
   receipt path returns `NotProcessedYet` when it did not. The already-handled
   branch does the same, because "handled" may itself be an unsaved in-memory
   fact from the previous attempt.

   Caveat inherited from ProfileStore: `OnAfterSave` is shared by every
   concurrent save of the profile, so this proves "a save committed", not "MY
   save committed". That is the guarantee needed — any committed write carries
   the already-mutated `Data`, grant included.

## Consequences

- Any future money handler must be COMMON, or explicitly document which place it
  belongs to and defer elsewhere.
- The ledger is per-profile and bounded: a receipt cannot resurface after 50
  further purchases by the same player. That is far outside Roblox's retry
  window, but it IS a bound, not a proof.
- `ShopSection` gains `receipts` with a default, so no version bump and no
  migration (P2). Its `sanitize` rebuilds the list rather than repairing it, and
  carries its own 200-entry corruption ceiling separate from the tuning knob.
- A place that maps only one partition still boots: `PassOwnershipSubs` resolves
  `ShopSubs` through the registry and tolerates its absence.

## Alternatives rejected

- **Keep receipts lobby-only and accept the delay.** Rejected: the failure is
  silent, and "the player bought something and nothing happened" is exactly the
  case that must never be quiet.
- **Split a minimal `ReceiptSubs` into common, leaving ShopSubs in the lobby.**
  Rejected: the receipt path needs `ShopService`, `ShopData` and the catalogue
  push anyway, so the split would have been a seam with no owner.
- **Trust Roblox not to re-deliver a granted receipt.** Rejected: the retry
  contract explicitly requires `PurchaseGranted` to be observed, and a crashed
  server never returns it.
