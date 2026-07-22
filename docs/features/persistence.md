# Persistence (schema-driven player profiles)

## What it does
Loads, migrates, auto-saves and session-locks one profile per player.
Built on vendored ProfileStore (`src/shared/lib/ProfileStore.luau`) — session
locking, ~300s auto-save (first ~150s after load skipped), retries and final save on shutdown are inherited.

## The schema
Each top-level slice of the profile is one **section file** in
`src/server/data/ProfileSchema/` declaring:

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

Sections removed from the schema are preserved in stored data untouched.

## Runtime access
- `PlayerProfileData.profiles[userId]` / `.Get(userId)` — the profile data
  table services read and mutate directly; changes auto-save while active.
- `PlayerProfileData.sessions[userId]` — ProfileStore handle
  (`FirstSessionTime`, `SessionLoadCount` for analytics).
- `PersistenceService.LoadProfile(player) -> (profile?, isNew)` — yields;
  kicks the player on lock conflict/failure. `isNew` is true only for a
  genuinely fresh profile (never on failed reads).
- `PersistenceService.Save(userId)` — immediate save for critical moments
  (Robux purchases). Routine saving is automatic.
- `PersistenceService.Unload(userId)` — final save + session end (on leave).
- `PersistenceService.IsLoaded(userId)`.

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
