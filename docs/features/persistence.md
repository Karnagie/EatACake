# Persistence (schema-driven player profiles)

## What it does
Loads, migrates, auto-saves and session-locks one profile per player.
Built on vendored ProfileStore (`src/shared/lib/ProfileStore.luau`) — session
locking, ~300s auto-save (first ~150s after load skipped), retries and final save on shutdown are inherited.

## The schema
Each top-level slice of the profile is one **section file** in
`src/server/common/data/ProfileSchema/` declaring:

- `key` — field name in the profile table (unique; `__schema` reserved)
- `version` + `migrations[oldVersion]` — sequential shape upgrades
- `defaults` — deep-copied for new profiles; missing fields reconciled on load
- `intKeySets` — dot-paths of number-keyed tables (DataStore JSON stringifies
  numeric keys; these are converted back on every load)
- `sanitize` — optional final coercion

A field is defined **once**; there are no separate default/load/save/sanitize
whitelists to keep in sync.

## Load pipeline (per section, in order)
1. Missing section → deep-copy defaults
2. `migrations` from stored `__schema[key]` version up to current
3. Reconcile: fill missing keys from defaults (recursively)
4. Normalize declared `intKeySets`
5. `sanitize`
6. Stamp `__schema[key] = max(storedVersion, version)` — the stamp is NEVER
   downgraded (a fresh/missing section from step 1 just stamps `version`). On a
   mixed-version fleet an old server must not re-stamp its lower version onto
   data a newer server already migrated, or the migration re-runs and corrupts
   the section (`PersistenceService.lua`).

The full pipeline runs on a deep copy and commits back only after every section
succeeds. A missing/throwing migration or throwing sanitizer aborts the load;
the unchanged profile session is ended and no partial shape/version stamp can
be saved. Migration steps may mutate their copy and return nil, or return a
replacement table.

Sections removed from the schema are preserved in stored data untouched.

## Runtime access
- `PlayerProfileData.profiles[userId]` / `.Get(userId)` — the profile data
  table services read and mutate directly; changes auto-save while active.
- `PlayerProfileData.sessions[userId]` — ProfileStore handle
  (`FirstSessionTime`, `SessionLoadCount` for analytics).
- `PersistenceService.LoadProfile(player, options?) -> (profile?, isNew)` —
  yields; normal lifecycle loads kick on lock conflict/failure. Recovery may
  supply `{deadline, cancel, kickOnFailure=false}`; a late acquisition is ended
  before it can enter `PlayerProfileData`. `isNew` is true only for a genuinely
  fresh profile (never on failed reads).
- `PersistenceService.Save(userId)` — immediate save for critical moments:
  Robux purchases AND in-game earning **milestones** (upgrade buy, cake-clear
  reward, treasure find, gym-drain complete / instant-burn). Short game rounds
  never reach the 300s autosave (first 150s skipped), so without milestone saves
  a crash would lose the round. Routine saving is otherwise automatic.
- `PersistenceService.Unload(userId, intentional?)` — final save + session end
  (on leave). `intentional = true` marks a deliberate pre-teleport release,
  writes a unique nonce into `RobloxMetaData`, and suppresses the expected
  `session-taken` kick. `VerifyReleased(userId)` then read-backs the profile and
  succeeds only when that exact nonce and a nil persisted session appear
  together. Routine leave omits it.
- `PersistenceService.IsLoaded(userId)`.
- `PersistenceService.SendMessage(userId, message)` / `.RegisterMessageHandler(name, handler)` — see **Messages** below.
- `PersistenceService.IsReleased(userId)` / yielding `VerifyReleased(userId)` /
  `ClearReleaseState(userId)` — intentional-handoff proof and cleanup; callers
  must not treat ordinary unload as a verified release.

## Cross-place handoff (lobby ↔ game)
DataStores are universe-scoped, so both places share ONE `PlayerProfiles`
session lock. The profile FOLLOWS the player: the source folds playtime,
intentionally unloads (final save), verifies the exact nonce + cleared lock,
THEN calls `TeleportAsync`; the destination runs unchanged `LoadProfile`. Never
`Steal=true` (P5). The source `Teleporting` attribute acquires a common-client
movement lock until departure/recovery. Synchronous failures schedule concurrent
per-player re-acquisition; async `TeleportInitFailed` retries the exact returned
`TeleportOptions` (preserving a reserved party destination) before recovery.
Recovery is token-gated and bounded to 30 seconds; its watchdog safely kicks a
still-present player if ProfileStore cannot re-acquire, while any late acquired
session is immediately released and never published. On success every available
subscription `PushInitialState` hook (including the authoritative cake snapshot)
is replayed before the `Teleporting` input lock clears. Owners: `TeleportSubs`,
`TeleportRetrySubs`, `Teleport/Release`, `Teleport/Recovery`,
`Teleport/Resync`, `TeleportData`, `TeleportControlSubsClient`,
`PlayerControlService`, `PlaceConfig`. See
ADR-0009/0010. Verify the complete hop ONLY on PUBLISHED places — Studio cannot
prove the cross-server lock.
`RequestTeleport` is compatibility return only (game → lobby); lobby → game is
owned by the validated queue's `TeleportSubs.SendGroup` call.

