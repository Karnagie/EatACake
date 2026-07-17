# 2026-07-12: Daily rewards + economy + reward-grant registry

## Task
First feature triads on top of the persistence layer: Net plumbing, minimal
economy (gold), the reward-descriptor grant registry, and the daily-rewards
feature — ported from Dices with its known warts designed out.

## Context
Prior: `2026-07-11_schema-driven-persistence.md`. Reference implementation:
Dices `DailyRewardService`/`DailyRewardsData`/`RewardsSubs`/
`RewardsSubsClient`/`LocalRewardsService` + `Net.lua`. Dices duplicated the
`grantReward` helper across four subs and pushed initial state right after
LoadProfile with no client-ready handshake.

## Changes

**Created (shared):** `Net.lua`; remotes `ClientReady`, `ClaimDailyReward`;
remoteUpdates `GoldUpdate`, `DailyRewardUpdate`.

**Created (server):** `ProfileSchema/EconomySection.lua`,
`ProfileSchema/DailyRewardsSection.lua`, `data/DailyRewardsData.lua`,
`services/EconomyService.lua`, `services/DailyRewardService.lua`,
`subscriptions/RewardGrantSubs.lua` (ADR-0002), `subscriptions/EconomySubs.lua`,
`subscriptions/RewardsSubs.lua`.

**Created (client):** `data/UiData.lua` (nil-tolerant resolver),
`data/LocaleData.lua` (stub with Dices-compatible T/Tr API),
`modules/LocalRewardsService.lua`, `subscriptions/RewardsSubsClient.lua`.

**Modified:** `PlayerLifecycleSubs` (ClientReady gating + feature hooks),
`LocalBootstrap.client.lua` (fires ClientReady last), docs (MAP, registries,
features, ADR-0002).

## Decisions
- **Central grant registry (ADR-0002)** instead of Dices' four duplicated
  `grantReward` helpers: `RewardGrantSubs.Register(kind, handler)` /
  `Grant` / `HasHandler`. Template ships `gold` only.
- **ClientReady handshake**: initial state pushes wait for profile-loaded AND
  client-ready. Fixes a real race — RemoteEvents fired before the client
  connects listeners are lost (Dices pushed immediately after LoadProfile).
- **Respawn-proof client**: buttons wired per GUI instance; PlayerGui.ChildAdded
  re-wires + re-renders cached state if the ScreenGui is re-cloned
  (ResetOnSpawn). Dices' wire-once died on first respawn with ResetOnSpawn=true.
- **Claim is never consumed for an ungrantable reward**: server pre-checks
  `HasHandler(kind)` before `Claim`; plus deferred startup validation of the
  whole `days` table (gaps, out-of-range entries, unregistered kinds).
- **Loop-seam rendering**: `claimable == false` ⇔ "claimed today", so the
  client marks `prev(current)` claimed — fixes the day-N→1 wraparound where
  the just-claimed final day showed "Locked".
- `Claim` returns `table.clone(reward)` — handlers can't corrupt config.
- Streak semantics preserved from Dices: never resets on a miss, loops after
  the final day; `IsClaimable` uses `~=` (self-heals clock skew) — commented.

## Open Questions / Followups
- Celebration/toast hook is a stub (locale keys reserved).
- Gold HUD not built (GoldUpdate has no client consumer yet).
- Next triads: time rewards, group reward, shop (dev products), settings,
  promo codes, gamepasses.
- UI kit: author DailyRewardsGui per contract in `docs/features/daily-rewards.md`,
  save as .rbxm into the template.

## Related
- Feature: `docs/features/daily-rewards.md`, `docs/features/economy.md`
- ADRs touched: ADR-0002 (new), ADR-0001
- Prior flow: `docs/flow/2026-07-11_schema-driven-persistence.md`
