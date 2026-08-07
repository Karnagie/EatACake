# 2026-08-05 — Social rewards + attention pulses

**Tags:** upgrades, ui-kit, lobby-matchmaking, group-reward, referrals, persistence, app-root, theme, economy

## What was asked
Four user requests in one pass:
1. Tween the upgrade nodes that can be upgraded now, and the nodes that contain
   something upgradeable inside them.
2. Select Easy + 1 Player by default; tween the Start button.
3. An **Invite Friends** button; 500 gems per invited friend
   (`create.roblox.com/docs/production/promotion/referral-system`).
4. A button that opens a panel offering a 15-minute boost for liking the game and
   joining the community, with a **Get Reward** button: raise the community join
   prompt when not a member, show the red "Like the game and wait 10 seconds."
   either way, and grant after 10 s if membership verifies.

## What shipped

### 1. Affordable hexes breathe
`HexNode` gained a `pulse` prop: a looping reversing tween on its OWN
centre-anchored `UIScale` (ADR-0006 — React never writes that `Scale`), tuning in
`Theme.HexTree.Pulse`. `LocalUpgradeTree` sets `node.pulse` from the
**affordability** predicate, not from the gold `available` state — gold means
UNLOCKED and priced, which a tier must be *before* you can afford it, so the
pulse is the strictly narrower set and can never advertise a purchase the Buy
button refuses. Categories pulse when they hold an affordable next tier (the same
`canBuy` that drives their "!" badge), and the badge — which lives in the
overlay's own top layer and so cannot inherit the node's scale — got its own
UIScale on the same clock. `notifierElement` became a real component
(`NotifierBadge`) to own that hook.
Scale is **1.06, not `Theme.Feel.Pulse`'s 1.10**: `nodeFill = 1` packs the comb
edge-to-edge, so a node grows straight into its neighbours and 1.10 reads as a
z-order bug.

### 2. Selector opens on Easy / 1 Player, START breathes
`MatchConfig.defaults`. The panel applies them per SESSION, in the same effect
that used to clear the previous party's choices, and ignores a default the
selector is not offering (the party row is capped by the pad).

The non-obvious half is **analytics**: `difficulty-pick` and `party-pick` are
flow steps 7-8, sitting between `selector-open` and `start-press`. Leave a
preselection unreported and every one-tap start reads as a drop-off at step 7.
So the panel reports both picks through the existing callbacks with a new
`isDefault = true` argument, and nothing is lost — "did a finger land on a
choice" is carried by the kit's automatic press counting on `Difficulty_*` /
`Players_*`, which only exists when one did. The effect reports only for a real
`sessionKey`; the panel is mounted (hidden) for the whole lobby visit and must
not beat on mount.

START takes `Button.pulse` gated on `canStart` (so it also stops the moment the
queue goes busy). **A `CanvasGroup` clips to its own bounds** — the group is
there to dim the disabled button — so `StartPulseHeadroom` (1.18) inflates the
group and deflates the button inside it by the same factor: rest geometry
identical, headroom for the breath plus the 1.05 hover bounce riding the same
button.

### 3. Referrals (`features/referrals.md`, NEW)
500 gems to the inviter per friend, once per invited account, forever.

The design problem is that **the inviter is almost never on the server the
friend lands in**, and is often offline. So the two halves never run together:
attribution happens on the INVITEE's join (`GetJoinData().ReferredByPlayerId`,
read in `OnProfileLoaded` so the stamp lands before anything is replicated), and
payment is a **ProfileStore message** queued onto the inviter's profile.
That needed a new, small persistence surface —
`PersistenceService.SendMessage` / `.RegisterMessageHandler`, wrapping
`MessageAsync` / `Profile:MessageHandler` — which is also the only way to pay an
absent player without breaking P5.

Anti-abuse is one permanent stamp on the INVITEE (`social.referredBy`), committed
with `SaveAndWait` BEFORE the payment is queued: an account can be re-invited
forever and only ever pays once, on any server. Self-referral refused, and a
`minInviteeAccountAgeDays` floor under the throwaway-account farm (see below).

Failure semantics are all one-directional on purpose: a declined grant, an
unloaded profile or a mid-teleport-release leaves the message **unprocessed**, so
it is re-delivered rather than lost; `processed()` then `Save()` means a crash in
that window over-pays by one rather than losing the reward. The one lossy edge is
a failed `SendMessage` (the stamp is already permanent) and it warns loudly.

### 4. Community reward = a WAIT, because there is no like API
Roblox exposes no like/favorite verification, so rather than pretend, the reward
is built around the gap: press GET REWARD → the red **"Like the game and wait 10
seconds."** appears immediately (client-local — that instruction is the mechanic
and cannot wait for a round trip) → the server's `pending` push says whether they
are a member, and the client raises `GroupService:PromptJoinAsync` if not →
10 s later the server re-checks membership and grants.

A player who is **already a member takes the identical path**. That is
deliberate: a claim that resolved instantly for members would teach exactly the
group being asked to like the game that they can skip that half.

The reward became a 15-minute x2-calories boost (was 50 gems) — the same thing
the shop sells for 500 gems, which is what makes joining worth a tap.
`SocialData.groupId` is now the real community (307557979).

