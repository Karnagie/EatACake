# ADR-0002: Reward descriptors + central grant registry

## Status
Accepted (2026-07-12)

## Context
Dices established a uniform "reward descriptor" grammar
(`{kind="gold"|"exp"|"die"|"case", ...}`) produced by every reward feature
(daily/time/group/renown/shop/contracts) — but the granting helper
(`grantReward`) was duplicated near-identically in four subscription modules,
each hard-coding the service graph (Economy/Progression/Chest/Inventory).
Adding a reward kind meant editing every copy.

## Decision
- Keep the descriptor grammar as the game-wide loot language. Template ships
  `{ kind = "gold", amount = n }`; games add kinds freely.
- One subscription module, `RewardGrantSubs`, owns granting:
  `Grant(player, descriptor, source)` dispatches to handlers registered via
  `Register(kind, handler)`. Handlers are registered from feature
  subscriptions' `Start` (R3-legal: subs coordinate services). Unknown kinds
  warn and return nil — a claim is still consumed server-side, so tune data
  tables only with registered kinds.
- Feature services stay pure (R3): validate + return the owed descriptor;
  only RewardGrantSubs touches the granting service graph.

## Consequences
- New reward kind = one `Register` call in the owning feature's subs; reward
  tables (`DailyRewardsData.days`, future shop/quests) can use it immediately.
- The `granted` descriptor returned by a handler is the client-toast payload
  contract (echoed inside feature updates, e.g. `DailyRewardUpdate.granted`).
- Registration order is irrelevant (Grant runs at event time, after all
  Starts); duplicate registration warns and overwrites.
