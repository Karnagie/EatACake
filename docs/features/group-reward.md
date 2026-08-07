# Community reward (like the game + join the group)

## What it does
A one-time **15-minute x2-Calories boost** (`TreasureConfig.boosts["boost-15m"]`
— the same thing the shop sells for 500 gems) for liking the game and joining the
Roblox community. Own panel in the lobby meta menu; the shop's Free row is a
second door into it, not a second claim path.

## Why it is a 10-second WAIT
**Roblox exposes no like/favorite API — none, for anyone.** So "did they like
it?" is unanswerable and the reward is built around that instead of pretending
otherwise: the player is told to like the game and WAIT, and the boost lands
`SocialData.claimDelaySeconds` (10 s) later provided the one verifiable thing —
community membership — holds at the END of the window.

A player who is **already a member takes the identical path**: same red message,
same wait. A claim that resolved instantly for members would teach exactly the
group being asked to like the game that they can skip that half.

## Tuning
`src/server/lobby/data/SocialData.lua`:
- `groupId` — **307557979** (HBs Interactive). `0 = not configured`: claims
  refused, menu button + shop row hidden, boot warn.
- `reward` — descriptor, `{ kind = "boost", boostId = "boost-15m" }`.
  ⚠ The panel's body copy names the boost ("15 minute x2 Calories"); changing
  `boostId` means changing `group-body` in `LocaleData` too.
- `claimDelaySeconds` (10) — the wait; also the `{n}` in the red message.
- `claimCooldownSeconds` (5) — min seconds between **resolved** attempts.
  Measured from when an attempt finishes, not from the press, and concurrent
  claims are already impossible via the in-flight lock — so it deliberately does
  NOT need to exceed `claimDelaySeconds`. Keeping it short matters: the
  "join the community first, then try again" copy invites an immediate retry, and
  a cooldown timed from the press would silently refuse exactly that press.

## State
Profile section `social`: `groupRewardClaimed: bool` (one-time, meta — survives
the run reset). Referral fields in the same section: `features/referrals.md`.

## Flow
Join: `GroupRewardSubs.SendState` → `GroupRewardUpdate { configured, claimed,
groupId, waitSeconds }`.

Claim (`ClaimGroupReward`, no args):
1. Guards, in this order — configured, not in-flight, cooldown, then the
   already-claimed echo (deliberately BELOW the spam guards: it is a
   client-triggered push and otherwise unbounded), then `HasHandler` **and
   `IsReady`** (ADR-0018: checked BEFORE the wait, so a player never watches a
   countdown for a reward this place cannot deliver).
2. LIVE membership check (`SocialService.IsInGroup` → `GetGroupsAsync`, YIELDS).
   Its ONLY job is to tell the client whether to raise the join prompt.
3. Push `{ status = "pending", member, waitSeconds }`.
4. `task.wait(waitSeconds)`.
5. LIVE re-check — **this one decides.** Joining during the wait counts.
6. Re-guards (player present, not claimed concurrently, `IsLoaded`, **not
   mid-teleport-release**) → `RewardGrantSubs.Grant` → grant nil ⇒ claim NOT
   consumed (resync + warn) → `MarkRewardClaimed` → `Save` →
   `{ status = "granted", granted }`.
   Not a member ⇒ `{ status = "not-in-group" }`.

The whole body is **pcall'd**, and the in-flight lock is released in exactly one
place by the call that TOOK it (`owned.started`). It spans two web requests and a
10-second wait: anything raised in there would otherwise leave the lock set for
the rest of the session — a player who can never claim again, with nothing in the
console — and a press refused *because* another claim is running must not release
that claim's lock.

`GroupRewardUpdate` payload:
`{ configured, claimed, groupId, waitSeconds, status?, member?, granted? }`;
`status ∈ "pending" | "granted" | "not-in-group" | "already-claimed"`.
⚠ `waitSeconds` rides **every** payload, including the join push — the client
renders the red wait line on the press, before any reply exists, so it must
already hold the real number or its fallback constant becomes a second source of
truth for a value `SocialData` owns (R1).

## Client (SocialSubsClient — LOBBY, R4)
- The red **"Like the game and wait 10 seconds."** (`group-wait`, `{n}` from the
  server's `waitSeconds`) appears on the **press**, not a round-trip later. That
  instruction is the mechanic, so it cannot wait for the network.
- `GroupService:PromptJoinAsync(groupId)` — **client-only**, yields until
  answered — is raised when the `pending` push says `member ~= true`.
- The CTA is dead while a claim runs and once claimed.
- ⚠ Every server-side refusal on this path is deliberately SILENT (a modified
  client must not be able to farm replies), so the client releases its own button
  after `waitSeconds + 15` rather than freezing the panel for the session.

## UI
`AppRoot` panel `GroupReward` — `UIKit/SocialPanel` (`Theme.SocialLayout`), menu
button `GroupReward` (`UiHeart` — the shop's Free row already wears `UiFriend`),
badged while unclaimed, hidden entirely until the server says `configured`.
The shop's Free row (`LocalShopService.BuildTabs`, id `group`) now **opens this
panel** instead of firing the remote: the reward needs a surface that can show
the instruction and the wait.

## Gotchas
- ⚠ `Player:IsInGroup` / `GetRankInGroup` are cached from server-join and miss a
  mid-session join — which is every player this feature just prompted.
  `GetGroupsAsync` hits the web and sees it. Never swap them back.
- ⚠ `AppRoot.group` has exactly ONE consumer now (`SocialSubsClient`);
  `ShopSubsClient` no longer connects `GroupRewardUpdate`. Two consumers of one
  update is the drift D3 bans.
- Web errors in `IsInGroup` are treated as "not a member" (fail closed) — the
  player simply tries again.

## Files
Server (LOBBY): `SocialData`, `SocialService`, `GroupRewardSubs`.
Server (COMMON): `SocialSection`, `RewardGrantSubs` (`boost` kind →
`features/boosts.md`), `PersistenceService`.
Client (LOBBY): `SocialSubsClient`. Client (COMMON): `AppRoot`,
`LocalShopService` (Free row), `ShopSubsClient` (routes the row), `LocaleData`
(`title-group-reward`, `group-*`, `menu-group`).
Kit: `UIKit/SocialPanel`, `Theme.SocialLayout`.
Remotes: `ClaimGroupReward`, `GroupRewardUpdate`.
