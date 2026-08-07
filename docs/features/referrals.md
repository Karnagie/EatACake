# Referrals (Invite Friends)

## What it does
The inviter gets **500 gems for every friend who joins the game through a Roblox
invite**, once per invited account, forever. The panel is one button: it raises
Roblox's native invite prompt and shows how many friends have arrived so far.

## The two halves never run for the same player
| Half | Where | When |
|---|---|---|
| **Attribution** | the INVITEE's join, `ReferralSubs.OnProfileLoaded` | `Player:GetJoinData().ReferredByPlayerId` is non-zero |
| **Payment** | the INVITER's session, a ProfileStore MESSAGE handler | whenever/wherever their profile is next active |

Roblox drops an invited friend into whatever server has room, so the inviter is
usually **not on this server and often not online at all**. The payment is
therefore queued onto their profile with
`PersistenceService.SendMessage` (ProfileStore `MessageAsync`) rather than
written directly — see `features/persistence.md`. That is also what keeps P5:
no `DataStoreService` anywhere.

## Anti-abuse — and the part it does NOT solve
`social.referredBy` is written once, the first time an account ever joins
carrying a `ReferredByPlayerId`, and never cleared. An account can be re-invited
by anyone any number of times and only ever pays out once, across every server
and every session. Self-referral (`referrerId == userId`) is refused.
The stamp is committed with **`SaveAndWait` BEFORE the payment is queued** — it
is the anti-duplicate mark, and telling another profile about a grant whose mark
has not landed is the same money-path mistake ADR-0014 exists to prevent. If the
save does not confirm, no payment is sent (the invite is simply re-payable on
their next join).

⚠ **That stamp bounds ONE account, not many** — the alt-account farm is not
solved by it, and 500 gems is roughly one cleared cake's income.
`SocialData.referral.minInviteeAccountAgeDays` (default **1**) is a floor, not a
fix: `Player.AccountAge` is free (no web call) and it kills the
create-join-collect loop that runs inside a single sitting, while a friend who
signed up yesterday still counts. Raise it if the payout rate looks wrong; `0`
disables the gate. Roblox's referral guidance recommends exactly this class of
mitigation **plus monitoring** — nothing here monitors, so watch the
`referral reward paid` summaries.

## Flow
1. Invitee joins → `OnProfileLoaded` reads join data → account-age gate → stamp
   `referredBy` → **spawned** (never blocks the join): `SaveAndWait` the stamp,
   then `SendMessage(referrerId, {type="referral", from=userId})`.
2. Inviter's session receives it → guards (`IsLoaded`, not mid-teleport-release)
   → `RewardGrantSubs.Grant({kind="gems", amount=500, rawAmount=true})` →
   `SocialService.CountReferral` → `processed()` → `Save` → `ReferralUpdate`.

⚠ `rawAmount = true`: the gems multiplier (pets, the x2-gems pass) is for gems
EARNED in the cake. An advertised "500 per friend" that silently pays 1000 makes
the panel wrong for half the playerbase.

## Failure semantics (all deliberate)
- **Grant declined / profile not loaded / mid-teleport-release** → the message is
  NOT `processed()`, so it is re-delivered on the next load. Nothing is lost.
- **Crash between `processed()` and the save** → re-delivered, so the inviter is
  paid twice. The over-pay direction is chosen on purpose: the alternative
  (`Save` first) loses the reward outright.
- **`SendMessage` fails** (server closing) → the stamp is already committed, so
  that inviter is never paid for that friend. This is the one lossy edge and it
  WARNS loudly.
- **The inviter is in a MATCH when the message lands** → it waits, intact, until
  they are next in the lobby: this module is lobby-only, so the game place
  registers no handler for it. Nothing is lost; it is just not instant.

## State
Profile section `social` (`ProfileSchema/SocialSection`, still **v1** — new
fields with defaults need no migration, P2):
`referredBy: number` (0 = never attributed), `referralsRewarded: number`.
Both survive the run reset (ADR-0013) — they are meta, like gems.

## Network
| Direction | Remote | Contract |
|---|---|---|
| server → client | `ReferralUpdate` | `{ rewarded, rewardGems }` — the friend count and the advertised per-friend figure. Pushed on join (`PushInitialState`) and after every payment. |

There is **no client → server remote**: nothing is claimed. The invite prompt is
a pure client call.

## UI
`AppRoot` panel `InviteFriends` — `UIKit/SocialPanel` (`Theme.SocialLayout`),
opened from the lobby meta menu (`Theme.AppHud.MenuIcons.InviteFriends`,
`UiFriend`). The button and the panel are **hidden until `ReferralUpdate`
arrives**: the reward figure only exists server-side, so rendering early would
advertise "0 Gems Per Friend".
The status line is the friend COUNT by default and borrows the slot for ~6 s to
acknowledge `GameInvitePromptClosed` ("Invites sent!").

## Client APIs (all client-only, all pcall'd)
- `SocialService:CanSendGameInviteAsync(player)` — yields; false/throw → the
  panel says so rather than leaving a dead button (R8).
- `SocialService:PromptGameInvite(player)` — the native prompt.
- `SocialService.GameInvitePromptClosed(player, recipientIds)` — the only
  acknowledgement the button can honestly give; it is **not** the reward.

## Gotchas
- ⚠ **LOBBY partition, and it must stay there.** The public place is the lobby;
  a reserved game server is not reachable by an invite link, and the game place's
  join data is TELEPORT data. Moving `ReferralSubs` to common would read teleport
  payloads looking for a referrer.
- ⚠ `GetJoinData()` throws for a player who left mid-load — it is pcall'd and a
  failure logs at Info, not Warn (it happens on ordinary disconnects).
- ⚠ A message handler must be registered at **subscription Start**:
  `LoadProfile` attaches handlers to a session when it opens it, so one
  registered later never sees that session.
- ⚠ The boot-time `HasHandler` sanity check runs in a **`task.defer`**. Grant
  kinds are registered inside `RewardGrantSubs.Start`, and subscriptions Start in
  sorted name order — `ReferralSubs` sorts BEFORE `RewardGrantSubs`, so an
  inline check would warn "inviters will not be paid" on every single boot while
  the payout works perfectly (R8: a late dependency must never false-positive).
- The per-inviter reward is uncapped by design ("no limit" is the panel's copy).
  If that ever needs a cap it belongs in the message handler, not the attribution
  side — the stamp is what stops duplicates, the count is just a number.

## Files
Server (LOBBY): `data/SocialData` (`referral`), `services/SocialService`
(`ReferredBy`/`MarkReferredBy`/`ReferralsRewarded`/`CountReferral`/
`ReferralDescriptor`/`ReferralDisplayGems`/`ReferralMinInviteeAgeDays`),
`subscriptions/ReferralSubs`.
Server (COMMON): `ProfileSchema/SocialSection`, `services/PersistenceService`
(`RegisterMessageHandler` / `SendMessage`), `RewardGrantSubs` (`gems` kind).
Client (LOBBY): `subscriptions/SocialSubsClient`. Client (COMMON): `AppRoot`,
`data/LocaleData` (`title-invite`, `invite-*`, `menu-invite`).
Kit: `UIKit/SocialPanel`, `Theme.SocialLayout`, `Theme.AppHud.MenuIcons`.
Remote: `ReferralUpdate`.