## Lifecycle
`PlayerLifecycleSubs` wires PlayerAdded (load) and PlayerRemoving (unload).
If another server takes the session, the player is kicked with
`PersistenceData.messages["session-taken"]`.

Initial state push is double-gated: profile loaded AND `ClientReady` received
(remote, no args, fired once at the end of LocalBootstrap — RemoteEvents sent
before the client connects listeners are silently lost). Feature join-pushes
belong in `pushInitialState`.

**Two discovered hooks**, both found by scanning the merged `subscriptions` table
(so a sub absent in this place is simply skipped — that is what lets one file run
in the lobby and the game place):

| Hook | Fires | For |
|---|---|---|
| `OnProfileLoaded(player)` | right after `LoadProfile`, **before** the push gate opens | work that must MUTATE the profile before the client is told anything (`RunResetSubs` wipes the run-scoped tree/calories/belly — ADR-0013) |
| `PushInitialState(player)` | after profile load **and** `ClientReady` | replicate to a client that is ready to listen |

⚠ `PushInitialState` hooks run in **alphabetical order**, so they are not a safe
place to mutate shared state: a reset there would race `EconomySubs`/`UpgradeSubs`
(both sort earlier) and the client would keep the stale values with no later
correction. That is precisely why `OnProfileLoaded` exists — and because it runs
before any push, each domain's own `PushInitialState` then sends already-reset
state, so no re-push code is needed anywhere.
⚠ The catch-up sweep for players who joined before `Start` ran uses `task.defer`,
not `task.spawn`: this module sorts before several of the subs whose hooks it
discovers, and a spawned body runs immediately, so it could otherwise reach a hook
before the sub owning it had armed.

## Config
`PersistenceData`: `storeName` ("PlayerProfiles"), `useMockInStudio`,
kick `messages`.

## Rules
P1–P5 in `CLAUDE.md`. Recipe: `docs/recipes/add-profile-section.md`.
Decision record: ADR-0001.

## Messages — writing to a profile this server does not own

The only way to pay a player who is on another server, or offline, without
touching `DataStoreService` (P5). Wraps ProfileStore's `MessageAsync` /
`Profile:MessageHandler`; the referral reward is its one caller today
(`features/referrals.md`).

- `SendMessage(userId, message) -> boolean` — YIELDS. Queues a JSON table onto
  that profile. Delivered to their active session (immediately if that is this
  server) or on their next load. Can only APPEND — it never mutates their data;
  everything the message does happens inside the receiving session.
  ⚠ **A message is only consumed in a place that REGISTERED a handler for it.**
  Handlers are registered per subscription, and a lobby-partition subscription
  does not exist in the game place — so a message arriving while its recipient is
  in a match waits, intact, until they are next in the lobby.
  Returns false only when the server is closing / the store is unavailable
  (ProfileStore retries DataStore errors itself).
- `RegisterMessageHandler(name, handler)` — call from a subscription's `Start`.
  `LoadProfile` attaches every registered handler to a session as it opens it,
  **after** publishing it into `PlayerProfileData` (a handler that pays the
  player needs `.Get(userId)` to work), so a handler registered later never sees
  that session. `handler(player, message, processed)`.
- **`processed()` is the consume.** Call it only once the message has actually
  been applied; unprocessed messages are re-delivered on the next load. A
  throwing handler is logged and left unprocessed on purpose.
- ⚠ `processed()` only takes effect once a save commits, so `processed()` then
  `Save()` is the correct order. A crash in that window re-delivers and
  over-pays by one — the safe direction, since saving first would lose the
  reward outright.
- ⚠ A message is offered to registered handlers until one processes it, so every
  handler must check the message's own `type` field and return WITHOUT processing
  when it is not theirs — otherwise one feature silently consumes another's.
  A malformed (non-table) message is consumed by the wrapper and warned about.

## SaveAndWait — the money-path save

`Save(userId)` is fire-and-forget: ProfileStore's `Profile:Save()` is a
`task.spawn`, so it returns before anything reaches the DataStore. That is right
for gameplay state (the autosave picks it up) and WRONG wherever the caller must
then tell an external system the write happened.

`SaveAndWait(userId, timeoutSeconds?)` saves and waits (default 10 s) on
`session.OnAfterSave`, returning whether a save landed. `ShopSubs` uses it before
returning `PurchaseGranted` — see ADR-0014. Two properties to keep in mind:

- `OnAfterSave` is shared by every concurrent save of the profile, so a `true`
  means "a save committed", not "mine did". For a caller that has already
  mutated `Data`, that is equivalent.
- It refuses (false) while a teleport release nonce is set, exactly like `Save`.