New kit component `SocialPanel` (art / headline / body / status / one CTA,
portrait Panel family) serves both offers.

## Decisions worth remembering
- **The shop's Free row stopped claiming.** It now OPENS the reward panel. The
  reward needs a surface that can show the instruction and the wait, and one
  claim path is the whole point; `AppRoot.group` correspondingly has exactly one
  consumer again (`SocialSubsClient`), with `ShopSubsClient` no longer connecting
  `GroupRewardUpdate`.
- **Both new menu buttons are gated on their server push.** The reward figure and
  the friend count only exist server-side, so an early render would advertise
  "0 Gems Per Friend"; and a community button whose only possible answer is "not
  available" is worse than no button.
- **Every server-side refusal on the claim path is silent by design** (a modified
  client must not farm replies), which means the CLIENT has to give up on its own
  — hence the `waitSeconds + 15` release, or a dropped claim would freeze the
  panel for the rest of the session.
- **The claim cooldown is measured from RESOLUTION, not from the press**, and is
  stamped only for an attempt that got past the guards. Concurrent claims are
  already impossible via the in-flight lock, so the cooldown's only job is to
  space out completed attempts — and one timed from the press would silently
  refuse the immediate retry that "join the community first, then try again"
  explicitly invites.

## Flagged, not done
The user asked for the buttons on "the menu on the right". The lobby meta menu
renders on the **LEFT** (`Theme.AppHud.MenuPosition.X = 22/1920`); there is only
one menu, so both buttons went into it. Moving the menu is a one-line Theme
change if that is what was meant.

## Review pass (fan-out, 4 dimensions, adversarially verified)
30 findings raised, most refuted as pre-existing or misread. What survived and
was fixed:
- **My own ordering bug, caught before review**: `referral` / `groupState` were
  read in AppRoot's social view-model ~50 lines ABOVE their `local` declarations,
  so both resolved to nil globals. `luau-compile` cannot see this; a filtered
  `luau-analyze` unknown-global scan can, and is now part of the gate.
- **P1, false boot warn**: `ReferralSubs.Start` checked
  `RewardGrantSubs.HasHandler("gems")` inline — but subs Start in sorted NAME
  order and `ReferralSubs` sorts before `RewardGrantSubs`, so it warned
  "inviters will not be paid" on EVERY boot while the payout worked. Moved into
  `task.defer`, the pattern GroupRewardSubs already used one file away.
- **P1, lock ownership**: wrapping the 10-second claim in `pcall` (so a raised
  error could not strand `pending[userId]` forever) initially released the lock
  unconditionally — which let a press REFUSED because another claim was running
  release that claim's lock. Now `owned.started` is flipped on the exact line
  that takes the lock and only that call releases it.
- **Invisible body text**: `Theme.SocialLayout.BodyColor` had been copied from
  the hex tree's detail card — correct on a dark Chip, ~1.07:1 on the portrait
  Panel's near-WHITE fill. Now the kit's dark-on-light ink.
- **Clipped bounce**: `SocialPanel`'s CTA had the same CanvasGroup problem the
  START button did, for `usePressable`'s 1.05 hover pose. Headroom added.
- **Infinite tween on a hidden button**: with a default preselected `canStart` is
  true from MOUNT, and MatchmakingPanel is mounted-hidden for the whole lobby
  visit *and in the game place* — the START pulse is now gated on `visible`.
- **Money-path ordering**: the referral stamp is committed with `SaveAndWait`
  BEFORE the payment is queued (was fire-and-forget `Save`); a crash in that
  window would have made the same friend re-payable.
- **R8**: `GroupRewardSubs`' boot validation used raw `warn(...)` instead of
  `Log.Warn`, dropping the `[Server/…]` prefix every console grep relies on.
- **Cooldown semantics**: measured from RESOLUTION, not the press, and only for
  a real attempt — a cooldown timed from the press silently refused the retry
  that "join the community first, then try again" explicitly invites.
- **`waitSeconds` now rides every payload** (including the join push), so the
  client's fallback constant stops being a second source of truth for a value
  `SocialData` owns.
- Plus the alt-account floor below, and a batch of comments/doc lines that the
  change had made false.

## Flagged in review, added deliberately
The referral's per-invitee stamp bounds ONE account, not many — alt-account
farming is the standing risk of any Roblox referral, and 500 gems is about one
cleared cake's income. `SocialData.referral.minInviteeAccountAgeDays` (default 1)
is a floor, not a fix: `Player.AccountAge` costs no web call and kills the
create-join-collect loop that runs inside a single sitting, while a friend who
signed up yesterday still counts. Roblox's own guidance recommends this class of
mitigation **plus monitoring**; nothing here monitors yet.

## Verification
`luau-compile` clean over the whole `src/` tree, plus a filtered `luau-analyze`
unknown-global scan over every changed file. Studio playtest still pending —
nothing here has been seen running.

## Docs
`features/referrals.md` (new), `features/group-reward.md` (rewritten),
`features/upgrades.md`, `features/lobby-matchmaking.md`, `features/app-root.md`,
`features/ui-kit.md`, `features/persistence.md`, `features/boosts.md`, `MAP.md`,
`registries/remotes.md`, `registries/data-keys.md`.
