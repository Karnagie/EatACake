# ADR-0018: Grant READINESS predicates (a kind can be present and still unable to land)

## Status
Accepted (2026-08-04)

## Context
ADR-0002 gave every reward kind one question — `HasHandler(kind)` — and ADR-0014
built the receipt path on it: `ShopSubs.grantableList` validates the whole grants
list (handler exists + per-kind descriptor shape) BEFORE the first grant, which
is what makes the loop all-or-nothing.

`HasHandler` answers **"is this kind deliverable in this PLACE"**. It cannot
answer **"can it be delivered to THIS PLAYER, RIGHT NOW"**, and some kinds only
have an answer at grant time:

- `eatlayer` (the paid LayerEater, `features/checkpoint.md`) needs the cake in
  its eating phase, an edible band left, and a buyer on the round roster.
- `burn` needs the player to have stomach state at all.

Until now the only way a handler could say "not now" was to **return nil**, and
by then `grantProduct` has already run the grant loop and recorded the receipt;
it logs a warn and still returns `true`, so `processReceipt` answers
`PurchaseGranted`. The player pays real Robux, gets nothing, and Roblox never
re-delivers because it was told the purchase succeeded. On the gem path
(ADR-0015) the same shape spends gems and compensates only if a grant *declines*,
which is the same too-late signal.

This is not hypothetical for `eatlayer`: the Roblox purchase dialog takes seconds,
during which the boss phase can start; and a re-delivered receipt after a crash
can surface in an entirely different round.

## Decision
Add an OPTIONAL third question to the grant registry, alongside `Register`:

```lua
RewardGrantSubs.RegisterReady(kind, function(player, reward): (boolean, string?)
RewardGrantSubs.IsReady(player, reward): (boolean, string?)
```

- `grantableList(def, player)` calls `IsReady` for every descriptor, in the same
  pre-grant window as `HasHandler` and `descriptorValid`. A "not ready" therefore
  reaches the caller BEFORE anything is committed or spent.
- Consequences per path, unchanged in shape from what each already does with an
  invalid descriptor:
  - `ProcessReceipt` → `NotProcessedYet`. Roblox re-delivers forever, so the
    purchase self-heals when the world is ready.
  - `RequestGemPurchase` → refusal with **no spend** (nothing re-delivers gems).
  - `RequestPurchase` → the Roblox dialog is **not opened at all**. Deferring is
    correct but "you were charged, come back later" is a support ticket.
- A kind with no predicate is always ready, so nothing that existed changed.
- A predicate that THROWS is treated as not-ready and warns (R8) — a telemetry-
  grade failure must never take a money path down, and "not ready" is the safe
  direction because it defers rather than grants.

## Consequences
- The reason string is carried to the console at every refusal point, so a
  deferred purchase is never silent (R8).
- A predicate must be CHEAP and non-yielding: it runs inside the pre-grant
  validation of a receipt handler.
- It answers about the moment it is called, not the moment of the grant. The
  window between them is a few statements with no yields, but a predicate can
  still not protect against a race with ANOTHER player's purchase — that has to
  be handled by making the grant itself idempotent or self-correcting.
  `ClearActiveBand` does this by resolving the target band from the field rather
  than from the 1 Hz `activeBandIndex`, so a second buyer inside the same tick
  clears the next layer instead of an already-flat one.
- Readiness is NOT authorization: it may not be used as the only anti-cheat gate,
  because the client cannot reach it directly. Remote handlers keep their own
  validation.

## Alternatives rejected
- **Make `grantProduct` treat a declined grant as failure** (return false →
  NotProcessedYet). One line, and correct for a single-grant product — but for a
  multi-grant product the earlier grants have already applied and the receipt
  ledger has not been written, so the retry re-mints them. That is the exact
  failure ADR-0014's all-or-nothing loop exists to prevent.
- **Let the handler yield until the world is ready.** The grant loop is
  documented as yield-free precisely so a profile can never be observed
  half-granted, and a receipt handler holding a thread across a phase change is
  worse than a deferral.
- **Check the world state inside `descriptorValid`.** It is a pure shape check in
  a COMMON module; teaching it about cake phases would put game-partition
  knowledge in the lobby's code path.

## Related
ADR-0002 (descriptor grammar + registry), ADR-0014 (common receipt handling),
ADR-0015 (in-game-currency purchase path), `features/shop.md`,
`features/checkpoint.md`.
