# Group reward (one-time "join our group")

## What it does
One-time reward for being a member of the game's Roblox group. Membership is
verified LIVE server-side with `GroupService:GetGroupsAsync` (yields) —
`Player:IsInGroup` is cached from server-join and misses mid-session joins.
There is NO like/favorite verification (Roblox exposes none).

## Tuning
`src/server/data/SocialData.lua`: `groupId` (**0 = not configured**: claims
refused, client row hidden, boot warn), `reward` (descriptor),
`claimCooldownSeconds` (anti-spam for the web request).

## State
Profile section `social`: `groupRewardClaimed: bool`.

## Flow
Join: `GroupRewardSubs.SendState` → `GroupRewardUpdate { configured, claimed,
groupId }`. Claim: shop Free row → `ClaimGroupReward` → guards (configured,
not claimed, not pending, cooldown, HasHandler) → LIVE membership check
(yield; player-left / already-claimed / session-end re-checks after) →
`RewardGrantSubs.Grant` → grant nil ⇒ claim NOT consumed (resync + warn) →
`MarkRewardClaimed` → Save → `GroupRewardUpdate { status = "granted",
granted }`. Not a member → `{ status = "not-in-group" }` → client shows
"join first" hint; player retries after joining (web propagation can take
seconds).

## UI
No dedicated window: a row in the Shop panel's "Free" section
(`LocalShopService.BuildTabs`), FREE button, owned-dim when claimed.

## Files
Server: `SocialData`, `SocialSection`, `SocialService`, `GroupRewardSubs`.
Client: `ShopSubsClient` (routes `group` row id), `LocalShopService`.
Remotes: `ClaimGroupReward`, `GroupRewardUpdate`.
