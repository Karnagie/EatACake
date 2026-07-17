# Treasures (finds buried in the cake)

## What it does
GDD §6.1: at cake spawn, 8-40 finds (scaled by edible volume) are pinned to
cells + reveal heights. Surface drops past one → pickup spawns (cloned
template, R5). First player within 5 studs collects it — the consumed flag
lives ON THE FIND (§13), never on the player. Uncollected pickups despawn
after 45 s. Rewards are descriptors (`gems` / `boost` / `egg`) granted via
RewardGrantSubs; `progress.findsCollected += 1`.

## Config / state
`Shared/config/TreasureConfig` — find table (weights, rewards, colors),
spawn density, boost defs (`golden-slice` x2/60s, `boost-15m` x2/900s —
also used by shop/codes). Runtime state: `CakeStateData.treasures`.

## Replication
`TreasureUpdate` FireAllClients:
`{event="spawned", findId, position}` (pop FX) /
`{event="collected", findId, byUserId, position}` (burst; collector also
gets a coin sound). Currency updates ride the grant handlers.

## Cadence
`TreasureService.Tick` at 2 Hz inside CakeSubs (reveal check + proximity
collection — no Touched races).

## Files
`services/TreasureService`, `subscriptions/CakeSubs` (grants + FX fanout),
shared `config/TreasureConfig`; client FX in `CakeSubsClient`.
