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

## Config
`PersistenceData`: `storeName` ("PlayerProfiles"), `useMockInStudio`,
kick `messages`.

## Rules
P1–P5 in `CLAUDE.md`. Recipe: `docs/recipes/add-profile-section.md`.
Decision record: ADR-0001.
